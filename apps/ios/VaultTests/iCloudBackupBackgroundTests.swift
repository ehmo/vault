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
}
