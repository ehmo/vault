import Foundation
import Combine

/// Manages background sync of vault data to all active share recipients.
/// Debounces file changes (30s) and uploads to all share vault IDs.
@MainActor
final class ShareSyncManager: ObservableObject {
    static let shared = ShareSyncManager()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case upToDate
        case error(String)
    }

    @Published var syncStatus: SyncStatus = .idle
    @Published var syncProgress: (current: Int, total: Int)?
    @Published var lastSyncedAt: Date?

    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 30

    private init() {}

    // MARK: - Trigger Sync

    /// Called when vault files change. Debounces for 30 seconds, then syncs to all share targets.
    func scheduleSync(vaultKey: Data) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(30 * 1_000_000_000))
            } catch {
                return // Cancelled
            }
            await self?.performSync(vaultKey: vaultKey)
        }
    }

    /// Immediately syncs vault data to all active share recipients.
    func syncNow(vaultKey: Data) {
        debounceTask?.cancel()
        Task {
            await performSync(vaultKey: vaultKey)
        }
    }

    // MARK: - Sync Implementation

    private func performSync(vaultKey: Data) async {
        let transaction = SentryManager.shared.startTransaction(name: "share.sync", operation: "share.sync")

        // Load index and check for active shares
        let index: VaultStorage.VaultIndex
        do {
            index = try VaultStorage.shared.loadIndex(with: vaultKey)
        } catch {
            syncStatus = .error("Failed to load vault: \(error.localizedDescription)")
            SentryManager.shared.captureError(error)
            transaction.finish(status: .internalError)
            return
        }

        guard let activeShares = index.activeShares, !activeShares.isEmpty else {
            syncStatus = .idle
            transaction.finish(status: .ok)
            return
        }

        let fileCount = index.files.filter { !$0.isDeleted }.count
        transaction.setTag(value: "\(fileCount)", key: "fileCount")
        transaction.setTag(value: "\(activeShares.count)", key: "shareCount")

        syncStatus = .syncing

        // Upload to each active share
        let totalShares = activeShares.count
        var successCount = 0
        var missingKeyCount = 0

        for (i, share) in activeShares.enumerated() {
            do {
                // Use the stored phrase-derived share key
                guard let shareKey = share.shareKeyData else {
                    missingKeyCount += 1
                    continue
                }

                // Build shared vault data with per-file re-encryption using this share's key
                let sharedData: Data
                do {
                    sharedData = try buildSharedVaultData(index: index, vaultKey: vaultKey, shareKey: shareKey)
                } catch {
                    #if DEBUG
                    print("⚠️ [ShareSync] Failed to build vault data for share \(share.id): \(error)")
                    #endif
                    continue
                }

                syncProgress = (i + 1, totalShares)

                try await CloudKitSharingManager.shared.syncSharedVault(
                    shareVaultId: share.id,
                    vaultData: sharedData,
                    shareKey: shareKey,
                    currentVersion: 1
                )

                successCount += 1

                // Update lastSyncedAt on the share record
                var updatedIndex = try VaultStorage.shared.loadIndex(with: vaultKey)
                if let idx = updatedIndex.activeShares?.firstIndex(where: { $0.id == share.id }) {
                    updatedIndex.activeShares?[idx].lastSyncedAt = Date()
                    try VaultStorage.shared.saveIndex(updatedIndex, with: vaultKey)
                }
            } catch {
                #if DEBUG
                print("⚠️ [ShareSync] Failed to sync share \(share.id): \(error)")
                #endif
            }
        }

        syncProgress = nil

        if successCount == totalShares {
            syncStatus = .upToDate
            lastSyncedAt = Date()
            transaction.finish(status: .ok)
        } else if missingKeyCount == totalShares {
            syncStatus = .error("Shares need to be re-created to enable sync")
            transaction.finish(status: .internalError)
        } else if successCount > 0 {
            syncStatus = .error("Synced \(successCount)/\(totalShares) shares")
            lastSyncedAt = Date()
            transaction.finish(status: .ok)
        } else {
            syncStatus = .error("Sync failed for all shares")
            transaction.finish(status: .internalError)
        }
    }

    // MARK: - Helpers

    /// Builds serialized SharedVaultData from the current vault index.
    /// Re-encrypts each file with the share key (matching initial upload format).
    private func buildSharedVaultData(index: VaultStorage.VaultIndex, vaultKey: Data, shareKey: Data) throws -> Data {
        let masterKey = try CryptoEngine.shared.decrypt(index.encryptedMasterKey!, with: vaultKey)
        var sharedFiles: [SharedVaultData.SharedFile] = []
        var skippedFiles = 0

        for entry in index.files where !entry.isDeleted {
            do {
                let (header, content) = try VaultStorage.shared.retrieveFile(id: entry.fileId, with: vaultKey)
                // Re-encrypt file content with share key (same as initial upload)
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
            } catch {
                skippedFiles += 1
                #if DEBUG
                print("⚠️ [ShareSync] Skipping corrupted file \(entry.fileId) (offset: \(entry.offset), size: \(entry.size)): \(error)")
                #endif
            }
        }

        guard !sharedFiles.isEmpty else {
            #if DEBUG
            print("❌ [ShareSync] All \(skippedFiles) files are unreadable — cannot build share data")
            #endif
            throw VaultStorageError.readError
        }

        #if DEBUG
        if skippedFiles > 0 {
            print("⚠️ [ShareSync] Built share data with \(sharedFiles.count) files, skipped \(skippedFiles) corrupted")
        }
        #endif

        let data = SharedVaultData(
            files: sharedFiles,
            metadata: SharedVaultData.SharedVaultMetadata(
                ownerFingerprint: KeyDerivation.keyFingerprint(from: vaultKey),
                sharedAt: Date()
            ),
            createdAt: Date(),
            updatedAt: Date()
        )

        return try JSONEncoder().encode(data)
    }
}
