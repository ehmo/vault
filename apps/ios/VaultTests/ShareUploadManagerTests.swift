import CloudKit
import XCTest
@testable import Vault

// MARK: - Mock Implementations

private final class MockUploadVaultStorage: VaultStorageProtocol, @unchecked Sendable {
    var indexToReturn = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 0)
    var savedIndexes: [(VaultStorage.VaultIndex, VaultKey)] = []
    var shouldThrowOnLoad = false
    var shouldThrowOnSave = false

    func loadIndex(with _: VaultKey) async throws -> VaultStorage.VaultIndex {
        if shouldThrowOnLoad { throw VaultStorageError.corruptedData }
        return indexToReturn
    }

    func saveIndex(_ index: VaultStorage.VaultIndex, with key: VaultKey) async throws {
        if shouldThrowOnSave { throw VaultStorageError.corruptedData }
        savedIndexes.append((index, key))
        indexToReturn = index
    }

    func storeFile(data _: Data, filename _: String, mimeType _: String, with _: VaultKey, thumbnailData _: Data?, duration _: TimeInterval?, fileId _: UUID?) async throws -> UUID { UUID() }
    func storeFileFromURL(_: URL, filename _: String, mimeType _: String, with _: VaultKey, options _: FileStoreOptions) async throws -> UUID { UUID() }
    func retrieveFile(id _: UUID, with _: VaultKey) async throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        throw VaultStorageError.corruptedData
    }
    func retrieveFileContent(entry _: VaultStorage.VaultIndex.VaultFileEntry, index _: VaultStorage.VaultIndex, masterKey _: MasterKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        throw VaultStorageError.corruptedData
    }
    func retrieveFileToTempURL(id _: UUID, with _: VaultKey) async throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL) {
        throw VaultStorageError.corruptedData
    }
    func deleteFile(id _: UUID, with _: VaultKey) async throws {
        // No-op: test stub
    }
    func deleteFiles(ids _: Set<UUID>, with _: VaultKey, onProgress _: (@Sendable (Int) -> Void)?) async throws {
        // No-op: test stub
    }
    func listFiles(with _: VaultKey) async throws -> [VaultStorage.VaultFileEntry] { [] }
    func listFilesLightweight(with _: VaultKey) async throws -> (masterKey: MasterKey, files: [VaultStorage.LightweightFileEntry]) {
        (MasterKey(Data(repeating: 0, count: 32)), [])
    }
    func vaultExists(for _: VaultKey) -> Bool { true }
    func vaultHasFiles(for _: VaultKey) async -> Bool { false }
    func deleteVaultIndex(for _: VaultKey) throws {
        // No-op: test stub
    }
    func destroyAllIndexesExcept(_: VaultKey) {
        // No-op: test stub
    }
}

private final class MockUploadCloudKitSharing: CloudKitSharingClient {
    var phraseAvailable = true
    var uploadCalls: [String] = []
    var deleteCalls: [String] = []

    func checkPhraseAvailability(phrase _: String) async -> Result<Void, CloudKitSharingError> {
        phraseAvailable ? .success(()) : .failure(.notAvailable)
    }

