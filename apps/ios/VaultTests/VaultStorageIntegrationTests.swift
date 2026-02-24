import XCTest
@testable import Vault

final class VaultStorageIntegrationTests: XCTestCase {

    private var testKey: VaultKey!
    private var extraKeys: [VaultKey] = []
    private let storage = VaultStorage.shared

    override func setUp() {
        super.setUp()
        testKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        extraKeys = []
    }

    override func tearDown() {
        // Clean up all keys used in this test
        for key in [testKey!] + extraKeys {
            try? storage.deleteVaultIndex(for: key)
        }
        super.tearDown()
    }

    // MARK: - Index Round Trip

    func testSaveAndLoadIndexRoundTrip() async throws {
        let index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 50 * 1024 * 1024)
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(loaded.files.count, 0)
        XCTAssertEqual(loaded.totalSize, 50 * 1024 * 1024)
    }

    // MARK: - Vault Exists

    func testVaultExistsReturnsTrueAfterSave() async throws {
        XCTAssertFalse(storage.vaultExists(for: testKey))

        let index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 50 * 1024 * 1024)
        try await storage.saveIndex(index, with: testKey)

        XCTAssertTrue(storage.vaultExists(for: testKey))
    }

    func testVaultExistsReturnsFalseForUnknownKey() {
        let randomKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        extraKeys.append(randomKey)
        XCTAssertFalse(storage.vaultExists(for: randomKey))
    }

    // MARK: - Delete Vault Index

    func testDeleteVaultIndex() async throws {
        let index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 50 * 1024 * 1024)
        try await storage.saveIndex(index, with: testKey)
        XCTAssertTrue(storage.vaultExists(for: testKey))

        try storage.deleteVaultIndex(for: testKey)
        XCTAssertFalse(storage.vaultExists(for: testKey))
    }

    // MARK: - File Operations

    func testStoreAndRetrieveFile() async throws {
        // loadIndex auto-creates a proper v3 index with master key
        let index = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(index, with: testKey)

        let content = Data("test file content".utf8)
        let fileId = try await storage.storeFile(
            data: content, filename: "test.txt", mimeType: "text/plain", with: testKey
        )

        let result = try await storage.retrieveFile(id: fileId, with: testKey)
        XCTAssertEqual(result.content, content)
        XCTAssertEqual(result.header.originalFilename, "test.txt")
        XCTAssertEqual(result.header.mimeType, "text/plain")
    }

    func testStoreFromURLAndRetrieveToTempURLStreamingRoundTrip() async throws {
        let index = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(index, with: testKey)

        let payloadSize = VaultCoreConstants.streamingThreshold + (128 * 1024)
        let sourceBytes = Data((0..<payloadSize).map { UInt8($0 % 251) })
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        try sourceBytes.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let fileId = try await storage.storeFileFromURL(
            sourceURL,
            filename: "stream.bin",
            mimeType: "application/octet-stream",
            with: testKey
        )

        let result = try await storage.retrieveFileToTempURL(id: fileId, with: testKey)
        defer { try? FileManager.default.removeItem(at: result.tempURL) }

        XCTAssertEqual(result.header.originalFilename, "stream.bin")
        XCTAssertEqual(Int(result.header.originalSize), payloadSize)

        let restoredBytes = try Data(contentsOf: result.tempURL)
        XCTAssertEqual(restoredBytes, sourceBytes)
    }

    func testStoreAndListFiles() async throws {
        let index = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(index, with: testKey)

        var storedIds: [UUID] = []
        for i in 0..<3 {
            let id = try await storage.storeFile(
                data: Data("file \(i)".utf8),
                filename: "file\(i).txt",
                mimeType: "text/plain",
                with: testKey
            )
            storedIds.append(id)
        }

        let listed = try await storage.listFiles(with: testKey)
        XCTAssertEqual(listed.count, 3)

        let listedIds = Set(listed.map(\.fileId))
        for id in storedIds {
            XCTAssertTrue(listedIds.contains(id))
        }
    }

    func testDeleteFile() async throws {
        let index = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(index, with: testKey)

        let fileId = try await storage.storeFile(
            data: Data("delete me".utf8), filename: "temp.txt", mimeType: "text/plain", with: testKey
        )
        let countBeforeDelete = try await storage.listFiles(with: testKey).count
        XCTAssertEqual(countBeforeDelete, 1)

        try await storage.deleteFile(id: fileId, with: testKey)
        let countAfterDelete = try await storage.listFiles(with: testKey).count
        XCTAssertEqual(countAfterDelete, 0)
    }

    func testRetrieveDeletedFileThrows() async throws {
        let index = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(index, with: testKey)

        let fileId = try await storage.storeFile(
            data: Data("gone".utf8), filename: "gone.txt", mimeType: "text/plain", with: testKey
        )
        try await storage.deleteFile(id: fileId, with: testKey)

        do {
            _ = try await storage.retrieveFile(id: fileId, with: testKey)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? VaultStorageError, .fileNotFound)
        }
    }

    // MARK: - Change Vault Key

    func testChangeVaultKey() async throws {
        let index = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(index, with: testKey)

        let fileId = try await storage.storeFile(
            data: Data("survives key change".utf8),
            filename: "persist.txt",
            mimeType: "text/plain",
            with: testKey
        )

        let newKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        extraKeys.append(newKey)

        try await storage.changeVaultKey(from: testKey, to: newKey)

        // Old key no longer works
        XCTAssertFalse(storage.vaultExists(for: testKey))

        // New key finds the vault with the file
        XCTAssertTrue(storage.vaultExists(for: newKey))
        let result = try await storage.retrieveFile(id: fileId, with: newKey)
        XCTAssertEqual(result.content, Data("survives key change".utf8))
    }

    // MARK: - Index Codable

    func testIndexCodableRoundTrip() throws {
        let entry = VaultStorage.VaultIndex.VaultFileEntry(
            fileId: UUID(),
            offset: 1024,
            size: 2048,
            encryptedHeaderPreview: Data(repeating: 0xAB, count: 64),
            isDeleted: false,
            thumbnailData: nil,
            mimeType: "image/png",
            filename: "photo.png",
            blobId: nil,
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let masterKey = CryptoEngine.generateRandomBytes(count: 32)!
        let encryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: key)

        let index = VaultStorage.VaultIndex(
            files: [entry],
            nextOffset: 3072,
            totalSize: 50 * 1024 * 1024,
            encryptedMasterKey: encryptedMasterKey,
            version: 3
        )

        let encoded = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(VaultStorage.VaultIndex.self, from: encoded)

        XCTAssertEqual(decoded.files.count, 1)
        XCTAssertEqual(decoded.files[0].fileId, entry.fileId)
        XCTAssertEqual(decoded.files[0].offset, 1024)
        XCTAssertEqual(decoded.files[0].size, 2048)
        XCTAssertEqual(decoded.files[0].mimeType, "image/png")
        XCTAssertEqual(decoded.files[0].filename, "photo.png")
        XCTAssertEqual(decoded.nextOffset, 3072)
        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.encryptedMasterKey, encryptedMasterKey)
    }
}
