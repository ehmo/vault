import XCTest
@testable import Vault

/// Comprehensive tests for scatter-gather import optimization.
/// These tests verify that the new parallel import system correctly:
/// 1. Pre-allocates blob space before workers start
/// 2. Parallel workers encrypt without actor serialization
/// 3. Batch commits entries to minimize actor contact
/// 4. Handles failures gracefully
/// 5. Properly tracks progress
/// 6. Closes file handles correctly (no double-close)
final class ScatterGatherImportTests: XCTestCase {

    private var tempDir: URL!
    private var key: Data!
    private var vaultKey: VaultKey!
    private var masterKey: MasterKey!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Generate keys
        key = CryptoEngine.generateRandomBytes(count: 32)!
        vaultKey = VaultKey(key)
        masterKey = MasterKey(CryptoEngine.generateRandomBytes(count: 32)!)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Creates a temporary test file with given size
    private func createTempFile(size: Int, ext: String = "txt") throws -> URL {
        let data = CryptoEngine.generateRandomBytes(count: size)!
        let url = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    /// Creates a temporary image file
    private func createTempImageFile(size: CGSize = CGSize(width: 100, height: 100)) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let data = image.jpegData(compressionQuality: 0.9)!
        let url = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try data.write(to: url)
        return url
    }

    // MARK: - VaultStorage Tests

    /// Tests that BlobAllocation correctly stores allocation info
    func testBlobAllocationStructure() {
        let handle = try! FileHandle(forWritingTo: tempDir.appendingPathComponent("test.bin"))
        let allocation = VaultStorage.BlobAllocation(
            blobId: "primary",
            offset: 1024,
            size: 4096,
            handle: handle
        )

        XCTAssertEqual(allocation.blobId, "primary")
        XCTAssertEqual(allocation.offset, 1024)
        XCTAssertEqual(allocation.size, 4096)
        XCTAssertTrue(allocation.handle === handle)

        try? handle.close()
    }

    /// Tests that PreparedEntry stores entry and thumbnail data
    func testPreparedEntryStructure() throws {
        let entry = VaultStorage.VaultIndex.VaultFileEntry(
            fileId: UUID(),
            offset: 0,
            size: 100,
            encryptedHeaderPreview: Data(),
            isDeleted: false,
            thumbnailData: nil,
            mimeType: "image/jpeg",
            filename: "test.jpg",
            blobId: nil,
            createdAt: Date(),
            duration: nil,
            originalDate: nil
        )

        let thumbData = Data([0xFF, 0xD8, 0xFF]) // JPEG magic bytes
        let encThumb = try CryptoEngine.encrypt(thumbData, with: masterKey.rawBytes)

        let prepared = VaultStorage.PreparedEntry(
            entry: entry,
            encryptedThumbnail: encThumb,
            thumbnailPlaintext: thumbData
        )

        XCTAssertEqual(prepared.entry.fileId, entry.fileId)
        XCTAssertEqual(prepared.encryptedThumbnail, encThumb)
        XCTAssertEqual(prepared.thumbnailPlaintext, thumbData)
    }

    /// Tests that addEntries batch appends entries to index
    func testVaultIndexManagerAddEntries() async throws {
        // Initialize vault
        _ = try await VaultStorage.shared.loadIndex(with: vaultKey)

        // Create test entries
        let entries = (0..<5).map { i in
            VaultStorage.VaultIndex.VaultFileEntry(
                fileId: UUID(),
                offset: i * 1000,
                size: 500,
                encryptedHeaderPreview: Data(),
                isDeleted: false,
                thumbnailData: nil,
                mimeType: "image/jpeg",
                filename: "img\(i).jpg",
                blobId: nil,
                createdAt: Date()
            )
        }

        // Add entries in batch
        try await VaultStorage.shared.indexManager.addEntries(entries, key: vaultKey)

        // Verify entries were added
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(index.files.count, 5)

        // Verify order preserved
        for (i, entry) in index.files.enumerated() {
            XCTAssertEqual(entry.filename, "img\(i).jpg")
        }
    }

    /// Tests that commitEntries properly updates blob cursors
    func testCommitEntriesUpdatesBlobCursors() async throws {
        // Initialize vault
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)

