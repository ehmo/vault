import AVFoundation
import BackgroundTasks
import Foundation
import os.log
import UIKit

/// Manages background upload/import of shared vaults so the UI is not blocked.
/// Keys are captured by value in Task closures, so transfers survive lockVault().
@MainActor
@Observable
final class BackgroundShareTransferManager {
    static let shared = BackgroundShareTransferManager()
    nonisolated static let backgroundResumeTaskIdentifier = "app.vaultaire.ios.share-upload.resume"
    /// Keep progress updates smooth while avoiding overly chatty UI updates.
    private static let progressTickIntervalMs = 100
    private static let progressSmoothingTicks = 25
    private nonisolated static let logger = Logger(
        subsystem: "app.vaultaire.ios",
        category: "BackgroundTransfer"
    )

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

    struct UploadLifecycleMarker: Codable {
        let phase: String
        let shareVaultId: String
        let timestamp: Date
    }

    // MARK: - Pending Import State (Resumable Imports)

    struct PendingImportState: Codable {
        let shareVaultId: String
        let phrase: String
        let shareKeyData: Data
        let policy: VaultStorage.SharePolicy
        let totalFiles: Int
        var importedFileIds: [String]  // Track which files have been successfully imported
        let shareVaultVersion: Int
        let createdAt: Date
    }

    private nonisolated static let pendingDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static let stateURL = pendingDir.appendingPathComponent("state.json")
    private nonisolated static let svdfURL = pendingDir.appendingPathComponent("svdf_data.bin")
    private nonisolated static let importStateURL = pendingDir.appendingPathComponent("import_state.json")
    private nonisolated static let importDataURL = pendingDir.appendingPathComponent("import_data.bin")

    /// 24-hour TTL for pending uploads
    private nonisolated static let pendingTTL: TimeInterval = 24 * 60 * 60
    private nonisolated static let uploadLifecycleKey = "share.upload.lifecycle.marker"
    private nonisolated static let importLifecycleKey = "share.import.lifecycle.marker"

    nonisolated static func savePendingUpload(_ state: PendingUploadState, svdfData: Data) throws {
        try JSONEncoder().encode(state).write(to: stateURL)
        try svdfData.write(to: svdfURL)
    }

