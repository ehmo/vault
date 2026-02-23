import XCTest
@testable import Vault

final class ShareRoundTripTests: XCTestCase {

    private let storage = VaultStorage.shared
    private var ownerKey: VaultKey!
    private var recipientKey: VaultKey!

    override func setUp() {
        super.setUp()
        ownerKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        recipientKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
    }

    override func tearDown() {
        try? storage.deleteVaultIndex(for: ownerKey)
        try? storage.deleteVaultIndex(for: recipientKey)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Derives master key from an index and vault key (mirrors VaultIndexManager.getMasterKey).
    private func getMasterKey(from index: VaultStorage.VaultIndex, vaultKey: VaultKey) throws -> MasterKey {
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }
        return MasterKey(try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey))
    }

    // MARK: - Single File Round Trip

    func testShareRoundTripPreservesFileContent() throws {
        // 1. Owner stores a file
        let ownerIndex = try storage.loadIndex(with: ownerKey)
        try storage.saveIndex(ownerIndex, with: ownerKey)

        let testContent = Data("Hello, this is a secret file for sharing!".utf8)
        let testFilename = "test_share.txt"
        let testMimeType = "text/plain"

        let fileId = try storage.storeFile(
            data: testContent,
            filename: testFilename,
            mimeType: testMimeType,
            with: ownerKey
        )

        // 2. Derive share key from phrase
        let sharePhrase = "test-share-phrase-\(UUID().uuidString)"
        let shareKeyData = try KeyDerivation.deriveShareKey(from: sharePhrase)
        let shareKey = ShareKey(shareKeyData)

        // 3. Owner re-encrypts file with share key
        let index = try storage.loadIndex(with: ownerKey)
        let masterKey = try getMasterKey(from: index, vaultKey: ownerKey)

        guard let fileEntry = index.files.first(where: { $0.fileId == fileId }) else {
            XCTFail("File not found in owner index")
            return
        }

        let (_, plainContent) = try storage.retrieveFileContent(
            entry: fileEntry, index: index, masterKey: masterKey
        )
        XCTAssertEqual(plainContent, testContent, "Owner retrieval should match original")

        let shareEncrypted = try CryptoEngine.encrypt(plainContent, with: shareKey.rawBytes)

        // 4. Recipient decrypts with same share key
        let recipientDecrypted = try CryptoEngine.decrypt(shareEncrypted, with: shareKey.rawBytes)
        XCTAssertEqual(recipientDecrypted, testContent, "Recipient decryption should match original")

        // 5. Recipient stores in their vault
        let recipientIndex = try storage.loadIndex(with: recipientKey)
        try storage.saveIndex(recipientIndex, with: recipientKey)

        let recipientFileId = try storage.storeFile(
            data: recipientDecrypted,
            filename: testFilename,
            mimeType: testMimeType,
            with: recipientKey
        )

        // 6. Verify: retrieve from recipient vault and compare
        let result = try storage.retrieveFile(id: recipientFileId, with: recipientKey)
        XCTAssertEqual(result.content, testContent, "Round-trip content should match original")
        XCTAssertEqual(result.header.originalFilename, testFilename)
        XCTAssertEqual(result.header.mimeType, testMimeType)
    }

    // MARK: - Multiple Files

    func testShareRoundTripWithMultipleFiles() throws {
        // Store 3 files of different types
        let files: [(data: Data, name: String, mime: String)] = [
            (Data("Document content here".utf8), "doc.txt", "text/plain"),
            (Data(repeating: 0xFF, count: 1024), "image.jpg", "image/jpeg"),
            (Data(repeating: 0xAB, count: 512), "data.bin", "application/octet-stream"),
        ]

        let ownerIndex = try storage.loadIndex(with: ownerKey)
        try storage.saveIndex(ownerIndex, with: ownerKey)

        var storedIds: [UUID] = []
        for file in files {
            let id = try storage.storeFile(
                data: file.data, filename: file.name, mimeType: file.mime, with: ownerKey
            )
            storedIds.append(id)
        }

        // Derive share key
        let shareKeyData = try KeyDerivation.deriveShareKey(from: "multi-file-share-\(UUID().uuidString)")
        let shareKey = ShareKey(shareKeyData)

        // Re-encrypt all files
        let index = try storage.loadIndex(with: ownerKey)
        let masterKey = try getMasterKey(from: index, vaultKey: ownerKey)

        var shareEncryptedFiles: [(data: Data, name: String, mime: String)] = []
        for (i, fileId) in storedIds.enumerated() {
            guard let entry = index.files.first(where: { $0.fileId == fileId }) else {
                XCTFail("File \(i) not found in owner index")
                return
            }
            let (_, plain) = try storage.retrieveFileContent(entry: entry, index: index, masterKey: masterKey)
            XCTAssertEqual(plain, files[i].data, "Owner file \(i) should match original")

            let encrypted = try CryptoEngine.encrypt(plain, with: shareKey.rawBytes)
            shareEncryptedFiles.append((data: encrypted, name: files[i].name, mime: files[i].mime))
        }

        // Recipient decrypts and stores all files
        let recipientIndex = try storage.loadIndex(with: recipientKey)
        try storage.saveIndex(recipientIndex, with: recipientKey)

        for (i, shareFile) in shareEncryptedFiles.enumerated() {
            let decrypted = try CryptoEngine.decrypt(shareFile.data, with: shareKey.rawBytes)
            XCTAssertEqual(decrypted, files[i].data, "Recipient decryption of file \(i) should match")

            let recipientId = try storage.storeFile(
                data: decrypted, filename: shareFile.name, mimeType: shareFile.mime, with: recipientKey
            )

            let result = try storage.retrieveFile(id: recipientId, with: recipientKey)
            XCTAssertEqual(result.content, files[i].data, "Round-trip file \(i) content should match")
            XCTAssertEqual(result.header.originalFilename, files[i].name)
        }
    }

    // MARK: - Thumbnail Round Trip

    func testShareRoundTripWithThumbnail() throws {
        let ownerIndex = try storage.loadIndex(with: ownerKey)
        try storage.saveIndex(ownerIndex, with: ownerKey)

        let testContent = Data(repeating: 0xDE, count: 2048)
        let thumbnailData = Data(repeating: 0xBE, count: 256)

        let fileId = try storage.storeFile(
            data: testContent,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            with: ownerKey,
            thumbnailData: thumbnailData
        )

        // Derive share key
        let shareKeyData = try KeyDerivation.deriveShareKey(from: "thumb-share-\(UUID().uuidString)")
        let shareKey = ShareKey(shareKeyData)

        // Re-encrypt content and thumbnail
        let index = try storage.loadIndex(with: ownerKey)
        let masterKey = try getMasterKey(from: index, vaultKey: ownerKey)

        guard let entry = index.files.first(where: { $0.fileId == fileId }) else {
            XCTFail("File not found in owner index")
            return
        }

        let (_, plainContent) = try storage.retrieveFileContent(entry: entry, index: index, masterKey: masterKey)
        XCTAssertEqual(plainContent, testContent)

        let shareEncryptedContent = try CryptoEngine.encrypt(plainContent, with: shareKey.rawBytes)

        // Decrypt and re-encrypt thumbnail
        var shareEncryptedThumb: Data?
        if let encThumb = entry.thumbnailData {
            let plainThumb = try CryptoEngine.decrypt(encThumb, with: masterKey)
            XCTAssertEqual(plainThumb, thumbnailData, "Decrypted thumbnail should match original")
            shareEncryptedThumb = try CryptoEngine.encrypt(plainThumb, with: shareKey.rawBytes)
        }
        XCTAssertNotNil(shareEncryptedThumb, "Thumbnail should exist")

        // Recipient decrypts
        let recipientContent = try CryptoEngine.decrypt(shareEncryptedContent, with: shareKey.rawBytes)
        XCTAssertEqual(recipientContent, testContent)

        let recipientThumb = try CryptoEngine.decrypt(shareEncryptedThumb!, with: shareKey.rawBytes)
        XCTAssertEqual(recipientThumb, thumbnailData, "Thumbnail round-trip should match")

        // Recipient stores
        let recipientIndex = try storage.loadIndex(with: recipientKey)
        try storage.saveIndex(recipientIndex, with: recipientKey)

        let recipientFileId = try storage.storeFile(
            data: recipientContent,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            with: recipientKey,
            thumbnailData: recipientThumb
        )

        let result = try storage.retrieveFile(id: recipientFileId, with: recipientKey)
        XCTAssertEqual(result.content, testContent, "Content round-trip should match")
    }

    // MARK: - SVDF Format Round Trip

    func testShareRoundTripWithSVDF() throws {
        let shareKeyData = CryptoEngine.generateRandomBytes(count: 32)!

        // Create test files as SharedFile objects (already encrypted with share key)
        let file1Content = Data("SVDF file one".utf8)
        let file2Content = Data(repeating: 0xCC, count: 1024)

        let encryptedContent1 = try CryptoEngine.encrypt(file1Content, with: shareKeyData)
        let encryptedContent2 = try CryptoEngine.encrypt(file2Content, with: shareKeyData)

        let file1 = SharedVaultData.SharedFile(
            id: UUID(),
            filename: "svdf_test1.txt",
            mimeType: "text/plain",
            size: file1Content.count,
            encryptedContent: encryptedContent1,
            createdAt: Date(),
            encryptedThumbnail: nil
        )
        let file2 = SharedVaultData.SharedFile(
            id: UUID(),
            filename: "svdf_test2.bin",
            mimeType: "application/octet-stream",
            size: file2Content.count,
            encryptedContent: encryptedContent2,
            createdAt: Date(),
            encryptedThumbnail: nil
        )

        let metadata = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "test-fingerprint",
            sharedAt: Date()
        )

        // Build SVDF
        let (svdfData, manifest) = try SVDFSerializer.buildFull(
            files: [file1, file2],
            metadata: metadata,
            shareKey: shareKeyData
        )

        // Parse SVDF back
        XCTAssertTrue(SVDFSerializer.isSVDF(svdfData))
        let parsedManifest = try SVDFSerializer.parseManifest(from: svdfData, shareKey: shareKeyData)
        XCTAssertEqual(parsedManifest.count, 2)

        // Extract and decrypt each file
        for (i, manifestEntry) in parsedManifest.enumerated() {
            let extracted = try SVDFSerializer.extractFileEntry(
                from: svdfData, at: manifestEntry.offset, size: manifestEntry.size
            )
            let decrypted = try CryptoEngine.decrypt(extracted.encryptedContent, with: shareKeyData)

            let expectedContent = i == 0 ? file1Content : file2Content
            let expectedFilename = i == 0 ? "svdf_test1.txt" : "svdf_test2.bin"

            XCTAssertEqual(decrypted, expectedContent, "SVDF file \(i) content should match after round-trip")
            XCTAssertEqual(extracted.filename, expectedFilename)
        }
    }

    // MARK: - SVDF Streaming Round Trip

    func testShareRoundTripWithSVDFStreaming() throws {
        let shareKeyData = CryptoEngine.generateRandomBytes(count: 32)!

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileContents = [
            Data("streaming file one".utf8),
            Data(repeating: 0xAA, count: 2048),
        ]
        let filenames = ["stream1.txt", "stream2.bin"]
        let mimeTypes = ["text/plain", "application/octet-stream"]

        // Pre-encrypt files
        var sharedFiles: [SharedVaultData.SharedFile] = []
        for (i, content) in fileContents.enumerated() {
            let encrypted = try CryptoEngine.encrypt(content, with: shareKeyData)
            sharedFiles.append(SharedVaultData.SharedFile(
                id: UUID(),
                filename: filenames[i],
                mimeType: mimeTypes[i],
                size: content.count,
                encryptedContent: encrypted,
                createdAt: Date()
            ))
        }

        let metadata = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "stream-test",
            sharedAt: Date()
        )

        let svdfURL = tempDir.appendingPathComponent("test.svdf")

        // Build SVDF via streaming API
        let (manifest, fileIds) = try SVDFSerializer.buildFullStreaming(
            to: svdfURL,
            fileCount: sharedFiles.count,
            forEachFile: { i in sharedFiles[i] },
            metadata: metadata,
            shareKey: shareKeyData
        )

        XCTAssertEqual(fileIds.count, 2)
        XCTAssertEqual(manifest.count, 2)

        // Read back and parse
        let svdfData = try Data(contentsOf: svdfURL)
        let parsedManifest = try SVDFSerializer.parseManifest(from: svdfData, shareKey: shareKeyData)

        for (i, entry) in parsedManifest.enumerated() {
            let extracted = try SVDFSerializer.extractFileEntry(
                from: svdfData, at: entry.offset, size: entry.size
            )
            let decrypted = try CryptoEngine.decrypt(extracted.encryptedContent, with: shareKeyData)
            XCTAssertEqual(decrypted, fileContents[i], "Streaming SVDF file \(i) should round-trip correctly")
        }
    }

    // MARK: - Wrong Key Fails

    func testWrongShareKeyCannotDecrypt() throws {
        let correctKeyData = CryptoEngine.generateRandomBytes(count: 32)!
        let wrongKeyData = CryptoEngine.generateRandomBytes(count: 32)!

        let testContent = Data("secret data".utf8)
        let encrypted = try CryptoEngine.encrypt(testContent, with: correctKeyData)

        XCTAssertThrowsError(
            try CryptoEngine.decrypt(encrypted, with: wrongKeyData),
            "Decryption with wrong key should fail"
        )
    }

    // MARK: - Share Key Determinism

    func testShareKeyDerivationIsDeterministic() throws {
        let phrase = "deterministic-test-\(UUID().uuidString)"
        let key1 = try KeyDerivation.deriveShareKey(from: phrase)
        let key2 = try KeyDerivation.deriveShareKey(from: phrase)
        XCTAssertEqual(key1, key2, "Same phrase should derive the same key")
        XCTAssertEqual(key1.count, 32)
    }

    // MARK: - End-to-End with SVDF Deserialize

    func testFullEndToEndSVDFDeserialize() throws {
        let shareKeyData = CryptoEngine.generateRandomBytes(count: 32)!

        let originalContent = Data("full end-to-end test content".utf8)
        let encryptedContent = try CryptoEngine.encrypt(originalContent, with: shareKeyData)

        let file = SharedVaultData.SharedFile(
            id: UUID(),
            filename: "e2e.txt",
            mimeType: "text/plain",
            size: originalContent.count,
            encryptedContent: encryptedContent,
            createdAt: Date()
        )

        let metadata = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "e2e-test",
            sharedAt: Date()
        )

        // Build SVDF
        let (svdfData, _) = try SVDFSerializer.buildFull(
            files: [file],
            metadata: metadata,
            shareKey: shareKeyData
        )

        // Deserialize completely (as a recipient would)
        let sharedVaultData = try SVDFSerializer.deserialize(from: svdfData, shareKey: shareKeyData)
        XCTAssertEqual(sharedVaultData.files.count, 1)
        XCTAssertEqual(sharedVaultData.files[0].filename, "e2e.txt")
        XCTAssertEqual(sharedVaultData.metadata.ownerFingerprint, "e2e-test")

        // Decrypt the content
        let decrypted = try CryptoEngine.decrypt(sharedVaultData.files[0].encryptedContent, with: shareKeyData)
        XCTAssertEqual(decrypted, originalContent, "End-to-end SVDF round-trip should preserve content")
    }
}
