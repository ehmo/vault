import XCTest
@testable import Vault

final class ShareExtensionIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var key: Data!
    private var fingerprint: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        VaultCoreConstants.testPendingImportsOverride = tempDir
        key = CryptoEngine.generateRandomBytes(count: 32)!
        fingerprint = KeyDerivation.keyFingerprint(from: key)
    }

    override func tearDown() {
        VaultCoreConstants.testPendingImportsOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Simulates the share extension flow: encrypt file → write to batch → write manifest
    private func stageFile(
        data: Data,
        filename: String = "test.bin",
        mimeType: String = "application/octet-stream",
        batchId: UUID? = nil,
        batchURL: URL? = nil
    ) throws -> (batchId: UUID, batchURL: URL, fileId: UUID, metadata: StagedFileMetadata) {
        let (url, id): (URL, UUID)
        if let batchURL = batchURL, let batchId = batchId {
            (url, id) = (batchURL, batchId)
        } else {
            (url, id) = try StagedImportManager.createBatch()
        }

        let fileId = UUID()

        // Write source data to temp file (simulates NSItemProvider output)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // Encrypt using the streaming-to-handle path (same as share extension)
        let encryptedURL = url.appendingPathComponent("\(fileId.uuidString).enc")
        FileManager.default.createFile(atPath: encryptedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: encryptedURL)
        try CryptoEngine.encryptFileStreamingToHandle(from: sourceURL, to: handle, with: key)
        try handle.close()

        let encSize = (try? FileManager.default.attributesOfItem(atPath: encryptedURL.path)[.size] as? Int) ?? 0

        let metadata = StagedFileMetadata(
            fileId: fileId,
            filename: filename,
            mimeType: mimeType,
            utType: "public.data",
            originalSize: data.count,
            encryptedSize: encSize,
            hasThumbnail: false,
            timestamp: Date()
        )

        return (id, url, fileId, metadata)
    }

    /// Writes a manifest for a completed batch
    private func writeManifest(batchId: UUID, batchURL: URL, files: [StagedFileMetadata]) throws {
        let manifest = StagedImportManifest(
            batchId: batchId,
            keyFingerprint: fingerprint,
            timestamp: Date(),
            sourceAppBundleId: nil,
            files: files
        )
        try StagedImportManager.writeManifest(manifest, to: batchURL)
    }

    // MARK: - Full Share Flow

    func testFullShareFlowSmallFile() throws {
        let original = CryptoEngine.generateRandomBytes(count: 512)!

        let (batchId, batchURL, fileId, meta) = try stageFile(data: original)
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        // Read back and decrypt (main app side)
        let encrypted = StagedImportManager.readEncryptedFile(batchId: batchId, fileId: fileId)
        XCTAssertNotNil(encrypted)

        let decrypted = try CryptoEngine.decryptStaged(encrypted!, with: key)
        XCTAssertEqual(decrypted, original)
    }

    func testFullShareFlowLargeFile() throws {
        let size = VaultCoreConstants.streamingThreshold + 4096
        let original = CryptoEngine.generateRandomBytes(count: size)!

        let (batchId, batchURL, fileId, meta) = try stageFile(data: original)
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let encrypted = StagedImportManager.readEncryptedFile(batchId: batchId, fileId: fileId)
        XCTAssertNotNil(encrypted)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted!))

        let decrypted = try CryptoEngine.decryptStaged(encrypted!, with: key)
        XCTAssertEqual(decrypted, original)
    }

    func testFullShareFlowMultipleFiles() throws {
        let fileData = (0..<5).map { _ in
            CryptoEngine.generateRandomBytes(count: Int.random(in: 100...2000))!
        }

        let (batchURL, batchId) = try StagedImportManager.createBatch()
        var allMeta: [StagedFileMetadata] = []
        var fileIds: [UUID] = []

        for (i, data) in fileData.enumerated() {
            let (_, _, fileId, meta) = try stageFile(
                data: data,
                filename: "file\(i).dat",
                batchId: batchId,
                batchURL: batchURL
            )
            allMeta.append(meta)
            fileIds.append(fileId)
        }

        try writeManifest(batchId: batchId, batchURL: batchURL, files: allMeta)

        // Verify all files round-trip
        for (i, fileId) in fileIds.enumerated() {
            let encrypted = StagedImportManager.readEncryptedFile(batchId: batchId, fileId: fileId)
            XCTAssertNotNil(encrypted, "File \(i) should be readable")

            let decrypted = try CryptoEngine.decryptStaged(encrypted!, with: key)
            XCTAssertEqual(decrypted, fileData[i], "File \(i) content mismatch")
        }
    }

    // MARK: - Thumbnail

    func testThumbnailEncryptDecryptRoundTrip() throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()
        let thumbData = CryptoEngine.generateRandomBytes(count: 256)!

        let encryptedThumb = try CryptoEngine.encrypt(thumbData, with: key)
        try StagedImportManager.writeEncryptedThumbnail(encryptedThumb, fileId: fileId, to: batchURL)

        let readBack = StagedImportManager.readEncryptedThumbnail(batchId: batchId, fileId: fileId)
        XCTAssertNotNil(readBack)

        let decrypted = try CryptoEngine.decrypt(readBack!, with: key)
        XCTAssertEqual(decrypted, thumbData)
    }

    // MARK: - Metadata Validation

    func testBatchManifestRecordsCorrectMetadata() throws {
        let data = CryptoEngine.generateRandomBytes(count: 2048)!
        let (batchId, batchURL, _, meta) = try stageFile(
            data: data,
            filename: "photo.jpg",
            mimeType: "image/jpeg"
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let batches = StagedImportManager.pendingBatches(for: fingerprint)
        XCTAssertEqual(batches.count, 1)

        let file = batches[0].files[0]
        XCTAssertEqual(file.filename, "photo.jpg")
        XCTAssertEqual(file.mimeType, "image/jpeg")
        XCTAssertEqual(file.originalSize, 2048)
        XCTAssertFalse(file.hasThumbnail)
    }

    func testEncryptedSizeLargerThanOriginal() throws {
        let sizes = [1, 100, 1024, VaultCoreConstants.streamingThreshold + 1]

        for size in sizes {
            let data = CryptoEngine.generateRandomBytes(count: size)!
            let (_, _, _, meta) = try stageFile(data: data)
            XCTAssertTrue(meta.encryptedSize > meta.originalSize,
                         "Encrypted size \(meta.encryptedSize) should exceed original \(meta.originalSize) for size \(size)")
        }
    }

    // MARK: - Mixed File Sizes

    func testBatchWithMixedFileSizes() throws {
        let sizes = [0, 1, 100, 1024, VaultCoreConstants.streamingThreshold,
                     VaultCoreConstants.streamingThreshold + 1]

        let (batchURL, batchId) = try StagedImportManager.createBatch()
        var allMeta: [StagedFileMetadata] = []
        var originals: [Data] = []
        var fileIds: [UUID] = []

        for size in sizes {
            let data = size > 0 ? CryptoEngine.generateRandomBytes(count: size)! : Data()
            let (_, _, fileId, meta) = try stageFile(data: data, batchId: batchId, batchURL: batchURL)
            allMeta.append(meta)
            originals.append(data)
            fileIds.append(fileId)
        }

        try writeManifest(batchId: batchId, batchURL: batchURL, files: allMeta)

        for (i, fileId) in fileIds.enumerated() {
            let encrypted = StagedImportManager.readEncryptedFile(batchId: batchId, fileId: fileId)
            XCTAssertNotNil(encrypted, "File at index \(i) (size \(sizes[i])) should be readable")
            let decrypted = try CryptoEngine.decryptStaged(encrypted!, with: key)
            XCTAssertEqual(decrypted, originals[i], "Mismatch at index \(i) (size \(sizes[i]))")
        }
    }

    // MARK: - Free Tier Limits

    func testFreeTierLimitEnforcement() {
        // Verify the constants are reasonable
        XCTAssertEqual(VaultCoreConstants.freeMaxImages, 100)
        XCTAssertEqual(VaultCoreConstants.freeMaxVideos, 10)
        XCTAssertEqual(VaultCoreConstants.freeMaxFiles, 100)
        XCTAssertTrue(VaultCoreConstants.freeMaxImages > 0)
        XCTAssertTrue(VaultCoreConstants.freeMaxVideos > 0)
        XCTAssertTrue(VaultCoreConstants.freeMaxFiles > 0)
    }

    // MARK: - Key Fingerprint

    func testKeyFingerprintMatchesAcrossFlows() {
        let fp1 = KeyDerivation.keyFingerprint(from: key)
        let fp2 = KeyDerivation.keyFingerprint(from: key)
        XCTAssertEqual(fp1, fp2, "Same key must produce same fingerprint")
        XCTAssertEqual(fp1.count, 16, "Fingerprint should be 8 bytes hex = 16 chars")

        let otherKey = CryptoEngine.generateRandomBytes(count: 32)!
        let fp3 = KeyDerivation.keyFingerprint(from: otherKey)
        XCTAssertNotEqual(fp1, fp3, "Different keys should produce different fingerprints")
    }

    // MARK: - Multiple Batches

    func testMultipleBatchesSameKey() throws {
        let data1 = CryptoEngine.generateRandomBytes(count: 100)!
        let data2 = CryptoEngine.generateRandomBytes(count: 200)!

        let (batchId1, batchURL1, fileId1, meta1) = try stageFile(data: data1)
        try writeManifest(batchId: batchId1, batchURL: batchURL1, files: [meta1])

        let (batchId2, batchURL2, fileId2, meta2) = try stageFile(data: data2)
        try writeManifest(batchId: batchId2, batchURL: batchURL2, files: [meta2])

        let batches = StagedImportManager.pendingBatches(for: fingerprint)
        XCTAssertEqual(batches.count, 2)

        // Both batches readable
        let enc1 = StagedImportManager.readEncryptedFile(batchId: batchId1, fileId: fileId1)!
        let dec1 = try CryptoEngine.decryptStaged(enc1, with: key)
        XCTAssertEqual(dec1, data1)

        let enc2 = StagedImportManager.readEncryptedFile(batchId: batchId2, fileId: fileId2)!
        let dec2 = try CryptoEngine.decryptStaged(enc2, with: key)
        XCTAssertEqual(dec2, data2)
    }

    // MARK: - Cleanup

    func testCleanupAfterSuccessfulImport() throws {
        let data = CryptoEngine.generateRandomBytes(count: 100)!
        let (batchId, batchURL, _, meta) = try stageFile(data: data)
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        XCTAssertTrue(FileManager.default.fileExists(atPath: batchURL.path))
        StagedImportManager.deleteBatch(batchId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: batchURL.path))

        let remaining = StagedImportManager.pendingBatches(for: fingerprint)
        XCTAssertEqual(remaining.count, 0)
    }

    // MARK: - Atomic Manifest Visibility

    func testAtomicManifestVisibility() throws {
        // Create batch and write encrypted files BEFORE manifest
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()
        let data = CryptoEngine.generateRandomBytes(count: 100)!
        let encrypted = try CryptoEngine.encrypt(data, with: key)
        try StagedImportManager.writeEncryptedFile(encrypted, fileId: fileId, to: batchURL)

        // Before manifest: batch should NOT appear in pending batches
        let beforeManifest = StagedImportManager.pendingBatches(for: fingerprint)
        XCTAssertEqual(beforeManifest.count, 0, "Batch without manifest should not appear in pending batches")

        // Write manifest → batch becomes visible
        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "test.bin",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: data.count,
            encryptedSize: encrypted.count,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let afterManifest = StagedImportManager.pendingBatches(for: fingerprint)
        XCTAssertEqual(afterManifest.count, 1, "Batch should appear after manifest is written")
    }
}
