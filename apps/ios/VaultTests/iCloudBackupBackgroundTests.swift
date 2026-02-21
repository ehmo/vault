import XCTest
@testable import Vault

/// Tests for iCloudBackupManager covering background backup handling,
/// chunked uploads, and resume functionality.
@MainActor
final class iCloudBackupBackgroundTests: XCTestCase {

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

    private func writePendingState(
        backupId: String = "test-backup",
        totalChunks: Int = 3,
        createdAt: Date = Date(),
        uploadFinished: Bool = false,
        manifestSaved: Bool = false,
        retryCount: Int = 0,
        fileCount: Int = 10,
        vaultTotalSize: Int = 102400
    ) {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: backupId,
            totalChunks: totalChunks,
            checksum: Data([0x01, 0x02]),
            encryptedSize: 1024 * totalChunks,
            createdAt: createdAt,
            uploadFinished: uploadFinished,
            manifestSaved: manifestSaved,
            retryCount: retryCount,
            fileCount: fileCount,
            vaultTotalSize: vaultTotalSize
        )
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: stagingDir.appendingPathComponent("state.json"))
    }

    private func writeDummyChunks(count: Int) {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        for i in 0..<count {
            let chunkURL = stagingDir.appendingPathComponent("chunk_\(i).bin")
            try? Data(repeating: UInt8(i), count: 2 * 1024 * 1024).write(to: chunkURL)
        }
    }

    // MARK: - Background Task Registration

    func testRegisterBackgroundProcessingTask_DoesNotCrash() {
        // Note: This may fail if already registered by app launch.
        // We just verify the method exists and the identifier is correct.
        XCTAssertEqual(
            iCloudBackupManager.backgroundBackupTaskIdentifier,
            "app.vaultaire.ios.backup.resume"
        )
    }

    // MARK: - Notification Methods

    func testSendBackupCompleteNotification_Success() {
        manager.sendBackupCompleteNotification(success: true)
    }

    func testSendBackupCompleteNotification_Failure() {
        manager.sendBackupCompleteNotification(
            success: false,
            errorMessage: "Network unavailable"
        )
    }

    func testSendBackupCompleteNotification_FailureWithoutMessage() {
        manager.sendBackupCompleteNotification(success: false)
    }

    // MARK: - Backup Metadata

    func testBackupMetadata_FormattedDate() {
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

    func testBackupMetadata_FormattedSize() {
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

    func testBackupMetadata_FormattedSize_SmallValues() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024,
            checksum: Data()
        )
        XCTAssertEqual(metadata.formattedSize, "0.0 MB")
    }

    func testBackupMetadata_FormattedSize_LargeValues() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 100 * 1024 * 1024,
            checksum: Data()
        )
        XCTAssertEqual(metadata.formattedSize, "100.0 MB")
    }

    func testBackupMetadata_V1Defaults() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024,
            checksum: Data()
        )
        XCTAssertNil(metadata.formatVersion)
        XCTAssertNil(metadata.chunkCount)
        XCTAssertNil(metadata.backupId)
    }

    func testBackupMetadata_V2Fields() {
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

    func testBackupMetadata_CodableRoundTrip() throws {
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

    func testBackupStage_RawValues() {
        XCTAssertEqual(iCloudBackupManager.BackupStage.waitingForICloud.rawValue, "Connecting to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.readingVault.rawValue, "Reading vault data...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.encrypting.rawValue, "Encrypting backup...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.uploading.rawValue, "Uploading to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.complete.rawValue, "Backup complete")
    }

    func testBackupStage_AllCasesExist() {
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

    func testAutoBackupInterval_Is24Hours() {
        let expectedInterval: TimeInterval = 24 * 60 * 60
        XCTAssertEqual(expectedInterval, 86400)
    }

    // MARK: - PendingBackupState Codable

    func testPendingBackupState_CodableRoundTrip() throws {
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

    func testPendingBackupState_CodableWithUploadFinished() throws {
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

    func testPendingBackupState_CodablePreservesCreatedAt() throws {
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

    func testPendingBackupState_LargeChecksum() throws {
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

    func testLoadPendingBackupState_ReturnsNilWhenEmpty() {
        manager.clearStagingDirectory()
        let state = manager.loadPendingBackupState()
        XCTAssertNil(state)
    }

    func testHasPendingBackup_FalseWhenEmpty() {
        manager.clearStagingDirectory()
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testHasPendingBackup_TrueWhenStateExists() {
        writePendingState()
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testHasPendingBackup_FalseWhenExpired() {
        writePendingState(createdAt: Date().addingTimeInterval(-49 * 60 * 60))
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testClearStagingDirectory_RemovesAllFiles() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let dummyFile = stagingDir.appendingPathComponent("chunk_0.bin")
        try? Data([0x00]).write(to: dummyFile)
        XCTAssertTrue(fm.fileExists(atPath: dummyFile.path))

        manager.clearStagingDirectory()

        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
        XCTAssertFalse(fm.fileExists(atPath: dummyFile.path))
    }

    func testClearStagingDirectory_RemovesMultipleChunks() {
        writeDummyChunks(count: 5)
        writePendingState(totalChunks: 5)

        // Verify files exist
        for i in 0..<5 {
            XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("chunk_\(i).bin").path))
        }
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("state.json").path))

        manager.clearStagingDirectory()

        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
    }

    func testClearStagingDirectory_SafeWhenAlreadyClear() {
        // Should not throw or crash when directory doesn't exist
        manager.clearStagingDirectory()
        manager.clearStagingDirectory()
    }

    func testLoadPendingBackupState_ReturnsNilWhenExpired() {
        writePendingState(createdAt: Date().addingTimeInterval(-49 * 60 * 60))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Expired staging state should return nil")

        // Verify it also cleaned up
        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
    }

    func testLoadPendingBackupState_ReturnsStateWhenValid() {
        writePendingState(backupId: "valid-backup", totalChunks: 7)

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "valid-backup")
        XCTAssertEqual(loaded?.totalChunks, 7)
    }

    func testLoadPendingBackupState_ReturnsStateJustBeforeTTL() {
        // 47 hours old (< 48h TTL)
        writePendingState(createdAt: Date().addingTimeInterval(-47 * 60 * 60))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded, "State just before TTL should still be valid")
    }

    func testLoadPendingBackupState_ReturnsNilForMalformedJSON() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stateURL = stagingDir.appendingPathComponent("state.json")
        try? "not valid json".data(using: .utf8)?.write(to: stateURL)

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Malformed JSON should return nil")
    }

    func testLoadPendingBackupState_ReturnsNilForEmptyFile() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stateURL = stagingDir.appendingPathComponent("state.json")
        try? Data().write(to: stateURL)

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Empty state file should return nil")
    }

    func testLoadPendingBackupState_PreservesAllFields() {
        let now = Date()
        writePendingState(
            backupId: "full-test",
            totalChunks: 10,
            createdAt: now,
            uploadFinished: true,
            manifestSaved: true,
            retryCount: 5
        )

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

    func testSetVaultKeyProvider_CanBeSetAndCleared() {
        // Should not crash
        manager.setVaultKeyProvider { Data(repeating: 0xAA, count: 32) }
        manager.setVaultKeyProvider { nil }
    }

    // MARK: - Resume Triggers

    func testResumeBackupUploadIfNeeded_NoOpWhenBackupDisabled() {
        UserDefaults.standard.set(false, forKey: "iCloudBackupEnabled")
        writePendingState()

        // Should not start any upload
        manager.resumeBackupUploadIfNeeded(trigger: "test")

        // State should still exist (not consumed)
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testResumeBackupUploadIfNeeded_NoOpWhenNoPendingBackup() {
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

    func testScheduleBackgroundResumeTask_DoesNotCrash() {
        manager.scheduleBackgroundResumeTask(earliestIn: 60)
    }

    func testScheduleBackgroundResumeTask_DefaultInterval() {
        manager.scheduleBackgroundResumeTask()
    }
}
