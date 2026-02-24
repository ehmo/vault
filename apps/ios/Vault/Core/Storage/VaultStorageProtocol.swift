import Foundation

/// Optional metadata for file store operations, bundling optional parameters.
struct FileStoreOptions: Sendable {
    var thumbnailData: Data?
    var duration: TimeInterval?
    var fileId: UUID?
    var originalDate: Date?

    init(thumbnailData: Data? = nil, duration: TimeInterval? = nil, fileId: UUID? = nil, originalDate: Date? = nil) {
        self.thumbnailData = thumbnailData
        self.duration = duration
        self.fileId = fileId
        self.originalDate = originalDate
    }
}

/// Protocol abstracting VaultStorage for testability.
/// Covers the public API surface used by ShareSyncManager, ShareUploadManager, and other consumers.
protocol VaultStorageProtocol: Sendable {
    // MARK: - Index Operations

    func loadIndex(with key: VaultKey) async throws -> VaultStorage.VaultIndex
    func saveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) async throws

    // MARK: - File Operations

    func storeFile(data: Data, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data?, duration: TimeInterval?, fileId: UUID?) async throws -> UUID
    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: VaultKey, options: FileStoreOptions) async throws -> UUID
    func retrieveFile(id: UUID, with key: VaultKey) async throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data)
    func retrieveFileContent(entry: VaultStorage.VaultIndex.VaultFileEntry, index: VaultStorage.VaultIndex, masterKey: MasterKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data)
    func retrieveFileToTempURL(id: UUID, with key: VaultKey) async throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL)
    func deleteFile(id: UUID, with key: VaultKey) async throws
    func deleteFiles(ids: Set<UUID>, with key: VaultKey, onProgress: (@Sendable (Int) -> Void)?) async throws
    func listFiles(with key: VaultKey) async throws -> [VaultStorage.VaultFileEntry]
    func listFilesLightweight(with key: VaultKey) async throws -> (masterKey: MasterKey, files: [VaultStorage.LightweightFileEntry])

    // MARK: - Vault Lifecycle

    func vaultExists(for key: VaultKey) -> Bool
    func vaultHasFiles(for key: VaultKey) async -> Bool
    func deleteVaultIndex(for key: VaultKey) throws
    func destroyAllIndexesExcept(_ preservedKey: VaultKey)
}

// MARK: - Default Parameter Values

extension VaultStorageProtocol {
    func storeFile(data: Data, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data? = nil, fileId: UUID? = nil) async throws -> UUID {
        try await storeFile(data: data, filename: filename, mimeType: mimeType, with: key, thumbnailData: thumbnailData, duration: nil, fileId: fileId)
    }

    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data? = nil, originalDate: Date? = nil) async throws -> UUID {
        try await storeFileFromURL(fileURL, filename: filename, mimeType: mimeType, with: key, options: FileStoreOptions(thumbnailData: thumbnailData, originalDate: originalDate))
    }

    func deleteFiles(ids: Set<UUID>, with key: VaultKey) async throws {
        try await deleteFiles(ids: ids, with: key, onProgress: nil)
    }
}

extension VaultStorage: VaultStorageProtocol {}
