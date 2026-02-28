import Foundation
@testable import Vault

/// Configurable mock VaultStorageProtocol for testing.
/// Combines features used across ShareUploadManager, ShareSyncManager, and ShareUploadDebounce tests.
final class MockVaultStorage: VaultStorageProtocol, @unchecked Sendable {
    var indexToReturn: VaultStorage.VaultIndex?
    var loadIndexError: Error?
    var saveIndexError: Error?
    var savedIndexes: [(VaultStorage.VaultIndex, VaultKey)] = []
    var loadIndexCallCount = 0

    /// Convenience initializer with a default non-nil index.
    convenience init(defaultIndex: VaultStorage.VaultIndex) {
        self.init()
        self.indexToReturn = defaultIndex
    }

    func loadIndex(with _: VaultKey) async throws -> VaultStorage.VaultIndex {
        loadIndexCallCount += 1
        if let error = loadIndexError { throw error }
        guard let index = indexToReturn else {
            throw VaultStorageError.corruptedData
        }
        return index
    }

    func saveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) async throws {
        if let error = saveIndexError { throw error }
        savedIndexes.append((index, key))
        indexToReturn = index
    }

    func storeFile(data _: Data, filename _: String, mimeType _: String, with _: VaultKey, thumbnailData _: Data?, duration _: TimeInterval?, fileId _: UUID?) async throws -> UUID { UUID() }
    func storeFileFromURL(_: URL, filename _: String, mimeType _: String, with _: VaultKey, options _: FileStoreOptions) async throws -> UUID { UUID() }
    func retrieveFile(id _: UUID, with _: VaultKey) async throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) { throw VaultStorageError.corruptedData }
    func retrieveFileContent(entry _: VaultStorage.VaultIndex.VaultFileEntry, index _: VaultStorage.VaultIndex, masterKey _: MasterKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) { throw VaultStorageError.corruptedData }
    func retrieveFileToTempURL(id _: UUID, with _: VaultKey) async throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL) { throw VaultStorageError.corruptedData }
    func deleteFile(id _: UUID, with _: VaultKey) async throws { /* No-op */ }
    func deleteFiles(ids _: Set<UUID>, with _: VaultKey, onProgress _: (@Sendable (Int) -> Void)?) async throws { /* No-op */ }
    func listFiles(with _: VaultKey) async throws -> [VaultStorage.VaultFileEntry] { [] }
    func listFilesLightweight(with _: VaultKey) async throws -> (masterKey: MasterKey, files: [VaultStorage.LightweightFileEntry]) { (MasterKey(Data(repeating: 0, count: 32)), []) }
    func vaultExists(for _: VaultKey) -> Bool { true }
    func vaultHasFiles(for _: VaultKey) async -> Bool { false }
    func deleteVaultIndex(for _: VaultKey) throws { /* No-op */ }
    func destroyAllIndexesExcept(_: VaultKey) { /* No-op */ }
}
