import ActivityKit
import Foundation
import os.log
import UIKit

/// Manages background upload/import of shared vaults so the UI is not blocked.
/// Keys are captured by value in Task closures, so transfers survive lockVault().
@MainActor
@Observable
final class BackgroundShareTransferManager {
    static let shared = BackgroundShareTransferManager()

    enum TransferStatus: Equatable {
        case idle
        case uploading(progress: Int, total: Int)
        case uploadComplete
        case uploadFailed(String)
        case importing
        case importComplete
        case importFailed(String)
    }

    // MARK: - Pending Upload State (Resumable Uploads)

    struct PendingUploadState: Codable {
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

    private static let pendingDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let stateURL = pendingDir.appendingPathComponent("state.json")
    private static let svdfURL = pendingDir.appendingPathComponent("svdf_data.bin")

    /// 24-hour TTL for pending uploads
    private static let pendingTTL: TimeInterval = 24 * 60 * 60

    nonisolated static func savePendingUpload(_ state: PendingUploadState, svdfData: Data) throws {
        try JSONEncoder().encode(state).write(to: stateURL)
        try svdfData.write(to: svdfURL)
    }

    nonisolated static func loadPendingUpload() -> (state: PendingUploadState, svdfData: Data)? {
        guard let stateData = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PendingUploadState.self, from: stateData) else {
            return nil
        }
        // TTL check
        guard Date().timeIntervalSince(state.createdAt) < pendingTTL else {
            clearPendingUpload()
            return nil
        }
        guard let svdfData = try? Data(contentsOf: svdfURL) else {
            return nil
        }
        return (state, svdfData)
    }