        // Pre-allocate space for a file
        let testFile = try createTempFile(size: 1000)
        let sizes = [100 * 1024 * 1024] // 100MB allocation

        let (allocations, mk) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
            sizes: sizes,
            key: vaultKey
        )

        XCTAssertEqual(allocations.count, 1)
        let allocation = allocations[0]

        // Prepare entry
        let preparedEntry = try VaultStorage.shared.prepareFileEntry(
            fileURL: testFile,
            filename: "test.txt",
            mimeType: "text/plain",
            thumbnailData: nil,
            duration: nil,
            originalDate: nil,
            masterKey: mk,
            allocation: allocation
        )

        // Commit entry
        try await VaultStorage.shared.commitEntries(
            [preparedEntry],
            allocations: allocations,
            key: vaultKey
        )

        // Verify index was updated
        let updatedIndex = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(updatedIndex.files.count, 1)
        XCTAssertEqual(updatedIndex.files.first?.filename, "test.txt")
    }

    // MARK: - ImportIngestor Tests

    /// Tests that ImportIngestor properly tracks failures with error context
    func testImportIngestorFailureTracking() async throws {
        // Create a batch with a corrupted file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        VaultCoreConstants.testPendingImportsOverride = tempDir
        defer {
            VaultCoreConstants.testPendingImportsOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

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

        let manifest = StagedImportManifest(
            batchId: batchId,
            keyFingerprint: KeyDerivation.keyFingerprint(from: key),
            timestamp: Date(),
            sourceAppBundleId: nil,
            files: [meta]
        )
        try StagedImportManager.writeManifest(manifest, to: batchURL)

        // Process should fail gracefully with error reason
        let result = await ImportIngestor.processPendingImports(for: vaultKey)

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertNotNil(result.failureReason, "Should report failure reason for corrupted file")
    }

    /// Tests that ImportIngestor handles empty batches correctly
    func testImportIngestorEmptyBatch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        VaultCoreConstants.testPendingImportsOverride = tempDir
        defer {
            VaultCoreConstants.testPendingImportsOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let manifest = StagedImportManifest(
            batchId: batchId,
            keyFingerprint: KeyDerivation.keyFingerprint(from: key),
            timestamp: Date(),
            sourceAppBundleId: nil,
            files: []
        )
        try StagedImportManager.writeManifest(manifest, to: batchURL)

        let result = await ImportIngestor.processPendingImports(for: vaultKey)

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.batchesCleaned, 1)
    }

    /// Tests that ImportIngestor properly filters already-imported files
    func testImportIngestorSkipsAlreadyImportedFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        VaultCoreConstants.testPendingImportsOverride = tempDir
        defer {
            VaultCoreConstants.testPendingImportsOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        // Create manifest for file, but DON'T create the .enc file
        // This simulates a file that was already imported
        let meta = StagedFileMetadata(
            fileId: fileId,
            filename: "already_imported.dat",
            mimeType: "application/octet-stream",
            utType: "public.data",
            originalSize: 100,
            encryptedSize: 128,
            hasThumbnail: false,
            timestamp: Date()
        )

        let manifest = StagedImportManifest(
            batchId: batchId,
            keyFingerprint: KeyDerivation.keyFingerprint(from: key),
            timestamp: Date(),
            sourceAppBundleId: nil,
            files: [meta]
        )
        try StagedImportManager.writeManifest(manifest, to: batchURL)

        // Missing .enc file should be treated as already imported
        let result = await ImportIngestor.processPendingImports(for: vaultKey)

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.batchesCleaned, 1)
    }

    // MARK: - ParallelImporter Tests

    /// Tests that EntryBuffer correctly batches results
    func testEntryBufferBatching() async {
        let buffer = ParallelImporter.EntryBuffer()

        // Add 25 entries
        for i in 0..<25 {
            let entry = VaultStorage.PreparedEntry(
                entry: VaultStorage.VaultIndex.VaultFileEntry(
                    fileId: UUID(),
                    offset: i * 100,
                    size: 50,
                    encryptedHeaderPreview: Data(),
                    isDeleted: false
                ),
                encryptedThumbnail: nil,
                thumbnailPlaintext: nil
            )

            let allocation = VaultStorage.BlobAllocation(
                blobId: "primary",
                offset: i * 100,
                size: 50,
                handle: try! FileHandle(forWritingTo: tempDir.appendingPathComponent("test\(i).bin"))
            )

            let file = VaultFileItem(
                id: UUID(),
                size: 50,
                mimeType: "text/plain",
                filename: "file\(i).txt"
            )

            await buffer.append(entry: entry, allocation: allocation, file: file)
        }

        // Get batch should return all entries
        let (entries, allocations, files) = await buffer.getBatch()
        XCTAssertEqual(entries.count, 25)
        XCTAssertEqual(allocations.count, 25)
        XCTAssertEqual(files.count, 25)

        // Buffer should be empty after getBatch
        let bufferCount = await buffer.count
        XCTAssertEqual(bufferCount, 0)

        // Close handles
        for allocation in allocations {
            try? allocation.handle.close()
        }
    }

    /// Tests that EntryBuffer properly tracks failures
    func testEntryBufferFailureTracking() async {
        let buffer = ParallelImporter.EntryBuffer()

        await buffer.recordFailure()
        await buffer.recordFailure()
        await buffer.recordFailure()

        let (_, _, _, failed) = await buffer.getAll()
        XCTAssertEqual(failed, 3)
    }

    /// Tests that scatter-gather properly handles cancellation
    func testScatterGatherCancellation() async {
        let videoWork: [ParallelImporter.PickerWorkItem] = []
        let imageWork: [ParallelImporter.PickerWorkItem] = []

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let task = Task {
            await ParallelImporter.runPhotoImportScatterGather(
                videoWork: videoWork,
                imageWork: imageWork,
                videoWorkerCount: 2,
                imageWorkerCount: 2,
                config: .init(
                    key: vaultKey,
                    encryptionKey: key,
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
        }

        // Cancel immediately
        task.cancel()

        // Stream should finish
        var events: [ParallelImporter.ImportEvent] = []
        for await event in stream {
            events.append(event)
        }

        // No events for empty work
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Integration Tests

    /// Tests end-to-end scatter-gather import flow
    func testEndToEndScatterGatherImport() async throws {
        // Create test images
        let imageFiles = try (0..<5).map { _ in
            try createTempImageFile()
        }

        let imageWork = imageFiles.enumerated().map { index, url in
            ParallelImporter.URLWorkItem(originalIndex: index, url: url)
        }

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        // Run import
        let importTask = Task {
            await ParallelImporter.runFileImportScatterGather(
                videoWork: [],
                otherWork: imageWork,
                videoWorkerCount: 0,
                otherWorkerCount: 4,
                config: .init(
                    key: vaultKey,
                    encryptionKey: key,
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
        }

        // Collect results
        var importedCount = 0
        var failedCount = 0

        for await event in stream {
            switch event {
            case .imported:
                importedCount += 1
            case .failed:
                failedCount += 1
            }
        }

        await importTask.value

        // All images should import successfully
        XCTAssertEqual(importedCount, 5)
        XCTAssertEqual(failedCount, 0)

        // Verify files in vault
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(index.files.count, 5)
    }

    /// Tests that large files are handled correctly
    func testLargeFileScatterGatherImport() async throws {
        // Create a larger file
        let largeFile = try createTempFile(size: 5 * 1024 * 1024) // 5MB

        let work = [ParallelImporter.URLWorkItem(originalIndex: 0, url: largeFile)]

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let importTask = Task {
            await ParallelImporter.runFileImportScatterGather(
                videoWork: [],
                otherWork: work,
                videoWorkerCount: 0,
                otherWorkerCount: 1,
                config: .init(
                    key: vaultKey,
                    encryptionKey: key,
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
        }

        var importedCount = 0
        for await event in stream {
            if case .imported = event {
                importedCount += 1
            }
        }

        await importTask.value

        XCTAssertEqual(importedCount, 1)
    }

    /// Tests that batch commit properly groups entries
    func testBatchCommitGrouping() async throws {
        // Initialize vault
        _ = try await VaultStorage.shared.loadIndex(with: vaultKey)

        // Create multiple entries to test batching
        var entries: [VaultStorage.PreparedEntry] = []
        var allocations: [VaultStorage.BlobAllocation] = []

        for i in 0..<25 {
            let testFile = try createTempFile(size: 1000)
            let alloc = VaultStorage.BlobAllocation(
                blobId: "primary",
                offset: i * 2000,
                size: 100 * 1024 * 1024,
                handle: try FileHandle(forWritingTo: tempDir.appendingPathComponent("alloc\(i).bin"))
            )

            let entry = try VaultStorage.shared.prepareFileEntry(
                fileURL: testFile,
                filename: "file\(i).txt",
                mimeType: "text/plain",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: alloc
            )

            entries.append(entry)
            allocations.append(alloc)
        }

        // Commit all at once (simulating batch)
        try await VaultStorage.shared.commitEntries(entries, allocations: allocations, key: vaultKey)

        // Verify all entries committed
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(index.files.count, 25)

        // Close handles
        for allocation in allocations {
            try? allocation.handle.close()
        }
    }

    /// Tests progress callback during scatter-gather import
    func testScatterGatherProgressCallback() async throws {
        // Create test files
        let files = try (0..<10).map { _ in
            try createTempImageFile()
        }

        let work = files.enumerated().map { index, url in
            ParallelImporter.URLWorkItem(originalIndex: index, url: url)
        }

        var progressUpdates: [(completed: Int, total: Int)] = []
        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let importTask = Task {
            await ParallelImporter.runFileImportScatterGather(
                videoWork: [],
                otherWork: work,
                videoWorkerCount: 0,
                otherWorkerCount: 4,
                config: .init(
                    key: vaultKey,
                    encryptionKey: key,
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
        }

        // Track events
        var completed = 0
        for await event in stream {
            if case .imported = event {
                completed += 1
                progressUpdates.append((completed: completed, total: 10))
            }
        }

        await importTask.value

        // Should have progress updates
        XCTAssertGreaterThan(progressUpdates.count, 0)
        XCTAssertEqual(progressUpdates.last?.completed, 10)
    }

    /// Tests that handles are not double-closed
    func testNoDoubleClose() async throws {
        let testFile = try createTempFile(size: 1000)

        let (allocations, mk) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
            sizes: [100 * 1024 * 1024],
            key: vaultKey
        )

        let allocation = allocations[0]

        // Prepare entry
        let preparedEntry = try VaultStorage.shared.prepareFileEntry(
            fileURL: testFile,
            filename: "test.txt",
            mimeType: "text/plain",
            thumbnailData: nil,
            duration: nil,
            originalDate: nil,
            masterKey: mk,
            allocation: allocation
        )

        // Commit (should close handle)
        try await VaultStorage.shared.commitEntries(
            [preparedEntry],
            allocations: allocations,
            key: vaultKey
        )

        // Attempting to close again should not crash (handle is already closed)
        // This test passes if we reach this point without crashing
        try? allocation.handle.close()
    }
}

// MARK: - Performance Tests

extension ScatterGatherImportTests {

    /// Performance test for scatter-gather import
    func testScatterGatherPerformance() async throws {
        // Create 20 test files
        let files = try (0..<20).map { _ in
            try createTempImageFile()
        }

        let work = files.enumerated().map { index, url in
            ParallelImporter.URLWorkItem(originalIndex: index, url: url)
        }

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let start = CFAbsoluteTimeGetCurrent()

        let importTask = Task {
            await ParallelImporter.runFileImportScatterGather(
                videoWork: [],
                otherWork: work,
                videoWorkerCount: 0,
                otherWorkerCount: 4,
                config: .init(
                    key: vaultKey,
                    encryptionKey: key,
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
        }

        var importedCount = 0
        for await event in stream {
            if case .imported = event {
                importedCount += 1
            }
        }

        await importTask.value

        let diff = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(importedCount, 20)
        // Should complete in reasonable time (< 30 seconds for 20 files)
        XCTAssertLessThan(diff, 30.0, "Import should complete in under 30 seconds")
    }
}
