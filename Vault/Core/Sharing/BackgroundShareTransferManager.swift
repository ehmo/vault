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

    var status: TransferStatus = .idle

    private var activeTask: Task<Void, Never>?
    private var currentActivity: Activity<TransferActivityAttributes>?

    private var targetProgress: Int = 0
    private var displayProgress: Int = 0
    private var animationStep: Int = 0
    private var currentMessage: String = ""
    private var progressTimer: Timer?

    private init() {}

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

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let shareVaultId = CloudKitSharingManager.generateShareVaultId()
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: capturedPhrase)

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
                await self?.setTargetProgress(keyPhaseEnd, message: "Preparing vault...")
                var sharedFiles: [SharedVaultData.SharedFile] = []
                let activeFiles = index.files.filter { !$0.isDeleted }
                let fileCount = activeFiles.count

                // Process files concurrently: read + re-encrypt in parallel
                let capturedIndex = index
                let capturedMasterKey = masterKey
                let capturedShareKey = shareKey

                sharedFiles = try await withThrowingTaskGroup(
                    of: (Int, SharedVaultData.SharedFile).self
                ) { group in
                    for (i, entry) in activeFiles.enumerated() {
                        group.addTask {
                            let (header, content) = try VaultStorage.shared.retrieveFileContent(
                                entry: entry, index: capturedIndex, masterKey: capturedMasterKey
                            )
                            let reencrypted = try CryptoEngine.encrypt(content, with: capturedShareKey)

                            var encryptedThumb: Data? = nil
                            if let thumbData = entry.thumbnailData {
                                let decryptedThumb = try CryptoEngine.decrypt(thumbData, with: capturedMasterKey)
                                encryptedThumb = try CryptoEngine.encrypt(decryptedThumb, with: capturedShareKey)
                            }

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

                guard !Task.isCancelled else { return }

                let sharedData = SharedVaultData(
                    files: sharedFiles,
                    metadata: SharedVaultData.SharedVaultMetadata(
                        ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey),
                        sharedAt: Date()
                    ),
                    createdAt: Date(),
                    updatedAt: Date()
                )

                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let encodedData = try encoder.encode(sharedData)
                await self?.setTargetProgress(5, message: "Uploading vault...")

                guard !Task.isCancelled else { return }

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

                // Save share record
                let shareRecord = VaultStorage.ShareRecord(
                    id: shareVaultId,
                    createdAt: Date(),
                    policy: policy,
                    lastSyncedAt: Date(),
                    shareKeyData: shareKey
                )

                var updatedIndex = try VaultStorage.shared.loadIndex(with: capturedVaultKey)
                if updatedIndex.activeShares == nil {
                    updatedIndex.activeShares = []
                }
                updatedIndex.activeShares?.append(shareRecord)
                try VaultStorage.shared.saveIndex(updatedIndex, with: capturedVaultKey)

                await MainActor.run {
                    self?.stopProgressTimer()
                    self?.status = .uploadComplete
                    self?.endLiveActivity(success: true, message: "Vault shared successfully")
                    LocalNotificationManager.shared.sendUploadComplete()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.stopProgressTimer()
                    self?.status = .uploadFailed(error.localizedDescription)
                    self?.endLiveActivity(success: false, message: "Upload failed")
                    LocalNotificationManager.shared.sendUploadFailed()
                }
            }
        }
    }

    // MARK: - Background Download + Import

    /// Downloads and imports a shared vault entirely in the background.
    func startBackgroundDownloadAndImport(
        phrase: String,
        patternKey: Data,
        pattern: [Int]
    ) {
        activeTask?.cancel()
        status = .importing
        startLiveActivity(.downloading)
        startProgressTimer()

        // Unified progress: download = 0→95%, import = 95→99%
        let downloadWeight = 95
        let importWeight = 4

        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
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

                await MainActor.run {
                    self?.stopProgressTimer()
                    self?.status = .importComplete
                    self?.endLiveActivity(success: true, message: "Shared vault is ready")
                    LocalNotificationManager.shared.sendImportComplete()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.stopProgressTimer()
                    self?.status = .importFailed(error.localizedDescription)
                    self?.endLiveActivity(success: false, message: "Import failed")
                    LocalNotificationManager.shared.sendImportFailed()
                }
            }
        }
    }

    // MARK: - Background Import

    /// Starts a background import of downloaded vault data. All keys captured by value.
    func startBackgroundImport(
        downloadedData: Data,
        downloadedPolicy: VaultStorage.SharePolicy,
        shareVaultId: String,
        phrase: String,
        patternKey: Data,
        pattern: [Int]
    ) {
        activeTask?.cancel()
        status = .importing
        startLiveActivity(.downloading)
        startProgressTimer()

        // Capture everything by value
        let capturedData = downloadedData
        let capturedPolicy = downloadedPolicy
        let capturedShareVaultId = shareVaultId
        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let sharedVault = try SharedVaultData.decode(from: capturedData)
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

                    let pct = fileCount > 0 ? 99 * (i + 1) / fileCount : 99
                    await self?.setTargetProgress(pct, message: "Importing files...")
                    await Task.yield()
                }

                guard !Task.isCancelled else { return }

                // Mark vault index as shared vault
                var index = try VaultStorage.shared.loadIndex(with: capturedPatternKey)
                index.isSharedVault = true
                index.sharedVaultId = capturedShareVaultId
                index.sharePolicy = capturedPolicy
                index.openCount = 0
                index.shareKeyData = shareKey
                try VaultStorage.shared.saveIndex(index, with: capturedPatternKey)

                await MainActor.run {
                    self?.stopProgressTimer()
                    self?.status = .importComplete
                    self?.endLiveActivity(success: true, message: "Shared vault is ready")
                    LocalNotificationManager.shared.sendImportComplete()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.stopProgressTimer()
                    self?.status = .importFailed(error.localizedDescription)
                    self?.endLiveActivity(success: false, message: "Import failed")
                    LocalNotificationManager.shared.sendImportFailed()
                }
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

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.17, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
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

        status = .uploading(progress: displayProgress, total: 100)

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

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "LiveActivity")

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

    // MARK: - Control

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        stopProgressTimer()
        status = .idle
        endLiveActivity(success: false, message: "Transfer cancelled")
    }

    func reset() {
        status = .idle
    }
}
