import BackgroundTasks
import Foundation
import os.log
import UIKit

/// Manages concurrent shared-vault uploads across all vaults.
///
/// Responsibilities:
/// - Multiple concurrent upload jobs (same vault and cross-vault)
/// - Per-job persistence for crash/background resume
/// - Per-job cancellation/termination
@MainActor
@Observable
final class ShareUploadManager {
    static let shared = ShareUploadManager()

    nonisolated static let backgroundResumeTaskIdentifier = "app.vaultaire.ios.share-upload.resume"
    private nonisolated static let pendingTTL: TimeInterval = 24 * 60 * 60

    enum UploadJobStatus: String, Codable {
        case preparing
        case uploading
        case finalizing
        case paused
        case failed
        case complete
        case cancelled

        var isRunning: Bool {
            switch self {
            case .preparing, .uploading, .finalizing:
                return true
            default:
                return false
            }
        }
    }

    struct UploadJob: Identifiable, Equatable {
        let id: String
        let ownerFingerprint: String
        let createdAt: Date
        var shareVaultId: String
        var phrase: String?
        var status: UploadJobStatus
        var progress: Int
        var total: Int
        var message: String
        var errorMessage: String?

        var canResume: Bool {
            switch status {
            case .failed, .paused:
                return true
            default:
                return false
            }
        }

        var canTerminate: Bool {
            switch status {
            case .complete, .cancelled:
                return false
            default:
                return true
            }
        }
    }

    struct PendingUploadState: Codable {
        let jobId: String
        let shareVaultId: String
        let phraseVaultId: String
        let shareKeyData: Data
        let policy: VaultStorage.SharePolicy
        let ownerFingerprint: String
        let totalChunks: Int
        let sharedFileIds: [String]
        let svdfManifest: [SVDFSerializer.FileManifestEntry]
        let createdAt: Date
        var uploadFinished: Bool
        var lastProgress: Int
        var lastMessage: String
        /// The human-readable share phrase needed by the recipient. Stored so the
        /// owner can copy/share it while the upload runs, even after app restart.
        let phrase: String?

        enum CodingKeys: String, CodingKey {
            case jobId
            case shareVaultId
            case phraseVaultId
            case shareKeyData
            case policy
            case ownerFingerprint
            case totalChunks
            case sharedFileIds
            case svdfManifest
            case createdAt
            case uploadFinished
            case lastProgress
            case lastMessage
            case phrase
        }

        init(
            jobId: String,
            shareVaultId: String,
            phraseVaultId: String,
            shareKeyData: Data,
            policy: VaultStorage.SharePolicy,
            ownerFingerprint: String,
            totalChunks: Int,
            sharedFileIds: [String],
            svdfManifest: [SVDFSerializer.FileManifestEntry],
            createdAt: Date,
            uploadFinished: Bool,
            lastProgress: Int,
            lastMessage: String,
            phrase: String?
        ) {
            self.jobId = jobId
            self.shareVaultId = shareVaultId
            self.phraseVaultId = phraseVaultId
            self.shareKeyData = shareKeyData
            self.policy = policy
            self.ownerFingerprint = ownerFingerprint
            self.totalChunks = totalChunks
            self.sharedFileIds = sharedFileIds
            self.svdfManifest = svdfManifest
            self.createdAt = createdAt
            self.uploadFinished = uploadFinished
            self.lastProgress = lastProgress
            self.lastMessage = lastMessage
            self.phrase = phrase
        }

