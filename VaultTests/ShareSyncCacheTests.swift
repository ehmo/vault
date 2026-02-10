import XCTest
@testable import Vault

final class ShareSyncCacheTests: XCTestCase {

    private var cache: ShareSyncCache!
    private var shareId: String!

    override func setUp() {
        super.setUp()
        shareId = UUID().uuidString
        cache = ShareSyncCache(shareVaultId: shareId)
    }

    override func tearDown() {
        try? cache.purge()
        super.tearDown()
    }

    // MARK: - Sync State

    func testSyncStateSaveLoad() throws {
        var state = ShareSyncCache.SyncState.empty
        state.syncedFileIds = ["id-1", "id-2"]
        state.chunkHashes = ["aaa", "bbb"]
        state.syncSequence = 5

        try cache.saveSyncState(state)

        let loaded = cache.loadSyncState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.syncedFileIds, ["id-1", "id-2"])
        XCTAssertEqual(loaded?.chunkHashes, ["aaa", "bbb"])
        XCTAssertEqual(loaded?.syncSequence, 5)
    }

    // MARK: - SVDF Blob

    func testSVDFSaveLoad() throws {
        let blob = Data("fake-svdf-data".utf8)
        try cache.saveSVDF(blob)

        let loaded = cache.loadSVDF()
        XCTAssertEqual(loaded, blob)
    }

    // MARK: - Encrypted Files

    func testEncryptedFileSaveLoad() throws {
        let fileId = UUID().uuidString
        let data = Data("encrypted-content".utf8)

        try cache.saveEncryptedFile(fileId, data: data)
        XCTAssertTrue(cache.hasEncryptedFile(fileId))

        let loaded = cache.loadEncryptedFile(fileId)
        XCTAssertEqual(loaded, data)
    }

    func testEncryptedThumbSaveLoad() throws {
        let fileId = UUID().uuidString
        let data = Data("encrypted-thumb".utf8)

        try cache.saveEncryptedThumb(fileId, data: data)
        XCTAssertTrue(cache.hasEncryptedThumb(fileId))

        let loaded = cache.loadEncryptedThumb(fileId)
        XCTAssertEqual(loaded, data)
    }

    // MARK: - Prune

    func testPruneFiles() throws {
        try cache.saveEncryptedFile("keep-1", data: Data("a".utf8))
        try cache.saveEncryptedFile("keep-2", data: Data("b".utf8))
        try cache.saveEncryptedFile("remove-1", data: Data("c".utf8))

        cache.pruneFiles(keeping: ["keep-1", "keep-2"])

        XCTAssertTrue(cache.hasEncryptedFile("keep-1"))
        XCTAssertTrue(cache.hasEncryptedFile("keep-2"))
        XCTAssertFalse(cache.hasEncryptedFile("remove-1"))
    }

    // MARK: - Compaction

    func testNeedsCompaction() {
        var state = ShareSyncCache.SyncState.empty
        state.totalBytes = 1000
        state.totalDeletedBytes = 350 // 35% > 30% threshold
        XCTAssertTrue(cache.needsCompaction(state))

        state.totalDeletedBytes = 200 // 20% < 30% threshold
        XCTAssertFalse(cache.needsCompaction(state))
    }

    // MARK: - Chunk Hashes

    func testComputeChunkHashes() {
        let data = Data(repeating: 0xAB, count: 100)
        let hashes = ShareSyncCache.computeChunkHashes(data)

        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(hashes[0].count, 64) // SHA-256 hex string

        // Same data → same hash
        let hashes2 = ShareSyncCache.computeChunkHashes(data)
        XCTAssertEqual(hashes, hashes2)
    }

    func testComputeChunkHashesSmallData() {
        let data = Data("tiny".utf8)
        let hashes = ShareSyncCache.computeChunkHashes(data)
        XCTAssertEqual(hashes.count, 1)
    }

    // MARK: - Purge

    func testPurge() throws {
        try cache.saveEncryptedFile("x", data: Data("data".utf8))
        try cache.purge()
        XCTAssertFalse(cache.hasEncryptedFile("x"))
        XCTAssertNil(cache.loadSyncState())
    }

    // MARK: - Empty State

    func testEmptySyncState() {
        let state = ShareSyncCache.SyncState.empty
        XCTAssertTrue(state.syncedFileIds.isEmpty)
        XCTAssertTrue(state.chunkHashes.isEmpty)
        XCTAssertTrue(state.manifest.isEmpty)
        XCTAssertEqual(state.syncSequence, 0)
        XCTAssertTrue(state.deletedFileIds.isEmpty)
        XCTAssertEqual(state.totalDeletedBytes, 0)
        XCTAssertEqual(state.totalBytes, 0)
    }
}
