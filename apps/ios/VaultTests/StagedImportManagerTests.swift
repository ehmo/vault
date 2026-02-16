import XCTest
@testable import Vault

final class StagedImportManagerTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        VaultCoreConstants.testPendingImportsOverride = tempDir
    }

    override func tearDown() {
        VaultCoreConstants.testPendingImportsOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func createManifest(
        batchId: UUID = UUID(),
        fingerprint: String = "abcd1234",
        fileCount: Int = 1,
        timestamp: Date = Date(),
        sourceApp: String? = "com.example.app",
        retryCount: Int = 0
    ) -> StagedImportManifest {
        let files = (0..<fileCount).map { i in
            StagedFileMetadata(
                fileId: UUID(),
                filename: "file\(i).jpg",
                mimeType: "image/jpeg",
                utType: "public.jpeg",
                originalSize: 1024 * (i + 1),
                encryptedSize: 1052 * (i + 1),
                hasThumbnail: i == 0,
                timestamp: timestamp
            )
        }
        return StagedImportManifest(
            batchId: batchId,
            keyFingerprint: fingerprint,
            timestamp: timestamp,
            sourceAppBundleId: sourceApp,
            files: files,
            retryCount: retryCount
        )
    }

    @discardableResult
    private func writeBatch(_ manifest: StagedImportManifest) throws -> URL {
        let batchURL = tempDir.appendingPathComponent(manifest.batchId.uuidString)
        try FileManager.default.createDirectory(at: batchURL, withIntermediateDirectories: true)
        try StagedImportManager.writeManifest(manifest, to: batchURL)
        return batchURL
    }

    // MARK: - Batch Creation

    func testCreateBatchCreatesDirectory() throws {
        let (url, batchId) = try StagedImportManager.createBatch()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.path.contains(batchId.uuidString))
    }

    // MARK: - Manifest Round Trip

    func testWriteAndReadManifestRoundTrip() throws {
        let batchId = UUID()
        let manifest = createManifest(batchId: batchId, fileCount: 3)
        let batchURL = try writeBatch(manifest)

        let manifestURL = batchURL.appendingPathComponent(VaultCoreConstants.manifestFilename)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(StagedImportManifest.self, from: data)

        XCTAssertEqual(restored.batchId, batchId)
        XCTAssertEqual(restored.keyFingerprint, "abcd1234")
        XCTAssertEqual(restored.files.count, 3)
        XCTAssertEqual(restored.files[0].filename, "file0.jpg")
        XCTAssertEqual(restored.files[1].filename, "file1.jpg")
        XCTAssertEqual(restored.files[2].filename, "file2.jpg")
    }

    func testManifestRetryCountDefaultsToZero() throws {
        let manifest = createManifest()
        let batchURL = try writeBatch(manifest)

        let manifestURL = batchURL.appendingPathComponent(VaultCoreConstants.manifestFilename)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(StagedImportManifest.self, from: data)
        XCTAssertEqual(restored.retryCount, 0)
    }

    // MARK: - File Read/Write

    func testWriteAndReadEncryptedFile() throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()
        let content = CryptoEngine.generateRandomBytes(count: 512)!

        try StagedImportManager.writeEncryptedFile(content, fileId: fileId, to: batchURL)
        let readBack = StagedImportManager.readEncryptedFile(batchId: batchId, fileId: fileId)

        XCTAssertEqual(readBack, content)
    }

    func testWriteAndReadEncryptedThumbnail() throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()
        let thumbData = CryptoEngine.generateRandomBytes(count: 128)!

        try StagedImportManager.writeEncryptedThumbnail(thumbData, fileId: fileId, to: batchURL)
        let readBack = StagedImportManager.readEncryptedThumbnail(batchId: batchId, fileId: fileId)

        XCTAssertEqual(readBack, thumbData)
    }

    func testReadNonexistentFileReturnsNil() throws {
        let (_, batchId) = try StagedImportManager.createBatch()
        let result = StagedImportManager.readEncryptedFile(batchId: batchId, fileId: UUID())
        XCTAssertNil(result)
    }

    func testReadNonexistentThumbnailReturnsNil() throws {
        let (_, batchId) = try StagedImportManager.createBatch()
        let result = StagedImportManager.readEncryptedThumbnail(batchId: batchId, fileId: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Pending Batches

    func testPendingBatchesFiltersByFingerprint() throws {
        let m1 = createManifest(fingerprint: "aaaa1111")
        let m2 = createManifest(fingerprint: "bbbb2222")
        try writeBatch(m1)
        try writeBatch(m2)

        let matchingA = StagedImportManager.pendingBatches(for: "aaaa1111")
        XCTAssertEqual(matchingA.count, 1)
        XCTAssertEqual(matchingA.first?.keyFingerprint, "aaaa1111")

        let matchingB = StagedImportManager.pendingBatches(for: "bbbb2222")
        XCTAssertEqual(matchingB.count, 1)

        let matchingNone = StagedImportManager.pendingBatches(for: "cccc3333")
        XCTAssertEqual(matchingNone.count, 0)
    }

    func testPendingBatchesSortedByTimestamp() throws {
        let older = createManifest(fingerprint: "test", timestamp: Date().addingTimeInterval(-3600))
        let newer = createManifest(fingerprint: "test", timestamp: Date())
        try writeBatch(newer)
        try writeBatch(older)

        let batches = StagedImportManager.pendingBatches(for: "test")
        XCTAssertEqual(batches.count, 2)
        XCTAssertTrue(batches[0].timestamp < batches[1].timestamp)
    }

    func testPendingFileCountAcrossMultipleBatches() throws {
        let m1 = createManifest(fingerprint: "fp", fileCount: 3)
        let m2 = createManifest(fingerprint: "fp", fileCount: 5)
        let m3 = createManifest(fingerprint: "other", fileCount: 10)
        try writeBatch(m1)
        try writeBatch(m2)
        try writeBatch(m3)

        XCTAssertEqual(StagedImportManager.pendingFileCount(for: "fp"), 8)
        XCTAssertEqual(StagedImportManager.pendingFileCount(for: "other"), 10)
    }

    func testPendingImportableFileCountOnlyCountsExistingEncryptedPayloads() throws {
        let manifest = createManifest(fingerprint: "fp", fileCount: 3)
        let batchURL = try writeBatch(manifest)

        let presentFileIds = [manifest.files[0].fileId, manifest.files[2].fileId]
        for fileId in presentFileIds {
            try StagedImportManager.writeEncryptedFile(
                CryptoEngine.generateRandomBytes(count: 64)!,
                fileId: fileId,
                to: batchURL
            )
        }

        XCTAssertEqual(StagedImportManager.pendingFileCount(for: "fp"), 3)
        XCTAssertEqual(StagedImportManager.pendingImportableFileCount(for: "fp"), 2)
    }

    // MARK: - Batch Deletion

    func testDeleteBatchRemovesDirectory() throws {
        let batchId = UUID()
        let manifest = createManifest(batchId: batchId)
        let batchURL = try writeBatch(manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: batchURL.path))

        StagedImportManager.deleteBatch(batchId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: batchURL.path))
    }

    // MARK: - Retry Logic

    func testIncrementRetryKeepsBatchAtRetryZero() throws {
        let batchId = UUID()
        let manifest = createManifest(batchId: batchId)
        let batchURL = try writeBatch(manifest)

        let deleted = StagedImportManager.incrementRetryOrDelete(batchId: batchId)
        XCTAssertFalse(deleted, "Batch at retry 0 should be kept after first increment")
        XCTAssertTrue(FileManager.default.fileExists(atPath: batchURL.path))

        // Verify retry count was incremented
        let manifestURL = batchURL.appendingPathComponent(VaultCoreConstants.manifestFilename)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let updated = try decoder.decode(StagedImportManifest.self, from: data)
        XCTAssertEqual(updated.retryCount, 1)
    }

    func testIncrementRetryDeletesBatchAtRetryOne() throws {
        let batchId = UUID()
        let manifest = createManifest(batchId: batchId)
        let batchURL = try writeBatch(manifest)

        // First increment: retry 0 → 1 (kept)
        StagedImportManager.incrementRetryOrDelete(batchId: batchId)
        // Second increment: retry 1 → 2 (deleted because >= 2)
        let deleted = StagedImportManager.incrementRetryOrDelete(batchId: batchId)
        XCTAssertTrue(deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: batchURL.path))
    }

    func testIncrementRetryDeletesOrphanedBatch() throws {
        let batchId = UUID()
        let batchURL = tempDir.appendingPathComponent(batchId.uuidString)
        try FileManager.default.createDirectory(at: batchURL, withIntermediateDirectories: true)
        // No manifest written — this is an orphan

        let deleted = StagedImportManager.incrementRetryOrDelete(batchId: batchId)
        XCTAssertTrue(deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: batchURL.path))
    }

    // MARK: - Cleanup

    func testCleanupOrphansDeletesDirsWithoutManifest() throws {
        // Valid batch
        let valid = createManifest()
        try writeBatch(valid)

        // Orphan directory (no manifest)
        let orphanURL = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: orphanURL, withIntermediateDirectories: true)
        try Data("orphan file".utf8).write(to: orphanURL.appendingPathComponent("data.bin"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanURL.path))

        StagedImportManager.cleanupOrphans()

        // Orphan should be gone, valid batch should remain
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        let remaining = StagedImportManager.pendingBatches(for: valid.keyFingerprint)
        XCTAssertEqual(remaining.count, 1)
    }

    func testCleanupExpiredDeletesOldBatches() throws {
        let old = createManifest(fingerprint: "fp", timestamp: Date().addingTimeInterval(-48 * 3600))
        try writeBatch(old)

        let deleted = StagedImportManager.cleanupExpiredBatches(olderThan: 24 * 3600)
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(StagedImportManager.pendingBatches(for: "fp").count, 0)
    }

    func testCleanupExpiredKeepsRecentBatches() throws {
        let recent = createManifest(fingerprint: "fp", timestamp: Date())
        try writeBatch(recent)

        let deleted = StagedImportManager.cleanupExpiredBatches(olderThan: 24 * 3600)
        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(StagedImportManager.pendingBatches(for: "fp").count, 1)
    }

    func testDeleteAllBatches() throws {
        for _ in 0..<3 {
            try writeBatch(createManifest())
        }

        let deleted = StagedImportManager.deleteAllBatches()
        XCTAssertEqual(deleted, 3)

        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.count, 0)
    }

    // MARK: - Total Pending Size

    func testTotalPendingSizeCalculation() throws {
        let (batchURL, _) = try StagedImportManager.createBatch()
        let fileId = UUID()
        let content = Data(repeating: 0xCC, count: 2048)
        try StagedImportManager.writeEncryptedFile(content, fileId: fileId, to: batchURL)
        // Write manifest too
        let manifest = createManifest()
        try StagedImportManager.writeManifest(manifest, to: batchURL)

        let totalSize = StagedImportManager.totalPendingSize()
        // At least the 2048 bytes of the .enc file
        XCTAssertTrue(totalSize >= 2048, "Total pending size should include the encrypted file")
    }

    // MARK: - Manifest Codable

    func testManifestCodableRoundTripWithAllFields() throws {
        let fileId = UUID()
        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "photo.heic",
            mimeType: "image/heic",
            utType: "public.heic",
            originalSize: 4_500_000,
            encryptedSize: 4_500_028,
            hasThumbnail: true,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        let manifest = StagedImportManifest(
            batchId: UUID(),
            keyFingerprint: "deadbeef",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            sourceAppBundleId: "com.apple.Photos",
            files: [meta],
            retryCount: 0
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(StagedImportManifest.self, from: data)

        XCTAssertEqual(restored.batchId, manifest.batchId)
        XCTAssertEqual(restored.keyFingerprint, "deadbeef")
        XCTAssertEqual(restored.sourceAppBundleId, "com.apple.Photos")
        XCTAssertEqual(restored.files.count, 1)

        let restoredFile = restored.files[0]
        XCTAssertEqual(restoredFile.fileId, fileId)
        XCTAssertEqual(restoredFile.filename, "photo.heic")
        XCTAssertEqual(restoredFile.mimeType, "image/heic")
        XCTAssertEqual(restoredFile.utType, "public.heic")
        XCTAssertEqual(restoredFile.originalSize, 4_500_000)
        XCTAssertEqual(restoredFile.encryptedSize, 4_500_028)
        XCTAssertEqual(restoredFile.hasThumbnail, true)
    }

    func testManifestWithNilSourceAppBundleId() throws {
        let manifest = createManifest(sourceApp: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(StagedImportManifest.self, from: data)

        XCTAssertNil(restored.sourceAppBundleId)
    }
}
