import Foundation

/// Protocol abstracting VaultStorage for testability.
/// Covers the public API surface used by ShareSyncManager, ShareUploadManager, and other consumers.
protocol VaultStorageProtocol {
    // MARK: - Index Operations

    func loadIndex(with key: VaultKey) throws -> VaultStorage.VaultIndex
    func saveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) throws

    // MARK: - File Operations

    func storeFile(data: Data, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data?, duration: TimeInterval?, fileId: UUID?) throws -> UUID
    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data?, duration: TimeInterval?, fileId: UUID?) throws -> UUID
    func retrieveFile(id: UUID, with key: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data)
    func retrieveFileContent(entry: VaultStorage.VaultIndex.VaultFileEntry, index: VaultStorage.VaultIndex, masterKey: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data)
    func retrieveFileToTempURL(id: UUID, with key: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL)
    func deleteFile(id: UUID, with key: VaultKey) throws
    func deleteFiles(ids: Set<UUID>, with key: VaultKey, onProgress: ((Int) -> Void)?) throws
    func listFiles(with key: VaultKey) throws -> [VaultStorage.VaultFileEntry]
    func listFilesLightweight(with key: VaultKey) throws -> (masterKey: Data, files: [VaultStorage.LightweightFileEntry])

    // MARK: - Vault Lifecycle

    func vaultExists(for key: VaultKey) -> Bool
    func vaultHasFiles(for key: VaultKey) -> Bool
    func deleteVaultIndex(for key: VaultKey) throws
    func destroyAllIndexesExcept(_ preservedKey: VaultKey)
}

// MARK: - Default Parameter Values

extension VaultStorageProtocol {
    func storeFile(data: Data, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data? = nil, fileId: UUID? = nil) throws -> UUID {
        try storeFile(data: data, filename: filename, mimeType: mimeType, with: key, thumbnailData: thumbnailData, duration: nil, fileId: fileId)
    }

    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data? = nil, fileId: UUID? = nil) throws -> UUID {
        try storeFileFromURL(fileURL, filename: filename, mimeType: mimeType, with: key, thumbnailData: thumbnailData, duration: nil, fileId: fileId)
    }

    func deleteFiles(ids: Set<UUID>, with key: VaultKey) throws {
        try deleteFiles(ids: ids, with: key, onProgress: nil)
    }
}

extension VaultStorage: VaultStorageProtocol {}
