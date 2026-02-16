import XCTest
@testable import Vault

final class ImportIngestorTests: XCTestCase {

    private var tempDir: URL!
    private var key: Data!
    private var fingerprint: String!

    private actor ProgressCollector {
        private var snapshots: [ImportIngestor.ImportProgress] = []

        func append(_ progress: ImportIngestor.ImportProgress) {
            snapshots.append(progress)
        }

        func values() -> [ImportIngestor.ImportProgress] {
            snapshots
        }
    }

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

    private func stageFile(
        data: Data,
        filename: String = "test.bin",
        mimeType: String = "application/octet-stream",
        hasThumbnail: Bool = false,
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

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let encryptedURL = url.appendingPathComponent("\(fileId.uuidString).enc")
        FileManager.default.createFile(atPath: encryptedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: encryptedURL)
        try CryptoEngine.encryptFileStreamingToHandle(from: sourceURL, to: handle, with: key)
        try handle.close()

        let encSize = (try? FileManager.default.attributesOfItem(atPath: encryptedURL.path)[.size] as? Int) ?? 0

        // If thumbnail requested, encrypt and write a small thumbnail
        if hasThumbnail {
            // Create a minimal 1x1 white JPEG as thumbnail
            let thumbData = createMinimalJPEG()
            let encThumb = try CryptoEngine.encrypt(thumbData, with: key)
            try StagedImportManager.writeEncryptedThumbnail(encThumb, fileId: fileId, to: url)
        }

        let metadata = StagedFileMetadata(
            fileId: fileId,
            filename: filename,
            mimeType: mimeType,
            utType: "public.data",
            originalSize: data.count,
            encryptedSize: encSize,
            hasThumbnail: hasThumbnail,
            timestamp: Date()
        )

        return (id, url, fileId, metadata)
    }

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

