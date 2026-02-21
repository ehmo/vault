import Foundation
import CryptoKit
import os

private let indexLogger = Logger(subsystem: "com.vaultaire.vault", category: "index")

/// Manages all vault index operations: load, save, cache, migration, and master key extraction.
/// Extracted from VaultStorage to isolate index concerns for future @MainActor adoption.
final class VaultIndexManager {

    private let fileManager = FileManager.default

    /// Serializes all index read/write operations to prevent concurrent access races
    /// between VaultView, ShareSyncManager, and ShareImportManager.
    /// Recursive lock allows compound operations (load+modify+save) to call loadIndex/saveIndex internally.
    let indexLock = NSRecursiveLock()

    // In-memory index cache -- avoids decrypt+decode on every retrieveFile/listFiles call
    private var cachedIndex: VaultStorage.VaultIndex?
    private var cachedIndexFingerprint: String?

    // Properties from VaultStorage context
    private let documentsURL: URL
    private let blobFileName: String
    private let defaultBlobSize: Int
    private let cursorBlockOffset: Int

    /// Closure that reads the global cursor from the blob footer.
    /// Set by VaultStorage after init to avoid circular dependency.
    var readGlobalCursor: () -> Int = { 0 }

    /// Closure that returns the actual cursor footer offset (handles legacy 500MB blobs).
    var cursorFooterOffset: () -> Int = { 0 }

    init(documentsURL: URL, blobFileName: String, defaultBlobSize: Int, cursorBlockOffset: Int) {
        self.documentsURL = documentsURL
        self.blobFileName = blobFileName
        self.defaultBlobSize = defaultBlobSize
        self.cursorBlockOffset = cursorBlockOffset
    }

    // MARK: - Index URL

    /// Returns the index file URL for a specific vault key.
    /// Each vault gets its own index file based on a hash of the key.
    func indexURL(for key: VaultKey) -> URL {
        let keyHash = SHA256.hash(data: key.rawBytes)
        let fingerprint = keyHash.prefix(16).map { String(format: "%02x", $0) }.joined()
        let fileName = "vault_index_\(fingerprint).bin"

        indexLogger.debug("Index file for this vault: \(fileName, privacy: .public)")

        return documentsURL.appendingPathComponent(fileName)
    }

    // MARK: - Key Fingerprint

    func keyFingerprint(_ key: VaultKey) -> String {
        SHA256.hash(data: key.rawBytes).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Load Index

    func loadIndex(with key: VaultKey) throws -> VaultStorage.VaultIndex {
        indexLock.lock()
        defer { indexLock.unlock() }
        return try performLoadIndex(with: key)
    }

    private func performLoadIndex(with key: VaultKey) throws -> VaultStorage.VaultIndex {
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
            let encryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: key.rawBytes)
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
            let decryptedData = try CryptoEngine.decrypt(encryptedData, with: key.rawBytes)
            var index = try JSONDecoder().decode(VaultStorage.VaultIndex.self, from: decryptedData)

            indexLogger.info("Index decrypted. Files: \(index.files.count, privacy: .public), nextOffset: \(index.nextOffset, privacy: .public), version: \(index.version, privacy: .public)")

            // Migration: If index doesn't have a master key (version 1), create one
            if index.encryptedMasterKey == nil {
                indexLogger.info("Migrating vault to use master key (v1 -> v2)")
                guard let masterKeyData = CryptoEngine.generateRandomBytes(count: 32) else {
                    throw VaultStorageError.corruptedData
                }
                index.encryptedMasterKey = try CryptoEngine.encrypt(masterKeyData, with: key.rawBytes)
                index.version = 2

                try performSaveIndex(index, with: key)

                indexLogger.info("Vault migrated to v2 with master key")
            }

            // Migration: v2 -> v3 (add blob descriptors)
            if index.version < 3 {
                indexLogger.info("Migrating vault v2 -> v3 (multi-blob)")
                migrateToV3(&index)
                try performSaveIndex(index, with: key)

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
        indexLock.lock()
        defer { indexLock.unlock() }
        try performSaveIndex(index, with: key)
    }

    private func performSaveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) throws {
        let span = EmbraceManager.shared.startTransaction(name: "storage.index_save", operation: "storage.index_save")
        defer { span.finish(status: .ok) }

        indexLogger.debug("saveIndex called")
        indexLogger.debug("Files: \(index.files.count, privacy: .public), nextOffset: \(index.nextOffset, privacy: .public)")
        indexLogger.debug("Key hash: \(key.rawBytes.hashValue, privacy: .private)")

        let encoded = try JSONEncoder().encode(index)

        indexLogger.debug("Index encoded, size: \(encoded.count, privacy: .public) bytes")

        let encrypted = try CryptoEngine.encrypt(encoded, with: key.rawBytes)

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
    func getMasterKey(from index: VaultStorage.VaultIndex, vaultKey: VaultKey) throws -> Data {
        indexLogger.info("[DEBUG] getMasterKey called - hasEncryptedMasterKey: \(index.encryptedMasterKey != nil)")
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            indexLogger.error("[DEBUG] encryptedMasterKey is nil - throwing corruptedData error")
            throw VaultStorageError.corruptedData
        }

        indexLogger.info("[DEBUG] Decrypting master key...")
        let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey.rawBytes)
        indexLogger.info("[DEBUG] Master key decrypted successfully, length: \(masterKey.count)")

        indexLogger.debug("Master key decrypted")

        return masterKey
    }

    // MARK: - Cache Invalidation

    /// Invalidate cache unconditionally (used by destroyAllVaultData).
    func invalidateCache() {
        cachedIndex = nil
        cachedIndexFingerprint = nil
    }

    /// Invalidate cache for a specific key fingerprint (used by deleteVaultIndex).
    func invalidateCache(for key: VaultKey) {
        let fp = keyFingerprint(key)
        if cachedIndexFingerprint == fp {
            cachedIndex = nil
            cachedIndexFingerprint = nil
        }
    }

    // MARK: - Migration

    /// Migrate a v2 index to v3 by adding blob descriptors.
    private func migrateToV3(_ index: inout VaultStorage.VaultIndex) {
        let globalCursor = readGlobalCursor()
        let cursor = max(globalCursor, index.nextOffset)

        // Use actual file size for capacity -- legacy blobs may be 500MB
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