    nonisolated static func clearPendingUpload() {
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: svdfURL)
    }

    var hasPendingUpload: Bool {
        Self.loadPendingUpload() != nil
    }

    var status: TransferStatus = .idle

    private var activeTask: Task<Void, Never>?
    private var currentActivity: Activity<TransferActivityAttributes>?
    private var currentBgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var isUploadOperation: Bool = true

    private var targetProgress: Int = 0
    private var displayProgress: Int = 0
    private var animationStep: Int = 0
    private var currentMessage: String = ""
    private var progressTimer: Timer?

    private init() {}

    // MARK: - Background Task Management

    /// Ends the current iOS background task if one is active. Idempotent.
    private func endBackgroundExecution() {
        let taskId = currentBgTaskId
        currentBgTaskId = .invalid
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    /// Begins an iOS background task with a standardized expiration handler.
    /// Returns the task ID for capture in defer blocks — this prevents the re-entry
    /// race where a new task's bgTaskId overwrites the property before the old defer runs.
    private func beginProtectedTask(
        failureStatus: TransferStatus,
        logTag: String
    ) -> UIBackgroundTaskIdentifier {
        endBackgroundExecution()
        let bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            MainActor.assumeIsolated {
                Self.logger.warning("[\(logTag)] Background time expiring — cancelling")
                self?.activeTask?.cancel()
                self?.activeTask = nil
                self?.stopProgressTimer()
                self?.status = failureStatus
                self?.endLiveActivity(success: false, message: "\(logTag.capitalized) interrupted")
                self?.endBackgroundExecution()
            }
        }
        currentBgTaskId = bgTaskId
        return bgTaskId
    }

    // MARK: - Background Upload

    /// Starts a background upload of vault data. All crypto material is captured by value.
    func startBackgroundUpload(
        vaultKey: Data,
        phrase: String,
        hasExpiration: Bool,
        expiresAt: Date?,
        hasMaxOpens: Bool,
        maxOpens: Int?,
        allowDownloads: Bool = true
    ) {
        activeTask?.cancel()
        isUploadOperation = true
        status = .uploading(progress: 0, total: 100)
        startLiveActivity(.uploading)
        startProgressTimer()

        // Capture everything by value
        let capturedVaultKey = vaultKey
        let capturedPhrase = phrase
        let capturedHasExpiration = hasExpiration
        let capturedExpiresAt = expiresAt
        let capturedHasMaxOpens = hasMaxOpens
        let capturedMaxOpens = maxOpens
        let capturedAllowDownloads = allowDownloads

        // Capture bgTaskId by value so the defer always ends the correct task,
        // even if a new startBackground* call overwrites currentBgTaskId.
        let bgTaskId = beginProtectedTask(
            failureStatus: .uploadFailed("Upload interrupted — iOS suspended the app. Try again while keeping the app in the foreground."),
            logTag: "upload"
        )

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) }
            }
            do {
                let uploadStart = CFAbsoluteTimeGetCurrent()
                var phaseStart = uploadStart

                let shareVaultId = CloudKitSharingManager.generateShareVaultId()
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: capturedPhrase)
                Self.logger.info("[upload-telemetry] PBKDF2 key derivation: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()

                let policy = VaultStorage.SharePolicy(
                    expiresAt: capturedHasExpiration ? capturedExpiresAt : nil,
                    maxOpens: capturedHasMaxOpens ? capturedMaxOpens : nil,
                    allowScreenshots: false,
                    allowDownloads: capturedAllowDownloads
                )

                // Progress: local processing 0→5%, upload chunks 5→99%
                let keyPhaseEnd = 1
                let encryptPhaseEnd = 5

                // Build vault data
                let index = try VaultStorage.shared.loadIndex(with: capturedVaultKey)
                guard let encryptedMasterKey = index.encryptedMasterKey else {
                    throw VaultStorageError.corruptedData
                }
                let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: capturedVaultKey)
                Self.logger.info("[upload-telemetry] loadIndex + decryptMasterKey: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()
                await self?.setTargetProgress(keyPhaseEnd, message: "Preparing vault...")
                var sharedFiles: [SharedVaultData.SharedFile] = []
                let activeFiles = index.files.filter { !$0.isDeleted }
                let fileCount = activeFiles.count

                // Process files concurrently: read + re-encrypt in parallel
                let capturedIndex = index
                let capturedMasterKey = masterKey
                let capturedShareKey = shareKey

                Self.logger.info("[upload-telemetry] re-encrypting \(fileCount) files...")
                sharedFiles = try await withThrowingTaskGroup(
                    of: (Int, SharedVaultData.SharedFile).self
                ) { group in
                    for (i, entry) in activeFiles.enumerated() {
                        group.addTask {
                            let fileStart = CFAbsoluteTimeGetCurrent()
                            let (header, content) = try VaultStorage.shared.retrieveFileContent(
                                entry: entry, index: capturedIndex, masterKey: capturedMasterKey
                            )
                            let readElapsed = CFAbsoluteTimeGetCurrent() - fileStart
                            let reencrypted = try CryptoEngine.encrypt(content, with: capturedShareKey)
                            let encryptElapsed = CFAbsoluteTimeGetCurrent() - fileStart - readElapsed

                            var encryptedThumb: Data? = nil
                            if let thumbData = entry.thumbnailData {
                                let decryptedThumb = try CryptoEngine.decrypt(thumbData, with: capturedMasterKey)
                                encryptedThumb = try CryptoEngine.encrypt(decryptedThumb, with: capturedShareKey)
                            }

                            Self.logger.info("[upload-telemetry] file[\(i)] \(header.originalFilename, privacy: .public) (\(content.count / 1024)KB): read=\(String(format: "%.2f", readElapsed))s encrypt=\(String(format: "%.2f", encryptElapsed))s")

                            return (i, SharedVaultData.SharedFile(
                                id: header.fileId,
                                filename: header.originalFilename,
                                mimeType: header.mimeType,
                                size: Int(header.originalSize),
                                encryptedContent: reencrypted,
                                createdAt: header.createdAt,
                                encryptedThumbnail: encryptedThumb
                            ))
                        }
                    }

                    var results: [(Int, SharedVaultData.SharedFile)] = []
                    results.reserveCapacity(fileCount)
                    for try await (i, file) in group {
                        results.append((i, file))
                        let encryptRange = encryptPhaseEnd - keyPhaseEnd
                        let pct = fileCount > 0
                            ? keyPhaseEnd + encryptRange * results.count / fileCount
                            : encryptPhaseEnd
                        await self?.setTargetProgress(pct, message: "Encrypting files...")
                    }
                    return results.sorted { $0.0 < $1.0 }.map(\.1)
                }
                Self.logger.info("[upload-telemetry] all files re-encrypted: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()

                guard !Task.isCancelled else { return }

                let metadata = SharedVaultData.SharedVaultMetadata(
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey),
                    sharedAt: Date()
                )

                let svdfResult = try SVDFSerializer.buildFull(
                    files: sharedFiles,
                    metadata: metadata,
                    shareKey: capturedShareKey
                )
                let encodedData = svdfResult.data
                Self.logger.info("[upload-telemetry] SVDF encoding (\(encodedData.count / 1024)KB): \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()
                await self?.setTargetProgress(5, message: "Uploading vault...")

                guard !Task.isCancelled else { return }

                // Persist pending upload state so we can resume if backgrounded
                let phraseVaultId = CloudKitSharingManager.vaultId(from: capturedPhrase)
                let chunkSize = 2 * 1024 * 1024
                let totalChunks = (encodedData.count + chunkSize - 1) / chunkSize
                let pendingState = PendingUploadState(
                    shareVaultId: shareVaultId,
                    phraseVaultId: phraseVaultId,
                    shareKeyData: shareKey,
                    policy: policy,
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey),
                    totalChunks: totalChunks,
                    sharedFileIds: sharedFiles.map { $0.id.uuidString },
                    svdfManifest: svdfResult.manifest,
                    createdAt: Date()
                )
                try Self.savePendingUpload(pendingState, svdfData: encodedData)
                Self.logger.info("[upload-telemetry] pending upload state saved to disk")

                Self.logger.info("[upload-telemetry] starting CloudKit upload (\(encodedData.count / (1024 * 1024))MB)...")
                try await CloudKitSharingManager.shared.uploadSharedVault(
                    shareVaultId: shareVaultId,
                    phrase: capturedPhrase,
                    vaultData: encodedData,
                    shareKey: shareKey,
                    policy: policy,
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey),
                    onProgress: { current, total in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let pct = total > 0
                                ? 5 + 94 * current / total
                                : 5
                            self.setTargetProgress(pct, message: "Uploading vault...")
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                Self.logger.info("[upload-telemetry] CloudKit upload complete: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                Self.logger.info("[upload-telemetry] total elapsed so far: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - uploadStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()

                // Initialize sync cache for future incremental syncs
                let syncCache = ShareSyncCache(shareVaultId: shareVaultId)
                try syncCache.saveSVDF(encodedData)
                let chunkHashes = ShareSyncCache.computeChunkHashes(encodedData)
                let currentFileIds = Set(sharedFiles.map { $0.id.uuidString })
                let syncState = ShareSyncCache.SyncState(
                    syncedFileIds: currentFileIds,
                    chunkHashes: chunkHashes,
                    manifest: svdfResult.manifest,
                    syncSequence: 1,
                    deletedFileIds: [],
                    totalDeletedBytes: 0,
                    totalBytes: encodedData.count
                )
                try syncCache.saveSyncState(syncState)

                // Cache each encrypted file for future incremental syncs
                for file in sharedFiles {
                    try? syncCache.saveEncryptedFile(file.id.uuidString, data: file.encryptedContent)
                    if let thumb = file.encryptedThumbnail {
                        try? syncCache.saveEncryptedThumb(file.id.uuidString, data: thumb)
                    }
                }

                // Save share record
                let shareRecord = VaultStorage.ShareRecord(
                    id: shareVaultId,
                    createdAt: Date(),
                    policy: policy,
                    lastSyncedAt: Date(),
                    shareKeyData: shareKey,
                    syncSequence: 1
                )

                var updatedIndex = try VaultStorage.shared.loadIndex(with: capturedVaultKey)
                if updatedIndex.activeShares == nil {
                    updatedIndex.activeShares = []
                }
                updatedIndex.activeShares?.append(shareRecord)
                try VaultStorage.shared.saveIndex(updatedIndex, with: capturedVaultKey)

                Self.clearPendingUpload()
                await self?.finishTransfer(.uploadComplete, activityMessage: "Vault shared successfully")
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("[upload-telemetry] UPLOAD FAILED: \(error.localizedDescription, privacy: .public)")
                Self.logger.error("[upload-telemetry] error type: \(String(describing: type(of: error)), privacy: .public)")
                if let ckError = (error as? CloudKitSharingError),
                   case .uploadFailed(let inner) = ckError {
                    Self.logger.error("[upload-telemetry] inner CK error: \(inner.localizedDescription, privacy: .public)")
                }
                SentryManager.shared.captureError(error)
                await self?.finishTransfer(.uploadFailed(error.localizedDescription), activityMessage: "Upload failed")
            }
        }
    }

    // MARK: - Resume Pending Upload

    /// Resumes a previously interrupted upload by querying CloudKit for already-uploaded
    /// chunks and only uploading the missing ones. Skips all crypto (PBKDF2, re-encryption,
    /// SVDF build) since those results are persisted to disk.
    func resumePendingUpload(vaultKey: Data?) {
        guard let (pending, svdfData) = Self.loadPendingUpload() else {
            Self.logger.warning("[resume] No pending upload found")
            return
        }
        guard let vaultKey else {
            Self.logger.warning("[resume] No vault key available")
            return
        }

        activeTask?.cancel()
        isUploadOperation = true
        status = .uploading(progress: 0, total: 100)
        startLiveActivity(.uploading)
        startProgressTimer()

        let capturedVaultKey = vaultKey
        let capturedPending = pending
        let capturedSvdfData = svdfData

        let bgTaskId = beginProtectedTask(
            failureStatus: .uploadFailed("Resume interrupted — iOS suspended the app. You can try again."),
            logTag: "resume"
        )

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) }
            }
            do {
                await self?.setTargetProgress(2, message: "Checking uploaded chunks...")

                // Query CloudKit for already-uploaded chunks
                let existingIndices = try await CloudKitSharingManager.shared.existingChunkIndices(
                    for: capturedPending.shareVaultId
                )
                Self.logger.info("[resume] \(existingIndices.count)/\(capturedPending.totalChunks) chunks already uploaded")

                guard !Task.isCancelled else { return }

                // Chunk the SVDF data and filter to missing chunks only
                let chunkSize = 2 * 1024 * 1024
                let allChunks: [(Int, Data)] = stride(from: 0, to: capturedSvdfData.count, by: chunkSize)
                    .enumerated()
                    .map { (index, start) in
                        let end = min(start + chunkSize, capturedSvdfData.count)
                        return (index, Data(capturedSvdfData[start..<end]))
                    }
                let missingChunks = allChunks.filter { !existingIndices.contains($0.0) }

                Self.logger.info("[resume] uploading \(missingChunks.count) missing chunks")
                await self?.setTargetProgress(5, message: "Uploading remaining chunks...")

                try await CloudKitSharingManager.shared.uploadChunksParallel(
                    shareVaultId: capturedPending.shareVaultId,
                    chunks: missingChunks,
                    onProgress: { current, total in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let pct = total > 0 ? 5 + 84 * current / total : 89
                            self.setTargetProgress(pct, message: "Uploading remaining chunks...")
                        }
                    }
                )

                guard !Task.isCancelled else { return }
                await self?.setTargetProgress(90, message: "Saving manifest...")

                // Save manifest (may already exist — saveWithRetry handles serverRecordChanged)
                try await CloudKitSharingManager.shared.saveManifest(
                    shareVaultId: capturedPending.shareVaultId,
                    phraseVaultId: capturedPending.phraseVaultId,
                    shareKey: capturedPending.shareKeyData,
                    policy: capturedPending.policy,
                    ownerFingerprint: capturedPending.ownerFingerprint,
                    totalChunks: capturedPending.totalChunks
                )

                guard !Task.isCancelled else { return }
                await self?.setTargetProgress(95, message: "Finalizing...")

                // Initialize sync cache
                let syncCache = ShareSyncCache(shareVaultId: capturedPending.shareVaultId)
                try syncCache.saveSVDF(capturedSvdfData)
                let chunkHashes = ShareSyncCache.computeChunkHashes(capturedSvdfData)
                let currentFileIds = Set(capturedPending.sharedFileIds)
                let syncState = ShareSyncCache.SyncState(
                    syncedFileIds: currentFileIds,
                    chunkHashes: chunkHashes,
                    manifest: capturedPending.svdfManifest,
                    syncSequence: 1,
                    deletedFileIds: [],
                    totalDeletedBytes: 0,
                    totalBytes: capturedSvdfData.count
                )
                try syncCache.saveSyncState(syncState)

                // Save share record (guard against duplicates)
                var updatedIndex = try VaultStorage.shared.loadIndex(with: capturedVaultKey)
                let alreadyExists = updatedIndex.activeShares?.contains(where: {
                    $0.id == capturedPending.shareVaultId
                }) ?? false
                if !alreadyExists {
                    let shareRecord = VaultStorage.ShareRecord(
                        id: capturedPending.shareVaultId,
                        createdAt: Date(),
                        policy: capturedPending.policy,
                        lastSyncedAt: Date(),
                        shareKeyData: capturedPending.shareKeyData,
                        syncSequence: 1
                    )
                    if updatedIndex.activeShares == nil {
                        updatedIndex.activeShares = []
                    }
                    updatedIndex.activeShares?.append(shareRecord)
                    try VaultStorage.shared.saveIndex(updatedIndex, with: capturedVaultKey)
                }

                Self.clearPendingUpload()
                await self?.finishTransfer(.uploadComplete, activityMessage: "Vault shared successfully")
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("[resume] RESUME FAILED: \(error.localizedDescription, privacy: .public)")
                SentryManager.shared.captureError(error)
                await self?.finishTransfer(.uploadFailed(error.localizedDescription), activityMessage: "Resume failed")
            }
        }
    }

    // MARK: - Background Download + Import

    /// Downloads and imports a shared vault entirely in the background.
    func startBackgroundDownloadAndImport(
        phrase: String,
        patternKey: Data
    ) {
        activeTask?.cancel()
        isUploadOperation = false
        status = .importing
        startLiveActivity(.downloading)
        startProgressTimer()

        // Unified progress: download = 0→95%, import = 95→99%
        let downloadWeight = 95
        let importWeight = 4

        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        let bgTaskId = beginProtectedTask(
            failureStatus: .importFailed("Import interrupted — iOS suspended the app."),
            logTag: "import"
        )

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) }
            }
            do {
                let result = try await CloudKitSharingManager.shared.downloadSharedVault(
                    phrase: capturedPhrase,
                    onProgress: { current, total in
                        Task { @MainActor [weak self] in
                            let pct = total > 0 ? downloadWeight * current / total : 0
                            self?.setTargetProgress(pct, message: "Downloading vault...")
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                let sharedVault = try SharedVaultData.decode(from: result.data)
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: capturedPhrase)
                let fileCount = sharedVault.files.count

                for (i, file) in sharedVault.files.enumerated() {
                    guard !Task.isCancelled else { return }
                    let decrypted = try CryptoEngine.decrypt(file.encryptedContent, with: shareKey)
                    let thumbnailData = Self.resolveThumbnail(
                        encryptedThumbnail: file.encryptedThumbnail,
                        mimeType: file.mimeType,
                        decryptedData: decrypted,
                        shareKey: shareKey
                    )

                    _ = try VaultStorage.shared.storeFile(
                        data: decrypted,
                        filename: file.filename,
                        mimeType: file.mimeType,
                        with: capturedPatternKey,
                        thumbnailData: thumbnailData
                    )

                    let pct = downloadWeight + (fileCount > 0 ? importWeight * (i + 1) / fileCount : importWeight)
                    await self?.setTargetProgress(pct, message: "Importing files...")
                    await Task.yield()
                }

                guard !Task.isCancelled else { return }

                // Mark vault index as shared vault
                var index = try VaultStorage.shared.loadIndex(with: capturedPatternKey)
                index.isSharedVault = true
                index.sharedVaultId = result.shareVaultId
                index.sharePolicy = result.policy
                index.openCount = 0
                index.shareKeyData = shareKey
                index.sharedVaultVersion = result.version
                try VaultStorage.shared.saveIndex(index, with: capturedPatternKey)

                await self?.finishTransfer(.importComplete, activityMessage: "Shared vault is ready")
            } catch {
                guard !Task.isCancelled else { return }
                SentryManager.shared.captureError(error)
                await self?.finishTransfer(.importFailed(error.localizedDescription), activityMessage: "Import failed")
            }
        }
    }

    // MARK: - Helpers

    /// Decrypts an encrypted thumbnail with the share key, or generates one from image data.
    nonisolated private static func resolveThumbnail(
        encryptedThumbnail: Data?,
        mimeType: String,
        decryptedData: Data,
        shareKey: Data
    ) -> Data? {
        if let encThumb = encryptedThumbnail {
            return try? CryptoEngine.decrypt(encThumb, with: shareKey)
        } else if mimeType.hasPrefix("image/"), let img = UIImage(data: decryptedData) {
            let maxSize: CGFloat = 200
            let scale = min(maxSize / img.size.width, maxSize / img.size.height)
            let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let thumb = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
            return thumb.jpegData(compressionQuality: 0.7)
        }
        return nil
    }

    // MARK: - Smooth Progress Timer

    private func setTargetProgress(_ progress: Int, message: String) {
        targetProgress = min(progress, 100)
        currentMessage = message
    }

    private func startProgressTimer() {
        targetProgress = 0
        displayProgress = 0
        animationStep = 0
        currentMessage = "Starting..."
        stopProgressTimer()

        // Timer fires on main RunLoop → guaranteed main thread.
        // MainActor.assumeIsolated avoids Task allocation overhead.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.17, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.progressTimerTick()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func progressTimerTick() {
        animationStep += 1

        if displayProgress < targetProgress {
            let step = max(1, (targetProgress - displayProgress + 4) / 5)
            displayProgress = min(displayProgress + step, targetProgress)
        }

        // Only update status for uploads; imports keep their .importing status
        // since the TransferStatus.importing enum has no progress associated value.
        if isUploadOperation {
            status = .uploading(progress: displayProgress, total: 100)
        }

        let state = TransferActivityAttributes.ContentState(
            progress: displayProgress,
            total: 100,
            message: currentMessage,
            isComplete: false,
            isFailed: false,
            animationStep: animationStep
        )
        Task { await currentActivity?.update(.init(state: state, staleDate: nil)) }
    }

    // MARK: - Live Activity

    private nonisolated static let logger = Logger(subsystem: "app.vaultaire.ios", category: "LiveActivity")

    private func startLiveActivity(_ type: TransferActivityAttributes.TransferType) {
        // End any stale activities from previous runs
        for activity in Activity<TransferActivityAttributes>.activities {
            Self.logger.info("Ending stale activity: \(activity.id, privacy: .public)")
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        let authInfo = ActivityAuthorizationInfo()
        Self.logger.info("areActivitiesEnabled: \(authInfo.areActivitiesEnabled), frequentPushesEnabled: \(authInfo.frequentPushesEnabled)")
        guard authInfo.areActivitiesEnabled else {
            Self.logger.warning("Live Activities not enabled — skipping")
            return
        }
        let attributes = TransferActivityAttributes(transferType: type)
        let state = TransferActivityAttributes.ContentState(
            progress: 0, total: 100, message: "Starting...", isComplete: false, isFailed: false
        )
        let content = ActivityContent(
            state: state,
            staleDate: nil,
            relevanceScore: 100
        )
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            Self.logger.info("Activity started id=\(self.currentActivity?.id ?? "nil", privacy: .public), activityState=\(String(describing: self.currentActivity?.activityState), privacy: .public)")
            Self.logger.info("Total active activities: \(Activity<TransferActivityAttributes>.activities.count)")
        } catch {
            Self.logger.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endLiveActivity(success: Bool, message: String) {
        let activity = currentActivity
        currentActivity = nil
        let state = TransferActivityAttributes.ContentState(
            progress: 0, total: 0, message: message, isComplete: success, isFailed: !success
        )
        Task {
            await activity?.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
        }
    }

    /// Finishes a transfer by stopping the timer, updating status, ending the Live Activity,
    /// and firing the appropriate local notification. Called via `await self?.finishTransfer(...)`.
    private func finishTransfer(_ newStatus: TransferStatus, activityMessage: String) {
        stopProgressTimer()
        status = newStatus
        let success: Bool
        switch newStatus {
        case .uploadComplete:
            success = true
            LocalNotificationManager.shared.sendUploadComplete()
        case .uploadFailed:
            success = false
            LocalNotificationManager.shared.sendUploadFailed()
        case .importComplete:
            success = true
            LocalNotificationManager.shared.sendImportComplete()
        case .importFailed:
            success = false
            LocalNotificationManager.shared.sendImportFailed()
        default:
            success = false
        }
        endLiveActivity(success: success, message: activityMessage)
    }

    // MARK: - Control

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        stopProgressTimer()
        status = .idle
        endLiveActivity(success: false, message: "Transfer cancelled")
        endBackgroundExecution()
    }

    func reset() {
        status = .idle
    }
}
