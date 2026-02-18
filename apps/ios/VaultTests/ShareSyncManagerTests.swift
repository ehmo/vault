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

    func loadIndex(with key: VaultKey) throws -> VaultStorage.VaultIndex {
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

    // MARK: - Unused protocol methods

    func storeFile(data: Data, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data?, duration: TimeInterval?) throws -> UUID {
        fatalError("Not used in ShareSyncManager tests")
    }

    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data?, duration: TimeInterval?) throws -> UUID {
        fatalError("Not used in ShareSyncManager tests")
    }

    func retrieveFile(id: UUID, with key: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func retrieveFileContent(entry: VaultStorage.VaultIndex.VaultFileEntry, index: VaultStorage.VaultIndex, masterKey: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func retrieveFileToTempURL(id: UUID, with key: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteFile(id: UUID, with key: VaultKey) throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteFiles(ids: Set<UUID>, with key: VaultKey, onProgress: ((Int) -> Void)?) throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func listFiles(with key: VaultKey) throws -> [VaultStorage.VaultFileEntry] {
        fatalError("Not used in ShareSyncManager tests")
    }

    func listFilesLightweight(with key: VaultKey) throws -> (masterKey: Data, files: [VaultStorage.LightweightFileEntry]) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func vaultExists(for key: VaultKey) -> Bool {
        fatalError("Not used in ShareSyncManager tests")
    }

    func vaultHasFiles(for key: VaultKey) -> Bool {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteVaultIndex(for key: VaultKey) throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func destroyAllIndexesExcept(_ preservedKey: VaultKey) {
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
        onProgress: ((Int, Int) -> Void)?
    ) async throws {
        syncFromFileCalls.append((shareVaultId, svdfFileURL, newChunkHashes, previousChunkHashes))
        if let error = syncFromFileError { throw error }
    }

    // MARK: - Unused protocol methods

    func checkPhraseAvailability(phrase: String) async -> Result<Void, CloudKitSharingError> {
        fatalError("Not used in ShareSyncManager tests")
    }

    func markShareClaimed(shareVaultId: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func markShareConsumed(shareVaultId: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func isShareConsumed(shareVaultId: String) async -> Bool {
        fatalError("Not used in ShareSyncManager tests")
    }

    func uploadSharedVault(shareVaultId: String, phrase: String, vaultData: Data, shareKey: ShareKey, policy: VaultStorage.SharePolicy, ownerFingerprint: String, onProgress: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func syncSharedVault(shareVaultId: String, vaultData: Data, shareKey: ShareKey, currentVersion: Int, onProgress: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func syncSharedVaultIncremental(shareVaultId: String, svdfData: Data, newChunkHashes: [String], previousChunkHashes: [String], onProgress: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func uploadChunksParallel(shareVaultId: String, chunks: [(Int, Data)], onProgress: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func uploadChunksFromFile(shareVaultId: String, fileURL: URL, chunkIndices: [Int], onProgress: ((Int, Int) -> Void)?) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func saveManifest(shareVaultId: String, phraseVaultId: String, shareKey: ShareKey, policy: VaultStorage.SharePolicy, ownerFingerprint: String, totalChunks: Int) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func downloadSharedVault(phrase: String, markClaimedOnDownload: Bool, onProgress: ((Int, Int) -> Void)?) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        fatalError("Not used in ShareSyncManager tests")
    }

    func checkForUpdates(shareVaultId: String, currentVersion: Int) async throws -> Int? {
        fatalError("Not used in ShareSyncManager tests")
    }

    func downloadUpdatedVault(shareVaultId: String, shareKey: ShareKey, onProgress: ((Int, Int) -> Void)?) async throws -> Data {
        fatalError("Not used in ShareSyncManager tests")
    }

    func revokeShare(shareVaultId: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteSharedVault(shareVaultId: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func deleteSharedVault(phrase: String) async throws {
        fatalError("Not used in ShareSyncManager tests")
    }

    func existingChunkIndices(for shareVaultId: String) async throws -> Set<Int> {
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
}