    func consumedStatusByShareVaultIds(_ shareVaultIds: [String]) async throws -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: shareVaultIds.map { ($0, false) })
    }

    func claimedStatusByShareVaultIds(_ shareVaultIds: [String]) async throws -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: shareVaultIds.map { ($0, false) })
    }

    func markShareClaimed(shareVaultId _: String) async throws {
        // No-op: test stub
    }
    func markShareConsumed(shareVaultId _: String) async throws {
        // No-op: test stub
    }
    func isShareConsumed(shareVaultId _: String) async throws -> Bool { false }

    func uploadSharedVault(shareVaultId: String, phrase _: String, vaultData _: Data, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, onProgress _: ((Int, Int) -> Void)?) async throws {
        uploadCalls.append(shareVaultId)
    }

    func syncSharedVault(shareVaultId _: String, vaultData _: Data, shareKey _: ShareKey, currentVersion _: Int, onProgress _: ((Int, Int) -> Void)?) async throws {
        // No-op: test stub
    }

    func syncSharedVaultIncremental(shareVaultId _: String, svdfData _: Data, newChunkHashes _: [String], previousChunkHashes _: [String], onProgress _: ((Int, Int) -> Void)?) async throws {
        // No-op: test stub
    }

    func syncSharedVaultIncrementalFromFile(shareVaultId _: String, svdfFileURL _: URL, newChunkHashes _: [String], previousChunkHashes _: [String], onProgress _: ((Int, Int) -> Void)?) async throws {
        // No-op: test stub
    }

    func uploadChunksParallel(shareVaultId _: String, chunks _: [(Int, Data)], onProgress _: ((Int, Int) -> Void)?) async throws {
        // No-op: test stub
    }

    func uploadChunksFromFile(shareVaultId: String, fileURL _: URL, chunkIndices _: [Int], onProgress _: ((Int, Int) -> Void)?) async throws {
        uploadCalls.append(shareVaultId)
    }

    func saveManifest(shareVaultId _: String, phraseVaultId _: String, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, totalChunks _: Int) async throws {
        // No-op: test stub
    }

    func downloadSharedVault(phrase _: String, markClaimedOnDownload _: Bool, onProgress _: ((Int, Int) -> Void)?) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        (Data(), "mock-id", VaultStorage.SharePolicy(), 1)
    }

    func checkForUpdates(shareVaultId _: String, currentVersion _: Int) async throws -> Int? { nil }

    func downloadUpdatedVault(shareVaultId _: String, shareKey _: ShareKey, onProgress _: ((Int, Int) -> Void)?) async throws -> Data { Data() }

    func downloadSharedVaultToFile(phrase _: String, outputURL: URL, markClaimedOnDownload _: Bool, onProgress _: ((Int, Int) -> Void)?) async throws -> (fileURL: URL, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) { (outputURL, "", VaultStorage.SharePolicy(), 1) }
    func downloadUpdatedVaultToFile(shareVaultId _: String, shareKey _: ShareKey, outputURL _: URL, onProgress _: ((Int, Int) -> Void)?) async throws {}

    func revokeShare(shareVaultId _: String) async throws {
        // No-op: test stub
    }

    func deleteSharedVault(shareVaultId: String) async throws {
        deleteCalls.append(shareVaultId)
    }

    func deleteSharedVault(phrase _: String) async throws {
        // No-op: test stub
    }

    func existingChunkIndices(for _: String) async throws -> Set<Int> { [] }

    func checkiCloudStatus() async -> CKAccountStatus { .available }
}

// MARK: - Tests

@MainActor
final class ShareUploadManagerTests: XCTestCase {

    private var mockStorage: MockUploadVaultStorage!
    private var mockCloudKit: MockUploadCloudKitSharing!
    private var sut: ShareUploadManager!

    override func setUp() {
        super.setUp()
        mockStorage = MockUploadVaultStorage()
        mockCloudKit = MockUploadCloudKitSharing()
        sut = ShareUploadManager.createForTesting(
            storage: mockStorage,
            cloudKit: mockCloudKit
        )
    }

    override func tearDown() {
        sut = nil
        mockStorage = nil
        mockCloudKit = nil
        super.tearDown()
    }

    // MARK: - 1. Initial Job List Empty

    func testInitialJobListEmpty() {
        XCTAssertTrue(sut.jobs.isEmpty, "A fresh ShareUploadManager should have no jobs")
        XCTAssertEqual(sut.runningUploadCount, 0)
        XCTAssertFalse(sut.hasPendingUpload)
    }

    // MARK: - 2. Start Upload Creates Job

    func testStartUploadCreatesJob() {
        let vaultKey = VaultKey(Data(repeating: 0xAA, count: 32))

        sut.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: "test-phrase",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        XCTAssertEqual(sut.jobs.count, 1, "Starting an upload should create exactly one job")

        let job = sut.jobs[0]
        XCTAssertEqual(job.status, .preparing, "New job should be in preparing state")
        XCTAssertEqual(job.phrase, "test-phrase")
        XCTAssertEqual(job.progress, 0)
        XCTAssertTrue(job.shareVaultId.count > 0, "Share vault ID should be non-empty")
    }

    // MARK: - 3. Cancel Upload Terminates Job

    func testCancelUploadTerminatesJob() {
        let vaultKey = VaultKey(Data(repeating: 0xBB, count: 32))
        sut.setVaultKeyProvider { vaultKey }

        sut.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: "cancel-me",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        XCTAssertEqual(sut.jobs.count, 1)
        let jobId = sut.jobs[0].id

        sut.terminateUpload(jobId: jobId, vaultKey: vaultKey, cleanupRemote: false)

        XCTAssertTrue(sut.jobs.isEmpty, "Terminated job should be removed from jobs list")
    }

