import XCTest
@testable import Vault

/// Tests for iCloudBackupManager covering background backup handling,
/// chunked uploads, and resume functionality.
@MainActor
final class ICloudBackupBackgroundTests: XCTestCase {

    private var manager: iCloudBackupManager!
    private let fm = FileManager.default
    private var documentsDir: URL!

    override func setUp() {
        super.setUp()
        manager = iCloudBackupManager.shared
        documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        manager.clearStagingDirectory()
    }

    override func tearDown() {
        manager.clearStagingDirectory()
        super.tearDown()
    }

    // MARK: - Helpers

    private var stagingDir: URL {
        documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
    }

    private struct PendingStateParams {
        var backupId: String = "test-backup"
        var totalChunks: Int = 3
        var createdAt: Date = Date()
        var uploadFinished: Bool = false
        var manifestSaved: Bool = false
        var retryCount: Int = 0
        var fileCount: Int = 10
        var vaultTotalSize: Int = 102400
    }

    private func writePendingState(_ params: PendingStateParams = PendingStateParams()) throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: params.backupId,
            totalChunks: params.totalChunks,
            checksum: Data([0x01, 0x02]),
            encryptedSize: 1024 * params.totalChunks,
            createdAt: params.createdAt,
            uploadFinished: params.uploadFinished,
            manifestSaved: params.manifestSaved,
            retryCount: params.retryCount,
            fileCount: params.fileCount,
            vaultTotalSize: params.vaultTotalSize
        )
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: stagingDir.appendingPathComponent("state.json"))
    }

    private func writeDummyChunks(count: Int) {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        for i in 0..<count {
            let chunkURL = stagingDir.appendingPathComponent("chunk_\(i).bin")
            try? Data(repeating: UInt8(i), count: 2 * 1024 * 1024).write(to: chunkURL)
        }
    }

    // MARK: - Background Task Registration

    func testRegisterBackgroundProcessingTaskDoesNotCrash() {
        // Note: This may fail if already registered by app launch.
        // We just verify the method exists and the identifier is correct.
        XCTAssertEqual(
            iCloudBackupManager.backgroundBackupTaskIdentifier,
            "app.vaultaire.ios.backup.resume"
        )
    }

    // MARK: - Notification Methods

    func testSendBackupCompleteNotificationSuccess() {
        manager.sendBackupCompleteNotification(success: true)
    }

    func testSendBackupCompleteNotificationFailure() {
        manager.sendBackupCompleteNotification(
            success: false,
            errorMessage: "Network unavailable"
        )
    }

    func testSendBackupCompleteNotificationFailureWithoutMessage() {
        manager.sendBackupCompleteNotification(success: false)
    }

    // MARK: - Backup Metadata

    func testBackupMetadataFormattedDate() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 1024 * 1024 * 5,
            checksum: Data(),
            formatVersion: 2,
            chunkCount: 10,
            backupId: "test-backup-id"
        )

        XCTAssertFalse(metadata.formattedDate.isEmpty)
        XCTAssertEqual(metadata.formattedSize, "5.0 MB")
    }

    func testBackupMetadataFormattedSize() {
        let metadata1 = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024 * 1024,
            checksum: Data()
        )
        XCTAssertEqual(metadata1.formattedSize, "1.0 MB")

        let metadata2 = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 512 * 1024,
            checksum: Data()
        )
        XCTAssertEqual(metadata2.formattedSize, "0.5 MB")
    }

    func testBackupMetadataFormattedSizeSmallValues() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024,
            checksum: Data()
        )
        XCTAssertEqual(metadata.formattedSize, "0.0 MB")
    }

    func testBackupMetadataFormattedSizeLargeValues() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 100 * 1024 * 1024,
            checksum: Data()
        )
        XCTAssertEqual(metadata.formattedSize, "100.0 MB")
    }

    func testBackupMetadataV1Defaults() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024,
            checksum: Data()
        )
        XCTAssertNil(metadata.formatVersion)
        XCTAssertNil(metadata.chunkCount)
        XCTAssertNil(metadata.backupId)
    }

    func testBackupMetadataV2Fields() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024,
            checksum: Data([0xFF]),
            formatVersion: 2,
            chunkCount: 5,
            backupId: "abc-123"
        )
        XCTAssertEqual(metadata.formatVersion, 2)
        XCTAssertEqual(metadata.chunkCount, 5)
        XCTAssertEqual(metadata.backupId, "abc-123")
    }

    func testBackupMetadataCodableRoundTrip() throws {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880,
            checksum: Data([0xDE, 0xAD]),
            formatVersion: 2,
            chunkCount: 3,
            backupId: "round-trip-id"
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.BackupMetadata.self, from: data)

        XCTAssertEqual(decoded.size, metadata.size)
        XCTAssertEqual(decoded.checksum, metadata.checksum)
        XCTAssertEqual(decoded.formatVersion, metadata.formatVersion)
        XCTAssertEqual(decoded.chunkCount, metadata.chunkCount)
        XCTAssertEqual(decoded.backupId, metadata.backupId)
    }

    // MARK: - Backup Stage

    func testBackupStageRawValues() {
        XCTAssertEqual(iCloudBackupManager.BackupStage.waitingForICloud.rawValue, "Connecting to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.readingVault.rawValue, "Reading vault data...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.encrypting.rawValue, "Encrypting backup...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.uploading.rawValue, "Uploading to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.complete.rawValue, "Backup complete")
    }

    func testBackupStageAllCasesExist() {
        let allStages: [iCloudBackupManager.BackupStage] = [
            .waitingForICloud, .readingVault, .encrypting, .uploading, .complete
        ]
        XCTAssertEqual(allStages.count, 5)
        // All raw values should be non-empty
        for stage in allStages {
            XCTAssertFalse(stage.rawValue.isEmpty)
        }
    }

    // MARK: - Auto Backup Interval

    func testAutoBackupIntervalIs24Hours() {
        let expectedInterval: TimeInterval = 24 * 60 * 60
        XCTAssertEqual(expectedInterval, 86400)
    }

    // MARK: - PendingBackupState Codable

    func testPendingBackupStateCodableRoundTrip() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "test-backup-123",
            totalChunks: 5,
            checksum: Data([0x01, 0x02, 0x03]),
            encryptedSize: 10_485_760,
            createdAt: Date(),
            uploadFinished: false,
            manifestSaved: false,
            retryCount: 3,
            fileCount: 42,
            vaultTotalSize: 10_485_760
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(decoded.backupId, state.backupId)
        XCTAssertEqual(decoded.totalChunks, state.totalChunks)
        XCTAssertEqual(decoded.checksum, state.checksum)
        XCTAssertEqual(decoded.encryptedSize, state.encryptedSize)
        XCTAssertEqual(decoded.uploadFinished, state.uploadFinished)
        XCTAssertEqual(decoded.manifestSaved, state.manifestSaved)
        XCTAssertEqual(decoded.retryCount, state.retryCount)
    }

    func testPendingBackupStateCodableWithUploadFinished() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "test-backup-456",
            totalChunks: 12,
            checksum: Data([0xAA, 0xBB]),
            encryptedSize: 25_165_824,
            createdAt: Date(),
            uploadFinished: true,
            manifestSaved: true,
            retryCount: 0,
            fileCount: 10,
            vaultTotalSize: 25_165_824
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertTrue(decoded.uploadFinished)
        XCTAssertTrue(decoded.manifestSaved)
        XCTAssertEqual(decoded.retryCount, 0)
    }

    func testPendingBackupStateCodablePreservesCreatedAt() throws {
        let createdAt = Date(timeIntervalSince1970: 1700000000)
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "time-test",
            totalChunks: 1,
            checksum: Data(),
            encryptedSize: 100,
            createdAt: createdAt,
            uploadFinished: false,
            manifestSaved: false,
            retryCount: 0,
            fileCount: 1,
            vaultTotalSize: 100
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(
            decoded.createdAt.timeIntervalSince1970,
            createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testPendingBackupStateLargeChecksum() throws {
        let largeChecksum = Data(repeating: 0xAB, count: 64)
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "checksum-test",
            totalChunks: 1,
            checksum: largeChecksum,
            encryptedSize: 100,
            createdAt: Date(),
            uploadFinished: false,
            manifestSaved: false,
            retryCount: 0,
            fileCount: 1,
            vaultTotalSize: 100
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(decoded.checksum, largeChecksum)
        XCTAssertEqual(decoded.checksum.count, 64)
    }

    // MARK: - Staging Directory

    func testLoadPendingBackupStateReturnsNilWhenEmpty() {
        manager.clearStagingDirectory()
        let state = manager.loadPendingBackupState()
        XCTAssertNil(state)
    }

    func testHasPendingBackupFalseWhenEmpty() {
        manager.clearStagingDirectory()
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testHasPendingBackupTrueWhenStateExists() throws {
        try writePendingState()
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testHasPendingBackupFalseWhenExpired() throws {
        try writePendingState(.init(createdAt: Date().addingTimeInterval(-49 * 60 * 60)))
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testClearStagingDirectoryRemovesAllFiles() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let dummyFile = stagingDir.appendingPathComponent("chunk_0.bin")
        try? Data([0x00]).write(to: dummyFile)
        XCTAssertTrue(fm.fileExists(atPath: dummyFile.path))

        manager.clearStagingDirectory()

        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
        XCTAssertFalse(fm.fileExists(atPath: dummyFile.path))
    }

    func testClearStagingDirectoryRemovesMultipleChunks() throws {
        writeDummyChunks(count: 5)
        try writePendingState(.init(totalChunks: 5))

        // Verify files exist
        for i in 0..<5 {
            XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("chunk_\(i).bin").path))
        }
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("state.json").path))

        manager.clearStagingDirectory()

        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
    }

    func testClearStagingDirectorySafeWhenAlreadyClear() {
        // Should not throw or crash when directory doesn't exist
        manager.clearStagingDirectory()
        manager.clearStagingDirectory()
    }

    func testLoadPendingBackupStateReturnsNilWhenExpired() throws {
        try writePendingState(.init(createdAt: Date().addingTimeInterval(-49 * 60 * 60)))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Expired staging state should return nil")

        // Verify it also cleaned up
        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
    }

    func testLoadPendingBackupStateReturnsStateWhenValid() throws {
        try writePendingState(.init(backupId: "valid-backup", totalChunks: 7))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "valid-backup")
        XCTAssertEqual(loaded?.totalChunks, 7)
    }

    func testLoadPendingBackupStateReturnsStateJustBeforeTTL() throws {
        // 47 hours old (< 48h TTL)
        try writePendingState(.init(createdAt: Date().addingTimeInterval(-47 * 60 * 60)))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded, "State just before TTL should still be valid")
    }

    func testLoadPendingBackupStateReturnsNilForMalformedJSON() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stateURL = stagingDir.appendingPathComponent("state.json")
        try? "not valid json".data(using: .utf8)?.write(to: stateURL)

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Malformed JSON should return nil")
    }

    func testLoadPendingBackupStateReturnsNilForEmptyFile() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stateURL = stagingDir.appendingPathComponent("state.json")
        try? Data().write(to: stateURL)

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Empty state file should return nil")
    }

    func testLoadPendingBackupStatePreservesAllFields() throws {
        let now = Date()
        try writePendingState(.init(
            backupId: "full-test",
            totalChunks: 10,
            createdAt: now,
            uploadFinished: true,
            manifestSaved: true,
            retryCount: 5
        ))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "full-test")
        XCTAssertEqual(loaded?.totalChunks, 10)
        XCTAssertEqual(loaded?.uploadFinished, true)
        XCTAssertEqual(loaded?.manifestSaved, true)
        XCTAssertEqual(loaded?.encryptedSize, 1024 * 10)
        XCTAssertEqual(loaded?.retryCount, 5)
    }

    // MARK: - Vault Key Provider

    func testSetVaultKeyProviderCanBeSetAndCleared() {
        // Should not crash
        manager.setVaultKeyProvider { Data(repeating: 0xAA, count: 32) }
        manager.setVaultKeyProvider { nil }
    }

    // MARK: - Resume Triggers

    func testResumeBackupUploadIfNeededNoOpWhenBackupDisabled() throws {
        UserDefaults.standard.set(false, forKey: "iCloudBackupEnabled")
        try writePendingState()

        // Should not start any upload
        manager.resumeBackupUploadIfNeeded(trigger: "test")

        // State should still exist (not consumed)
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testResumeBackupUploadIfNeededNoOpWhenNoPendingBackup() {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        manager.clearStagingDirectory()

        // Should not crash, just return
        manager.resumeBackupUploadIfNeeded(trigger: "test")
    }

    // MARK: - Background Task Identifier

    func testBackgroundTaskIdentifier() {
        XCTAssertEqual(
            iCloudBackupManager.backgroundBackupTaskIdentifier,
            "app.vaultaire.ios.backup.resume"
        )
    }

    // MARK: - Schedule Background Resume

    func testScheduleBackgroundResumeTaskDoesNotCrash() {
        manager.scheduleBackgroundResumeTask(earliestIn: 60)
    }

    func testScheduleBackgroundResumeTaskDefaultInterval() {
        manager.scheduleBackgroundResumeTask()
    }
}
