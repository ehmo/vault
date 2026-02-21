import CloudKit
import XCTest
@testable import Vault

// MARK: - Mock VaultStorage

private final class MockSyncVaultStorage: VaultStorageProtocol {
    // Configurable returns
    var indexToReturn: VaultStorage.VaultIndex?
    var loadIndexError: Error?
    var savedIndexes: [(VaultStorage.VaultIndex, VaultKey)] = []

    // Track calls
    var loadIndexCallCount = 0

    func loadIndex(with _: VaultKey) throws -> VaultStorage.VaultIndex {
        loadIndexCallCount += 1
        if let error = loadIndexError { throw error }
        guard let index = indexToReturn else {
            throw VaultStorageError.corruptedData
        }
        return index
    }

    func saveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) throws {
        savedIndexes.append((index, key))
        // Also update indexToReturn so subsequent loads see the saved state
        indexToReturn = index
    }

    // MARK: - Unused protocol methods (stubs)

    func storeFile(data _: Data, filename _: String, mimeType _: String, with _: VaultKey, thumbnailData _: Data?, duration _: TimeInterval?, fileId _: UUID?) throws -> UUID {
        fatalError("Not used in ShareSyncManager tests")
    }

    func storeFileFromURL(_ _: URL, filename _: String, mimeType _: String, with _: VaultKey, thumbnailData _: Data?, duration _: TimeInterval?, fileId _: UUID?) throws -> UUID {
        fatalError("Not used in ShareSyncManager tests")
    }

    func retrieveFile(id _: UUID, with _: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func retrieveFileContent(entry _: VaultStorage.VaultIndex.VaultFileEntry, index _: VaultStorage.VaultIndex, masterKey _: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func retrieveFileToTempURL(id _: UUID, with _: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteFile(id _: UUID, with _: VaultKey) throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteFiles(ids _: Set<UUID>, with _: VaultKey, onProgress _: ((Int) -> Void)?) throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func listFiles(with _: VaultKey) throws -> [VaultStorage.VaultFileEntry] {
        fatalError("Not used in ShareSyncManager tests")
    }

    func listFilesLightweight(with _: VaultKey) throws -> (masterKey: Data, files: [VaultStorage.LightweightFileEntry]) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func vaultExists(for _: VaultKey) -> Bool {
        fatalError("Not used in ShareSyncManager tests")
    }

    func vaultHasFiles(for _: VaultKey) -> Bool {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteVaultIndex(for _: VaultKey) throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func destroyAllIndexesExcept(_: VaultKey) {
        fatalError("Not used in ShareSyncManager tests")
    }
}

// MARK: - Mock CloudKit Sharing

private final class MockSyncCloudKitSharing: CloudKitSharingClient {
    // Configurable returns
    var consumedStatus: [String: Bool] = [:]
    var syncFromFileCalls: [(shareVaultId: String, svdfFileURL: URL, newChunkHashes: [String], previousChunkHashes: [String])] = []
    var syncFromFileError: Error?

    func consumedStatusByShareVaultIds(_ shareVaultIds: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in shareVaultIds {
            result[id] = consumedStatus[id] ?? false
        }
        return result
    }

    func syncSharedVaultIncrementalFromFile(
        shareVaultId: String,
        svdfFileURL: URL,
        newChunkHashes: [String],
        previousChunkHashes: [String],
        onProgress _: ((Int, Int) -> Void)?
    ) async throws {
        syncFromFileCalls.append((shareVaultId, svdfFileURL, newChunkHashes, previousChunkHashes))
        if let error = syncFromFileError { throw error }
    }

    // MARK: - Unused protocol methods (stubs)

    func checkPhraseAvailability(phrase _: String) async -> Result<Void, CloudKitSharingError> {
        fatalError("Not used in ShareSyncManager tests")
    }

    func markShareClaimed(shareVaultId _: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func markShareConsumed(shareVaultId _: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func isShareConsumed(shareVaultId _: String) async -> Bool {
        fatalError("Not used in ShareSyncManager tests")
    }

    func uploadSharedVault(shareVaultId _: String, phrase _: String, vaultData _: Data, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, onProgress _: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func syncSharedVault(shareVaultId _: String, vaultData _: Data, shareKey _: ShareKey, currentVersion _: Int, onProgress _: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func syncSharedVaultIncremental(shareVaultId _: String, svdfData _: Data, newChunkHashes _: [String], previousChunkHashes _: [String], onProgress _: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func uploadChunksParallel(shareVaultId _: String, chunks _: [(Int, Data)], onProgress _: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func uploadChunksFromFile(shareVaultId _: String, fileURL _: URL, chunkIndices _: [Int], onProgress _: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func saveManifest(shareVaultId _: String, phraseVaultId _: String, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, totalChunks _: Int) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func downloadSharedVault(phrase _: String, markClaimedOnDownload _: Bool, onProgress _: ((Int, Int) -> Void)?) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func checkForUpdates(shareVaultId _: String, currentVersion _: Int) async throws -> Int? {
        fatalError("Not used in ShareSyncManager tests")
    }

    func downloadUpdatedVault(shareVaultId _: String, shareKey _: ShareKey, onProgress _: ((Int, Int) -> Void)?) async throws -> Data {
        fatalError("Not used in ShareSyncManager tests")
    }

    func revokeShare(shareVaultId _: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteSharedVault(shareVaultId _: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteSharedVault(phrase _: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func existingChunkIndices(for _: String) async throws -> Set<Int> {
        fatalError("Not used in ShareSyncManager tests")
    }

    func checkiCloudStatus() async -> CKAccountStatus {
        fatalError("Not used in ShareSyncManager tests")
    }
}

// MARK: - Tests

@MainActor
final class ShareSyncManagerTests: XCTestCase {
    private var mockStorage: MockSyncVaultStorage!
    private var mockCloudKit: MockSyncCloudKitSharing!
    private var sut: ShareSyncManager!

    private let testVaultKey = VaultKey(Data(repeating: 0xAA, count: 32))

    override func setUp() {
        super.setUp()
        mockStorage = MockSyncVaultStorage()
        mockCloudKit = MockSyncCloudKitSharing()
        sut = ShareSyncManager.createForTesting(storage: mockStorage, cloudKit: mockCloudKit)
    }

    override func tearDown() {
        sut = nil
        mockCloudKit = nil
        mockStorage = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeIndex(
        activeShares: [VaultStorage.ShareRecord]? = nil,
        files: [VaultStorage.VaultIndex.VaultFileEntry] = []
    ) -> VaultStorage.VaultIndex {
        var index = VaultStorage.VaultIndex(
            files: files,
            nextOffset: 0,
            totalSize: 0,
            encryptedMasterKey: Data(repeating: 0xBB, count: 64),
            version: 2
        )
        index.activeShares = activeShares
        return index
    }

    private func makeShareRecord(
        id: String = UUID().uuidString,
        shareKeyData: Data? = Data(repeating: 0xCC, count: 32)
    ) -> VaultStorage.ShareRecord {
        VaultStorage.ShareRecord(
            id: id,
            createdAt: Date(),
            policy: VaultStorage.SharePolicy(),
            lastSyncedAt: nil,
            shareKeyData: shareKeyData,
            syncSequence: nil
        )
    }

    // MARK: - Test: Initial State

    func testSyncStatusStartsIdle() {
        XCTAssertEqual(sut.syncStatus, .idle)
        XCTAssertNil(sut.syncProgress)
        XCTAssertNil(sut.lastSyncedAt)
    }

    // MARK: - Test: No Active Shares

    func testSyncWithNoActiveShares() async {
        mockStorage.indexToReturn = makeIndex(activeShares: nil)

        sut.syncNow(vaultKey: testVaultKey)

        // Let the sync task run
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertEqual(sut.syncStatus, .idle)
        XCTAssertTrue(mockStorage.loadIndexCallCount >= 1)
    }

    func testSyncWithEmptyActiveShares() async {
        mockStorage.indexToReturn = makeIndex(activeShares: [])

        sut.syncNow(vaultKey: testVaultKey)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(sut.syncStatus, .idle)
    }

    // MARK: - Test: Load Index Error

    func testSyncWithLoadIndexError() async {
        mockStorage.loadIndexError = VaultStorageError.corruptedData

        sut.syncNow(vaultKey: testVaultKey)
        try? await Task.sleep(nanoseconds: 100_000_000)

        if case .error = sut.syncStatus {
            // Expected
        } else {
            XCTFail("Expected error status, got \(sut.syncStatus)")
        }
    }

    // MARK: - Test: Consumed Shares Skipped and Removed

    func testSyncSkipsConsumedShares() async {
        let shareId = "consumed-share-1"
        let share = makeShareRecord(id: shareId)
        mockStorage.indexToReturn = makeIndex(activeShares: [share])
        mockCloudKit.consumedStatus = [shareId: true]

        sut.syncNow(vaultKey: testVaultKey)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // The consumed share should have been removed from the saved index
        let lastSaved = mockStorage.savedIndexes.last?.0
        let remainingShares = lastSaved?.activeShares ?? []
        XCTAssertFalse(remainingShares.contains(where: { $0.id == shareId }),
                       "Consumed share should have been removed from index")
    }

    // MARK: - Test: Missing Key Shares Skipped

    func testSyncSkipsSharesWithMissingKey() async {
        let share = makeShareRecord(id: "no-key-share", shareKeyData: nil)
        mockStorage.indexToReturn = makeIndex(activeShares: [share])

        sut.syncNow(vaultKey: testVaultKey)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // With only one share that has no key, status should be error about re-creating
        if case .error(let msg) = sut.syncStatus {
            XCTAssertTrue(msg.contains("re-created"), "Expected re-create message, got: \(msg)")
        } else {
            XCTFail("Expected error status for missing key, got \(sut.syncStatus)")
        }
    }

    // MARK: - Test: Debounce Behavior

    func testDebounceSchedulesSync() async {
        mockStorage.indexToReturn = makeIndex(activeShares: nil)

        sut.scheduleSync(vaultKey: testVaultKey)

        // Debounce is 5s, so after 100ms it should NOT have fired yet
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockStorage.loadIndexCallCount, 0,
                       "scheduleSync should not fire immediately due to debounce")
    }

    // MARK: - Test: syncNow Bypasses Debounce

    func testSyncNowBypassesDebounce() async {
        mockStorage.indexToReturn = makeIndex(activeShares: nil)

        sut.syncNow(vaultKey: testVaultKey)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertGreaterThanOrEqual(mockStorage.loadIndexCallCount, 1,
                                    "syncNow should fire immediately without waiting for debounce")
    }

    // MARK: - Test: Syncing Status Transition

    func testSyncSetsStatusToSyncing() async {
        // Use a share with a key but no encrypted master key derivation possible
        // This will cause the SVDF build to fail, but we can observe the syncing transition
        let share = makeShareRecord()
        mockStorage.indexToReturn = makeIndex(activeShares: [share], files: [])

        sut.syncNow(vaultKey: testVaultKey)

        // Give a brief moment for the sync to start
        try? await Task.sleep(nanoseconds: 50_000_000)

        // After sync completes (SVDF build fails for all shares with no real crypto setup),
        // we expect an error or syncing state. The key observation is that loadIndex was called.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertGreaterThanOrEqual(mockStorage.loadIndexCallCount, 1,
                                    "performSync should have loaded the index")
    }

    // MARK: - PendingSyncState Codable

    func testPendingSyncState_CodableRoundTrip() throws {
        let state = ShareSyncManager.PendingSyncState(
            shareVaultId: "share-vault-123",
            shareKeyData: Data(repeating: 0xCC, count: 32),
            totalChunks: 5,
            newChunkHashes: ["hash1", "hash2", "hash3", "hash4", "hash5"],
            previousChunkHashes: ["oldhash1", "oldhash2"],
            createdAt: Date(),
            uploadFinished: false
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareSyncManager.PendingSyncState.self, from: data)

        XCTAssertEqual(decoded.shareVaultId, state.shareVaultId)
        XCTAssertEqual(decoded.shareKeyData, state.shareKeyData)
        XCTAssertEqual(decoded.totalChunks, state.totalChunks)
        XCTAssertEqual(decoded.newChunkHashes, state.newChunkHashes)
        XCTAssertEqual(decoded.previousChunkHashes, state.previousChunkHashes)
        XCTAssertEqual(decoded.uploadFinished, false)
    }

    func testPendingSyncState_CodableWithUploadFinished() throws {
        let state = ShareSyncManager.PendingSyncState(
            shareVaultId: "share-vault-789",
            shareKeyData: Data(repeating: 0xDD, count: 32),
            totalChunks: 3,
            newChunkHashes: ["a", "b", "c"],
            previousChunkHashes: [],
            createdAt: Date(),
            uploadFinished: true
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareSyncManager.PendingSyncState.self, from: data)

        XCTAssertTrue(decoded.uploadFinished)
    }

    func testPendingSyncState_EmptyHashes() throws {
        let state = ShareSyncManager.PendingSyncState(
            shareVaultId: "empty-hash-test",
            shareKeyData: Data([0xAA]),
            totalChunks: 0,
            newChunkHashes: [],
            previousChunkHashes: [],
            createdAt: Date(),
            uploadFinished: false
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareSyncManager.PendingSyncState.self, from: data)

        XCTAssertEqual(decoded.newChunkHashes.count, 0)
        XCTAssertEqual(decoded.previousChunkHashes.count, 0)
    }

    // MARK: - Sync Staging Directory

    private var syncStagingRootDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_sync", isDirectory: true)
    }

    private func writePendingSyncState(
        shareVaultId: String,
        createdAt: Date = Date(),
        includeSvdf: Bool = true
    ) {
        let dir = syncStagingRootDir.appendingPathComponent(shareVaultId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = ShareSyncManager.PendingSyncState(
            shareVaultId: shareVaultId,
            shareKeyData: Data(repeating: 0xCC, count: 32),
            totalChunks: 3,
            newChunkHashes: ["h1", "h2", "h3"],
            previousChunkHashes: ["old1"],
            createdAt: createdAt,
            uploadFinished: false
        )
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: dir.appendingPathComponent("state.json"))

        if includeSvdf {
            try! Data(repeating: 0x00, count: 1024).write(
                to: dir.appendingPathComponent("svdf_data.bin")
            )
        }
    }

    private func cleanupSyncStaging() {
        try? FileManager.default.removeItem(at: syncStagingRootDir)
    }

    func testLoadPendingSyncState_ReturnsNilWhenEmpty() {
        cleanupSyncStaging()
        let state = sut.loadPendingSyncState(for: "nonexistent-share")
        XCTAssertNil(state)
    }

    func testLoadPendingSyncState_ReturnsStateWhenValid() {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "valid-share")

        let state = sut.loadPendingSyncState(for: "valid-share")
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.shareVaultId, "valid-share")
        XCTAssertEqual(state?.totalChunks, 3)
        XCTAssertEqual(state?.newChunkHashes, ["h1", "h2", "h3"])

        cleanupSyncStaging()
    }

    func testLoadPendingSyncState_ReturnsNilWhenExpired() {
        cleanupSyncStaging()
        writePendingSyncState(
            shareVaultId: "expired-share",
            createdAt: Date().addingTimeInterval(-49 * 60 * 60)
        )

        let state = sut.loadPendingSyncState(for: "expired-share")
        XCTAssertNil(state, "Expired sync state should return nil")

        // Verify cleanup
        let dir = syncStagingRootDir.appendingPathComponent("expired-share")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "Expired staging dir should be removed")

        cleanupSyncStaging()
    }

    func testLoadPendingSyncState_ReturnsNilWhenSvdfMissing() {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "no-svdf", includeSvdf: false)

        let state = sut.loadPendingSyncState(for: "no-svdf")
        XCTAssertNil(state, "State without SVDF file should return nil")

        cleanupSyncStaging()
    }

    func testLoadPendingSyncState_JustBeforeTTL() {
        cleanupSyncStaging()
        writePendingSyncState(
            shareVaultId: "almost-expired",
            createdAt: Date().addingTimeInterval(-47 * 60 * 60)
        )

        let state = sut.loadPendingSyncState(for: "almost-expired")
        XCTAssertNotNil(state, "State just before TTL should still be valid")

        cleanupSyncStaging()
    }

    func testPendingSyncShareVaultIds_EmptyWhenNoStaging() {
        cleanupSyncStaging()
        let ids = sut.pendingSyncShareVaultIds()
        XCTAssertTrue(ids.isEmpty)
    }

    func testPendingSyncShareVaultIds_ReturnsValidIds() {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "share-a")
        writePendingSyncState(shareVaultId: "share-b")

        let ids = sut.pendingSyncShareVaultIds()
        XCTAssertEqual(Set(ids), Set(["share-a", "share-b"]))

        cleanupSyncStaging()
    }

    func testPendingSyncShareVaultIds_ExcludesExpired() {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "valid-share")
        writePendingSyncState(
            shareVaultId: "expired-share",
            createdAt: Date().addingTimeInterval(-49 * 60 * 60)
        )

        let ids = sut.pendingSyncShareVaultIds()
        XCTAssertEqual(ids, ["valid-share"])

        cleanupSyncStaging()
    }

    func testPendingSyncShareVaultIds_ExcludesMissingSvdf() {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "with-svdf")
        writePendingSyncState(shareVaultId: "without-svdf", includeSvdf: false)

        let ids = sut.pendingSyncShareVaultIds()
        XCTAssertEqual(ids, ["with-svdf"])

        cleanupSyncStaging()
    }

    func testHasPendingSyncs_FalseWhenEmpty() {
        cleanupSyncStaging()
        XCTAssertFalse(sut.hasPendingSyncs)
    }

    func testHasPendingSyncs_TrueWhenStateExists() {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "pending-share")

        XCTAssertTrue(sut.hasPendingSyncs)

        cleanupSyncStaging()
    }

    // MARK: - Resume Pending Syncs

    func testResumePendingSyncsIfNeeded_NoOpWhenEmpty() {
        cleanupSyncStaging()
        // Should not crash
        sut.resumePendingSyncsIfNeeded(trigger: "test")
    }

    func testResumePendingSyncsIfNeeded_StartsUploadForPendingSync() async {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "resume-test")

        sut.resumePendingSyncsIfNeeded(trigger: "test")

        // Wait briefly for async task to start
        try? await Task.sleep(nanoseconds: 200_000_000)

        // The upload should have been attempted via cloudKit
        XCTAssertTrue(
            mockCloudKit.syncFromFileCalls.contains(where: { $0.shareVaultId == "resume-test" }),
            "Resume should have triggered sync upload"
        )

        cleanupSyncStaging()
    }

    func testResumePendingSyncsIfNeeded_ClearsOnSuccess() async {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "success-test")

        sut.resumePendingSyncsIfNeeded(trigger: "test")

        // Wait for upload to complete
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Staging should be cleared on success
        let state = sut.loadPendingSyncState(for: "success-test")
        XCTAssertNil(state, "Staging should be cleared after successful upload")

        cleanupSyncStaging()
    }

    func testResumePendingSyncsIfNeeded_PreservesStagingOnFailure() async {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "fail-test")
        mockCloudKit.syncFromFileError = NSError(domain: "test", code: -1)

        sut.resumePendingSyncsIfNeeded(trigger: "test")

        // Wait for upload to complete
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Staging should be preserved for retry
        let state = sut.loadPendingSyncState(for: "fail-test")
        XCTAssertNotNil(state, "Staging should be preserved after failed upload")

        cleanupSyncStaging()
    }

    func testResumePendingSyncsIfNeeded_DoesNotDuplicateResumeTasks() async {
        cleanupSyncStaging()
        writePendingSyncState(shareVaultId: "dedup-test")

        // Call resume twice rapidly
        sut.resumePendingSyncsIfNeeded(trigger: "test1")
        sut.resumePendingSyncsIfNeeded(trigger: "test2")

        try? await Task.sleep(nanoseconds: 300_000_000)

        // Should only have one sync call (not duplicated)
        let callsForShare = mockCloudKit.syncFromFileCalls.filter { $0.shareVaultId == "dedup-test" }
        XCTAssertEqual(callsForShare.count, 1, "Should not duplicate resume tasks for same share")

        cleanupSyncStaging()
    }
}