    // MARK: - 4. Terminate All Clears All Jobs

    func testTerminateAllClearsAllJobs() {
        let vaultKey = VaultKey(Data(repeating: 0xCC, count: 32))
        sut.setVaultKeyProvider { vaultKey }

        for i in 0..<3 {
            sut.startBackgroundUpload(
                vaultKey: vaultKey,
                phrase: "phrase-\(i)",
                hasExpiration: false,
                expiresAt: nil,
                hasMaxOpens: false,
                maxOpens: nil
            )
        }

        XCTAssertEqual(sut.jobs.count, 3, "Should have 3 jobs")

        let jobIds = sut.jobs.map(\.id)
        for jobId in jobIds {
            sut.terminateUpload(jobId: jobId, vaultKey: vaultKey, cleanupRemote: false)
        }

        XCTAssertTrue(sut.jobs.isEmpty, "All jobs should be removed after terminating each")
        XCTAssertEqual(sut.runningUploadCount, 0)
    }

    // MARK: - 5. Remove Share Record Updates Index

    func testRemoveShareRecordUpdatesIndex() async throws {
        let vaultKey = VaultKey(Data(repeating: 0xDD, count: 32))

        // Set up an index with share records
        var index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 0)
        index.activeShares = [
            VaultStorage.ShareRecord(
                id: "other-share",
                createdAt: Date(),
                policy: VaultStorage.SharePolicy(),
                lastSyncedAt: nil,
                shareKeyData: Data(repeating: 0x02, count: 32),
                syncSequence: 1
            ),
        ]
        mockStorage.indexToReturn = index

        // Start an upload so we get a job with a shareVaultId
        sut.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: "remove-share-test",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        let jobId = sut.jobs[0].id
        let jobShareVaultId = sut.jobs[0].shareVaultId

        // Add a record matching the job's shareVaultId to the index
        var updatedIndex = mockStorage.indexToReturn
        updatedIndex.activeShares?.append(VaultStorage.ShareRecord(
            id: jobShareVaultId,
            createdAt: Date(),
            policy: VaultStorage.SharePolicy(),
            lastSyncedAt: nil,
            shareKeyData: Data(repeating: 0x03, count: 32),
            syncSequence: 1
        ))
        mockStorage.indexToReturn = updatedIndex

        sut.terminateUpload(jobId: jobId, vaultKey: vaultKey, cleanupRemote: false)

        // Wait for the fire-and-forget removeShareRecord Task to complete
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(mockStorage.savedIndexes.isEmpty, "Index should have been saved")

