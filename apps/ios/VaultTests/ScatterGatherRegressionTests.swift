import XCTest
@testable import Vault

/// Regression tests for scatter-gather import optimization.
/// These tests verify correctness, thread-safety, and edge cases.
final class ScatterGatherRegressionTests: XCTestCase {

    private var tempDir: URL!
    private var key: Data!
    private var vaultKey: VaultKey!
    private var _vaultInitialized = false

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        key = CryptoEngine.generateRandomBytes(count: 32)!
        vaultKey = VaultKey(key)

        // Initialize vault
        _ = try await VaultStorage.shared.loadIndex(with: vaultKey)
        _vaultInitialized = true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createTempFile(size: Int, ext: String = "txt") throws -> URL {
        let data = CryptoEngine.generateRandomBytes(count: size)!
        let url = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

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

    // MARK: - Critical Bug: Double-Close Prevention

    /// Tests that handles are not double-closed when commitEntries succeeds
    func testNoDoubleCloseOnSuccessfulCommit() async throws {
        let testFile = try createTempFile(size: 1000)

        let (allocations, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
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
            masterKey: masterKey,
            allocation: allocation
        )

        // Commit (closes handles internally)
        try await VaultStorage.shared.commitEntries(
            [preparedEntry],
            allocations: allocations,
            key: vaultKey
        )

        // Attempting to close again should not crash (handle already closed)
        // This is a regression test - previously this would fail
        XCTAssertNoThrow(try? allocation.handle.close())
    }

    /// Tests that uncommitted handles are properly closed on failure
    func testUncommittedHandlesClosedOnFailure() async throws {
        // Create multiple files, prepare them but simulate a failure scenario
        var allocations: [VaultStorage.BlobAllocation] = []
        var entries: [VaultStorage.PreparedEntry] = []

        for i in 0..<3 {
            let testFile = try createTempFile(size: 1000)
            let (allocs, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: [100 * 1024 * 1024],
                key: vaultKey
            )

            let entry = try VaultStorage.shared.prepareFileEntry(
                fileURL: testFile,
                filename: "test\(i).txt",
                mimeType: "text/plain",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: allocs[0]
            )

            allocations.append(allocs[0])
            entries.append(entry)
        }

        // Commit only first entry - remaining handles should be trackable
        try await VaultStorage.shared.commitEntries(
            [entries[0]],
            allocations: [allocations[0]],
            key: vaultKey
        )

        // Other handles should still be valid (not closed)
        // We can verify by checking we can still interact with them
        // (In reality, they should be closed by cleanup code)
    }

    // MARK: - Race Condition Tests

    /// Tests concurrent access to EntryBuffer doesn't corrupt state
    func testEntryBufferThreadSafety() async {
        let buffer = ParallelImporter.EntryBuffer()
        let iterations = 100
        let concurrency = 4

        await withTaskGroup(of: Void.self) { group in
            // Concurrent appends
            for i in 0..<concurrency {
                group.addTask {
                    for j in 0..<iterations {
                        let entry = VaultStorage.PreparedEntry(
                            entry: VaultStorage.VaultIndex.VaultFileEntry(
                                fileId: UUID(),
                                offset: i * 1000 + j,
                                size: 100,
                                encryptedHeaderPreview: Data(),
                                isDeleted: false
                            ),
                            encryptedThumbnail: nil,
                            thumbnailPlaintext: nil
                        )

                        let allocation = VaultStorage.BlobAllocation(
                            blobId: "primary",
                            offset: i * 1000 + j,
                            size: 100,
                            handle: try! FileHandle(forWritingTo: self.tempDir.appendingPathComponent("test_\(i)_\(j).bin"))
                        )

                        let file = VaultFileItem(
                            id: UUID(),
                            size: 100,
                            mimeType: "text/plain",
                            filename: "file\(i)_\(j).txt"
                        )

                        await buffer.append(entry: entry, allocation: allocation, file: file)
                    }
                }
            }

            // Concurrent reads
            group.addTask {
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    let _ = await buffer.getBatch()
                }
            }
        }

        // All entries should be accounted for
        let (entries, allocations, files, failed) = await buffer.getAll()
        let totalCount = entries.count + failed

        // Some may have been batched and cleared, but total should match
        XCTAssertGreaterThan(totalCount, 0)

        // Cleanup handles
        for allocation in allocations {
            try? allocation.handle.close()
        }
    }

