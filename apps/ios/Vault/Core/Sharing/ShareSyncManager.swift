import Foundation
import os.log
import UIKit

private let shareSyncLogger = Logger(subsystem: "app.vaultaire.ios", category: "ShareSync")
// Note: No per-file size limit. With streaming SVDF builds, only one file's
// content is in memory at a time, so arbitrarily large files are safe.

/// Manages background sync of vault data to all active share recipients.
/// Debounces file changes briefly and uploads to all active share vault IDs.
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
    private var syncTask: Task<Void, Never>?
    private var deferredSyncVaultKey: VaultKey?
    private var currentBgTaskId: UIBackgroundTaskIdentifier = .invalid
    private let debounceInterval: TimeInterval = 5

    private init() { /* No-op */ }

    // MARK: - Trigger Sync

    /// Called when vault files change. Debounces briefly, then syncs to all share targets.
    func scheduleSync(vaultKey: VaultKey) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                let delayNs = UInt64((self?.debounceInterval ?? 30) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delayNs)
            } catch {
                return // Cancelled
            }
            await self?.requestSync(vaultKey: vaultKey)
        }
    }

    /// Immediately syncs vault data to all active share recipients.
    func syncNow(vaultKey: VaultKey) {
        debounceTask?.cancel()
        Task { await requestSync(vaultKey: vaultKey) }
    }

    // MARK: - Sync Implementation

    private func requestSync(vaultKey: VaultKey) async {
        if syncTask != nil {
            deferredSyncVaultKey = vaultKey
            return
        }

        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.performSync(vaultKey: vaultKey)
            await self.runDeferredSyncIfNeeded()
        }
    }

    private func runDeferredSyncIfNeeded() async {
        while let nextVaultKey = deferredSyncVaultKey {
            deferredSyncVaultKey = nil
            await performSync(vaultKey: nextVaultKey)
        }
        syncTask = nil
    }

    private func beginBackgroundExecution() {
        guard currentBgTaskId == .invalid else { return }
        currentBgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                shareSyncLogger.warning("Background sync time expired")
                self.syncTask?.cancel()
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

    private func performSync(vaultKey: VaultKey) async {
        beginBackgroundExecution()
        defer { endBackgroundExecution() }

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
                guard let shareKeyData = share.shareKeyData else {
                    missingKeyCount += 1
                    continue
                }

                let capturedIndex = index
                let capturedVaultKey = vaultKey
                let capturedShareKey = ShareKey(shareKeyData)
                let capturedShareId = share.id

                // Build SVDF to a temp file off main thread (streaming, O(largest_file) memory)
                let buildResult: (svdfFileURL: URL, chunkHashes: [String], syncState: ShareSyncCache.SyncState)
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

                // Ensure temp file is always cleaned up
                defer { try? FileManager.default.removeItem(at: buildResult.svdfFileURL) }

                syncProgress = (i + 1, totalShares)

                // Upload changed chunks from file (reads 2MB at a time)
                try await CloudKitSharingManager.shared.syncSharedVaultIncrementalFromFile(
                    shareVaultId: share.id,
                    svdfFileURL: buildResult.svdfFileURL,
                    newChunkHashes: buildResult.chunkHashes,
                    previousChunkHashes: buildResult.syncState.chunkHashes
                )

                // Save updated cache (copies file, doesn't load into memory)
                let cache = ShareSyncCache(shareVaultId: share.id)
                try cache.saveSVDF(from: buildResult.svdfFileURL)

                // Get file size for sync state
                let fileAttrs = try FileManager.default.attributesOfItem(atPath: buildResult.svdfFileURL.path)
                let svdfSize = (fileAttrs[.size] as? Int) ?? 0

                var updatedState = buildResult.syncState
                updatedState.chunkHashes = buildResult.chunkHashes
                updatedState.totalBytes = svdfSize
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

    // MARK: - Streaming SVDF Build

    /// Builds SVDF data by streaming to a temporary file.
    /// Re-encrypts only new files, reuses cached encrypted files for unchanged ones.
    /// Falls back to full rebuild when no prior cache exists or compaction is needed.
    /// Peak memory is O(largest_file) instead of O(total_vault_size).
    nonisolated private static func buildIncrementalSharedVaultData(
        index: VaultStorage.VaultIndex,
        vaultKey: VaultKey,
        shareKey: ShareKey,
        shareVaultId: String
    ) throws -> (svdfFileURL: URL, chunkHashes: [String], syncState: ShareSyncCache.SyncState) {
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }
        let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey.rawBytes)

        let cache = ShareSyncCache(shareVaultId: shareVaultId)
        let priorState = cache.loadSyncState()

        // Current vault file IDs
        let activeFiles = index.files.filter { !$0.isDeleted }
        let currentFileIds = Set(activeFiles.map { $0.fileId.uuidString })

        // Determine new and removed files
        let syncedIds = priorState?.syncedFileIds ?? []
        let newFileIds = currentFileIds.subtracting(syncedIds)
        let removedFileIds = syncedIds.subtracting(currentFileIds)

        // Check if we need a full rebuild
        let priorSVDFExists = cache.svdfFileExists()
        let needsFullRebuild = priorState == nil
            || !priorSVDFExists
            || (priorState.map { cache.needsCompaction($0) } ?? true)

        let metadata = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: KeyDerivation.keyFingerprint(from: vaultKey.rawBytes),
            sharedAt: Date()
        )

        // Temp file for streaming SVDF output
        let svdfFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svdf_sync_\(shareVaultId)_\(UUID().uuidString).bin")

        let manifest: [SVDFSerializer.FileManifestEntry]

        if needsFullRebuild {
            // Full rebuild — stream all files one at a time
            let result = try SVDFSerializer.buildFullStreaming(
                to: svdfFileURL,
                fileCount: activeFiles.count,
                forEachFile: { i in
                    let entry = activeFiles[i]
                    return try Self.reencryptFileForShare(
                        entry: entry, index: index, masterKey: masterKey,
                        shareKey: shareKey, cache: cache
                    )
                },
                metadata: metadata,
                shareKey: shareKey.rawBytes
            )
            manifest = result.manifest
        } else {
            // Incremental append — stream prior entries from file, append new ones
            let filesToAppend = activeFiles.filter { newFileIds.contains($0.fileId.uuidString) }

            manifest = try SVDFSerializer.buildIncrementalStreaming(
                to: svdfFileURL,
                priorSVDFURL: cache.svdfFileURL,
                priorManifest: priorState!.manifest,
                newFileCount: filesToAppend.count,
                forEachNewFile: { i in
                    let entry = filesToAppend[i]
                    return try Self.reencryptFileForShare(
                        entry: entry, index: index, masterKey: masterKey,
                        shareKey: shareKey, cache: cache
                    )
                },
                removedFileIds: removedFileIds,
                metadata: metadata,
                shareKey: shareKey.rawBytes
            )
        }

        // Compute chunk hashes by streaming from file
        let chunkHashes = try ShareSyncCache.computeChunkHashes(from: svdfFileURL)

        // Get file size for sync state
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: svdfFileURL.path)
        let totalBytes = (fileAttributes[.size] as? Int) ?? 0

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
            totalBytes: totalBytes
        )

        return (svdfFileURL, chunkHashes, syncState)
    }

    /// Re-encrypts a single vault file for sharing, using cache when available.
    /// Returns a SharedFile with the re-encrypted content (held temporarily in memory).
    nonisolated private static func reencryptFileForShare(
        entry: VaultStorage.VaultIndex.VaultFileEntry,
        index: VaultStorage.VaultIndex,
        masterKey: Data,
        shareKey: ShareKey,
        cache: ShareSyncCache
    ) throws -> SharedVaultData.SharedFile {
        let fileIdStr = entry.fileId.uuidString

        // Check cache for already-encrypted content
        let reencrypted: Data
        if let cached = cache.loadEncryptedFile(fileIdStr) {
            reencrypted = cached
        } else {
            let (_, content) = try VaultStorage.shared.retrieveFileContent(
                entry: entry, index: index, masterKey: masterKey
            )
            reencrypted = try CryptoEngine.encrypt(content, with: shareKey.rawBytes)
            try? cache.saveEncryptedFile(fileIdStr, data: reencrypted)
        }

        // Thumbnail
        let encryptedThumb: Data?
        if let cached = cache.loadEncryptedThumb(fileIdStr) {
            encryptedThumb = cached
        } else if let thumbData = entry.thumbnailData {
            let decryptedThumb = try CryptoEngine.decrypt(thumbData, with: masterKey)
            let encThumb = try CryptoEngine.encrypt(decryptedThumb, with: shareKey.rawBytes)
            try? cache.saveEncryptedThumb(fileIdStr, data: encThumb)
            encryptedThumb = encThumb
        } else {
            encryptedThumb = nil
        }

        return SharedVaultData.SharedFile(
            id: entry.fileId,
            filename: entry.filename ?? "unknown",
            mimeType: entry.mimeType ?? "application/octet-stream",
            size: entry.size,
            encryptedContent: reencrypted,
            createdAt: entry.createdAt ?? Date(),
            encryptedThumbnail: encryptedThumb
        )
    }
}