        let savedIndex = mockStorage.savedIndexes.last!.0
        let remainingShareIds = savedIndex.activeShares?.map(\.id) ?? []
        XCTAssertFalse(remainingShareIds.contains(jobShareVaultId), "Terminated job's share record should be removed")
        XCTAssertTrue(remainingShareIds.contains("other-share"), "Other share records should remain")
    }

    // MARK: - 6. Append Share Record via Mock Storage

    func testAppendShareRecordUpdatesIndex() async throws {
        let vaultKey = VaultKey(Data(repeating: 0xEE, count: 32))

        // Start with an index that has no shares
        let index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 0)
        mockStorage.indexToReturn = index

        XCTAssertNil(mockStorage.indexToReturn.activeShares)

        // Exercise the same pattern as appendShareRecord (private) uses
        var mutableIndex = try await mockStorage.loadIndex(with: vaultKey)
        XCTAssertNil(mutableIndex.activeShares)

        let newRecord = VaultStorage.ShareRecord(
            id: "appended-share",
            createdAt: Date(),
            policy: VaultStorage.SharePolicy(),
            lastSyncedAt: Date(),
            shareKeyData: Data(repeating: 0xFF, count: 32),
            syncSequence: 1
        )

        if mutableIndex.activeShares == nil {
            mutableIndex.activeShares = []
        }
        mutableIndex.activeShares?.append(newRecord)
        try await mockStorage.saveIndex(mutableIndex, with: vaultKey)

        let reloaded = try await mockStorage.loadIndex(with: vaultKey)
        XCTAssertEqual(reloaded.activeShares?.count, 1)
        XCTAssertEqual(reloaded.activeShares?.first?.id, "appended-share")
    }

    // MARK: - 7. Job Status isRunning

    func testJobStatusIsRunning() {
        XCTAssertTrue(ShareUploadManager.UploadJobStatus.preparing.isRunning)
        XCTAssertTrue(ShareUploadManager.UploadJobStatus.uploading.isRunning)
        XCTAssertTrue(ShareUploadManager.UploadJobStatus.finalizing.isRunning)

        XCTAssertFalse(ShareUploadManager.UploadJobStatus.paused.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.failed.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.complete.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.cancelled.isRunning)
    }

    // MARK: - 8. Running Upload Count

    func testRunningUploadCount() {
        let vaultKey = VaultKey(Data(repeating: 0x11, count: 32))

        XCTAssertEqual(sut.runningUploadCount, 0)

        sut.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: "count-test-1",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        XCTAssertEqual(sut.runningUploadCount, 1)

        sut.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: "count-test-2",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        XCTAssertEqual(sut.runningUploadCount, 2)
    }

    // MARK: - 9. Jobs Filtered by Owner Fingerprint

    func testJobsFilteredByOwnerFingerprint() {
        let vaultKeyA = VaultKey(Data(repeating: 0xAA, count: 32))
        let vaultKeyB = VaultKey(Data(repeating: 0xBB, count: 32))

        sut.startBackgroundUpload(
            vaultKey: vaultKeyA,
            phrase: "owner-a-phrase",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        sut.startBackgroundUpload(
            vaultKey: vaultKeyB,
            phrase: "owner-b-phrase",
            hasExpiration: false,
            expiresAt: nil,
            hasMaxOpens: false,
            maxOpens: nil
        )

        XCTAssertEqual(sut.jobs.count, 2)

        let fingerprintA = sut.jobs.first(where: { $0.phrase == "owner-a-phrase" })!.ownerFingerprint
        let filteredA = sut.jobs(forOwnerFingerprint: fingerprintA)
        XCTAssertEqual(filteredA.count, 1)
        XCTAssertEqual(filteredA[0].phrase, "owner-a-phrase")

        // nil fingerprint returns all jobs
        let allJobs = sut.jobs(forOwnerFingerprint: nil)
        XCTAssertEqual(allJobs.count, 2)
    }

    // MARK: - 10. Upload Job canResume and canTerminate

    func testUploadJobCanResumeAndCanTerminate() {
        let failedJob = ShareUploadManager.UploadJob(
            id: "j1", ownerFingerprint: "fp", createdAt: Date(),
            shareVaultId: "sv1", phrase: nil, status: .failed,
            progress: 0, total: 100, message: "", errorMessage: "err"
        )
        XCTAssertTrue(failedJob.canResume)
        XCTAssertTrue(failedJob.canTerminate)

        let pausedJob = ShareUploadManager.UploadJob(
            id: "j2", ownerFingerprint: "fp", createdAt: Date(),
            shareVaultId: "sv2", phrase: nil, status: .paused,
            progress: 50, total: 100, message: "", errorMessage: nil
        )
        XCTAssertTrue(pausedJob.canResume)
        XCTAssertTrue(pausedJob.canTerminate)

        let completeJob = ShareUploadManager.UploadJob(
            id: "j3", ownerFingerprint: "fp", createdAt: Date(),
            shareVaultId: "sv3", phrase: nil, status: .complete,
            progress: 100, total: 100, message: "", errorMessage: nil
        )
        XCTAssertFalse(completeJob.canResume)
        XCTAssertFalse(completeJob.canTerminate)

        let cancelledJob = ShareUploadManager.UploadJob(
            id: "j4", ownerFingerprint: "fp", createdAt: Date(),
            shareVaultId: "sv4", phrase: nil, status: .cancelled,
            progress: 0, total: 100, message: "", errorMessage: nil
        )
        XCTAssertFalse(cancelledJob.canResume)
        XCTAssertFalse(cancelledJob.canTerminate)

        let preparingJob = ShareUploadManager.UploadJob(
            id: "j5", ownerFingerprint: "fp", createdAt: Date(),
            shareVaultId: "sv5", phrase: nil, status: .preparing,
            progress: 5, total: 100, message: "", errorMessage: nil
        )
        XCTAssertFalse(preparingJob.canResume)
        XCTAssertTrue(preparingJob.canTerminate)
    }
}
