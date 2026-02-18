import XCTest
@testable import Vault

final class VaultFullChainTests: XCTestCase {

    private let storage = VaultStorage.shared
    private var testKeys: [Data] = []

    override func setUp() {
        super.setUp()
        testKeys = []
    }

    override func tearDown() {
        for key in testKeys {
            try? storage.deleteVaultIndex(for: key)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// Derives a test key from a pattern using PatternSerializer + a simple hash.
    /// Does NOT use KeyDerivation.deriveKey (which requires SecureEnclave).
    private func deriveTestKey(from pattern: [Int]) -> Data {
        let serialized = PatternSerializer.serialize(pattern, gridSize: 5)
        // Use the serialized pattern hash directly as a 32-byte key
        // (PatternSerializer.serialize already returns a SHA-256 hash = 32 bytes)
        return serialized
    }

    private func registerKey(_ key: Data) {
        testKeys.append(key)
    }

    private func initializeVault(with key: Data) throws {
        let index = try storage.loadIndex(with: key)
        try storage.saveIndex(index, with: key)
    }

    // MARK: - Full Chain: Pattern -> Key -> Store -> Retrieve

    func testFullChainPatternToFile() throws {
        // 1. Create a pattern and derive key
        let pattern = [0, 1, 6, 7, 12, 13]
        let key = deriveTestKey(from: pattern)
        registerKey(key)

        // 2. Initialize vault
        try initializeVault(with: key)

        // 3. Store a file
        let content = Data("Hello from the full chain test!".utf8)
        let fileId = try storage.storeFile(
            data: content,
            filename: "chain_test.txt",
            mimeType: "text/plain",
            with: key
        )

        // 4. Retrieve and verify
        let result = try storage.retrieveFile(id: fileId, with: key)
        XCTAssertEqual(result.content, content, "Retrieved content should match stored content")
        XCTAssertEqual(result.header.originalFilename, "chain_test.txt")
        XCTAssertEqual(result.header.mimeType, "text/plain")
    }

    func testFullChainWithThumbnail() throws {
        let pattern = [0, 5, 10, 11, 12, 13]
        let key = deriveTestKey(from: pattern)
        registerKey(key)

        try initializeVault(with: key)

        let content = Data("image data placeholder".utf8)
        let thumbnail = Data("thumbnail placeholder".utf8)
        let fileId = try storage.storeFile(
            data: content,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            with: key,
            thumbnailData: thumbnail
        )

        // Verify the file is listed with thumbnail
        let listed = try storage.listFiles(with: key)
        XCTAssertEqual(listed.count, 1)

        let entry = listed.first!
        XCTAssertEqual(entry.fileId, fileId)
        XCTAssertEqual(entry.filename, "photo.jpg")
        XCTAssertEqual(entry.mimeType, "image/jpeg")
        XCTAssertNotNil(entry.thumbnailData, "Thumbnail should be present in listing")
        XCTAssertEqual(entry.thumbnailData, thumbnail,
                       "Decrypted thumbnail in listing should match original")
    }

    func testFullChainStoreMultipleRetrieveAll() throws {
        let pattern = [0, 1, 2, 7, 12, 17]
        let key = deriveTestKey(from: pattern)
        registerKey(key)

        try initializeVault(with: key)

        // Store 3 files
        var storedIds: [UUID] = []
        let filenames = ["doc1.txt", "doc2.txt", "doc3.txt"]
        for (i, filename) in filenames.enumerated() {
            let id = try storage.storeFile(
                data: Data("content \(i)".utf8),
                filename: filename,
                mimeType: "text/plain",
                with: key
            )
            storedIds.append(id)
        }

        // List and verify all 3 are present
        let listed = try storage.listFiles(with: key)
        XCTAssertEqual(listed.count, 3, "All 3 files should be listed")

        let listedIds = Set(listed.map(\.fileId))
        for id in storedIds {
            XCTAssertTrue(listedIds.contains(id),
                          "File \(id) should be present in listing")
        }

        let listedFilenames = Set(listed.compactMap(\.filename))
        for filename in filenames {
            XCTAssertTrue(listedFilenames.contains(filename),
                          "Filename '\(filename)' should be present in listing")
        }
    }

    func testFullChainDeleteReducesFileCount() throws {
        let pattern = [0, 5, 6, 11, 16, 21]
        let key = deriveTestKey(from: pattern)
        registerKey(key)

        try initializeVault(with: key)

        // Store 2 files
        let id1 = try storage.storeFile(
            data: Data("file one".utf8),
            filename: "one.txt",
            mimeType: "text/plain",
            with: key
        )
        let _ = try storage.storeFile(
            data: Data("file two".utf8),
            filename: "two.txt",
            mimeType: "text/plain",
            with: key
        )

        XCTAssertEqual(try storage.listFiles(with: key).count, 2)

        // Delete one file
        try storage.deleteFile(id: id1, with: key)

        let remaining = try storage.listFiles(with: key)
        XCTAssertEqual(remaining.count, 1, "Only 1 file should remain after deletion")
        XCTAssertEqual(remaining.first?.filename, "two.txt")
    }

    func testWrongKeyCannotRetrieve() throws {
        let pattern1 = [0, 1, 2, 3, 4, 9]
        let key1 = deriveTestKey(from: pattern1)
        registerKey(key1)

        try initializeVault(with: key1)

        let fileId = try storage.storeFile(
            data: Data("secret".utf8),
            filename: "secret.txt",
            mimeType: "text/plain",
            with: key1
        )

        // Try to retrieve with a different key
        let pattern2 = [20, 21, 22, 23, 24, 19]
        let key2 = deriveTestKey(from: pattern2)
        registerKey(key2)

        // The wrong key should either fail to load the index or fail to decrypt the file.
        // loadIndex with key2 creates a new empty vault (different index file),
        // so retrieveFile should throw fileNotFound.
        XCTAssertThrowsError(try storage.retrieveFile(id: fileId, with: key2)) { error in
            XCTAssertEqual(error as? VaultStorageError, .fileNotFound,
                           "Wrong key should not find the file (different vault index)")
        }
    }
}
