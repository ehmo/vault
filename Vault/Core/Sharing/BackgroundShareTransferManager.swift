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
        status = .uploading(progress: 0, total: 1)
        startLiveActivity(.uploading)

        // Capture everything by value
        let capturedVaultKey = vaultKey
        let capturedPhrase = phrase
        let capturedHasExpiration = hasExpiration
        let capturedExpiresAt = expiresAt
        let capturedHasMaxOpens = hasMaxOpens
        let capturedMaxOpens = maxOpens
        let capturedAllowDownloads = allowDownloads

        activeTask = Task { [weak self] in
            do {
                let shareVaultId = CloudKitSharingManager.generateShareVaultId()
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: capturedPhrase)

                let policy = VaultStorage.SharePolicy(
                    expiresAt: capturedHasExpiration ? capturedExpiresAt : nil,
                    maxOpens: capturedHasMaxOpens ? capturedMaxOpens : nil,
                    allowScreenshots: false,
                    allowDownloads: capturedAllowDownloads
                )

                // Build vault data
                let index = try VaultStorage.shared.loadIndex(with: capturedVaultKey)
                let masterKey = try CryptoEngine.shared.decrypt(index.encryptedMasterKey!, with: capturedVaultKey)
                var sharedFiles: [SharedVaultData.SharedFile] = []

                for entry in index.files where !entry.isDeleted {
                    let (header, content) = try VaultStorage.shared.retrieveFile(id: entry.fileId, with: capturedVaultKey)
                    let reencrypted = try CryptoEngine.shared.encrypt(content, with: shareKey)

                    // Re-encrypt thumbnail with share key
                    var encryptedThumb: Data? = nil
                    if let thumbData = entry.thumbnailData {
                        let decryptedThumb = try CryptoEngine.shared.decrypt(thumbData, with: masterKey)
                        encryptedThumb = try CryptoEngine.shared.encrypt(decryptedThumb, with: shareKey)
                    }

                    sharedFiles.append(SharedVaultData.SharedFile(
                        id: header.fileId,
                        filename: header.originalFilename,
                        mimeType: header.mimeType,
                        size: Int(header.originalSize),
                        encryptedContent: reencrypted,
                        createdAt: header.createdAt,
                        encryptedThumbnail: encryptedThumb
                    ))
                }

                let sharedData = SharedVaultData(
                    files: sharedFiles,
                    metadata: SharedVaultData.SharedVaultMetadata(
                        ownerFingerprint: KeyDerivation.keyFingerprint(from: capturedVaultKey),
                        sharedAt: Date()
                    ),
                    createdAt: Date(),
                    updatedAt: Date()
                )

                let encodedData = try JSONEncoder().encode(sharedData)

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
                            self.status = .uploading(progress: current, total: total)
                            self.updateLiveActivity(progress: current, total: total, message: "Uploading vault...")
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
                    self?.status = .uploadComplete
                    self?.endLiveActivity(success: true, message: "Vault shared successfully")
                }

                LocalNotificationManager.shared.sendUploadComplete()
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.status = .uploadFailed(error.localizedDescription)
                    self?.endLiveActivity(success: false, message: "Upload failed")
                }
                LocalNotificationManager.shared.sendUploadFailed()
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

        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        activeTask = Task { [weak self] in
            do {
                let result = try await CloudKitSharingManager.shared.downloadSharedVault(
                    phrase: capturedPhrase,
                    onProgress: { _, _ in }
                )

                guard !Task.isCancelled else { return }

                let sharedVault = try JSONDecoder().decode(SharedVaultData.self, from: result.data)
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: capturedPhrase)

                for file in sharedVault.files {
                    guard !Task.isCancelled else { return }
                    let decrypted = try CryptoEngine.shared.decrypt(file.encryptedContent, with: shareKey)

                    var thumbnailData: Data? = nil
                    if let encThumb = file.encryptedThumbnail {
                        thumbnailData = try? CryptoEngine.shared.decrypt(encThumb, with: shareKey)
                    } else if file.mimeType.hasPrefix("image/"), let img = UIImage(data: decrypted) {
                        let maxSize: CGFloat = 200
                        let scale = min(maxSize / img.size.width, maxSize / img.size.height)
                        let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                        let renderer = UIGraphicsImageRenderer(size: newSize)
                        let thumb = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
                        thumbnailData = thumb.jpegData(compressionQuality: 0.7)
                    }

                    _ = try VaultStorage.shared.storeFile(
                        data: decrypted,
                        filename: file.filename,
                        mimeType: file.mimeType,
                        with: capturedPatternKey,
                        thumbnailData: thumbnailData
                    )
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
                    self?.status = .importComplete
                    self?.endLiveActivity(success: true, message: "Shared vault is ready")
                }

                LocalNotificationManager.shared.sendImportComplete()
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.status = .importFailed(error.localizedDescription)
                    self?.endLiveActivity(success: false, message: "Import failed")
                }
                LocalNotificationManager.shared.sendImportFailed()
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

        // Capture everything by value
        let capturedData = downloadedData
        let capturedPolicy = downloadedPolicy
        let capturedShareVaultId = shareVaultId
        let capturedPhrase = phrase
        let capturedPatternKey = patternKey

        activeTask = Task { [weak self] in
            do {
                let sharedVault = try JSONDecoder().decode(SharedVaultData.self, from: capturedData)
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: capturedPhrase)

                for file in sharedVault.files {
                    guard !Task.isCancelled else { return }
                    let decrypted = try CryptoEngine.shared.decrypt(file.encryptedContent, with: shareKey)

                    // Decrypt thumbnail from share key, or generate from image data
                    var thumbnailData: Data? = nil
                    if let encThumb = file.encryptedThumbnail {
                        thumbnailData = try? CryptoEngine.shared.decrypt(encThumb, with: shareKey)
                    } else if file.mimeType.hasPrefix("image/"), let img = UIImage(data: decrypted) {
                        let maxSize: CGFloat = 200
                        let scale = min(maxSize / img.size.width, maxSize / img.size.height)
                        let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                        let renderer = UIGraphicsImageRenderer(size: newSize)
                        let thumb = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
                        thumbnailData = thumb.jpegData(compressionQuality: 0.7)
                    }

                    _ = try VaultStorage.shared.storeFile(
                        data: decrypted,
                        filename: file.filename,
                        mimeType: file.mimeType,
                        with: capturedPatternKey,
                        thumbnailData: thumbnailData
                    )
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
                    self?.status = .importComplete
                    self?.endLiveActivity(success: true, message: "Shared vault is ready")
                }

                LocalNotificationManager.shared.sendImportComplete()
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.status = .importFailed(error.localizedDescription)
                    self?.endLiveActivity(success: false, message: "Import failed")
                }
                LocalNotificationManager.shared.sendImportFailed()
            }
        }
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
            progress: 0, total: 1, message: "Starting...", isComplete: false, isFailed: false
        )
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            Self.logger.info("Activity started id=\(self.currentActivity?.id ?? "nil", privacy: .public), activityState=\(String(describing: self.currentActivity?.activityState), privacy: .public)")
            Self.logger.info("Total active activities: \(Activity<TransferActivityAttributes>.activities.count)")
        } catch {
            Self.logger.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateLiveActivity(progress: Int, total: Int, message: String) {
        let state = TransferActivityAttributes.ContentState(
            progress: progress, total: total, message: message, isComplete: false, isFailed: false
        )
        Task { await currentActivity?.update(.init(state: state, staleDate: nil)) }
    }

    private func endLiveActivity(success: Bool, message: String) {
        let state = TransferActivityAttributes.ContentState(
            progress: 0, total: 0, message: message, isComplete: success, isFailed: !success
        )
        Task {
            await currentActivity?.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
        }
        currentActivity = nil
    }

    // MARK: - Control

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        status = .idle
        endLiveActivity(success: false, message: "Transfer cancelled")
    }

    func reset() {
        status = .idle
    }
}
