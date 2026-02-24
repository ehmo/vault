import Foundation
import CryptoKit
import os

private let indexLogger = Logger(subsystem: "com.vaultaire.vault", category: "index")

/// Manages all vault index operations: load, save, cache, migration, and master key extraction.
/// Uses a custom serial executor to keep blocking blob I/O off the cooperative thread pool.
actor VaultIndexManager {

    private let fileManager = FileManager.default

    // Custom serial executor — keeps blocking file I/O off the cooperative pool
    private let serialQueue = DispatchSerialQueue(label: "vault.index.actor")
    nonisolated var unownedExecutor: UnownedSerialExecutor { serialQueue.asUnownedSerialExecutor() }

    // In-memory index cache -- avoids decrypt+decode on every retrieveFile/listFiles call
    private var cachedIndex: VaultStorage.VaultIndex?
    private var cachedIndexFingerprint: String?

    // Batch mode — defers per-file index persistence for bulk import throughput.
    // Without batching, every storeFileFromURL serializes a full JSON encode + encrypt +
    // atomic write of the entire index (which includes inline thumbnails and can be 20-50MB).
    // For 100 files, that's 100 saves × 2-5 seconds each = minutes of overhead.
    // Batching defers saves and flushes every N mutations, reducing 100 saves to ~5.
    private var batchDepth = 0
    private var mutationsSinceFlush = 0
    private static let batchFlushInterval = 20

    // Properties from VaultStorage context
    private let documentsURL: URL
    private let blobFileName: String
    private let defaultBlobSize: Int
    private let cursorBlockOffset: Int

    /// Closure that reads the global cursor from the blob footer.
    /// Set by VaultStorage after init to avoid circular dependency.
    nonisolated(unsafe) var readGlobalCursor: @Sendable () -> Int = { 0 }

    /// Closure that returns the actual cursor footer offset (handles legacy 500MB blobs).
    nonisolated(unsafe) var cursorFooterOffset: @Sendable () -> Int = { 0 }

    init(documentsURL: URL, blobFileName: String, defaultBlobSize: Int, cursorBlockOffset: Int) {
        self.documentsURL = documentsURL
        self.blobFileName = blobFileName
        self.defaultBlobSize = defaultBlobSize
        self.cursorBlockOffset = cursorBlockOffset
    }

    // MARK: - Index URL

    /// Returns the index file URL for a specific vault key.
    /// Each vault gets its own index file based on a hash of the key.
    nonisolated func indexURL(for key: VaultKey) -> URL {
        let keyHash = SHA256.hash(data: key.rawBytes)
        let fingerprint = keyHash.prefix(16).map { String(format: "%02x", $0) }.joined()
        let fileName = "vault_index_\(fingerprint).bin"

        indexLogger.debug("Index file for this vault: \(fileName, privacy: .public)")

        return documentsURL.appendingPathComponent(fileName)
    }

    // MARK: - Key Fingerprint

    nonisolated func keyFingerprint(_ key: VaultKey) -> String {
        SHA256.hash(data: key.rawBytes).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Load Index

    func loadIndex(with key: VaultKey) throws -> VaultStorage.VaultIndex {
        let span = EmbraceManager.shared.startTransaction(name: "storage.index_load", operation: "storage.index_load")
        defer { span.finish(status: .ok) }

        // Return cached index if available for this key
        let fp = keyFingerprint(key)
        if let cached = cachedIndex, cachedIndexFingerprint == fp {
            return cached
        }

        indexLogger.debug("loadIndex called with key hash: \(key.rawBytes.hashValue, privacy: .private)")

        let url = indexURL(for: key)

        guard fileManager.fileExists(atPath: url.path) else {
            indexLogger.debug("No index file exists, creating new vault with master key")
            // Return empty v3 index for new vaults with a fresh master key
            guard let masterKey = CryptoEngine.generateRandomBytes(count: 32) else {
                throw VaultStorageError.corruptedData
            }
            let encryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: key)
            let globalCursor = readGlobalCursor()
            let primary = VaultStorage.BlobDescriptor(
                blobId: "primary",
                fileName: blobFileName,
                capacity: cursorBlockOffset,
                cursor: globalCursor
            )
            var newIndex = VaultStorage.VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: cursorBlockOffset,
                encryptedMasterKey: encryptedMasterKey,
                version: 3
            )
            newIndex.blobs = [primary]
            cachedIndex = newIndex
            cachedIndexFingerprint = fp
            return newIndex
        }

        let encryptedData = try Data(contentsOf: url)

        indexLogger.debug("Index file loaded, size: \(encryptedData.count, privacy: .public) bytes")

        // Try to decrypt - if it fails, this key doesn't match any vault
        do {
            let decryptedData = try CryptoEngine.decrypt(encryptedData, with: key)
            var index = try JSONDecoder().decode(VaultStorage.VaultIndex.self, from: decryptedData)

            indexLogger.info("Index decrypted. Files: \(index.files.count, privacy: .public), nextOffset: \(index.nextOffset, privacy: .public), version: \(index.version, privacy: .public)")

            // Migration: If index doesn't have a master key (version 1), create one
            if index.encryptedMasterKey == nil {
                indexLogger.info("Migrating vault to use master key (v1 -> v2)")
                guard let masterKeyData = CryptoEngine.generateRandomBytes(count: 32) else {
                    throw VaultStorageError.corruptedData
                }
                index.encryptedMasterKey = try CryptoEngine.encrypt(masterKeyData, with: key)
                index.version = 2

                try saveIndex(index, with: key)

                indexLogger.info("Vault migrated to v2 with master key")
            }

            // Migration: v2 -> v3 (add blob descriptors)
            if index.version < 3 {
                indexLogger.info("Migrating vault v2 -> v3 (multi-blob)")
                migrateToV3(&index)
                try saveIndex(index, with: key)

                indexLogger.info("Vault migrated to v3")
            }

            cachedIndex = index
            cachedIndexFingerprint = fp
            return index
        } catch {
            indexLogger.warning("Failed to decrypt index: \(error.localizedDescription, privacy: .public)")
            // Index file exists at this key's path but cannot be decrypted -- corruption.
            throw VaultStorageError.indexDecryptionFailed
        }
    }

    // MARK: - Save Index

    func saveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) throws {
        let span = EmbraceManager.shared.startTransaction(name: "storage.index_save", operation: "storage.index_save")
        defer { span.finish(status: .ok) }

        indexLogger.debug("saveIndex called")
        indexLogger.debug("Files: \(index.files.count, privacy: .public), nextOffset: \(index.nextOffset, privacy: .public)")
        indexLogger.debug("Key hash: \(key.rawBytes.hashValue, privacy: .private)")

        let encoded = try JSONEncoder().encode(index)

        indexLogger.debug("Index encoded, size: \(encoded.count, privacy: .public) bytes")

        let encrypted = try CryptoEngine.encrypt(encoded, with: key)

        indexLogger.debug("Index encrypted, size: \(encrypted.count, privacy: .public) bytes")

        let url = indexURL(for: key)
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])

        // Update in-memory cache
        cachedIndex = index
        cachedIndexFingerprint = keyFingerprint(key)

        indexLogger.info("Index saved to disk")
    }

    // MARK: - Master Key

    /// Extract and decrypt the master key from the vault index
    nonisolated func getMasterKey(from index: VaultStorage.VaultIndex, vaultKey: VaultKey) throws -> MasterKey {
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }

        let masterKeyData = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey)
        indexLogger.debug("Master key decrypted")

        return MasterKey(masterKeyData)
    }

    // MARK: - Cache Invalidation

    func invalidateCache() {
        cachedIndex = nil
        cachedIndexFingerprint = nil
    }

    func invalidateCache(for key: VaultKey) {
        let fp = keyFingerprint(key)
        if cachedIndexFingerprint == fp {
            cachedIndex = nil
            cachedIndexFingerprint = nil
        }
    }

    // MARK: - Batch Mode

    /// Begin a batch scope. Index mutations accumulate in the in-memory cache;
    /// disk persistence is deferred until endBatch() or the flush interval is reached.
    func beginBatch() {
        batchDepth += 1
        mutationsSinceFlush = 0
        indexLogger.info("beginBatch (depth=\(self.batchDepth))")
    }

    /// End the outermost batch scope, persisting any accumulated changes to disk.
    func endBatch(key: VaultKey) throws {
        guard batchDepth > 0 else { return }
        batchDepth -= 1
        if batchDepth == 0, let index = cachedIndex {
            indexLogger.info("endBatch: flushing \(self.mutationsSinceFlush) deferred mutations")
            try saveIndex(index, with: key)
            mutationsSinceFlush = 0
        }
    }

    /// Persists the index immediately or defers based on batch mode + flush interval.
    private func persistOrDefer(_ index: VaultStorage.VaultIndex, key: VaultKey) throws {
        if batchDepth > 0 {
            cachedIndex = index
            cachedIndexFingerprint = keyFingerprint(key)
            mutationsSinceFlush += 1
            if mutationsSinceFlush >= Self.batchFlushInterval {
                indexLogger.info("Batch flush at \(self.mutationsSinceFlush) mutations")
                try saveIndex(index, with: key)
                mutationsSinceFlush = 0
            }
        } else {
            try saveIndex(index, with: key)
        }
    }

    // MARK: - Transactions

    /// Execute a compound operation (load → mutate → save) under actor isolation.
    /// Prevents interleaving with other index operations.
    /// In batch mode, defers disk persistence (saves every N mutations).
    func withTransaction<T: Sendable>(
        key: VaultKey,
        body: @Sendable (inout VaultStorage.VaultIndex, MasterKey) throws -> T
    ) throws -> T {
        var index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)
        let result = try body(&index, masterKey)
        try persistOrDefer(index, key: key)
        return result
    }

    /// Execute a compound operation without master key access.
    func withTransaction<T: Sendable>(
        key: VaultKey,
        body: @Sendable (inout VaultStorage.VaultIndex) throws -> T
    ) throws -> T {
        var index = try loadIndex(with: key)
        let result = try body(&index)
        try persistOrDefer(index, key: key)
        return result
    }

    // MARK: - Change Key

    /// Change the vault key (pattern) without re-encrypting files.
    /// Dedicated actor method because it loads with old key and saves with new key.
    /// Self-contained: performs all index checks and mutations under actor isolation.
    func changeKey(from oldKey: VaultKey, to newKey: VaultKey) throws {
        indexLogger.debug("Changing vault key (pattern change)")

        // Check if new key would overwrite an existing vault with actual files
        let newKeyURL = indexURL(for: newKey)
        if fileManager.fileExists(atPath: newKeyURL.path) {
            // Try loading — if it has non-deleted files, reject
            if let existingIndex = try? loadIndex(with: newKey),
               existingIndex.files.contains(where: { !$0.isDeleted }) {
                indexLogger.error("Cannot change to this pattern - vault with files already exists!")
                throw VaultStorageError.vaultAlreadyExists
            }
            // Clean up empty vault index at target key
            invalidateCache(for: newKey)
            try? fileManager.removeItem(at: newKeyURL)
        }

        // 1. Load index with old key
        let index = try loadIndex(with: oldKey)

        indexLogger.debug("Index loaded with old key. Files: \(index.files.count, privacy: .public)")

        // 2. Decrypt master key with old vault key
        let masterKey = try getMasterKey(from: index, vaultKey: oldKey)

        indexLogger.debug("Master key decrypted with old vault key")

        // 3. Re-encrypt master key with NEW vault key
        let newEncryptedMasterKey = try CryptoEngine.encrypt(masterKey.rawBytes, with: newKey)

        indexLogger.debug("Master key re-encrypted with new vault key")

        // 4. Copy index and replace only the master key
        var newIndex = index
        newIndex.encryptedMasterKey = newEncryptedMasterKey

        // 5. Write-ahead: save new index to temp file, verify, then move into place
        let tempURL = newKeyURL.appendingPathExtension("tmp")

        let encoded = try JSONEncoder().encode(newIndex)
        let encrypted = try CryptoEngine.encrypt(encoded, with: newKey)
        try encrypted.write(to: tempURL, options: [.atomic, .completeFileProtection])

        // Verify: read back and decrypt to confirm integrity
        let readBack = try Data(contentsOf: tempURL)
        let decrypted = try CryptoEngine.decrypt(readBack, with: newKey)
        let verified = try JSONDecoder().decode(VaultStorage.VaultIndex.self, from: decrypted)
        guard verified.files.count == newIndex.files.count,
              verified.encryptedMasterKey == newEncryptedMasterKey else {
            try? fileManager.removeItem(at: tempURL)
            throw VaultStorageError.corruptedData
        }

        // Atomic move temp -> final
        if fileManager.fileExists(atPath: newKeyURL.path) {
            try fileManager.removeItem(at: newKeyURL)
        }
        try fileManager.moveItem(at: tempURL, to: newKeyURL)

        indexLogger.debug("New index verified and moved into place")

        // 6. Delete old index file
        let oldKeyURL = indexURL(for: oldKey)
        invalidateCache(for: oldKey)
        if fileManager.fileExists(atPath: oldKeyURL.path) {
            try fileManager.removeItem(at: oldKeyURL)
        }

        // 7. Invalidate all cache
        invalidateCache()

        indexLogger.info("Vault key change complete! No files were re-encrypted.")
    }

    // MARK: - Migration

    private func migrateToV3(_ index: inout VaultStorage.VaultIndex) {
        let globalCursor = readGlobalCursor()
        let cursor = max(globalCursor, index.nextOffset)

        let actualCapacity = cursorFooterOffset()
        let primary = VaultStorage.BlobDescriptor(
            blobId: "primary",
            fileName: blobFileName,
            capacity: actualCapacity,
            cursor: cursor
        )
        index.blobs = [primary]
        index.version = 3

        indexLogger.info("Migrated index to v3. Primary blob cursor: \(cursor, privacy: .public)")
    }
}
