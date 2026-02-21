import Foundation
import os.log
import UIKit

private let shareSyncLogger = Logger(subsystem: "app.vaultaire.ios", category: "ShareSync")
// Note: No per-file size limit. With streaming SVDF builds, only one file's
// content is in memory at a time, so arbitrarily large files are safe.

/// Manages background sync of vault data to all active share recipients.
/// Debounces file changes briefly and uploads to all active share vault IDs.
///
/// Sync is two-phase for resilience:
/// 1. **Stage**: Build SVDF while vault is unlocked → write encrypted data to
///    `Documents/pending_sync/{shareVaultId}/` with `.completeUntilFirstUserAuthentication`.
/// 2. **Upload**: Read staged data from disk → upload to CloudKit. No vault key needed.
///
/// If the app is killed mid-upload, the staged SVDF survives on disk and upload
/// resumes automatically on next app launch (no vault key required).
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
    /// Active resume tasks by shareVaultId, to avoid duplicate resume attempts
    private var resumeTasks: [String: Task<Void, Never>] = [:]

    private let storage: VaultStorageProtocol
    private let cloudKit: CloudKitSharingClient

    // MARK: - Pending Sync State (Staging)

    struct PendingSyncState: Codable {
        let shareVaultId: String
        let shareKeyData: Data
        let totalChunks: Int
        let newChunkHashes: [String]
        let previousChunkHashes: [String]
        let createdAt: Date
        var uploadFinished: Bool
        /// Vault key fingerprint for ShareSyncCache lookup on resume
        let vaultKeyFingerprint: String?
        /// Manifest entries for updating cache on resume
        let manifest: [SVDFSerializer.FileManifestEntry]?
        /// File IDs synced in this batch for cache state
        let syncedFileIds: Set<String>?
        /// Current sync sequence for cache state
        let syncSequence: Int?
    }

    /// 48-hour TTL for staged syncs
    private nonisolated static let pendingSyncTTL: TimeInterval = 48 * 60 * 60

    private nonisolated static var syncStagingRootDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated static func syncStagingDir(for shareVaultId: String) -> URL {
        syncStagingRootDir.appendingPathComponent(shareVaultId, isDirectory: true)
    }

    private nonisolated static func syncSvdfURL(for shareVaultId: String) -> URL {
        syncStagingDir(for: shareVaultId).appendingPathComponent("svdf_data.bin")
    }

    private nonisolated static func syncStateURL(for shareVaultId: String) -> URL {
        syncStagingDir(for: shareVaultId).appendingPathComponent("state.json")
    }

    nonisolated func loadPendingSyncState(for shareVaultId: String) -> PendingSyncState? {
        let stateURL = Self.syncStateURL(for: shareVaultId)
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PendingSyncState.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(state.createdAt) < Self.pendingSyncTTL else {
            clearSyncStaging(for: shareVaultId)
            return nil
        }
        // Verify SVDF file still exists
        let svdfURL = Self.syncSvdfURL(for: shareVaultId)
        guard FileManager.default.fileExists(atPath: svdfURL.path) else {
            clearSyncStaging(for: shareVaultId)
            return nil
        }
        return state
    }

    private nonisolated func savePendingSyncState(_ state: PendingSyncState) {
        let dir = Self.syncStagingDir(for: state.shareVaultId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(state)
            let stateURL = Self.syncStateURL(for: state.shareVaultId)
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: stateURL.path
            )
        } catch {
            shareSyncLogger.error("[staging] Failed to save pending sync state: \(error.localizedDescription)")
        }
    }

    private nonisolated func clearSyncStaging(for shareVaultId: String) {
        try? FileManager.default.removeItem(at: Self.syncStagingDir(for: shareVaultId))
    }

    /// Returns all shareVaultIds with valid pending sync state on disk.
    nonisolated func pendingSyncShareVaultIds() -> [String] {
        let rootDir = Self.syncStagingRootDir
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.compactMap { dir -> String? in
            guard dir.hasDirectoryPath else { return nil }
            let shareVaultId = dir.lastPathComponent
            return loadPendingSyncState(for: shareVaultId) != nil ? shareVaultId : nil
        }
    }

    var hasPendingSyncs: Bool {
        !pendingSyncShareVaultIds().isEmpty
    }

    private init(
        storage: VaultStorageProtocol = VaultStorage.shared,
        cloudKit: CloudKitSharingClient = CloudKitSharingManager.shared
    ) {
        self.storage = storage
        self.cloudKit = cloudKit
    }

    #if DEBUG
    static func createForTesting(
        storage: VaultStorageProtocol,
        cloudKit: CloudKitSharingClient
    ) -> ShareSyncManager {
        ShareSyncManager(storage: storage, cloudKit: cloudKit)
    }
    #endif

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
            shareSyncLogger.warning("Background sync time expired")
            Task { @MainActor [weak self] in
                self?.syncTask?.cancel()
                self?.endBackgroundExecution()
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
        
        // Capture vault key fingerprint for consistency verification
        let vaultKeyFingerprint = vaultKey.rawBytes.hashValue
        shareSyncLogger.info("Starting sync for vault with key hash: \(vaultKeyFingerprint, privacy: .private)")

        let transaction = EmbraceManager.shared.startTransaction(name: "share.sync", operation: "share.sync")

        // Load index and check for active shares
        let index: VaultStorage.VaultIndex
        do {
            index = try storage.loadIndex(with: vaultKey)
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

        let consumedByShareId = await cloudKit.consumedStatusByShareVaultIds(
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
                let capturedStorage = storage

                // Build SVDF to a temp file off main thread (streaming, O(largest_file) memory)
                let buildResult: (svdfFileURL: URL, chunkHashes: [String], syncState: ShareSyncCache.SyncState)
                do {
                    buildResult = try await Task.detached(priority: .userInitiated) {
                        try ShareSyncManager.buildIncrementalSharedVaultData(
                            index: capturedIndex,
                            vaultKey: capturedVaultKey,
                            shareKey: capturedShareKey,
                            shareVaultId: capturedShareId,
                            storage: capturedStorage
                        )
                    }.value
                } catch {
                    shareSyncLogger.warning("Failed to build vault data for share \(capturedShareId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }

                syncProgress = (i + 1, totalShares)

                // Cancel any in-flight resume upload for this share to avoid
                // reading stale SVDF data while we replace the staging directory
                resumeTasks[share.id]?.cancel()
                resumeTasks.removeValue(forKey: share.id)

                // Stage SVDF to persistent dir (replaces any old staging for this share)
                let stagingDir = Self.syncStagingDir(for: share.id)
                let stagedSvdfURL = Self.syncSvdfURL(for: share.id)
                clearSyncStaging(for: share.id)
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: buildResult.svdfFileURL, to: stagedSvdfURL)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: stagedSvdfURL.path
                )

                let keyFingerprint = vaultKey.rawBytes.hashValue
                let currentSyncSeq = (buildResult.syncState.syncSequence) + 1
                let pendingSyncState = PendingSyncState(
                    shareVaultId: share.id,
                    shareKeyData: shareKeyData,
                    totalChunks: buildResult.chunkHashes.count,
                    newChunkHashes: buildResult.chunkHashes,
                    previousChunkHashes: buildResult.syncState.chunkHashes,
                    createdAt: Date(),
                    uploadFinished: false,
                    vaultKeyFingerprint: String(keyFingerprint),
                    manifest: buildResult.syncState.manifest,
                    syncedFileIds: buildResult.syncState.syncedFileIds,
                    syncSequence: currentSyncSeq
                )
                savePendingSyncState(pendingSyncState)

                // Upload changed chunks from staged file (reads 2MB at a time)
                try await cloudKit.syncSharedVaultIncrementalFromFile(
                    shareVaultId: share.id,
                    svdfFileURL: stagedSvdfURL,
                    newChunkHashes: buildResult.chunkHashes,
                    previousChunkHashes: buildResult.syncState.chunkHashes
                )

                // Save updated cache (copies file, doesn't load into memory)
                let cache = ShareSyncCache(shareVaultId: share.id, vaultKeyFingerprint: String(keyFingerprint))
                try cache.saveSVDF(from: stagedSvdfURL)

                // Get file size for sync state
                let fileAttrs = try FileManager.default.attributesOfItem(atPath: stagedSvdfURL.path)
                let svdfSize = (fileAttrs[.size] as? Int) ?? 0

                var updatedState = buildResult.syncState
                updatedState.chunkHashes = buildResult.chunkHashes
                updatedState.totalBytes = svdfSize
                updatedState.syncSequence += 1
                try cache.saveSyncState(updatedState)

                // Upload succeeded — clear staging for this share
                clearSyncStaging(for: share.id)

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
                var updatedIndex = try storage.loadIndex(with: vaultKey)
                let fileCountBefore = updatedIndex.files.filter { !$0.isDeleted }.count
                updatedIndex.activeShares?.removeAll { consumedShareIds.contains($0.id) }
                try storage.saveIndex(updatedIndex, with: vaultKey)
                let fileCountAfter = updatedIndex.files.filter { !$0.isDeleted }.count
                shareSyncLogger.info("Removed \(consumedShareIds.count) consumed shares from index. Files: \(fileCountBefore) -> \(fileCountAfter)")
            } catch {
                shareSyncLogger.warning("Failed to remove consumed shares: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Batch-update share records in a single index load/save
        if !shareUpdates.isEmpty {
            do {
                var updatedIndex = try storage.loadIndex(with: vaultKey)
                let fileCountBefore = updatedIndex.files.filter { !$0.isDeleted }.count
                for update in shareUpdates {
                    if let idx = updatedIndex.activeShares?.firstIndex(where: { $0.id == update.id }) {
                        updatedIndex.activeShares?[idx].lastSyncedAt = Date()
                        updatedIndex.activeShares?[idx].syncSequence = update.syncSequence
                    }
                }
                try storage.saveIndex(updatedIndex, with: vaultKey)
                let fileCountAfter = updatedIndex.files.filter { !$0.isDeleted }.count
                shareSyncLogger.info("Updated \(shareUpdates.count) share records. Files: \(fileCountBefore) -> \(fileCountAfter)")
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
        shareVaultId: String,
        storage: VaultStorageProtocol = VaultStorage.shared
    ) throws -> (svdfFileURL: URL, chunkHashes: [String], syncState: ShareSyncCache.SyncState) {
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }
        let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey.rawBytes)

        let keyFingerprint = vaultKey.rawBytes.hashValue
        let cache = ShareSyncCache(shareVaultId: shareVaultId, vaultKeyFingerprint: String(keyFingerprint))
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
                        shareKey: shareKey, cache: cache, storage: storage
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
                        shareKey: shareKey, cache: cache, storage: storage
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
        cache: ShareSyncCache,
        storage: VaultStorageProtocol = VaultStorage.shared
    ) throws -> SharedVaultData.SharedFile {
        let fileIdStr = entry.fileId.uuidString

        // Check cache for already-encrypted content
        let reencrypted: Data
        let header: CryptoEngine.EncryptedFileHeader
        if let cached = cache.loadEncryptedFile(fileIdStr) {
            reencrypted = cached
            // For cached files, we need to get the header to determine original size
            // The header is stored in the entry's encryptedHeaderPreview
            header = try retrieveHeaderFromEntry(entry, masterKey: masterKey)
        } else {
            let (fileHeader, content) = try storage.retrieveFileContent(
                entry: entry, index: index, masterKey: masterKey
            )
            header = fileHeader
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
            filename: header.originalFilename,
            mimeType: header.mimeType,
            size: Int(header.originalSize),
            encryptedContent: reencrypted,
            createdAt: header.createdAt,
            encryptedThumbnail: encryptedThumb,
            duration: entry.duration
        )
    }
    
    /// Retrieves just the header from a file entry (for cached files where we need header info).
    nonisolated private static func retrieveHeaderFromEntry(
        _ entry: VaultStorage.VaultIndex.VaultFileEntry,
        masterKey: Data
    ) throws -> CryptoEngine.EncryptedFileHeader {
        // The entry stores the first 64 bytes of encrypted file data as encryptedHeaderPreview
        // This contains the header size + encrypted header
        guard entry.encryptedHeaderPreview.count >= 4 else {
            throw VaultStorageError.corruptedData
        }
        
        let headerSizeData = entry.encryptedHeaderPreview.prefix(4)
        let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        guard entry.encryptedHeaderPreview.count >= 4 + Int(headerSize) else {
            throw VaultStorageError.corruptedData
        }
        
        let encryptedHeader = entry.encryptedHeaderPreview.subdata(in: 4..<(4 + Int(headerSize)))
        let decryptedHeaderData = try CryptoEngine.decrypt(encryptedHeader, with: masterKey)
        return try CryptoEngine.EncryptedFileHeader.deserialize(from: decryptedHeaderData)
    }

    // MARK: - Resume Pending Syncs

    /// Scans staging directory for pending sync uploads and resumes them.
    /// No vault key needed — SVDF files are already share-key encrypted.
    func resumePendingSyncsIfNeeded(trigger: String) {
        let pendingIds = pendingSyncShareVaultIds()
        guard !pendingIds.isEmpty else { return }

        shareSyncLogger.info("[resume] Found \(pendingIds.count) pending sync(s), trigger=\(trigger, privacy: .public)")

        for shareVaultId in pendingIds {
            guard resumeTasks[shareVaultId] == nil else { continue }

            let capturedCloudKit = cloudKit
            let task = Task { [weak self] in
                guard let self else { return }
                await self.uploadStagedSync(shareVaultId: shareVaultId, cloudKit: capturedCloudKit)
                self.resumeTasks.removeValue(forKey: shareVaultId)
            }
            resumeTasks[shareVaultId] = task
        }
    }

    /// Uploads a staged SVDF for a single share. No vault key needed.
    /// Uses its own background task ID to avoid conflicts with parallel resume uploads.
    /// Updates ShareSyncCache on success so subsequent syncs can build incrementally.
    private func uploadStagedSync(shareVaultId: String, cloudKit: CloudKitSharingClient) async {
        guard let state = loadPendingSyncState(for: shareVaultId) else {
            shareSyncLogger.info("[resume] No valid pending sync for \(shareVaultId, privacy: .public)")
            return
        }

        let stagedSvdfURL = Self.syncSvdfURL(for: shareVaultId)

        // Use a per-upload background task to avoid conflicts with parallel resumes.
        // The expiration handler cancels the resume task so iOS doesn't kill us.
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            shareSyncLogger.warning("[resume] Background time expired for sync \(shareVaultId, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.resumeTasks[shareVaultId]?.cancel()
            }
        }
        defer {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
        }

        do {
            try await cloudKit.syncSharedVaultIncrementalFromFile(
                shareVaultId: shareVaultId,
                svdfFileURL: stagedSvdfURL,
                newChunkHashes: state.newChunkHashes,
                previousChunkHashes: state.previousChunkHashes
            )

            // Update ShareSyncCache so the next sync can build incrementally
            // instead of doing a full rebuild
            if let fingerprint = state.vaultKeyFingerprint,
               let manifest = state.manifest,
               let syncedIds = state.syncedFileIds,
               let syncSeq = state.syncSequence {
                do {
                    let cache = ShareSyncCache(shareVaultId: shareVaultId, vaultKeyFingerprint: fingerprint)
                    try cache.saveSVDF(from: stagedSvdfURL)
                    let fileAttrs = try FileManager.default.attributesOfItem(atPath: stagedSvdfURL.path)
                    let svdfSize = (fileAttrs[.size] as? Int) ?? 0
                    let deletedBytes = manifest.filter { $0.deleted }.reduce(0) { $0 + $1.size }
                    let syncState = ShareSyncCache.SyncState(
                        syncedFileIds: syncedIds,
                        chunkHashes: state.newChunkHashes,
                        manifest: manifest,
                        syncSequence: syncSeq,
                        deletedFileIds: [],
                        totalDeletedBytes: deletedBytes,
                        totalBytes: svdfSize
                    )
                    try cache.saveSyncState(syncState)
                    shareSyncLogger.info("[resume] Updated sync cache for \(shareVaultId, privacy: .public)")
                } catch {
                    shareSyncLogger.warning("[resume] Failed to update sync cache: \(error.localizedDescription, privacy: .public)")
                    // Non-fatal: next sync will do a full rebuild
                }
            }

            clearSyncStaging(for: shareVaultId)
            shareSyncLogger.info("[resume] Sync upload completed for \(shareVaultId, privacy: .public)")
        } catch {
            shareSyncLogger.warning("[resume] Sync upload failed for \(shareVaultId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Leave staging in place for next resume attempt
        }
    }
}