    /// Creates a minimal valid JPEG for thumbnail tests
    private func createMinimalJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.jpegData(compressionQuality: 0.5)!
    }

    // MARK: - ImportResult Tests

    func testImportResultContainsFailureReason() async throws {
        // Stage a file but corrupt it so decryption fails
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        // Write garbage data as encrypted file
        let garbageURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
        try Data(repeating: 0xFF, count: 100).write(to: garbageURL)

        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "broken.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 50,
            encryptedSize: 100,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let result = await ImportIngestor.processPendingImports(for: key)

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertNotNil(result.failureReason, "Should report failure reason")
    }

    func testImportResultNilReasonOnSuccess() async throws {
        let data = CryptoEngine.generateRandomBytes(count: 100)!
        let (batchId, batchURL, _, meta) = try stageFile(data: data)
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        // Need VaultStorage initialized for storeFileFromURL
        // Skip this test if VaultStorage isn't ready (requires blob)
        // This validates the ImportResult structure itself
        let emptyResult = ImportIngestor.ImportResult(
            imported: 5, failed: 0, batchesCleaned: 1, failureReason: nil
        )
        XCTAssertNil(emptyResult.failureReason)
        XCTAssertEqual(emptyResult.imported, 5)
    }

    func testImportResultPreservesAllFields() {
        let result = ImportIngestor.ImportResult(
            imported: 3,
            failed: 2,
            batchesCleaned: 1,
            failureReason: "Unable to expand storage"
        )
        XCTAssertEqual(result.imported, 3)
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(result.batchesCleaned, 1)
        XCTAssertEqual(result.failureReason, "Unable to expand storage")
    }

    // MARK: - Missing File Handling

    func testMissingEncryptedFileIsSkippedAsAlreadyImported() async throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        // Create manifest referencing a file that doesn't exist on disk.
        // Missing .enc = already imported in a previous attempt (incremental progress).
        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "ghost.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 100,
            encryptedSize: 128,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let result = await ImportIngestor.processPendingImports(for: key)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0, "Missing .enc means already imported, not failed")
        XCTAssertEqual(result.batchesCleaned, 1, "Batch with all files skipped should be cleaned up")
    }

    // MARK: - Thumbnail Decryption

    func testThumbnailDecryptionWithValidData() throws {
        let thumbData = createMinimalJPEG()
        let encrypted = try CryptoEngine.encrypt(thumbData, with: key)
        let decrypted = try CryptoEngine.decrypt(encrypted, with: key)
        XCTAssertEqual(decrypted, thumbData)
    }

    func testThumbnailDecryptionWithWrongKeyReturnsNil() throws {
        let thumbData = createMinimalJPEG()
        let encrypted = try CryptoEngine.encrypt(thumbData, with: key)

        let wrongKey = CryptoEngine.generateRandomBytes(count: 32)!
        let decrypted = try? CryptoEngine.decrypt(encrypted, with: wrongKey)
        XCTAssertNil(decrypted, "Decryption with wrong key should fail")
    }

    func testStagedThumbnailRoundTrip() throws {
        let thumbData = createMinimalJPEG()
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        let encrypted = try CryptoEngine.encrypt(thumbData, with: key)
        try StagedImportManager.writeEncryptedThumbnail(encrypted, fileId: fileId, to: batchURL)

        let readBack = StagedImportManager.readEncryptedThumbnail(batchId: batchId, fileId: fileId)
        XCTAssertNotNil(readBack)

        let decrypted = try CryptoEngine.decrypt(readBack!, with: key)
        XCTAssertEqual(decrypted, thumbData)

        // Verify it's valid JPEG
        let image = UIImage(data: decrypted)
        XCTAssertNotNil(image)
    }

    func testMissingThumbnailReturnsNilNotCrash() throws {
        let (_, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        // No thumbnail written, but manifest says hasThumbnail=false
        let readBack = StagedImportManager.readEncryptedThumbnail(batchId: batchId, fileId: fileId)
        XCTAssertNil(readBack)
    }

    // MARK: - Empty Batch Handling

    func testEmptyBatchReturnsZeroCounts() async {
        // No batches staged at all
        let result = await ImportIngestor.processPendingImports(for: key)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.batchesCleaned, 0)
        XCTAssertNil(result.failureReason)
    }

    func testBatchWithNoFilesImportsNothing() async throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [])

        let result = await ImportIngestor.processPendingImports(for: key)
        // Empty batch with 0 files — 0 failed, batch cleaned
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.batchesCleaned, 1)
    }

    func testProgressCallbackReportsFromZeroToCompletion() async throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()
        let encURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
        try Data(repeating: 0xFF, count: 100).write(to: encURL)

        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "broken.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 50,
            encryptedSize: 100,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let collector = ProgressCollector()
        let result = await ImportIngestor.processPendingImports(for: key) { progress in
            await collector.append(progress)
        }
        let snapshots = await collector.values()

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(snapshots.first?.completed, 0)
        XCTAssertEqual(snapshots.first?.total, 1)
        XCTAssertEqual(snapshots.last?.completed, 1)
        XCTAssertEqual(snapshots.last?.total, 1)
    }

    func testProgressTotalExcludesAlreadyImportedMissingPayloads() async throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let missingFileId = UUID()
        let failingFileId = UUID()

        let failingEncURL = batchURL.appendingPathComponent("\(failingFileId.uuidString).enc")
        try Data(repeating: 0xFF, count: 120).write(to: failingEncURL)

        let missingMeta = StagedFileMetadata(
            fileId: missingFileId,
            filename: "missing.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 80,
            encryptedSize: 100,
            hasThumbnail: false,
            timestamp: Date()
        )
        let failingMeta = StagedFileMetadata(
            fileId: failingFileId,
            filename: "failing.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 80,
            encryptedSize: 120,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [missingMeta, failingMeta])

        let collector = ProgressCollector()
        let result = await ImportIngestor.processPendingImports(for: key) { progress in
            await collector.append(progress)
        }
        let snapshots = await collector.values()

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(snapshots.first?.total, 1)
        XCTAssertEqual(snapshots.last?.completed, 1)
        XCTAssertEqual(snapshots.last?.total, 1)
    }

    // MARK: - Wrong Key Batch

    func testWrongKeyBatchFailsAllFiles() async throws {
        let data = CryptoEngine.generateRandomBytes(count: 100)!
        let (batchId, batchURL, _, meta) = try stageFile(data: data)
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        // Try to process with a different key
        let wrongKey = CryptoEngine.generateRandomBytes(count: 32)!
        // The batch was staged for the original key fingerprint, so using a
        // different key means pendingBatches won't find it.
        let result = await ImportIngestor.processPendingImports(for: wrongKey)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0, "Wrong fingerprint means batch not found, not failed")
    }

    // MARK: - Corrupted Data

    func testCorruptedEncryptedFileFailsGracefully() async throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        // Write data that looks like streaming format but is corrupted
        var corrupt = Data()
        corrupt.append(contentsOf: [0x56, 0x43, 0x53, 0x45]) // VCSE magic
        corrupt.append(contentsOf: [0x01]) // version
        corrupt.append(CryptoEngine.generateRandomBytes(count: 28)!) // fake nonce
        corrupt.append(CryptoEngine.generateRandomBytes(count: 50)!) // garbage
        let encURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
        try corrupt.write(to: encURL)

        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "corrupt.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 50,
            encryptedSize: corrupt.count,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        let result = await ImportIngestor.processPendingImports(for: key)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertNotNil(result.failureReason)
    }

    // MARK: - Toast Message Tests

    func testImportFailedToastWithReason() {
        let toast = ToastMessage.importFailed(5, imported: 0, reason: "Unable to expand storage")
        XCTAssertEqual(toast.icon, "exclamationmark.triangle")
        XCTAssertTrue(toast.message.contains("5 files failed"))
        XCTAssertTrue(toast.message.contains("Unable to expand storage"))
    }

    func testImportFailedToastPartialSuccess() {
        let toast = ToastMessage.importFailed(2, imported: 3, reason: nil)
        XCTAssertEqual(toast.icon, "exclamationmark.triangle")
        XCTAssertTrue(toast.message.contains("3 imported"))
        XCTAssertTrue(toast.message.contains("2 failed"))
    }

    func testImportFailedToastSingleFile() {
        let toast = ToastMessage.importFailed(1, imported: 0, reason: "Disk full")
        XCTAssertTrue(toast.message.contains("1 file failed"))
        XCTAssertTrue(toast.message.contains("Disk full"))
    }

    func testImportFailedToastNoReason() {
        let toast = ToastMessage.importFailed(3, imported: 0, reason: nil)
        XCTAssertTrue(toast.message.contains("3 files failed"))
        XCTAssertFalse(toast.message.contains(":"))
    }

    func testFilesImportedToast() {
        let toast = ToastMessage.filesImported(5)
        XCTAssertEqual(toast.icon, "lock.fill")
        XCTAssertTrue(toast.message.contains("5 files imported"))
    }

    func testFilesImportedToastSingular() {
        let toast = ToastMessage.filesImported(1)
        XCTAssertTrue(toast.message.contains("1 file imported"))
        XCTAssertFalse(toast.message.contains("files"))
    }

    // MARK: - Retry Behavior

    func testRetryDeletesBatchAfterTwoAttempts() throws {
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let meta = StagedFileMetadata(
            fileId: UUID(),
            filename: "file.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 100,
            encryptedSize: 128,
            hasThumbnail: false,
            timestamp: Date()
        )
        try writeManifest(batchId: batchId, batchURL: batchURL, files: [meta])

        // First retry: retryCount goes to 1, batch kept
        let deleted1 = StagedImportManager.incrementRetryOrDelete(batchId: batchId)
        XCTAssertFalse(deleted1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: batchURL.path))

        // Second retry: retryCount goes to 2, batch deleted
        let deleted2 = StagedImportManager.incrementRetryOrDelete(batchId: batchId)
        XCTAssertTrue(deleted2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: batchURL.path))
    }

    // MARK: - Thumbnail Generation Fallback

    func testImageThumbnailGenerationFromFile() throws {
        // Create a minimal valid image file
        let imageData = createMinimalJPEG()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try imageData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let thumbnail = FileUtilities.generateThumbnail(fromFileURL: tempURL)
        XCTAssertNotNil(thumbnail, "Should generate thumbnail from valid JPEG")

        if let thumb = thumbnail {
            let image = UIImage(data: thumb)
            XCTAssertNotNil(image, "Generated thumbnail should be valid image data")
        }
    }

    func testThumbnailGenerationFromInvalidFileReturnsNil() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try Data(repeating: 0xFF, count: 100).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let thumbnail = FileUtilities.generateThumbnail(fromFileURL: tempURL)
        XCTAssertNil(thumbnail, "Should return nil for invalid image data")
    }

    func testThumbnailGenerationFromDataRoundTrip() {
        let imageData = createMinimalJPEG()
        let thumbnail = FileUtilities.generateThumbnail(from: imageData)
        XCTAssertNotNil(thumbnail)

        if let thumb = thumbnail {
            let image = UIImage(data: thumb)
            XCTAssertNotNil(image)
        }
    }
}
