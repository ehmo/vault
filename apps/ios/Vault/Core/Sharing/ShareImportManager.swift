import AVFoundation
import Foundation
import os.log
import UIKit

/// Manages background download + import of shared vaults so the UI is not blocked.
/// Keys are captured by value in Task closures, so transfers survive lockVault().
@MainActor
@Observable
final class ShareImportManager {
    static let shared = ShareImportManager()

    /// Keep progress updates smooth while avoiding overly chatty UI updates.
    private static let progressTickIntervalMs = 100
    private static let progressSmoothingTicks = 25
    private nonisolated static let logger = Logger(
        subsystem: "app.vaultaire.ios",
        category: "ShareImport"
    )

    // MARK: - Status

    enum ImportStatus: Equatable {
        case idle
        case importing
        case importComplete
        case importFailed(String)
    }

    // MARK: - Pending Import State (Resumable)

    struct PendingImportState: Codable {
        let shareVaultId: String
        let phrase: String
        let shareKeyData: Data
        let policy: VaultStorage.SharePolicy
        let totalFiles: Int
        var importedFileIds: [String]  // Track which files have been successfully imported
        let shareVaultVersion: Int
        let createdAt: Date
        var isDownloadComplete: Bool  // Track if vault data has been fully downloaded
        var downloadError: String?    // Track download errors for debugging
    }

    // MARK: - Persistence Paths

    /// Uses the same directory as the old BackgroundShareTransferManager
    /// to preserve in-flight import state across the migration.
    private nonisolated static let pendingDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static let importStateURL = pendingDir.appendingPathComponent("import_state.json")
    private nonisolated static let importDataURL = pendingDir.appendingPathComponent("import_data.bin")

    /// 24-hour TTL for pending imports
    private nonisolated static let pendingTTL: TimeInterval = 24 * 60 * 60

    // MARK: - Pending Import Persistence

    nonisolated static func savePendingImport(_ state: PendingImportState, vaultData: Data) throws {
        try JSONEncoder().encode(state).write(to: importStateURL)
        try vaultData.write(to: importDataURL)
    }