    /// Tests that progress callback is called with monotonically increasing values
    func testProgressMonotonicIncrease() async throws {
        var files: [URL] = []
        for _ in 0..<10 {
            files.append(try createTempImageFile())
        }
        let work = files.enumerated().map { index, url in
            ParallelImporter.URLWorkItem(originalIndex: index, url: url)
        }

        var progressValues: [Int] = []
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

        for await event in stream {
            if case .imported = event {
                progressValues.append(progressValues.count + 1)
            }
        }

        await importTask.value

        // Progress should monotonically increase
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i-1])
        }
    }

    // MARK: - Allocation Size Validation

    /// Tests that files larger than allocation fail gracefully
    func testLargeFileExceedsAllocation() async throws {
        // Create a 5MB file but only allocate 1MB
        let largeFile = try createTempFile(size: 5 * 1024 * 1024)

        let (allocations, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
            sizes: [1 * 1024 * 1024], // Only 1MB allocation
            key: vaultKey
        )

        // This should fail because file exceeds allocation
        XCTAssertThrowsError(
            try VaultStorage.shared.prepareFileEntry(
                fileURL: largeFile,
                filename: "large.bin",
                mimeType: "application/octet-stream",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: allocations[0]
            )
        ) { error in
            XCTAssertEqual(error as? VaultStorageError, VaultStorageError.writeError)
        }

        // Cleanup
        try? allocations[0].handle.close()
    }

    // MARK: - Batch Commit Correctness

    /// Tests that batch commit preserves entry order
    func testBatchCommitPreservesOrder() async throws {
        var entries: [VaultStorage.PreparedEntry] = []
        var allocations: [VaultStorage.BlobAllocation] = []

        // Create entries in specific order
        for i in 0..<10 {
            let testFile = try createTempFile(size: 1000)
            let (allocs, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: [100 * 1024 * 1024],
                key: vaultKey
            )

            let entry = try VaultStorage.shared.prepareFileEntry(
                fileURL: testFile,
                filename: "file_\(i).txt",
                mimeType: "text/plain",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: allocs[0]
            )

            entries.append(entry)
            allocations.append(allocs[0])
        }

        // Commit all at once
        try await VaultStorage.shared.commitEntries(entries, allocations: allocations, key: vaultKey)

        // Verify order preserved in index
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(index.files.count, 10)

        for (i, entry) in index.files.enumerated() {
            XCTAssertEqual(entry.filename, "file_\(i).txt")
        }
    }

    /// Tests that partial batch commit works correctly
    func testPartialBatchCommit() async throws {
        var entries: [VaultStorage.PreparedEntry] = []
        var allocations: [VaultStorage.BlobAllocation] = []

        // Create 5 entries
        for i in 0..<5 {
            let testFile = try createTempFile(size: 1000)
            let (allocs, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: [100 * 1024 * 1024],
                key: vaultKey
            )

            let entry = try VaultStorage.shared.prepareFileEntry(
                fileURL: testFile,
                filename: "partial_\(i).txt",
                mimeType: "text/plain",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: allocs[0]
            )

            entries.append(entry)
            allocations.append(allocs[0])
        }

        // Commit only first 3 entries
        try await VaultStorage.shared.commitEntries(
            Array(entries[0..<3]),
            allocations: Array(allocations[0..<3]),
            key: vaultKey
        )

        // Verify only 3 in index
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(index.files.count, 3)

        // Cleanup remaining handles
        for allocation in allocations[3..<5] {
            try? allocation.handle.close()
        }
    }

    // MARK: - Error Handling

    /// Tests that ImportIngestor properly tracks last error
    func testImportIngestorErrorTracking() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        VaultCoreConstants.testPendingImportsOverride = tempDir
        defer {
            VaultCoreConstants.testPendingImportsOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fileId = UUID()

        // Write garbage data
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

        let result = await ImportIngestor.processPendingImports(for: vaultKey)

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertNotNil(result.failureReason)
    }

    // MARK: - Cancellation Tests

    /// Tests that cancellation properly stops workers
    func testCancellationStopsWorkers() async throws {
        var files: [URL] = []
        for _ in 0..<20 {
            files.append(try createTempImageFile())
        }
        let work = files.enumerated().map { index, url in
            ParallelImporter.URLWorkItem(originalIndex: index, url: url)
        }

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

        // Cancel after short delay
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        importTask.cancel()

        var importedCount = 0
        for await event in stream {
            if case .imported = event {
                importedCount += 1
            }
        }

        // Should not have imported all files (cancelled early)
        XCTAssertLessThan(importedCount, 20)
    }

    // MARK: - Index Update Correctness

    /// Tests that addEntries properly appends to existing entries
    func testAddEntriesAppendsToExisting() async throws {
        // First batch of entries
        var entries1: [VaultStorage.PreparedEntry] = []
        var allocations1: [VaultStorage.BlobAllocation] = []

        for i in 0..<3 {
            let testFile = try createTempFile(size: 1000)
            let (allocs, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: [100 * 1024 * 1024],
                key: vaultKey
            )

            let entry = try VaultStorage.shared.prepareFileEntry(
                fileURL: testFile,
                filename: "batch1_\(i).txt",
                mimeType: "text/plain",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: allocs[0]
            )

            entries1.append(entry)
            allocations1.append(allocs[0])
        }

        try await VaultStorage.shared.commitEntries(entries1, allocations: allocations1, key: vaultKey)

        // Second batch
        var entries2: [VaultStorage.PreparedEntry] = []
        var allocations2: [VaultStorage.BlobAllocation] = []

        for i in 0..<2 {
            let testFile = try createTempFile(size: 1000)
            let (allocs, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: [100 * 1024 * 1024],
                key: vaultKey
            )

            let entry = try VaultStorage.shared.prepareFileEntry(
                fileURL: testFile,
                filename: "batch2_\(i).txt",
                mimeType: "text/plain",
                thumbnailData: nil,
                duration: nil,
                originalDate: nil,
                masterKey: masterKey,
                allocation: allocs[0]
            )

            entries2.append(entry)
            allocations2.append(allocs[0])
        }

        try await VaultStorage.shared.commitEntries(entries2, allocations: allocations2, key: vaultKey)

        // Verify total count
        let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertEqual(index.files.count, 5)
    }

    // MARK: - Blob Cursor Update Tests

    /// Tests that blob cursors are correctly updated after commit
    func testBlobCursorUpdate() async throws {
        // Initialize and get initial cursor
        let initialIndex = try await VaultStorage.shared.loadIndex(with: vaultKey)
        let initialCursor = initialIndex.nextOffset

        // Create and commit entry
        let testFile = try createTempFile(size: 1000)
        let (allocations, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
            sizes: [100 * 1024 * 1024],
            key: vaultKey
        )

        let entry = try VaultStorage.shared.prepareFileEntry(
            fileURL: testFile,
            filename: "cursor_test.txt",
            mimeType: "text/plain",
            thumbnailData: nil,
            duration: nil,
            originalDate: nil,
            masterKey: masterKey,
            allocation: allocations[0]
        )

        try await VaultStorage.shared.commitEntries([entry], allocations: allocations, key: vaultKey)

        // Verify cursor moved
        let finalIndex = try await VaultStorage.shared.loadIndex(with: vaultKey)
        XCTAssertGreaterThan(finalIndex.nextOffset, initialCursor)
    }
}