        /// Backward compatibility with legacy single-pending schema that had no
        /// `jobId`, `lastProgress`, or `lastMessage`.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            jobId = try c.decodeIfPresent(String.self, forKey: .jobId) ?? UUID().uuidString.lowercased()
            shareVaultId = try c.decode(String.self, forKey: .shareVaultId)
            phraseVaultId = try c.decode(String.self, forKey: .phraseVaultId)
            shareKeyData = try c.decode(Data.self, forKey: .shareKeyData)
            policy = try c.decode(VaultStorage.SharePolicy.self, forKey: .policy)
            ownerFingerprint = try c.decode(String.self, forKey: .ownerFingerprint)
            totalChunks = try c.decode(Int.self, forKey: .totalChunks)
            sharedFileIds = try c.decode([String].self, forKey: .sharedFileIds)
            svdfManifest = try c.decode([SVDFSerializer.FileManifestEntry].self, forKey: .svdfManifest)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            uploadFinished = try c.decodeIfPresent(Bool.self, forKey: .uploadFinished) ?? false
            lastProgress = try c.decodeIfPresent(Int.self, forKey: .lastProgress) ?? 0
            lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? "Waiting to resume..."
            phrase = try c.decodeIfPresent(String.self, forKey: .phrase)
        }
    }

    private struct LegacyPendingUploadState: Codable {
        let shareVaultId: String
        let phraseVaultId: String
        let shareKeyData: Data
        let policy: VaultStorage.SharePolicy
        let ownerFingerprint: String
        let totalChunks: Int
        let sharedFileIds: [String]
        let svdfManifest: [SVDFSerializer.FileManifestEntry]
        let createdAt: Date
    }

    // MARK: - Upload Lifecycle Markers (for crash recovery diagnostics)

    struct UploadLifecycleMarker: Codable {
        let phase: String
        let shareVaultId: String
        let timestamp: Date
    }

    private nonisolated static let uploadLifecycleKey = "share.upload.lifecycle.marker"

    nonisolated static func setUploadLifecycleMarker(phase: String, shareVaultId: String) {
        let marker = UploadLifecycleMarker(
            phase: phase,
            shareVaultId: shareVaultId,
            timestamp: Date()
        )
        if let data = try? JSONEncoder().encode(marker) {
            UserDefaults.standard.set(data, forKey: uploadLifecycleKey)
        }
    }

    nonisolated static func clearUploadLifecycleMarker() {
        UserDefaults.standard.removeObject(forKey: uploadLifecycleKey)
    }

    /// Returns a prior unfinished upload marker and clears it.
    /// If the marker is too old, it is discarded and nil is returned.
    nonisolated static func consumeStaleUploadLifecycleMarker(
        maxAge: TimeInterval = 24 * 60 * 60
    ) -> UploadLifecycleMarker? {
        defer { clearUploadLifecycleMarker() }
        guard
            let data = UserDefaults.standard.data(forKey: uploadLifecycleKey),
            let marker = try? JSONDecoder().decode(UploadLifecycleMarker.self, from: data)
        else {
            return nil
        }
        guard Date().timeIntervalSince(marker.timestamp) <= maxAge else {
            return nil
        }
        return marker
    }

    var jobs: [UploadJob] = []

    var hasPendingUpload: Bool {
        !Self.loadAllPendingUploadStates().isEmpty
    }

    var runningUploadCount: Int {
        jobs.reduce(into: 0) { count, job in
            if job.status.isRunning { count += 1 }
        }
    }

    private var jobsById: [String: UploadJob] = [:]
    private var pendingStateByJobId: [String: PendingUploadState] = [:]
    private var uploadTasks: [String: Task<Void, Never>] = [:]
    private var terminatedJobIds: Set<String> = []

    private var currentBgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var currentBGProcessingTask: BGProcessingTask?

    private var vaultKeyProvider: (() -> VaultKey?)?

    private let storage: VaultStorageProtocol
    private let cloudKit: CloudKitSharingClient

    private struct PreparedUploadArtifacts {
        let shareKey: ShareKey
        let phraseVaultId: String
        let sharedFileIds: [String]
        let svdfManifest: [SVDFSerializer.FileManifestEntry]
        let totalChunks: Int
        let fileSize: Int
    }

    private nonisolated static let logger = Logger(subsystem: "app.vaultaire.ios", category: "ShareUpload")

    private nonisolated static let pendingRootDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static let legacyPendingDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_upload", isDirectory: true)
    }()

    private init(
        storage: VaultStorageProtocol = VaultStorage.shared,
        cloudKit: CloudKitSharingClient = CloudKitSharingManager.shared
    ) {
        self.storage = storage
        self.cloudKit = cloudKit
        migrateLegacyPendingIfNeeded()
        bootstrapJobsFromPendingState()
    }

    #if DEBUG
    static func createForTesting(
        storage: VaultStorageProtocol,
        cloudKit: CloudKitSharingClient
    ) -> ShareUploadManager {
        ShareUploadManager(storage: storage, cloudKit: cloudKit)
    }
    #endif

    // MARK: - Public API

    func setVaultKeyProvider(_ provider: @escaping () -> VaultKey?) {
        vaultKeyProvider = provider
    }

    func jobs(forOwnerFingerprint ownerFingerprint: String?) -> [UploadJob] {
        guard let ownerFingerprint else {
            return jobs.sorted(by: { $0.createdAt > $1.createdAt })
        }
        return jobs
            .filter { $0.ownerFingerprint == ownerFingerprint }
            .sorted(by: { $0.createdAt > $1.createdAt })
    }

    func registerBackgroundProcessingTask() {
        BackgroundTaskCoordinator.register(
            identifier: Self.backgroundResumeTaskIdentifier
        ) { task in
            ShareUploadManager.shared.handleBackgroundProcessingTask(task)
        }
    }

    func scheduleBackgroundResumeTask(earliestIn seconds: TimeInterval = 15) {
        guard hasPendingUpload else { return }
        BackgroundTaskCoordinator.schedule(
            identifier: Self.backgroundResumeTaskIdentifier,
            earliestIn: seconds
        )
    }

    func startBackgroundUpload(
        vaultKey: VaultKey,
        phrase: String,
        hasExpiration: Bool,
        expiresAt: Date?,
        hasMaxOpens: Bool,
        maxOpens: Int?,
        allowDownloads: Bool = true
    ) {
        Task {
            if await DuressHandler.shared.isDuressKey(vaultKey) {
                await DuressHandler.shared.clearDuressVault()
                Self.logger.info("Cleared duress vault designation before starting share upload")
            }
        }

        let ownerFingerprint = KeyDerivation.keyFingerprint(from: vaultKey.rawBytes)
        let shareVaultId = CloudKitSharingManager.generateShareVaultId()
        let jobId = UUID().uuidString.lowercased()

        let policy = VaultStorage.SharePolicy(
            expiresAt: hasExpiration ? expiresAt : nil,
            maxOpens: hasMaxOpens ? maxOpens : nil,
            allowScreenshots: false,
            allowDownloads: allowDownloads
        )

        let job = UploadJob(
            id: jobId,
            ownerFingerprint: ownerFingerprint,
            createdAt: Date(),
            shareVaultId: shareVaultId,
            phrase: phrase,
            status: .preparing,
            progress: 0,
            total: 100,
            message: "Preparing vault...",
            errorMessage: nil
        )
        upsertJob(job)

        ensureBackgroundExecution()

        let capturedVaultKey = vaultKey
        let capturedPhrase = phrase

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runInitialUpload(
                jobId: jobId,
                shareVaultId: shareVaultId,
                phrase: capturedPhrase,
                vaultKey: capturedVaultKey,
                ownerFingerprint: ownerFingerprint,
                policy: policy
            )
        }
        uploadTasks[jobId] = task
    }

    private var lastResumeTime: ContinuousClock.Instant = .now - .seconds(10)

    func resumePendingUploadsIfNeeded(trigger: String) {
        guard hasPendingUpload else { return }
        // Debounce: skip if called within 2s of last resume
        let now = ContinuousClock.now
        guard now - lastResumeTime >= .seconds(2) else {
            Self.logger.debug("[resume] Skipping duplicate resume trigger=\(trigger, privacy: .public) (debounced)")
            return
        }
        lastResumeTime = now
        guard CloudKitSharingManager.canProceedWithNetwork() else {
            Self.logger.info("[resume] Skipping upload resume: waiting for Wi-Fi (user preference)")
            return
        }
        resumePendingUploads(vaultKey: vaultKeyProvider?(), trigger: trigger)
    }

    func resumePendingUploads(vaultKey: VaultKey?, trigger: String = "manual") {
        let pendingStates: [PendingUploadState]
        if let vaultKey {
            let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey.rawBytes)
            pendingStates = Self.loadAllPendingUploadStates().filter { $0.ownerFingerprint == fingerprint }
        } else {
            pendingStates = Self.loadAllPendingUploadStates()
        }
        guard !pendingStates.isEmpty else {
            Self.logger.debug("[resume] trigger=\(trigger, privacy: .public) no matching pending uploads")
            return
        }

        for state in pendingStates {
            if uploadTasks[state.jobId] != nil { continue }

            if jobsById[state.jobId] == nil {
                let restoredJob = UploadJob(
                    id: state.jobId,
                    ownerFingerprint: state.ownerFingerprint,
                    createdAt: state.createdAt,
                    shareVaultId: state.shareVaultId,
                    phrase: state.phrase,
                    status: .paused,
                    progress: state.lastProgress,
                    total: 100,
                    message: state.lastMessage,
                    errorMessage: nil
                )
                upsertJob(restoredJob)
            } else {
                // Job exists in memory — restore phrase in case it was lost (e.g. after suspend)
                updateJob(jobId: state.jobId) { job in
                    if job.phrase == nil, let phrase = state.phrase {
                        job.phrase = phrase
                    }
                }
            }

            pendingStateByJobId[state.jobId] = state
            startResumeTask(state: state, vaultKey: vaultKey)
        }
    }

    func resumeUpload(jobId: String, vaultKey: VaultKey?) {
        guard let vaultKey else { return }
        guard let state = Self.loadPendingUploadState(jobId: jobId) else { return }
        
        // Immediately update UI to show resuming state and clear error
        updateJob(jobId: jobId) { job in
            job.status = .preparing
            job.message = "Resuming upload..."
            job.errorMessage = nil
        }
        
        pendingStateByJobId[jobId] = state
        startResumeTask(state: state, vaultKey: vaultKey)
    }

    func cancelUpload(jobId: String) {
        terminateUpload(
            jobId: jobId,
            vaultKey: vaultKeyProvider?(),
            cleanupRemote: true
        )
    }

    /// Hard-terminates an upload job:
    /// - cancel task
    /// - remove pending state + disk payload
    /// - remove row/state immediately
    /// - clean up share artifacts in background
    func terminateUpload(jobId: String, vaultKey: VaultKey?, cleanupRemote: Bool = true) {
        let shareVaultId = jobsById[jobId]?.shareVaultId
            ?? pendingStateByJobId[jobId]?.shareVaultId
            ?? Self.loadPendingUploadState(jobId: jobId)?.shareVaultId

        let hadRunningTask = uploadTasks[jobId] != nil
        if hadRunningTask {
            terminatedJobIds.insert(jobId)
        }

        uploadTasks[jobId]?.cancel()
        uploadTasks.removeValue(forKey: jobId)
        pendingSaveWorkItems[jobId]?.cancel()
        pendingSaveWorkItems[jobId] = nil
        pendingStateByJobId.removeValue(forKey: jobId)
        Self.clearPendingUpload(jobId: jobId)
        removeJob(jobId: jobId)

        teardownBackgroundExecutionIfIdle()

        guard let shareVaultId, let vaultKey else { return }
        let capturedCloudKit = cloudKit
        let keyFingerprint = vaultKey.rawBytes.hashValue
        Task { [weak self] in
            await self?.removeShareRecord(shareVaultId: shareVaultId, vaultKey: vaultKey)
        }
        Task.detached(priority: .utility) {
            if cleanupRemote {
                try? await capturedCloudKit.deleteSharedVault(shareVaultId: shareVaultId)
            }
            try? ShareSyncCache(shareVaultId: shareVaultId, vaultKeyFingerprint: String(keyFingerprint)).purge()
        }
    }

    // MARK: - Task runners

    private func runInitialUpload(
        jobId: String,
        shareVaultId: String,
        phrase: String,
        vaultKey: VaultKey,
        ownerFingerprint: String,
        policy: VaultStorage.SharePolicy
    ) async {
        defer {
            uploadTasks.removeValue(forKey: jobId)
            terminatedJobIds.remove(jobId)
            teardownBackgroundExecutionIfIdle()
            completeBackgroundProcessingTaskIfPossible()
        }

        do {
            updateJob(jobId: jobId) { job in
                job.status = .preparing
                job.progress = 1
                job.message = "Preparing vault..."
            }

            updateJob(jobId: jobId) { job in
                job.status = .preparing
                job.progress = 5
                job.message = "Encrypting files..."
            }

            let capturedStorage = storage
            let prepTask = Task.detached(priority: .userInitiated) {
                try await Self.buildInitialUploadArtifacts(
                    jobId: jobId,
                    phrase: phrase,
                    vaultKey: vaultKey,
                    ownerFingerprint: ownerFingerprint,
                    storage: capturedStorage
                )
            }
            let prepared: PreparedUploadArtifacts
            do {
                prepared = try await withTaskCancellationHandler {
                    try await prepTask.value
                } onCancel: {
                    prepTask.cancel()
                }
            } catch {
                prepTask.cancel()
                throw error
            }

            let svdfURL = Self.svdfURL(jobId: jobId)

            let pendingState = PendingUploadState(
                jobId: jobId,
                shareVaultId: shareVaultId,
                phraseVaultId: prepared.phraseVaultId,
                shareKeyData: prepared.shareKey.rawBytes,
                policy: policy,
                ownerFingerprint: ownerFingerprint,
                totalChunks: prepared.totalChunks,
                sharedFileIds: prepared.sharedFileIds,
                svdfManifest: prepared.svdfManifest,
                createdAt: Date(),
                uploadFinished: false,
                lastProgress: 5,
                lastMessage: "Uploading vault...",
                phrase: phrase
            )
            savePendingState(pendingState, immediate: true)

            scheduleBackgroundResumeTask(earliestIn: 15)

            updateJob(jobId: jobId) { job in
                job.status = .uploading
                job.progress = 5
                job.message = "Uploading vault..."
                job.errorMessage = nil
            }

            // Save manifest FIRST so the phrase is immediately valid
            // The manifest is saved before chunks so recipients can verify the share exists
            Self.logger.info("[upload-\(jobId)] Saving manifest before chunk upload for phraseVaultId: \(prepared.phraseVaultId)")
            do {
                try await cloudKit.saveManifest(
                    shareVaultId: shareVaultId,
                    phraseVaultId: prepared.phraseVaultId,
                    shareKey: prepared.shareKey,
                    policy: policy,
                    ownerFingerprint: ownerFingerprint,
                    totalChunks: prepared.totalChunks
                )
                Self.logger.info("[upload-\(jobId)] Manifest saved successfully - phrase is now valid")
            } catch {
                Self.logger.error("[upload-\(jobId)] Failed to save manifest: \(error.localizedDescription)")
                throw error
            }

            try await cloudKit.uploadChunksFromFile(
                shareVaultId: shareVaultId,
                fileURL: svdfURL,
                chunkIndices: Array(0..<prepared.totalChunks),
                onProgress: { [weak self] current, total in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let pct = total > 0 ? 5 + (84 * current / total) : 89
                        self.updateJob(jobId: jobId) { job in
                            job.status = .uploading
                            job.progress = max(job.progress, pct)
                            job.message = "Uploading vault..."
                            job.errorMessage = nil
                        }
                        self.updatePendingProgress(jobId: jobId, progress: pct, message: "Uploading vault...")
                    }
                }
            )

            try await cloudKit.saveManifest(
                shareVaultId: shareVaultId,
                phraseVaultId: prepared.phraseVaultId,
                shareKey: prepared.shareKey,
                policy: policy,
                ownerFingerprint: ownerFingerprint,
                totalChunks: prepared.totalChunks
            )

            updateJob(jobId: jobId) { job in
                job.status = .finalizing
                job.progress = 95
                job.message = "Finalizing..."
            }
            updatePendingProgress(jobId: jobId, progress: 95, message: "Finalizing...")

            let keyFingerprint = vaultKey.rawBytes.hashValue
            try await Task.detached(priority: .utility) {
                let syncCache = ShareSyncCache(shareVaultId: shareVaultId, vaultKeyFingerprint: String(keyFingerprint))
                try syncCache.saveSVDF(from: svdfURL)
                let chunkHashes = try ShareSyncCache.computeChunkHashes(from: svdfURL)
                let syncState = ShareSyncCache.SyncState(
                    syncedFileIds: Set(prepared.sharedFileIds),
                    chunkHashes: chunkHashes,
                    manifest: prepared.svdfManifest,
                    syncSequence: 1,
                    deletedFileIds: [],
                    totalDeletedBytes: 0,
                    totalBytes: prepared.fileSize
                )
                try syncCache.saveSyncState(syncState)
            }.value

            await appendShareRecord(
                shareVaultId: shareVaultId,
                policy: policy,
                shareKeyData: prepared.shareKey.rawBytes,
                vaultKey: vaultKey
            )

            pendingSaveWorkItems[jobId]?.cancel()
            pendingSaveWorkItems[jobId] = nil
            pendingStateByJobId.removeValue(forKey: jobId)
            Self.clearPendingUpload(jobId: jobId)

            removeJob(jobId: jobId)

            LocalNotificationManager.shared.sendUploadComplete()
        } catch is CancellationError {
            if terminatedJobIds.contains(jobId) {
                return
            }
            if let pendingState = pendingStateByJobId[jobId],
               Self.loadPendingUploadState(jobId: pendingState.jobId) != nil {
                updateJob(jobId: jobId) { job in
                    job.status = .paused
                    job.message = "Upload paused"
                }
                scheduleBackgroundResumeTask(earliestIn: 30)
            } else {
                updateJob(jobId: jobId) { job in
                    job.status = .cancelled
                    job.message = "Upload terminated"
                }
            }
        } catch {
            if terminatedJobIds.contains(jobId) {
                return
            }
            EmbraceManager.shared.captureError(error)
            updateJob(jobId: jobId) { job in
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.message = "Upload failed"
            }
            updatePendingProgress(jobId: jobId, progress: 0, message: "Upload failed")
            scheduleBackgroundResumeTask(earliestIn: 30)
            LocalNotificationManager.shared.sendUploadFailed()
        }
    }

    private func startResumeTask(state: PendingUploadState, vaultKey: VaultKey?) {
        if let existingTask = uploadTasks[state.jobId] {
            // A live task is still running — don't start a second one.
            // If the task is cancelled (e.g. by cancelAllRunningUploadsAsInterrupted) but
            // its defer hasn't run yet, treat it as gone so vault_unlocked / other triggers
            // can immediately start the resume instead of being silently skipped.
            guard existingTask.isCancelled else { return }
            uploadTasks.removeValue(forKey: state.jobId)
        }
        terminatedJobIds.remove(state.jobId)
        ensureBackgroundExecution()

        updateJob(jobId: state.jobId) { job in
            if state.uploadFinished {
                job.status = .finalizing
                job.progress = max(job.progress, 99)
                job.message = "Finalizing..."
            } else {
                job.status = .uploading
                job.progress = max(job.progress, max(2, state.lastProgress))
                job.message = "Checking uploaded chunks..."
            }
            job.errorMessage = nil
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runResumeUpload(state: state, vaultKey: vaultKey)
        }
        uploadTasks[state.jobId] = task
    }

    private func runResumeUpload(state: PendingUploadState, vaultKey: VaultKey?) async {
        defer {
            uploadTasks.removeValue(forKey: state.jobId)
            terminatedJobIds.remove(state.jobId)
            teardownBackgroundExecutionIfIdle()
            completeBackgroundProcessingTaskIfPossible()
        }

        do {
            if state.uploadFinished {
                // Prefer the captured key; fall back to the live provider in case the vault
                // was unlocked after the task was created with a nil key.
                let effectiveKey = vaultKey ?? vaultKeyProvider?()
                if let effectiveKey {
                    await appendShareRecord(
                        shareVaultId: state.shareVaultId,
                        policy: state.policy,
                        shareKeyData: state.shareKeyData,
                        vaultKey: effectiveKey
                    )
                    pendingSaveWorkItems[state.jobId]?.cancel()
                    pendingSaveWorkItems[state.jobId] = nil
                    pendingStateByJobId.removeValue(forKey: state.jobId)
                    Self.clearPendingUpload(jobId: state.jobId)
                    removeJob(jobId: state.jobId)
                    LocalNotificationManager.shared.sendUploadComplete()
                } else {
                    updateJob(jobId: state.jobId) { job in
                        job.status = .paused
                        job.progress = max(job.progress, 99)
                        job.message = "Uploaded. Finalizing when vault unlocks..."
                        job.errorMessage = nil
                    }
                    updatePendingProgress(
                        jobId: state.jobId,
                        progress: 99,
                        message: "Uploaded. Finalizing when vault unlocks..."
                    )
                    scheduleBackgroundResumeTask(earliestIn: 120)
                }
                return
            }

            let svdfURL = Self.svdfURL(jobId: state.jobId)
            guard FileManager.default.fileExists(atPath: svdfURL.path) else {
                throw CloudKitSharingError.invalidData
            }

            updateJob(jobId: state.jobId) { job in
                job.status = .uploading
                job.progress = max(job.progress, 2)
                job.message = "Checking uploaded chunks..."
                job.errorMessage = nil
            }
            updatePendingProgress(jobId: state.jobId, progress: 2, message: "Checking uploaded chunks...")

            let existingIndices = try await cloudKit.existingChunkIndices(for: state.shareVaultId)
            let missingIndices = (0..<state.totalChunks).filter { !existingIndices.contains($0) }

            updateJob(jobId: state.jobId) { job in
                job.status = .uploading
                job.progress = max(job.progress, 5)
                job.message = "Uploading remaining chunks..."
                job.errorMessage = nil
            }
            updatePendingProgress(jobId: state.jobId, progress: 5, message: "Uploading remaining chunks...")

            try await cloudKit.uploadChunksFromFile(
                shareVaultId: state.shareVaultId,
                fileURL: svdfURL,
                chunkIndices: missingIndices,
                onProgress: { [weak self] current, total in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let pct = total > 0 ? 5 + (84 * current / total) : 89
                        self.updateJob(jobId: state.jobId) { job in
                            job.status = .uploading
                            job.progress = max(job.progress, pct)
                            job.message = "Uploading remaining chunks..."
                            job.errorMessage = nil
                        }
                        self.updatePendingProgress(jobId: state.jobId, progress: pct, message: "Uploading remaining chunks...")
                    }
                }
            )

            try await cloudKit.saveManifest(
                shareVaultId: state.shareVaultId,
                phraseVaultId: state.phraseVaultId,
                shareKey: ShareKey(state.shareKeyData),
                policy: state.policy,
                ownerFingerprint: state.ownerFingerprint,
                totalChunks: state.totalChunks
            )
            markPendingUploadFinished(jobId: state.jobId)

            updateJob(jobId: state.jobId) { job in
                job.status = .finalizing
                job.progress = 95
                job.message = "Finalizing..."
            }
            updatePendingProgress(jobId: state.jobId, progress: 95, message: "Finalizing...")

            let keyFingerprint = vaultKey?.rawBytes.hashValue ?? 0
            try await Task.detached(priority: .utility) {
                let syncCache = ShareSyncCache(shareVaultId: state.shareVaultId, vaultKeyFingerprint: String(keyFingerprint))
                try syncCache.saveSVDF(from: svdfURL)
                let chunkHashes = try ShareSyncCache.computeChunkHashes(from: svdfURL)
                let fileSize = Self.fileSize(of: svdfURL)

                let syncState = ShareSyncCache.SyncState(
                    syncedFileIds: Set(state.sharedFileIds),
                    chunkHashes: chunkHashes,
                    manifest: state.svdfManifest,
                    syncSequence: 1,
                    deletedFileIds: [],
                    totalDeletedBytes: 0,
                    totalBytes: fileSize
                )
                try syncCache.saveSyncState(syncState)
            }.value

            let effectiveKey2 = vaultKey ?? vaultKeyProvider?()
            if let effectiveKey2 {
                await appendShareRecord(
                    shareVaultId: state.shareVaultId,
                    policy: state.policy,
                    shareKeyData: state.shareKeyData,
                    vaultKey: effectiveKey2
                )
            } else {
                updateJob(jobId: state.jobId) { job in
                    job.status = .paused
                    job.progress = max(job.progress, 99)
                    job.message = "Uploaded. Finalizing when vault unlocks..."
                    job.errorMessage = nil
                }
                updatePendingProgress(
                    jobId: state.jobId,
                    progress: 99,
                    message: "Uploaded. Finalizing when vault unlocks..."
                )
                scheduleBackgroundResumeTask(earliestIn: 120)
                return
            }

            pendingSaveWorkItems[state.jobId]?.cancel()
            pendingSaveWorkItems[state.jobId] = nil
            pendingStateByJobId.removeValue(forKey: state.jobId)
            Self.clearPendingUpload(jobId: state.jobId)

            removeJob(jobId: state.jobId)

            LocalNotificationManager.shared.sendUploadComplete()
        } catch is CancellationError {
            if terminatedJobIds.contains(state.jobId) {
                return
            }
            if Self.loadPendingUploadState(jobId: state.jobId) != nil {
                updateJob(jobId: state.jobId) { job in
                    job.status = .paused
                    job.message = "Upload paused"
                }
                scheduleBackgroundResumeTask(earliestIn: 30)
            } else {
                updateJob(jobId: state.jobId) { job in
                    job.status = .cancelled
                    job.message = "Upload terminated"
                }
            }
        } catch {
            if terminatedJobIds.contains(state.jobId) {
                return
            }
            EmbraceManager.shared.captureError(error)
            updateJob(jobId: state.jobId) { job in
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.message = "Resume failed"
            }
            updatePendingProgress(jobId: state.jobId, progress: state.lastProgress, message: "Resume failed")
            scheduleBackgroundResumeTask(earliestIn: 30)
            LocalNotificationManager.shared.sendUploadFailed()
        }
    }

    // MARK: - BG task handling

    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        currentBGProcessingTask = task
        scheduleBackgroundResumeTask(earliestIn: 60)

        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Self.logger.warning("[bg-task] Processing task expired — cancelling uploads")
                self.cancelAllRunningUploadsAsInterrupted()
                self.completeBackgroundProcessingTask(success: false)
            }
        }

        // Collect all work that needs to be done
        let pendingUploadStates = Self.loadAllPendingUploadStates()
        let hasSyncs = ShareSyncManager.shared.hasPendingSyncs
        
        guard !pendingUploadStates.isEmpty || hasSyncs else {
            completeBackgroundProcessingTask(success: true)
            return
        }
        
        Self.logger.info("[bg-task] Starting work: \(pendingUploadStates.count) uploads, syncs: \(hasSyncs)")
        
        // Kick off uploads first
        if !pendingUploadStates.isEmpty {
            resumePendingUploads(vaultKey: vaultKeyProvider?(), trigger: "bg_task")
        }
        
        // Kick off syncs
        if hasSyncs {
            ShareSyncManager.shared.resumePendingSyncsIfNeeded(trigger: "bg_task")
        }
        
        // Wait for all work to complete before marking task done
        Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            
            // Poll until all work is done (max 30 seconds of waiting after last activity)
            var lastActivityTime = Date()
            var consecutiveIdleChecks = 0
            
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 500ms
                
                let hasPendingUploads = !Self.loadAllPendingUploadStates().isEmpty
                let hasPendingSyncs = ShareSyncManager.shared.hasPendingSyncs
                let hasRunningUploadTasks = !self.uploadTasks.isEmpty
                
                if !hasPendingUploads && !hasPendingSyncs && !hasRunningUploadTasks {
                    consecutiveIdleChecks += 1
                    // Require 3 consecutive idle checks to ensure stability
                    if consecutiveIdleChecks >= 3 {
                        Self.logger.info("[bg-task] All work completed successfully")
                        self.completeBackgroundProcessingTask(success: true)
                        break
                    }
                } else {
                    consecutiveIdleChecks = 0
                    lastActivityTime = Date()
                }
                
                // Safety timeout: if no activity for 30 seconds, complete anyway
                if Date().timeIntervalSince(lastActivityTime) > 30 {
                    Self.logger.warning("[bg-task] Timeout waiting for work to complete, finishing")
                    self.completeBackgroundProcessingTask(success: !hasPendingUploads && !hasPendingSyncs)
                    break
                }
            }
        }
    }

    private func completeBackgroundProcessingTask(success: Bool) {
        currentBGProcessingTask?.setTaskCompleted(success: success)
        currentBGProcessingTask = nil
    }

    private func completeBackgroundProcessingTaskIfPossible() {
        guard currentBGProcessingTask != nil else { return }
        if uploadTasks.isEmpty {
            completeBackgroundProcessingTask(success: !hasPendingUpload)
        }
    }

    // MARK: - Background execution

    private func ensureBackgroundExecution() {
        guard currentBgTaskId == .invalid else { return }
        currentBgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Self.logger.warning("[upload] Background time expiring — cancelling uploads")
                self.cancelAllRunningUploadsAsInterrupted()
                self.endBackgroundExecution()
            }
        }
    }

    private func endBackgroundExecution() {
        let taskId = currentBgTaskId
        currentBgTaskId = .invalid
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    private func teardownBackgroundExecutionIfIdle() {
        if uploadTasks.isEmpty {
            endBackgroundExecution()
        }
    }

    private func cancelAllRunningUploadsAsInterrupted() {
        let runningIds = Array(uploadTasks.keys)
        for id in runningIds {
            uploadTasks[id]?.cancel()
            updateJob(jobId: id) { job in
                job.status = .failed
                job.errorMessage = "Upload interrupted by iOS background limits"
                job.message = "Upload interrupted"
            }
        }
        scheduleBackgroundResumeTask(earliestIn: 30)
    }

    // MARK: - Job state helpers

    private func upsertJob(_ job: UploadJob) {
        jobsById[job.id] = job
        jobs = jobsById.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id > rhs.id }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func updateJob(jobId: String, mutate: (inout UploadJob) -> Void) {
        guard var job = jobsById[jobId] else { return }
        mutate(&job)
        upsertJob(job)
    }

    private func removeJob(jobId: String) {
        jobsById.removeValue(forKey: jobId)
        jobs = jobsById.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id > rhs.id }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func removeShareRecord(shareVaultId: String, vaultKey: VaultKey) async {
        do {
            var index = try await storage.loadIndex(with: vaultKey)
            guard var shares = index.activeShares else { return }
            let originalCount = shares.count
            shares.removeAll { $0.id == shareVaultId }
            guard shares.count != originalCount else { return }
            index.activeShares = shares.isEmpty ? nil : shares
            try await storage.saveIndex(index, with: vaultKey)
        } catch {
            Self.logger.error("Failed to remove share record for terminated upload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func appendShareRecord(
        shareVaultId: String,
        policy: VaultStorage.SharePolicy,
        shareKeyData: Data,
        vaultKey: VaultKey
    ) async {
        do {
            var index = try await storage.loadIndex(with: vaultKey)
            let exists = index.activeShares?.contains(where: { $0.id == shareVaultId }) ?? false
            if !exists {
                let record = VaultStorage.ShareRecord(
                    id: shareVaultId,
                    createdAt: Date(),
                    policy: policy,
                    lastSyncedAt: Date(),
                    shareKeyData: shareKeyData,
                    syncSequence: 1
                )
                if index.activeShares == nil {
                    index.activeShares = []
                }
                index.activeShares?.append(record)
                try await storage.saveIndex(index, with: vaultKey)
            }
        } catch {
            Self.logger.error("Failed to append share record: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pending persistence

    private func bootstrapJobsFromPendingState() {
        let states = Self.loadAllPendingUploadStates()
        for state in states {
            pendingStateByJobId[state.jobId] = state

            let restored = UploadJob(
                id: state.jobId,
                ownerFingerprint: state.ownerFingerprint,
                createdAt: state.createdAt,
                shareVaultId: state.shareVaultId,
                phrase: nil,
                status: .paused,
                progress: state.lastProgress,
                total: 100,
                message: state.lastMessage,
                errorMessage: nil
            )
            upsertJob(restored)
        }
    }

    /// Tracks pending disk writes to coalesce rapid progress updates.
    private var pendingSaveWorkItems: [String: DispatchWorkItem] = [:]
    private static let saveQueue = DispatchQueue(label: "app.vaultaire.ios.share-upload.save", qos: .utility)

    private func savePendingState(_ state: PendingUploadState, immediate: Bool = false) {
        pendingStateByJobId[state.jobId] = state

        // Always cancel any pending debounced write first — prevents stale data
        // from overwriting a newer immediate write or being written after job cleanup.
        pendingSaveWorkItems[state.jobId]?.cancel()
        pendingSaveWorkItems[state.jobId] = nil

        if immediate {
            // Synchronous write for critical state changes (finish, cancel)
            Self.savePendingStateToDisk(state)
            return
        }

        // Debounced write: coalesce rapid progress updates to at most once per 0.5s per job
        let capturedState = state
        let workItem = DispatchWorkItem {
            Self.savePendingStateToDisk(capturedState)
        }
        pendingSaveWorkItems[state.jobId] = workItem
        Self.saveQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private nonisolated static func savePendingStateToDisk(_ state: PendingUploadState) {
        do {
            try prepareJobDirectory(jobId: state.jobId)
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL(jobId: state.jobId), options: .atomic)
        } catch {
            logger.error("Failed to save pending state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updatePendingProgress(jobId: String, progress: Int, message: String) {
        guard var state = pendingStateByJobId[jobId] else { return }
        state.lastProgress = max(0, min(100, progress))
        state.lastMessage = message
        savePendingState(state)
    }

    private func markPendingUploadFinished(jobId: String) {
        guard var state = pendingStateByJobId[jobId] else { return }
        state.uploadFinished = true
        savePendingState(state, immediate: true)
    }

    private nonisolated static func loadAllPendingUploadStates() -> [PendingUploadState] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: pendingRootDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var states: [PendingUploadState] = []
        for dir in contents where dir.hasDirectoryPath {
            let jobId = dir.lastPathComponent

            // A job directory can exist briefly before state.json is persisted
            // (during initial SVDF preparation). Treat it as in-progress and do
            // not delete it, otherwise we can remove svdf_data.bin mid-upload.
            guard FileManager.default.fileExists(atPath: stateURL(jobId: jobId).path) else {
                continue
            }

            guard let state = loadPendingUploadState(jobId: jobId) else {
                clearPendingUpload(jobId: jobId)
                continue
            }
            states.append(state)
        }
        return states
    }

    private nonisolated static func loadPendingUploadState(jobId: String) -> PendingUploadState? {
        let stateURL = stateURL(jobId: jobId)
        let svdfURL = svdfURL(jobId: jobId)

        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PendingUploadState.self, from: data) else {
            return nil
        }

        guard Date().timeIntervalSince(state.createdAt) < pendingTTL else {
            clearPendingUpload(jobId: jobId)
            return nil
        }

        guard FileManager.default.fileExists(atPath: svdfURL.path) else {
            clearPendingUpload(jobId: jobId)
            return nil
        }

        return state
    }

    private nonisolated static func clearPendingUpload(jobId: String) {
        try? FileManager.default.removeItem(at: jobDirectory(jobId: jobId))
    }

    private nonisolated static func prepareJobDirectory(jobId: String) throws {
        try FileManager.default.createDirectory(
            at: jobDirectory(jobId: jobId),
            withIntermediateDirectories: true
        )
    }

    private nonisolated static func jobDirectory(jobId: String) -> URL {
        pendingRootDir.appendingPathComponent(jobId, isDirectory: true)
    }

    private nonisolated static func stateURL(jobId: String) -> URL {
        jobDirectory(jobId: jobId).appendingPathComponent("state.json")
    }

    private nonisolated static func svdfURL(jobId: String) -> URL {
        jobDirectory(jobId: jobId).appendingPathComponent("svdf_data.bin")
    }

    private nonisolated static func fileSize(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    private nonisolated static func buildInitialUploadArtifacts(
        jobId: String,
        phrase: String,
        vaultKey: VaultKey,
        ownerFingerprint: String,
        storage: VaultStorageProtocol = VaultStorage.shared
    ) async throws -> PreparedUploadArtifacts {
        try Task.checkCancellation()

        let shareKey = ShareKey(try KeyDerivation.deriveShareKey(from: phrase))
        let phraseVaultId = KeyDerivation.shareVaultId(from: phrase)

        let index = try await storage.loadIndex(with: vaultKey)
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }
        let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey.rawBytes)
        let activeFiles = index.files.filter { !$0.isDeleted }

        let metadata = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: ownerFingerprint,
            sharedAt: Date()
        )

        let svdfURL = svdfURL(jobId: jobId)
        try prepareJobDirectory(jobId: jobId)

        // Pre-retrieve all files to temp URLs (async) so the sync SVDFSerializer
        // closure can consume them without needing await.
        struct PreRetrievedFile {
            let entry: VaultStorage.VaultIndex.VaultFileEntry
            let header: CryptoEngine.EncryptedFileHeader
            let plaintextURL: URL
        }

        var preRetrieved: [PreRetrievedFile] = []
        preRetrieved.reserveCapacity(activeFiles.count)
        for entry in activeFiles {
            try Task.checkCancellation()
            let (header, plaintextURL) = try await storage.retrieveFileToTempURL(
                id: entry.fileId,
                with: vaultKey
            )
            preRetrieved.append(PreRetrievedFile(
                entry: entry,
                header: header,
                plaintextURL: plaintextURL
            ))
        }

        // Clean up any remaining temp files on early exit
        var consumedIndices: Set<Int> = []
        defer {
            for (i, file) in preRetrieved.enumerated() where !consumedIndices.contains(i) {
                try? FileManager.default.removeItem(at: file.plaintextURL)
            }
        }

        let svdfResult = try SVDFSerializer.buildFullStreamingFromPlaintext(
            to: svdfURL,
            fileCount: activeFiles.count,
            forEachFile: { i in
                try Task.checkCancellation()
                let retrieved = preRetrieved[i]
                let entry = retrieved.entry
                let header = retrieved.header

                var encryptedThumb: Data? = nil
                if let thumbData = entry.thumbnailData {
                    let decryptedThumb = try CryptoEngine.decrypt(thumbData, with: masterKey)
                    encryptedThumb = try CryptoEngine.encrypt(decryptedThumb, with: shareKey.rawBytes)
                }

                return SVDFSerializer.StreamingSourceFile(
                    id: header.fileId,
                    filename: header.originalFilename,
                    mimeType: header.mimeType,
                    originalSize: Int(header.originalSize),
                    createdAt: header.createdAt,
                    encryptedThumbnail: encryptedThumb,
                    plaintextContentURL: retrieved.plaintextURL,
                    duration: entry.duration
                )
            },
            didWriteFile: { i, file in
                consumedIndices.insert(i)
                try? FileManager.default.removeItem(at: file.plaintextContentURL)
            },
            metadata: metadata,
            shareKey: shareKey.rawBytes
        )

        let fileSize = fileSize(of: svdfURL)
        let chunkSize = 2 * 1024 * 1024
        let totalChunks = max(1, (fileSize + chunkSize - 1) / chunkSize)

        return PreparedUploadArtifacts(
            shareKey: shareKey,
            phraseVaultId: phraseVaultId,
            sharedFileIds: svdfResult.fileIds,
            svdfManifest: svdfResult.manifest,
            totalChunks: totalChunks,
            fileSize: fileSize
        )
    }

    private nonisolated func migrateLegacyPendingIfNeeded() {
        let legacyStateURL = Self.legacyPendingDir.appendingPathComponent("state.json")
        let legacySVDFURL = Self.legacyPendingDir.appendingPathComponent("svdf_data.bin")
        guard FileManager.default.fileExists(atPath: legacyStateURL.path),
              FileManager.default.fileExists(atPath: legacySVDFURL.path),
              let data = try? Data(contentsOf: legacyStateURL),
              let legacy = try? JSONDecoder().decode(LegacyPendingUploadState.self, from: data) else {
            return
        }

        let migratedJobId = UUID().uuidString.lowercased()
        let migrated = PendingUploadState(
            jobId: migratedJobId,
            shareVaultId: legacy.shareVaultId,
            phraseVaultId: legacy.phraseVaultId,
            shareKeyData: legacy.shareKeyData,
            policy: legacy.policy,
            ownerFingerprint: legacy.ownerFingerprint,
            totalChunks: legacy.totalChunks,
            sharedFileIds: legacy.sharedFileIds,
            svdfManifest: legacy.svdfManifest,
            createdAt: legacy.createdAt,
            uploadFinished: false,
            lastProgress: 0,
            lastMessage: "Waiting to resume...",
            phrase: nil
        )

        do {
            try Self.prepareJobDirectory(jobId: migratedJobId)
            try JSONEncoder().encode(migrated).write(to: Self.stateURL(jobId: migratedJobId), options: .atomic)
            try FileManager.default.copyItem(at: legacySVDFURL, to: Self.svdfURL(jobId: migratedJobId))
            try? FileManager.default.removeItem(at: legacyStateURL)
            try? FileManager.default.removeItem(at: legacySVDFURL)
            try? FileManager.default.removeItem(at: Self.legacyPendingDir)
            Self.logger.info("Migrated legacy pending upload to job \(migratedJobId, privacy: .public)")
        } catch {
            Self.logger.error("Failed to migrate legacy pending upload: \(error.localizedDescription, privacy: .public)")
        }
    }
}