    /// Moves a downloaded temp file to `importDataURL` without copying data into memory.
    nonisolated static func savePendingImportFile(from tempURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: importDataURL.path) {
            try fm.removeItem(at: importDataURL)
        }
        try fm.moveItem(at: tempURL, to: importDataURL)
    }

    /// Updates just the state file without rewriting vault data (for progress updates)
    nonisolated static func updatePendingImportState(_ state: PendingImportState) throws {
        try JSONEncoder().encode(state).write(to: importStateURL)
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

    var hasPendingImport: Bool {
        Self.loadPendingImportState() != nil
    }

    /// Returns the pending import state if one exists
    func getPendingImportState() -> PendingImportState? {
        Self.loadPendingImportState()
    }

    // MARK: - Observable State

    var status: ImportStatus = .idle

    private var activeTask: Task<Void, Never>?
    private var currentBgTaskId: UIBackgroundTaskIdentifier = .invalid

    private var targetProgress: Int = 0
    private(set) var displayProgress: Int = 0
    private(set) var currentMessage: String = ""
    private var progressTask: Task<Void, Never>?

    private init() {
        // No-op: singleton
    }

    // MARK: - Background Download + Import

    /// Downloads and imports a shared vault entirely in the background.
    /// Supports resumable imports - if interrupted, will resume from last imported file.
    func startBackgroundDownloadAndImport(
        phrase: String,
        patternKey: VaultKey
    ) {
        activeTask?.cancel()
        status = .importing
        startProgressTimer()

        // Unified progress: download = 0→95%, import = 95→99%
        let downloadWeight = 95
        let importWeight = 4

        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        // Prevent screen from sleeping during download/import
        IdleTimerManager.shared.disable()

        let bgTaskId = beginProtectedTask(logTag: "import")

        // Use Task (not Task.detached) to stay on MainActor and avoid @Observable race conditions
        activeTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            defer {
                // Re-enable idle timer when done
                IdleTimerManager.shared.enable()
                self.finalizeTask(bgTaskId: bgTaskId)
            }

            // Declare variables outside do block so they're accessible in catch
            var pendingImport: PendingImportState? = Self.loadPendingImportState()

            do {
                let shareKey: ShareKey
                var shareVaultId: String
                var policy: VaultStorage.SharePolicy
                var version: Int

                if let pending = pendingImport, pending.isDownloadComplete {
                    // Validate that vault data file exists before attempting resume
                    guard FileManager.default.fileExists(atPath: Self.importDataURL.path) else {
                        Self.logger.error("[import] Vault data file missing for resume - clearing corrupted state")
                        Self.clearPendingImport()
                        throw CloudKitSharingError.invalidData
                    }

                    // Resume from completed download — SVDF file already on disk
                    Self.logger.info("[import] Resuming interrupted import with \(pending.importedFileIds.count)/\(pending.totalFiles) files already imported")
                    shareKey = ShareKey(pending.shareKeyData)
                    shareVaultId = pending.shareVaultId
                    policy = pending.policy
                    version = pending.shareVaultVersion
                    self.setTargetProgress(95, message: "Resuming import...")
                } else {
                    // Fresh download or download was interrupted
                    if let pending = pendingImport {
                        Self.logger.info("[import] Resuming interrupted download for vault \(pending.shareVaultId)")
                    }

                    shareKey = ShareKey(try KeyDerivation.deriveShareKey(from: capturedPhrase))

                    // Download directly to file — no in-memory accumulation
                    var downloadAttempts = 0
                    let maxDownloadAttempts = 3
                    var lastDownloadError: Error?
                    var downloadResult: (fileURL: URL, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int)!

                    let tempDownloadURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("svdf")

                    let downloadProgress: @Sendable (Int, Int) -> Void = { [weak self] current, total in
                        let pct = total > 0 ? downloadWeight * current / total : 0
                        Task { @MainActor [weak self] in
                            self?.setTargetProgress(pct, message: "Downloading shared vault...")
                        }
                    }

                    while downloadAttempts < maxDownloadAttempts {
                        do {
                            downloadResult = try await CloudKitSharingManager.shared.downloadSharedVaultToFile(
                                phrase: capturedPhrase,
                                outputURL: tempDownloadURL,
                                markClaimedOnDownload: false,
                                onProgress: downloadProgress
                            )
                            lastDownloadError = nil
                            break
                        } catch {
                            downloadAttempts += 1
                            lastDownloadError = error
                            Self.logger.warning("[import] Download attempt \(downloadAttempts)/\(maxDownloadAttempts) failed: \(error.localizedDescription)")

                            if downloadAttempts < maxDownloadAttempts {
                                let delay = min(Double(downloadAttempts) * 2.0, 10.0)
                                try? await Task.sleep(for: .seconds(delay))
                            }
                        }
                    }

                    if let error = lastDownloadError {
                        Self.logger.error("[import] Download failed after \(maxDownloadAttempts) attempts: \(error.localizedDescription)")
                        throw error
                    }

                    guard !Task.isCancelled else {
                        Self.logger.info("[import] Download cancelled, will resume on next attempt")
                        try? FileManager.default.removeItem(at: tempDownloadURL)
                        return
                    }

                    shareVaultId = downloadResult.shareVaultId
                    policy = downloadResult.policy
                    version = downloadResult.version

                    // Determine file count from SVDF metadata (no full deserialization)
                    let totalFiles: Int
                    if SVDFSerializer.isSVDFFile(tempDownloadURL) {
                        let (_, manifest, _) = try SVDFSerializer.deserializeStreamingMetadata(
                            from: tempDownloadURL, shareKey: shareKey.rawBytes
                        )
                        totalFiles = manifest.filter { !$0.deleted }.count
                    } else {
                        // Legacy non-SVDF: must load into memory (old, small vaults)
                        let vaultData = try Data(contentsOf: tempDownloadURL)
                        let sharedVault = try SharedVaultData.decode(from: vaultData)
                        totalFiles = sharedVault.files.count
                    }

                    // Move downloaded file to persistent location (no memory copy)
                    try Self.savePendingImportFile(from: tempDownloadURL)

                    pendingImport = PendingImportState(
                        shareVaultId: shareVaultId,
                        phrase: capturedPhrase,
                        shareKeyData: shareKey.rawBytes,
                        policy: policy,
                        totalFiles: totalFiles,
                        importedFileIds: [],
                        shareVaultVersion: version,
                        createdAt: Date(),
                        isDownloadComplete: true,
                        downloadError: nil
                    )
                    try Self.updatePendingImportState(pendingImport!)
                    Self.logger.info("[import] Download complete - saved state with \(totalFiles) files ready to import")
                }

                guard var pendingImportState = pendingImport else {
                    throw CloudKitSharingError.invalidData
                }

                // CRITICAL: Pre-mark vault as shared BEFORE importing any files.
                // This ensures that even if the app crashes during import, any
                // files already stored will have sharing restrictions enforced.
                do {
                    var index = try await VaultStorage.shared.loadIndex(with: capturedPatternKey)
                    let alreadyMarked = (index.isSharedVault == true && index.sharedVaultId == shareVaultId)
                    if !alreadyMarked {
                        index.isSharedVault = true
                        index.sharedVaultId = shareVaultId
                        index.sharePolicy = policy
                        index.openCount = 0
                        index.shareKeyData = shareKey.rawBytes
                        index.sharedVaultVersion = version
                        try await VaultStorage.shared.saveIndex(index, with: capturedPatternKey)
                        Self.logger.info("[import] Pre-marked vault as shared before file import")
                    }
                } catch {
                    Self.logger.error("[import] Failed to pre-mark vault as shared: \(error.localizedDescription)")
                    throw error
                }

                // Mark share as claimed on CloudKit now that the vault is protected locally.
                do {
                    try await CloudKitSharingManager.shared.markShareClaimed(shareVaultId: shareVaultId)
                    Self.logger.info("[import] Share claimed on CloudKit before file import")
                } catch {
                    Self.logger.warning("[import] Failed to mark share claimed before import: \(error.localizedDescription)")
                }

                let alreadyImportedIds = Set(pendingImportState.importedFileIds)

                // Streaming SVDF import: parse from file without loading content into memory
                if SVDFSerializer.isSVDFFile(Self.importDataURL) {
                    let (header, manifest, _) = try SVDFSerializer.deserializeStreamingMetadata(
                        from: Self.importDataURL, shareKey: shareKey.rawBytes
                    )

                    let activeEntries = manifest.filter { !$0.deleted }
                    let entriesToImport = activeEntries.filter { !alreadyImportedIds.contains($0.id) }
                    let fileCount = activeEntries.count

                    Self.logger.info("[import] Streaming import: \(entriesToImport.count) remaining files (\(alreadyImportedIds.count) already done)")

                    for entry in entriesToImport {
                        guard !Task.isCancelled else {
                            try Self.updatePendingImportState(pendingImportState)
                            Self.logger.info("[import] Import interrupted after \(pendingImportState.importedFileIds.count) files - saved state for resume")
                            return
                        }

                        do {
                            // Extract entry metadata (~1KB) — no content loaded
                            let entryMeta = try SVDFSerializer.extractFileEntryMetadata(
                                from: Self.importDataURL, at: entry.offset, size: entry.size, version: header.version
                            )

                            // Stream encrypted content to temp file (256KB chunks)
                            let encryptedTempURL = try SVDFSerializer.extractFileContentToTempURL(
                                from: Self.importDataURL, entry: entryMeta
                            )
                            defer { try? FileManager.default.removeItem(at: encryptedTempURL) }

                            // Streaming decrypt to another temp file
                            let decryptedTempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("dec")
                            defer { try? FileManager.default.removeItem(at: decryptedTempURL) }

                            try CryptoEngine.decryptStagedFileToURL(
                                from: encryptedTempURL, to: decryptedTempURL, with: shareKey.rawBytes
                            )

                            // Resolve thumbnail from file URL (memory-efficient)
                            let thumbnailData = Self.resolveThumbnailFromFile(
                                encryptedThumbnail: entryMeta.encryptedThumbnail,
                                mimeType: entryMeta.mimeType,
                                decryptedFileURL: decryptedTempURL,
                                shareKey: shareKey.rawBytes
                            )

                            // Store from decrypted temp file (streaming encryption into vault blob)
                            _ = try await VaultStorage.shared.storeFileFromURL(
                                decryptedTempURL,
                                filename: entryMeta.filename,
                                mimeType: entryMeta.mimeType,
                                with: capturedPatternKey,
                                options: FileStoreOptions(
                                    thumbnailData: thumbnailData,
                                    duration: entryMeta.duration,
                                    fileId: entryMeta.id,
                                    originalDate: entryMeta.createdAt
                                )
                            )

                            pendingImportState.importedFileIds.append(entryMeta.id.uuidString)
                            try Self.updatePendingImportState(pendingImportState)

                            let totalImported = pendingImportState.importedFileIds.count
                            let pct = downloadWeight + (fileCount > 0 ? importWeight * totalImported / fileCount : importWeight)
                            self.setTargetProgress(pct, message: "Importing files... (\(totalImported)/\(fileCount))")
                            await Task.yield()
                        } catch {
                            let fileIdString = entry.id
                            Self.logger.error("[import] Failed to import file \(fileIdString): \(error.localizedDescription)")

                            guard !fileIdString.isEmpty else {
                                Self.logger.error("[import] Skipping file with empty ID")
                                continue
                            }

                            let nsError = error as NSError
                            let isCriticalError = (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOSPC) ||
                                                (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)

                            if isCriticalError {
                                Self.logger.error("[import] Critical error (disk full) - stopping import: \(error.localizedDescription)")
                                try? Self.updatePendingImportState(pendingImportState)
                                throw error
                            }

                            pendingImportState.importedFileIds.append(fileIdString)
                            pendingImportState.downloadError = "Failed to import file: \(error.localizedDescription)"
                            try? Self.updatePendingImportState(pendingImportState)
                            continue
                        }
                    }
                } else {
                    // Legacy non-SVDF fallback: in-memory path for old, small vaults
                    let vaultData = try Data(contentsOf: Self.importDataURL)
                    let sharedVault = try SharedVaultData.decode(from: vaultData)
                    let fileCount = sharedVault.files.count
                    let filesToImport = sharedVault.files.filter { !alreadyImportedIds.contains($0.id.uuidString) }

                    Self.logger.info("[import] Legacy import: \(filesToImport.count) remaining files (\(alreadyImportedIds.count) already done)")

                    for file in filesToImport {
                        guard !Task.isCancelled else {
                            try Self.updatePendingImportState(pendingImportState)
                            return
                        }

                        do {
                            let (decrypted, thumbnailData) = try autoreleasepool {
                                let decrypted = try CryptoEngine.decryptStaged(file.encryptedContent, with: shareKey.rawBytes)
                                let thumbnailData = Self.resolveThumbnail(
                                    encryptedThumbnail: file.encryptedThumbnail,
                                    mimeType: file.mimeType,
                                    decryptedData: decrypted,
                                    shareKey: shareKey.rawBytes
                                )
                                return (decrypted, thumbnailData)
                            }

                            _ = try await VaultStorage.shared.storeFile(
                                data: decrypted,
                                filename: file.filename,
                                mimeType: file.mimeType,
                                with: capturedPatternKey,
                                thumbnailData: thumbnailData,
                                duration: file.duration,
                                fileId: file.id
                            )

                            pendingImportState.importedFileIds.append(file.id.uuidString)
                            try Self.updatePendingImportState(pendingImportState)

                            let totalImported = pendingImportState.importedFileIds.count
                            let pct = downloadWeight + (fileCount > 0 ? importWeight * totalImported / fileCount : importWeight)
                            self.setTargetProgress(pct, message: "Importing files... (\(totalImported)/\(fileCount))")
                            await Task.yield()
                        } catch {
                            let fileIdString = file.id.uuidString
                            Self.logger.error("[import] Failed to import file \(fileIdString): \(error.localizedDescription)")

                            let nsError = error as NSError
                            let isCriticalError = (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOSPC) ||
                                                (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)

                            if isCriticalError {
                                try? Self.updatePendingImportState(pendingImportState)
                                throw error
                            }

                            pendingImportState.importedFileIds.append(fileIdString)
                            pendingImportState.downloadError = "Failed to import \(file.filename): \(error.localizedDescription)"
                            try? Self.updatePendingImportState(pendingImportState)
                            continue
                        }
                    }
                }

                guard !Task.isCancelled else { return }

                // Sharing metadata was pre-marked before file import.
                // Just ensure version is current and clear pending state.
                var index = try await VaultStorage.shared.loadIndex(with: capturedPatternKey)
                index.sharedVaultVersion = version
                try await VaultStorage.shared.saveIndex(index, with: capturedPatternKey)

                // Clear pending import since we're done
                Self.clearPendingImport()

                self.finishImport(.importComplete)
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("[import] IMPORT FAILED: \(error.localizedDescription, privacy: .public)")
                Self.logger.error("[import] error type: \(String(describing: type(of: error)), privacy: .public)")
                EmbraceManager.shared.captureError(error)

                // CRITICAL: Save partial progress if we have any imported files
                if let pending = pendingImport, !pending.importedFileIds.isEmpty {
                    var pendingWithError = pending
                    pendingWithError.downloadError = error.localizedDescription
                    Self.logger.info("[import] Saving partial progress with \(pendingWithError.importedFileIds.count) files imported before error")
                    do {
                        try Self.updatePendingImportState(pendingWithError)
                    } catch {
                        Self.logger.error("[import] Failed to save partial progress: \(error.localizedDescription)")
                    }
                }

                self.finishImport(.importFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Resume

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

    /// Resolves a thumbnail from a decrypted file URL instead of in-memory Data.
    /// Uses memory-efficient ImageIO downsampling for images, AVAsset for videos.
    nonisolated private static func resolveThumbnailFromFile(
        encryptedThumbnail: Data?,
        mimeType: String,
        decryptedFileURL: URL,
        shareKey: Data
    ) -> Data? {
        // Decrypt encrypted thumbnail if available (small, ~5-30KB)
        if let encThumb = encryptedThumbnail {
            return try? CryptoEngine.decrypt(encThumb, with: shareKey)
        }

        // For images, use memory-efficient ImageIO downsampling
        if mimeType.hasPrefix("image/") {
            return FileUtilities.generateThumbnail(fromFileURL: decryptedFileURL)
        }

        // For videos, use AVAsset directly from file URL (no Data→tempFile round-trip)
        if mimeType.hasPrefix("video/") {
            return generateVideoThumbnailFromFile(url: decryptedFileURL)
        }

        return nil
    }

    /// Generates a thumbnail from a video file URL without loading data into memory.
    nonisolated private static func generateVideoThumbnailFromFile(url: URL) -> Data? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
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

    /// Begins an iOS background task with a standardized expiration handler.
    /// Returns the task ID for capture in defer blocks.
    private func beginProtectedTask(logTag: String) -> UIBackgroundTaskIdentifier {
        endBackgroundExecution()
        let bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor [weak self] in
                Self.logger.warning("[\(logTag)] Background time expiring — cancelling")
                self?.activeTask?.cancel()
                self?.activeTask = nil
                self?.stopProgressTimer()
                self?.status = .importFailed("Import interrupted — iOS suspended the app. Tap to resume.")
                self?.endBackgroundExecution()
            }
        }
        currentBgTaskId = bgTaskId
        return bgTaskId
    }

    private func finalizeTask(bgTaskId: UIBackgroundTaskIdentifier) {
        activeTask = nil
        if currentBgTaskId == bgTaskId {
            endBackgroundExecution()
        } else if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
        }
    }

    /// Finishes an import by stopping the timer, updating status, and firing local notifications.
    private func finishImport(_ newStatus: ImportStatus) {
        stopProgressTimer()
        status = newStatus
        if case .importComplete = newStatus {
            LocalNotificationManager.shared.sendImportComplete()
        } else if case .importFailed = newStatus {
            LocalNotificationManager.shared.sendImportFailed()
        }
    }

    // MARK: - Control

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        stopProgressTimer()
        status = .idle
        endBackgroundExecution()
    }

    func reset() {
        status = .idle
    }
}