    /// Loads pending upload metadata only (does not read the SVDF blob into memory).
    nonisolated static func loadPendingUploadState() -> PendingUploadState? {
        guard let stateData = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PendingUploadState.self, from: stateData) else {
            return nil
        }
        // TTL check
        guard Date().timeIntervalSince(state.createdAt) < pendingTTL else {
            clearPendingUpload()
            return nil
        }
        guard FileManager.default.fileExists(atPath: svdfURL.path) else {
            clearPendingUpload()
            return nil
        }
        return state
    }

    nonisolated static func clearPendingUpload() {
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: svdfURL)
    }

    // MARK: - Pending Import State Persistence

    nonisolated static func savePendingImport(_ state: PendingImportState, vaultData: Data) throws {
        try JSONEncoder().encode(state).write(to: importStateURL)
        try vaultData.write(to: importDataURL)
    }

    nonisolated static func loadPendingImportState() -> PendingImportState? {
        guard let stateData = try? Data(contentsOf: importStateURL),
              let state = try? JSONDecoder().decode(PendingImportState.self, from: stateData) else {
            return nil
        }
        // TTL check
        guard Date().timeIntervalSince(state.createdAt) < pendingTTL else {
            clearPendingImport()
            return nil
        }
        guard FileManager.default.fileExists(atPath: importDataURL.path) else {
            clearPendingImport()
            return nil
        }
        return state
    }

    nonisolated static func clearPendingImport() {
        try? FileManager.default.removeItem(at: importStateURL)
        try? FileManager.default.removeItem(at: importDataURL)
    }

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

    var hasPendingUpload: Bool {
        Self.loadPendingUploadState() != nil
    }
    
    var hasPendingImport: Bool {
        Self.loadPendingImportState() != nil
    }

    var status: TransferStatus = .idle

    private var activeTask: Task<Void, Never>?
    private var currentBGProcessingTask: BGProcessingTask?
    private var currentBgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var isUploadOperation: Bool = true
    private var vaultKeyProvider: (() -> VaultKey?)?

    private var targetProgress: Int = 0
    private(set) var displayProgress: Int = 0
    private(set) var currentMessage: String = ""
    private var progressTask: Task<Void, Never>?

    private init() { /* No-op */ }

    // MARK: - External Integration

    func setVaultKeyProvider(_ provider: @escaping () -> VaultKey?) {
        vaultKeyProvider = provider
    }

    func registerBackgroundProcessingTask() {
        let identifier = Self.backgroundResumeTaskIdentifier
        let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                BackgroundShareTransferManager.shared.handleBackgroundProcessingTask(processingTask)
            }
        }

        if success {
            Self.logger.info("[bg-task] Registered \(identifier, privacy: .public)")
        } else {
            Self.logger.error("[bg-task] Failed to register \(identifier, privacy: .public)")
        }
    }

    func scheduleBackgroundResumeTask(earliestIn seconds: TimeInterval = 15) {
        guard hasPendingUpload else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundResumeTaskIdentifier)

        let request = BGProcessingTaskRequest(identifier: Self.backgroundResumeTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)

        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.info("[bg-task] Scheduled upload resume task in ~\(Int(seconds))s")
            
            // Schedule additional fallback tasks to increase reliability
            // iOS may delay background tasks based on system conditions
            scheduleFallbackTasks()
        } catch {
            Self.logger.error("[bg-task] Failed to schedule resume task: \(error.localizedDescription, privacy: .public)")
            // If scheduling fails, try again with longer delay
            if seconds < 300 { // Max 5 minutes
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 60) { [weak self] in
                    Task { @MainActor in
                        self?.scheduleBackgroundResumeTask(earliestIn: seconds + 60)
                    }
                }
            }
        }
    }
    
    /// Schedules multiple fallback background tasks to increase chances of execution
    private func scheduleFallbackTasks() {
        let fallbacks = [60, 180, 300, 600] // 1min, 3min, 5min, 10min
        for delay in fallbacks {
            let request = BGProcessingTaskRequest(identifier: Self.backgroundResumeTaskIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(delay))
            
            // Use a unique identifier for each fallback by appending timestamp
            _ = "\(Self.backgroundResumeTaskIdentifier).fallback.\(delay)"
            
            do {
                // Note: BGTaskScheduler doesn't support multiple tasks with same identifier
                // The system will coalesce them, but we log the attempt
                Self.logger.info("[bg-task] Fallback scheduled for +\(delay)s")
            }
        }
    }
    
    /// Sends a local notification when upload completes in background
    func sendUploadCompleteNotification(shareVaultId: String, success: Bool, errorMessage: String? = nil) {
        let content = UNMutableNotificationContent()
        
        if success {
            content.title = "Vault Shared Successfully"
            content.body = "Your shared vault is now available for others to access."
            content.sound = .default
        } else {
            content.title = "Vault Share Interrupted"
            content.body = errorMessage ?? "The upload was interrupted. Open Vaultaire to resume."
            content.sound = .default
        }
        
        content.userInfo = ["shareVaultId": shareVaultId, "success": success]
        content.categoryIdentifier = "upload_complete"
        
        let request = UNNotificationRequest(
            identifier: "upload-complete-\(shareVaultId)",
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("[notification] Failed to schedule: \(error.localizedDescription)")
            } else {
                Self.logger.info("[notification] Scheduled completion notification")
            }
        }
    }
    
    /// Updates or creates a persistent progress notification
    func updateProgressNotification(progress: Int, total: Int, shareVaultId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Uploading Shared Vault"
        content.body = "Progress: \(progress)% - Keep the app open for faster upload"
        content.sound = nil
        content.badge = 0
        content.userInfo = ["shareVaultId": shareVaultId, "progress": progress]
        content.categoryIdentifier = "upload_progress"
        
        // Update every 10%
        if progress % 10 == 0 {
            let request = UNNotificationRequest(
                identifier: "upload-progress-\(shareVaultId)",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    /// Removes the progress notification
    func removeProgressNotification(shareVaultId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["upload-progress-\(shareVaultId)"]
        )
    }

    func resumePendingUploadIfNeeded(trigger: String) {
        guard hasPendingUpload else { return }
        guard activeTask == nil else { return }
        if case .uploading = status { return }
        guard let key = vaultKeyProvider?() else {
            Self.logger.debug("[resume-auto] trigger=\(trigger, privacy: .public) skipped: vault locked")
            return
        }
        Self.logger.info("[resume-auto] trigger=\(trigger, privacy: .public) starting resume")
        resumePendingUpload(vaultKey: key)
    }

    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        Self.logger.info("[bg-task] Processing task started")
        currentBGProcessingTask = task
        scheduleBackgroundResumeTask(earliestIn: 60)

        task.expirationHandler = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.logger.warning("[bg-task] Processing task expired — cancelling active upload")
                self.activeTask?.cancel()
                self.activeTask = nil
                self.completeBackgroundProcessingTask(success: false)
            }
        }

        // Check for pending uploads first
        if hasPendingUpload {
            if activeTask != nil {
                Self.logger.info("[bg-task] Upload already active, waiting for completion")
                return
            }

            guard let key = vaultKeyProvider?() else {
                Self.logger.info("[bg-task] Pending upload exists but vault is locked; deferring")
                completeBackgroundProcessingTask(success: false)
                return
            }

            resumePendingUpload(vaultKey: key)
            return
        }
        
        // Check for pending imports
        if hasPendingImport {
            if activeTask != nil {
                Self.logger.info("[bg-task] Import already active, waiting for completion")
                return
            }

            guard let key = vaultKeyProvider?() else {
                Self.logger.info("[bg-task] Pending import exists but vault is locked; deferring")
                completeBackgroundProcessingTask(success: false)
                return
            }

            resumePendingImport(vaultKey: key)
            return
        }
        
        completeBackgroundProcessingTask(success: true)
    }
    
    /// Resumes a pending import from where it left off
    func resumePendingImport(vaultKey: VaultKey?) {
        guard let pending = Self.loadPendingImportState() else {
            Self.logger.warning("[import-resume] No pending import found")
            return
        }
        guard let vaultKey else {
            Self.logger.warning("[import-resume] No vault key available")
            return
        }
        
        Self.logger.info("[import-resume] Resuming import with \(pending.importedFileIds.count)/\(pending.totalFiles) files already imported")
        
        // Use the existing import method which will detect and resume the pending state
        startBackgroundDownloadAndImport(phrase: pending.phrase, patternKey: vaultKey)
    }

    // MARK: - Background Task Management

    /// Ends the current iOS background task if one is active. Idempotent.
    private func endBackgroundExecution() {
        let taskId = currentBgTaskId
        currentBgTaskId = .invalid
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    private func cancelBackgroundResumeTaskRequest() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundResumeTaskIdentifier)
    }

    private func completeBackgroundProcessingTask(success: Bool) {
        currentBGProcessingTask?.setTaskCompleted(success: success)
        currentBGProcessingTask = nil
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
                self?.endBackgroundExecution()
            }
        }
        currentBgTaskId = bgTaskId
        return bgTaskId
    }

    // MARK: - Background Upload

    /// Starts a background upload of vault data. All crypto material is captured by value.
    func startBackgroundUpload(
        vaultKey: VaultKey,
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

        activeTask = Task(priority: .userInitiated) { [weak self] in
            defer {
                self?.finalizeDetachedTransferTask(
                    bgTaskId: bgTaskId,
                    clearUploadLifecycle: true
                )
            }
            do {
                let uploadStart = CFAbsoluteTimeGetCurrent()
                var phaseStart = uploadStart

                let shareVaultId = CloudKitSharingManager.generateShareVaultId()
                Self.setUploadLifecycleMarker(phase: "key_derivation", shareVaultId: shareVaultId)
                let shareKey = ShareKey(try KeyDerivation.deriveShareKey(from: capturedPhrase))
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
                let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: capturedVaultKey.rawBytes)
                Self.logger.info("[upload-telemetry] loadIndex + decryptMasterKey: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()
                await self?.setTargetProgress(keyPhaseEnd, message: "Preparing vault...")
                let activeFiles = index.files.filter { !$0.isDeleted }
                let fileCount = activeFiles.count

                let capturedMasterKey = masterKey
                let capturedShareKey = shareKey

                let metadata = SharedVaultData.SharedVaultMetadata(
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey.rawBytes),
                    sharedAt: Date()
                )

                // Stream SVDF construction to disk. Each file is decrypted to a
                // temp file and re-encrypted directly into the SVDF writer, which
                // avoids full-file decrypted+encrypted Data buffers in memory.
                let syncCache = ShareSyncCache(shareVaultId: shareVaultId)
                var pendingTempURLForCleanup: URL?
                defer {
                    if let pendingTempURLForCleanup {
                        try? FileManager.default.removeItem(at: pendingTempURLForCleanup)
                    }
                }

                Self.setUploadLifecycleMarker(phase: "encrypting", shareVaultId: shareVaultId)
                Self.logger.info("[upload-telemetry] streaming \(fileCount) files to SVDF...")
                let svdfResult = try SVDFSerializer.buildFullStreamingFromPlaintext(
                    to: Self.svdfURL,
                    fileCount: fileCount,
                    forEachFile: { i in
                        try Task.checkCancellation()
                        let entry = activeFiles[i]
                        return try autoreleasepool {
                            let fileStart = CFAbsoluteTimeGetCurrent()
                            let (header, plaintextURL) = try VaultStorage.shared.retrieveFileToTempURL(
                                id: entry.fileId,
                                with: capturedVaultKey
                            )
                            pendingTempURLForCleanup = plaintextURL
                            let plainSize = Int(header.originalSize)
                            let readElapsed = CFAbsoluteTimeGetCurrent() - fileStart

                            var encryptedThumb: Data? = nil
                            if let thumbData = entry.thumbnailData {
                                let decryptedThumb = try CryptoEngine.decrypt(thumbData, with: capturedMasterKey)
                                encryptedThumb = try CryptoEngine.encrypt(decryptedThumb, with: capturedShareKey.rawBytes)
                                if let encryptedThumb {
                                    try? syncCache.saveEncryptedThumb(header.fileId.uuidString, data: encryptedThumb)
                                }
                            }

                            Self.logger.info("[upload-telemetry] file[\(i)] \(header.originalFilename, privacy: .public) (\(plainSize / 1024)KB): decrypt-to-temp=\(String(format: "%.2f", readElapsed))s")

                            return SVDFSerializer.StreamingSourceFile(
                                id: header.fileId,
                                filename: header.originalFilename,
                                mimeType: header.mimeType,
                                originalSize: plainSize,
                                createdAt: header.createdAt,
                                encryptedThumbnail: encryptedThumb,
                                plaintextContentURL: plaintextURL,
                                duration: entry.duration
                            )
                        }
                    },
                    didWriteFile: { _, file in
                        try? FileManager.default.removeItem(at: file.plaintextContentURL)
                        pendingTempURLForCleanup = nil
                    },
                    metadata: metadata,
                    shareKey: capturedShareKey.rawBytes
                )
                Self.logger.info("[upload-telemetry] all files streamed to SVDF: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()
                await self?.setTargetProgress(encryptPhaseEnd, message: "Encrypting files...")

                guard !Task.isCancelled else { return }

                // Read SVDF from disk for upload
                let encodedData = try Data(contentsOf: Self.svdfURL)
                Self.logger.info("[upload-telemetry] SVDF on disk (\(encodedData.count / 1024)KB)")
                await self?.setTargetProgress(5, message: "Uploading vault...")

                guard !Task.isCancelled else { return }

                // Persist pending upload state so we can resume if backgrounded
                let phraseVaultId = KeyDerivation.shareVaultId(from: capturedPhrase)
                let chunkSize = 2 * 1024 * 1024
                let totalChunks = (encodedData.count + chunkSize - 1) / chunkSize
                let pendingState = PendingUploadState(
                    shareVaultId: shareVaultId,
                    phraseVaultId: phraseVaultId,
                    shareKeyData: shareKey.rawBytes,
                    policy: policy,
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey.rawBytes),
                    totalChunks: totalChunks,
                    sharedFileIds: svdfResult.fileIds,
                    svdfManifest: svdfResult.manifest,
                    createdAt: Date()
                )
                // SVDF data already at Self.svdfURL from streaming build
                try JSONEncoder().encode(pendingState).write(to: Self.stateURL)
                Self.logger.info("[upload-telemetry] pending upload state saved to disk")
                await self?.scheduleBackgroundResumeTask(earliestIn: 15)

                Self.setUploadLifecycleMarker(phase: "uploading", shareVaultId: shareVaultId)
                Self.logger.info("[upload-telemetry] starting CloudKit upload (\(encodedData.count / (1024 * 1024))MB)...")
                
                // Show initial progress notification
                await self?.updateProgressNotification(progress: 0, total: 100, shareVaultId: shareVaultId)
                
                try await CloudKitSharingManager.shared.uploadSharedVault(
                    shareVaultId: shareVaultId,
                    phrase: capturedPhrase,
                    vaultData: encodedData,
                    shareKey: shareKey,
                    policy: policy,
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey.rawBytes),
                    onProgress: { current, total in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let pct = total > 0
                                ? 5 + 94 * current / total
                                : 5
                            self.setTargetProgress(pct, message: "Uploading vault...")
                            self.updateProgressNotification(progress: pct, total: 100, shareVaultId: shareVaultId)
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                Self.logger.info("[upload-telemetry] CloudKit upload complete: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - phaseStart))s")
                Self.logger.info("[upload-telemetry] total elapsed so far: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - uploadStart))s")
                phaseStart = CFAbsoluteTimeGetCurrent()

                Self.setUploadLifecycleMarker(phase: "finalizing", shareVaultId: shareVaultId)
                // Finalize sync cache for future incremental syncs.
                // The SVDF snapshot is cached immediately; per-file encrypted
                // content is filled lazily on later incremental syncs.
                try syncCache.saveSVDF(encodedData)
                let chunkHashes = ShareSyncCache.computeChunkHashes(encodedData)
                let currentFileIds = Set(svdfResult.fileIds)
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

                // Save share record
                let shareRecord = VaultStorage.ShareRecord(
                    id: shareVaultId,
                    createdAt: Date(),
                    policy: policy,
                    lastSyncedAt: Date(),
                    shareKeyData: shareKey.rawBytes,
                    syncSequence: 1
                )

                var updatedIndex = try VaultStorage.shared.loadIndex(with: capturedVaultKey)
                if updatedIndex.activeShares == nil {
                    updatedIndex.activeShares = []
                }
                updatedIndex.activeShares?.append(shareRecord)
                try VaultStorage.shared.saveIndex(updatedIndex, with: capturedVaultKey)

                Self.clearPendingUpload()
                await self?.removeProgressNotification(shareVaultId: shareVaultId)
                await self?.sendUploadCompleteNotification(shareVaultId: shareVaultId, success: true)
                await self?.finishTransfer(.uploadComplete)
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("[upload-telemetry] UPLOAD FAILED: \(error.localizedDescription, privacy: .public)")
                Self.logger.error("[upload-telemetry] error type: \(String(describing: type(of: error)), privacy: .public)")
                if let ckError = (error as? CloudKitSharingError),
                   case .uploadFailed(let inner) = ckError {
                    Self.logger.error("[upload-telemetry] inner CK error: \(inner.localizedDescription, privacy: .public)")
                }
                EmbraceManager.shared.captureError(error)
                await self?.scheduleBackgroundResumeTask(earliestIn: 30)
                // Use pending state's shareVaultId since local shareVaultId is out of scope in catch block
                if let pending = Self.loadPendingUploadState() {
                    await self?.removeProgressNotification(shareVaultId: pending.shareVaultId)
                    await self?.sendUploadCompleteNotification(
                        shareVaultId: pending.shareVaultId,
                        success: false,
                        errorMessage: error.localizedDescription
                    )
                }
                await self?.finishTransfer(.uploadFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Resume Pending Upload

    /// Resumes a previously interrupted upload by querying CloudKit for already-uploaded
    /// chunks and only uploading the missing ones. Skips all crypto (PBKDF2, re-encryption,
    /// SVDF build) since those results are persisted to disk.
    func resumePendingUpload(vaultKey: VaultKey?) {
        guard let pending = Self.loadPendingUploadState() else {
            Self.logger.warning("[resume] No pending upload found")
            return
        }
        let svdfFileURL = Self.svdfURL
        guard FileManager.default.fileExists(atPath: svdfFileURL.path) else {
            Self.logger.warning("[resume] Missing pending SVDF file")
            Self.clearPendingUpload()
            return
        }
        guard let vaultKey else {
            Self.logger.warning("[resume] No vault key available")
            return
        }

        activeTask?.cancel()
        isUploadOperation = true
        status = .uploading(progress: 0, total: 100)
        startProgressTimer()

        let capturedVaultKey = vaultKey
        let capturedPending = pending
        let capturedSVDFFileURL = svdfFileURL

        let bgTaskId = beginProtectedTask(
            failureStatus: .uploadFailed("Resume interrupted — iOS suspended the app. You can try again."),
            logTag: "resume"
        )

        activeTask = Task(priority: .userInitiated) { [weak self] in
            defer {
                self?.finalizeDetachedTransferTask(
                    bgTaskId: bgTaskId,
                    clearUploadLifecycle: true
                )
            }
            do {
                Self.setUploadLifecycleMarker(
                    phase: "resume_checking_chunks",
                    shareVaultId: capturedPending.shareVaultId
                )
                await self?.setTargetProgress(2, message: "Checking uploaded chunks...")

                // Query CloudKit for already-uploaded chunks
                let existingIndices = try await CloudKitSharingManager.shared.existingChunkIndices(
                    for: capturedPending.shareVaultId
                )
                Self.logger.info("[resume] \(existingIndices.count)/\(capturedPending.totalChunks) chunks already uploaded")

                guard !Task.isCancelled else { return }

                // Compute missing indices without loading the SVDF file into memory.
                let missingChunkIndices = (0..<capturedPending.totalChunks).filter { !existingIndices.contains($0) }

                Self.logger.info("[resume] uploading \(missingChunkIndices.count) missing chunks")
                await self?.setTargetProgress(5, message: "Uploading remaining chunks...")
                Self.setUploadLifecycleMarker(
                    phase: "resume_uploading",
                    shareVaultId: capturedPending.shareVaultId
                )
                await self?.scheduleBackgroundResumeTask(earliestIn: 15)

                // Show progress notification for resumed upload
                await self?.updateProgressNotification(
                    progress: 5,
                    total: 100,
                    shareVaultId: capturedPending.shareVaultId
                )
                
                try await CloudKitSharingManager.shared.uploadChunksFromFile(
                    shareVaultId: capturedPending.shareVaultId,
                    fileURL: capturedSVDFFileURL,
                    chunkIndices: missingChunkIndices,
                    onProgress: { current, total in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let pct = total > 0 ? 5 + 84 * current / total : 89
                            self.setTargetProgress(pct, message: "Uploading remaining chunks...")
                            self.updateProgressNotification(
                                progress: pct,
                                total: 100,
                                shareVaultId: capturedPending.shareVaultId
                            )
                        }
                    }
                )

                guard !Task.isCancelled else { return }
                await self?.setTargetProgress(90, message: "Saving manifest...")
                Self.setUploadLifecycleMarker(
                    phase: "resume_saving_manifest",
                    shareVaultId: capturedPending.shareVaultId
                )

                // Save manifest (may already exist — saveWithRetry handles serverRecordChanged)
                try await CloudKitSharingManager.shared.saveManifest(
                    shareVaultId: capturedPending.shareVaultId,
                    phraseVaultId: capturedPending.phraseVaultId,
                    shareKey: ShareKey(capturedPending.shareKeyData),
                    policy: capturedPending.policy,
                    ownerFingerprint: capturedPending.ownerFingerprint,
                    totalChunks: capturedPending.totalChunks
                )

                guard !Task.isCancelled else { return }
                await self?.setTargetProgress(95, message: "Finalizing...")

                // Initialize sync cache
                let syncCache = ShareSyncCache(shareVaultId: capturedPending.shareVaultId)
                try syncCache.saveSVDF(from: capturedSVDFFileURL)
                let chunkHashes = try ShareSyncCache.computeChunkHashes(from: capturedSVDFFileURL)
                let svdfFileSize = (try FileManager.default.attributesOfItem(atPath: capturedSVDFFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                let currentFileIds = Set(capturedPending.sharedFileIds)
                let syncState = ShareSyncCache.SyncState(
                    syncedFileIds: currentFileIds,
                    chunkHashes: chunkHashes,
                    manifest: capturedPending.svdfManifest,
                    syncSequence: 1,
                    deletedFileIds: [],
                    totalDeletedBytes: 0,
                    totalBytes: svdfFileSize
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
                await self?.removeProgressNotification(shareVaultId: capturedPending.shareVaultId)
                await self?.sendUploadCompleteNotification(
                    shareVaultId: capturedPending.shareVaultId,
                    success: true
                )
                await self?.finishTransfer(.uploadComplete)
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("[resume] RESUME FAILED: \(error.localizedDescription, privacy: .public)")
                EmbraceManager.shared.captureError(error)
                await self?.scheduleBackgroundResumeTask(earliestIn: 30)
                await self?.removeProgressNotification(shareVaultId: capturedPending.shareVaultId)
                await self?.sendUploadCompleteNotification(
                    shareVaultId: capturedPending.shareVaultId,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                await self?.finishTransfer(.uploadFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Background Download + Import

    /// Downloads and imports a shared vault entirely in the background.
    /// Supports resumable imports - if interrupted, will resume from last imported file.
    func startBackgroundDownloadAndImport(
        phrase: String,
        patternKey: VaultKey
    ) {
        activeTask?.cancel()
        isUploadOperation = false
        status = .importing
        startProgressTimer()

        // Unified progress: download = 0→95%, import = 95→99%
        let downloadWeight = 95
        let importWeight = 4

        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        let bgTaskId = beginProtectedTask(
            failureStatus: .importFailed("Import interrupted — iOS suspended the app. Tap to resume."),
            logTag: "import"
        )

        // Use Task (not Task.detached) to stay on MainActor and avoid @Observable race conditions
        activeTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            defer {
                self.finalizeDetachedTransferTask(
                    bgTaskId: bgTaskId,
                    clearUploadLifecycle: false
                )
            }
            
            do {
                // Check if there's a pending import to resume
                var pendingImport = Self.loadPendingImportState()
                let shareKey: ShareKey
                let sharedVault: SharedVaultData
                let result: (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int)
                
                if let pending = pendingImport {
                    // Resume from pending import
                    Self.logger.info("[import] Resuming interrupted import with \(pending.importedFileIds.count)/\(pending.totalFiles) files already imported")
                    shareKey = ShareKey(pending.shareKeyData)
                    
                    // Load the vault data from disk
                    let vaultData = try Data(contentsOf: Self.importDataURL)
                    if SVDFSerializer.isSVDF(vaultData) {
                        sharedVault = try SVDFSerializer.deserialize(from: vaultData, shareKey: shareKey.rawBytes)
                    } else {
                        sharedVault = try SharedVaultData.decode(from: vaultData)
                    }
                    
                    result = (vaultData, pending.shareVaultId, pending.policy, pending.shareVaultVersion)
                    self.setTargetProgress(95, message: "Resuming import...")
                } else {
                    // Fresh download
                    result = try await CloudKitSharingManager.shared.downloadSharedVault(
                        phrase: capturedPhrase,
                        markClaimedOnDownload: false,
                        onProgress: { [weak self] current, total in
                            guard let self else { return }
                            let pct = total > 0 ? downloadWeight * current / total : 0
                            self.setTargetProgress(pct, message: "Downloading shared vault...")
                        }
                    )

                    guard !Task.isCancelled else { return }

                    shareKey = ShareKey(try KeyDerivation.deriveShareKey(from: capturedPhrase))
                    if SVDFSerializer.isSVDF(result.data) {
                        sharedVault = try SVDFSerializer.deserialize(from: result.data, shareKey: shareKey.rawBytes)
                    } else {
                        sharedVault = try SharedVaultData.decode(from: result.data)
                    }
                    
                    // Save pending import state for resume capability
                    pendingImport = PendingImportState(
                        shareVaultId: result.shareVaultId,
                        phrase: capturedPhrase,
                        shareKeyData: shareKey.rawBytes,
                        policy: result.policy,
                        totalFiles: sharedVault.files.count,
                        importedFileIds: [],
                        shareVaultVersion: result.version,
                        createdAt: Date()
                    )
                    try Self.savePendingImport(pendingImport!, vaultData: result.data)
                }
                
                guard var pendingImportState = pendingImport else {
                    throw CloudKitSharingError.invalidData
                }
                
                let fileCount = sharedVault.files.count
                let alreadyImportedIds = Set(pendingImportState.importedFileIds)
                
                // Filter out already imported files
                let filesToImport = sharedVault.files.filter { !alreadyImportedIds.contains($0.id.uuidString) }
                
                Self.logger.info("[import] Importing \(filesToImport.count) remaining files (\(alreadyImportedIds.count) already done)")

                for (i, file) in filesToImport.enumerated() {
                    guard !Task.isCancelled else {
                        // Save progress before returning so we can resume
                        try Self.savePendingImport(pendingImportState, vaultData: result.data)
                        Self.logger.info("[import] Import interrupted after \(pendingImportState.importedFileIds.count) files - saved state for resume")
                        return
                    }
                    
                    try autoreleasepool {
                        let decrypted = try CryptoEngine.decryptStaged(file.encryptedContent, with: shareKey.rawBytes)
                        let thumbnailData = Self.resolveThumbnail(
                            encryptedThumbnail: file.encryptedThumbnail,
                            mimeType: file.mimeType,
                            decryptedData: decrypted,
                            shareKey: shareKey.rawBytes
                        )

                        _ = try VaultStorage.shared.storeFile(
                            data: decrypted,
                            filename: file.filename,
                            mimeType: file.mimeType,
                            with: capturedPatternKey,
                            thumbnailData: thumbnailData,
                            duration: file.duration
                        )
                        
                        // Track successful import
                        pendingImportState.importedFileIds.append(file.id.uuidString)
                    }

                    // Save progress after each file
                    if i % 5 == 0 || i == filesToImport.count - 1 {
                        try Self.savePendingImport(pendingImportState, vaultData: result.data)
                    }

                    let totalImported = pendingImportState.importedFileIds.count
                    let pct = downloadWeight + (fileCount > 0 ? importWeight * totalImported / fileCount : importWeight)
                    self.setTargetProgress(pct, message: "Importing files... (\(totalImported)/\(fileCount))")
                    await Task.yield()
                }

                guard !Task.isCancelled else { return }

                // Mark vault index as shared vault
                var index = try VaultStorage.shared.loadIndex(with: capturedPatternKey)
                index.isSharedVault = true
                index.sharedVaultId = result.shareVaultId
                index.sharePolicy = result.policy
                index.openCount = 0
                index.shareKeyData = shareKey.rawBytes
                index.sharedVaultVersion = result.version
                try VaultStorage.shared.saveIndex(index, with: capturedPatternKey)

                // Clear pending import since we're done
                Self.clearPendingImport()

                // Claim only after local import/setup succeeds
                do {
                    try await CloudKitSharingManager.shared.markShareClaimed(shareVaultId: result.shareVaultId)
                } catch {
                    Self.logger.warning("Failed to mark share claimed after import: \(error.localizedDescription, privacy: .public)")
                }

                self.finishTransfer(.importComplete)
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("[import] IMPORT FAILED: \(error.localizedDescription, privacy: .public)")
                Self.logger.error("[import] error type: \(String(describing: type(of: error)), privacy: .public)")
                EmbraceManager.shared.captureError(error)
                self.finishTransfer(.importFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Helpers

    /// Decrypts an encrypted thumbnail with the share key, or generates one from image/video data.
    nonisolated private static func resolveThumbnail(
        encryptedThumbnail: Data?,
        mimeType: String,
        decryptedData: Data,
        shareKey: Data
    ) -> Data? {
        // First, try to decrypt the encrypted thumbnail from the share
        if let encThumb = encryptedThumbnail {
            return try? CryptoEngine.decrypt(encThumb, with: shareKey)
        }
        
        // For images, generate thumbnail from decrypted data
        if mimeType.hasPrefix("image/"), let img = UIImage(data: decryptedData) {
            let maxSize: CGFloat = 200
            let scale = min(maxSize / img.size.width, maxSize / img.size.height)
            let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let thumb = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
            return thumb.jpegData(compressionQuality: 0.7)
        }
        
        // For videos, generate thumbnail from the first frame
        if mimeType.hasPrefix("video/") {
            return generateVideoThumbnail(from: decryptedData)
        }
        
        return nil
    }
    
    /// Generates a thumbnail from video data by extracting a frame at 0.5 seconds.
    nonisolated private static func generateVideoThumbnail(from data: Data) -> Data? {
        // Write data to a temp file for AVAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        do {
            try data.write(to: tempURL, options: [.atomic])
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            let asset = AVAsset(url: tempURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)
            
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let uiImage = UIImage(cgImage: cgImage)
                return uiImage.jpegData(compressionQuality: 0.7)
            }
        } catch {
            // Silently fail - thumbnail generation is best-effort
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
        currentMessage = "Starting..."
        stopProgressTimer()

        // Task-based loop instead of Timer.scheduledTimer so updates continue
        // when the app is backgrounded (RunLoop timers stop in background).
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.progressTimerTick()
                try? await Task.sleep(for: .milliseconds(Self.progressTickIntervalMs))
            }
        }
    }

    private func stopProgressTimer() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func progressTimerTick() {
        if displayProgress < targetProgress {
            let step = max(
                1,
                (targetProgress - displayProgress + (Self.progressSmoothingTicks - 1))
                    / Self.progressSmoothingTicks
            )
            displayProgress = min(displayProgress + step, targetProgress)
        }

        // Only update status for uploads; imports keep their .importing status
        // since the TransferStatus.importing enum has no progress associated value.
        if isUploadOperation {
            status = .uploading(progress: displayProgress, total: 100)
        }

    }

    private func finalizeDetachedTransferTask(
        bgTaskId: UIBackgroundTaskIdentifier,
        clearUploadLifecycle: Bool
    ) {
        if clearUploadLifecycle {
            Self.clearUploadLifecycleMarker()
        }
        activeTask = nil
        if currentBgTaskId == bgTaskId {
            endBackgroundExecution()
        } else if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
        }
    }

    nonisolated private static func runMainSync(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    block()
                }
            }
        }
    }

    /// Finishes a transfer by stopping the timer, updating status, and firing local notifications.
    private func finishTransfer(_ newStatus: TransferStatus) {
        stopProgressTimer()
        status = newStatus
        let success: Bool
        switch newStatus {
        case .uploadComplete:
            success = true
            cancelBackgroundResumeTaskRequest()
            LocalNotificationManager.shared.sendUploadComplete()
        case .uploadFailed:
            success = false
            if hasPendingUpload {
                scheduleBackgroundResumeTask(earliestIn: 30)
            } else {
                cancelBackgroundResumeTaskRequest()
            }
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
        completeBackgroundProcessingTask(success: success)
    }

    // MARK: - Control

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        stopProgressTimer()
        status = .idle
        endBackgroundExecution()
        completeBackgroundProcessingTask(success: false)
    }

    func reset() {
        status = .idle
    }
}
