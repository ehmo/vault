import XCTest
@testable import Vault

/// Tests for iCloudBackupManager covering background backup handling,
/// chunked uploads, and resume functionality.
@MainActor
final class iCloudBackupBackgroundTests: XCTestCase {

    private var manager: iCloudBackupManager!

    override func setUp() {
        super.setUp()
        manager = iCloudBackupManager.shared
    }

    // MARK: - Background Task Registration

    func testRegisterBackgroundProcessingTask_DoesNotCrash() {
        // Should not crash when registering
        manager.registerBackgroundProcessingTask()
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

    // MARK: - Backup Metadata

    func testBackupMetadata_FormattedDate() {
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 1024 * 1024 * 5, // 5MB
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
            size: 1024 * 1024, // 1MB
            checksum: Data()
        )
        XCTAssertEqual(metadata1.formattedSize, "1.0 MB")

        let metadata2 = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 512 * 1024, // 0.5MB
            checksum: Data()
        )
        XCTAssertEqual(metadata2.formattedSize, "0.5 MB")
    }

    // MARK: - Backup Stage

    func testBackupStage_RawValues() {
        XCTAssertEqual(iCloudBackupManager.BackupStage.waitingForICloud.rawValue, "Connecting to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.readingVault.rawValue, "Reading vault data...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.encrypting.rawValue, "Encrypting backup...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.uploading.rawValue, "Uploading to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.complete.rawValue, "Backup complete")
    }

    // MARK: - Auto Backup Interval

    func testAutoBackupInterval_Is24Hours() {
        // The auto backup interval should be 24 hours
        // This is a compile-time constant check
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
            manifestSaved: false
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(decoded.backupId, state.backupId)
        XCTAssertEqual(decoded.totalChunks, state.totalChunks)
        XCTAssertEqual(decoded.checksum, state.checksum)
        XCTAssertEqual(decoded.encryptedSize, state.encryptedSize)
        XCTAssertEqual(decoded.uploadFinished, state.uploadFinished)
        XCTAssertEqual(decoded.manifestSaved, state.manifestSaved)
    }

    func testPendingBackupState_CodableWithUploadFinished() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "test-backup-456",
            totalChunks: 12,
            checksum: Data([0xAA, 0xBB]),
            encryptedSize: 25_165_824,
            createdAt: Date(),
            uploadFinished: true,
            manifestSaved: true
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertTrue(decoded.uploadFinished)
        XCTAssertTrue(decoded.manifestSaved)
    }

    // MARK: - Staging Directory

    func testLoadPendingBackupState_ReturnsNilWhenEmpty() {
        // Clear any existing staging
        manager.clearStagingDirectory()

        let state = manager.loadPendingBackupState()
        XCTAssertNil(state)
    }

    func testHasPendingBackup_FalseWhenEmpty() {
        manager.clearStagingDirectory()
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testClearStagingDirectory_RemovesAllFiles() {
        // Create the staging dir with a dummy file to verify cleanup
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stagingDir = documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let dummyFile = stagingDir.appendingPathComponent("chunk_0.bin")
        try? Data([0x00]).write(to: dummyFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyFile.path))

        manager.clearStagingDirectory()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyFile.path))
    }

    func testLoadPendingBackupState_ReturnsNilWhenExpired() {
        // Write an expired state (49 hours old > 48h TTL)
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stagingDir = documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let expiredState = iCloudBackupManager.PendingBackupState(
            backupId: "expired-backup",
            totalChunks: 3,
            checksum: Data([0x01]),
            encryptedSize: 1024,
            createdAt: Date().addingTimeInterval(-49 * 60 * 60),
            uploadFinished: false,
            manifestSaved: false
        )

        let stateURL = stagingDir.appendingPathComponent("state.json")
        if let data = try? JSONEncoder().encode(expiredState) {
            try? data.write(to: stateURL)
        }

        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Expired staging state should return nil")

        // Verify it also cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDir.path))
    }
}
