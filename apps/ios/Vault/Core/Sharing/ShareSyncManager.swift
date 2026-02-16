import Foundation
import os.log

private let shareSyncLogger = Logger(subsystem: "app.vaultaire.ios", category: "ShareSync")
/// Incremental sync currently re-encrypts uncached files in-memory.
/// Keep this bounded to avoid jetsam when a very large file is added.
private let maxInMemoryReencryptBytes = 256 * 1024 * 1024

/// Manages background sync of vault data to all active share recipients.
/// Debounces file changes (30s) and uploads to all share vault IDs.
@MainActor
@Observable
final class ShareSyncManager {
    static let shared = ShareSyncManager()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case upToDate
        case error(String)
    }

    var syncStatus: SyncStatus = .idle
    var syncProgress: (current: Int, total: Int)?
    var lastSyncedAt: Date?

    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 30

    private init() { /* No-op */ }

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
        let transaction = EmbraceManager.shared.startTransaction(name: "share.sync", operation: "share.sync")

        // Load index and check for active shares
        let index: VaultStorage.VaultIndex
        do {
            index = try VaultStorage.shared.loadIndex(with: vaultKey)
        } catch {
            syncStatus = .error("Failed to load vault: \(error.localizedDescription)")
            EmbraceManager.shared.captureError(error)
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

        let consumedByShareId = await CloudKitSharingManager.shared.consumedStatusByShareVaultIds(
            activeShares.map(\.id)
        )

        // Upload to each active share
        let totalShares = activeShares.count
        var successCount = 0
        var missingKeyCount = 0
        var shareUpdates: [(id: String, syncSequence: Int)] = []
        var consumedShareIds: Set<String> = []

        for (i, share) in activeShares.enumerated() {
            do {
                // Check if recipient has consumed this share
                if consumedByShareId[share.id] == true {
                    consumedShareIds.insert(share.id)
                    shareSyncLogger.info("Share \(share.id, privacy: .public) consumed by recipient, skipping sync")
                    continue
                }
                // Use the stored phrase-derived share key
                guard let shareKey = share.shareKeyData else {
                    missingKeyCount += 1
                    continue
                }

                let capturedIndex = index
                let capturedVaultKey = vaultKey
                let capturedShareKey = shareKey
                let capturedShareId = share.id

                // Build SVDF data incrementally off main thread
                let buildResult: (svdfData: Data, chunkHashes: [String], syncState: ShareSyncCache.SyncState)
                do {
                    buildResult = try await Task.detached(priority: .userInitiated) {
                        try ShareSyncManager.buildIncrementalSharedVaultData(
                            index: capturedIndex,
                            vaultKey: capturedVaultKey,
                            shareKey: capturedShareKey,
                            shareVaultId: capturedShareId
                        )
                    }.value
                } catch {
                    shareSyncLogger.warning("Failed to build vault data for share \(capturedShareId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }

                syncProgress = (i + 1, totalShares)

                // Upload using chunk-hash diffing
                try await CloudKitSharingManager.shared.syncSharedVaultIncremental(
                    shareVaultId: share.id,
                    svdfData: buildResult.svdfData,
                    newChunkHashes: buildResult.chunkHashes,
                    previousChunkHashes: buildResult.syncState.chunkHashes
                )

                // Save updated cache
                let cache = ShareSyncCache(shareVaultId: share.id)
                try cache.saveSVDF(buildResult.svdfData)
                var updatedState = buildResult.syncState
                updatedState.chunkHashes = buildResult.chunkHashes
                updatedState.totalBytes = buildResult.svdfData.count
                updatedState.syncSequence += 1
                try cache.saveSyncState(updatedState)

                successCount += 1
                shareUpdates.append((id: share.id, syncSequence: updatedState.syncSequence))
            } catch {
                shareSyncLogger.warning("Failed to sync share \(share.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        syncProgress = nil

        // Remove consumed shares from the index
        if !consumedShareIds.isEmpty {
            do {
                var updatedIndex = try VaultStorage.shared.loadIndex(with: vaultKey)
                updatedIndex.activeShares?.removeAll { consumedShareIds.contains($0.id) }
                try VaultStorage.shared.saveIndex(updatedIndex, with: vaultKey)
                shareSyncLogger.info("Removed \(consumedShareIds.count) consumed shares from index")
            } catch {
                shareSyncLogger.warning("Failed to remove consumed shares: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Batch-update share records in a single index load/save
        if !shareUpdates.isEmpty {
            do {
                var updatedIndex = try VaultStorage.shared.loadIndex(with: vaultKey)
                for update in shareUpdates {
                    if let idx = updatedIndex.activeShares?.firstIndex(where: { $0.id == update.id }) {
                        updatedIndex.activeShares?[idx].lastSyncedAt = Date()
                        updatedIndex.activeShares?[idx].syncSequence = update.syncSequence
                    }
                }
                try VaultStorage.shared.saveIndex(updatedIndex, with: vaultKey)
            } catch {
                shareSyncLogger.warning("Failed to update share records: \(error.localizedDescription, privacy: .public)")
            }
        }

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

    // MARK: - Incremental SVDF Build

    /// Builds SVDF data incrementally using the per-share cache.
    /// Re-encrypts only new files, reuses cached encrypted files for unchanged ones.
    /// Falls back to full rebuild when no prior cache exists or compaction is needed.
    nonisolated private static func buildIncrementalSharedVaultData(
        index: VaultStorage.VaultIndex,
        vaultKey: Data,
        shareKey: Data,
        shareVaultId: String
    ) throws -> (svdfData: Data, chunkHashes: [String], syncState: ShareSyncCache.SyncState) {
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }
        let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey)

        let cache = ShareSyncCache(shareVaultId: shareVaultId)
        let priorState = cache.loadSyncState()
        let priorSVDF = cache.loadSVDF()

        // Current vault file IDs
        let activeFiles = index.files.filter { !$0.isDeleted }
        let currentFileIds = Set(activeFiles.map { $0.fileId.uuidString })

        // Determine new and removed files
        let syncedIds = priorState?.syncedFileIds ?? []
        let newFileIds = currentFileIds.subtracting(syncedIds)
        let removedFileIds = syncedIds.subtracting(currentFileIds)

        // Check if we need a full rebuild
        let needsFullRebuild = priorState == nil
            || priorSVDF == nil
            || (priorState.map { cache.needsCompaction($0) } ?? true)

        // Re-encrypt new files (or all files if full rebuild)
        let filesToEncrypt = needsFullRebuild ? activeFiles : activeFiles.filter { newFileIds.contains($0.fileId.uuidString) }

        var sharedFiles: [SharedVaultData.SharedFile] = []
        var skippedFiles = 0

        for entry in filesToEncrypt {
            do {
                if entry.size > maxInMemoryReencryptBytes {
                    skippedFiles += 1
                    let name = entry.filename ?? entry.fileId.uuidString
                    shareSyncLogger.warning(
                        "Skipping oversized file \(name, privacy: .public) (\(entry.size / (1024 * 1024))MB) during incremental sync"
                    )
                    continue
                }
                let fileIdStr = entry.fileId.uuidString

                // Check cache for already-encrypted content
                let reencrypted: Data
                if let cached = cache.loadEncryptedFile(fileIdStr) {
                    reencrypted = cached
                } else {
                    let (_, content) = try VaultStorage.shared.retrieveFileContent(
                        entry: entry, index: index, masterKey: masterKey
                    )
                    reencrypted = try CryptoEngine.encrypt(content, with: shareKey)
                    try? cache.saveEncryptedFile(fileIdStr, data: reencrypted)
                }

                // Thumbnail
                let encryptedThumb: Data?
                if let cached = cache.loadEncryptedThumb(fileIdStr) {
                    encryptedThumb = cached
                } else if let thumbData = entry.thumbnailData {
                    let decryptedThumb = try CryptoEngine.decrypt(thumbData, with: masterKey)
                    let encThumb = try CryptoEngine.encrypt(decryptedThumb, with: shareKey)
                    try? cache.saveEncryptedThumb(fileIdStr, data: encThumb)
                    encryptedThumb = encThumb
                } else {
                    encryptedThumb = nil
                }

                sharedFiles.append(SharedVaultData.SharedFile(
                    id: entry.fileId,
                    filename: entry.filename ?? "unknown",
                    mimeType: entry.mimeType ?? "application/octet-stream",
                    size: entry.size,
                    encryptedContent: reencrypted,
                    createdAt: entry.createdAt ?? Date(),
                    encryptedThumbnail: encryptedThumb
                ))
            } catch {
                skippedFiles += 1
                shareSyncLogger.warning("Skipping corrupted file \(entry.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let metadata = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: KeyDerivation.keyFingerprint(from: vaultKey),
            sharedAt: Date()
        )

        // Build SVDF
        let svdfData: Data
        let manifest: [SVDFSerializer.FileManifestEntry]

        if needsFullRebuild {
            // Full rebuild — need all files encrypted
            guard !sharedFiles.isEmpty || skippedFiles == 0 else {
                throw VaultStorageError.readError
            }

            let result = try SVDFSerializer.buildFull(
                files: sharedFiles,
                metadata: metadata,
                shareKey: shareKey
            )
            svdfData = result.data
            manifest = result.manifest
        } else {
            // Incremental append
            let result = try SVDFSerializer.buildIncremental(
                priorData: priorSVDF!,
                priorManifest: priorState!.manifest,
                newFiles: sharedFiles,
                removedFileIds: removedFileIds,
                metadata: metadata,
                shareKey: shareKey
            )
            svdfData = result.data
            manifest = result.manifest
        }

        // Compute chunk hashes
        let chunkHashes = ShareSyncCache.computeChunkHashes(svdfData)

        // Compute deleted bytes for compaction tracking
        let deletedBytes = manifest.filter { $0.deleted }.reduce(0) { $0 + $1.size }

        // Prune cached encrypted files for removed IDs
        cache.pruneFiles(keeping: currentFileIds)

        let syncState = ShareSyncCache.SyncState(
            syncedFileIds: currentFileIds,
            chunkHashes: priorState?.chunkHashes ?? [],
            manifest: manifest,
            syncSequence: priorState?.syncSequence ?? 0,
            deletedFileIds: priorState?.deletedFileIds.union(removedFileIds) ?? removedFileIds,
            totalDeletedBytes: deletedBytes,
            totalBytes: svdfData.count
        )

        return (svdfData, chunkHashes, syncState)
    }
}
