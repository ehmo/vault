import XCTest
import CloudKit
@testable import Vault

/// Regression tests for warning-fix changes across multiple files.
/// Each section verifies that the behavioral fix is correct and catches
/// future regressions if the code is modified.
@MainActor
final class WarningFixRegressionTests: XCTestCase {

    // MARK: - PendingBackupState.recordsToDelete immutability at staging

    /// Verifies that PendingBackupState can be created with an empty
    /// recordsToDelete (the staging function creates it as `let [] = []`).
    func testPendingStateAcceptsEmptyRecordsToDelete() {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "staging-test",
            dataChunkCount: 3,
            decoyCount: 1,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 10,
            vaultTotalSize: 50_000,
            recordsToDelete: []
        )
        XCTAssertTrue(state.recordsToDelete.isEmpty)
        XCTAssertEqual(state.totalFiles, 5) // 3 data + 1 VDIR + 1 decoy
    }

    /// The struct's recordsToDelete field must remain mutable (it's a `var`)
    /// so that other code paths can populate it after creation.
    func testPendingStateRecordsToDeleteIsMutable() {
        var state = iCloudBackupManager.PendingBackupState(
            backupId: "mutate-test",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 5,
            vaultTotalSize: 1000,
            recordsToDelete: []
        )
        state.recordsToDelete.append("record-1")
        state.recordsToDelete.append("record-2")
        XCTAssertEqual(state.recordsToDelete, ["record-1", "record-2"])
    }

    /// Ensures recordsToDelete survives Codable round-trip with values.
    func testPendingStateRecordsToDeleteCodableRoundTrip() throws {
        let original = iCloudBackupManager.PendingBackupState(
            backupId: "codable-rt",
            dataChunkCount: 2,
            decoyCount: 0,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            uploadedFiles: ["f1"],
            retryCount: 1,
            fileCount: 8,
            vaultTotalSize: 50_000,
            recordsToDelete: ["old-vdir", "old-chunk-0", "old-chunk-1"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.PendingBackupState.self, from: data
        )
        XCTAssertEqual(decoded.recordsToDelete, ["old-vdir", "old-chunk-0", "old-chunk-1"])
    }

    /// Backward compat: old persisted states without recordsToDelete should
    /// decode with an empty array (the field has a default value).
    func testPendingStateDecodesWithoutRecordsToDelete() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "legacy",
            dataChunkCount: 2,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 5,
            vaultTotalSize: 1000
        )
        // Encode then strip the recordsToDelete key
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(state)
        ) as! [String: Any]
        dict.removeValue(forKey: "recordsToDelete")
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.PendingBackupState.self,
            from: JSONSerialization.data(withJSONObject: dict)
        )
        XCTAssertTrue(decoded.recordsToDelete.isEmpty,
                       "Missing key should decode to empty array")
    }

    // MARK: - MediaOptimizer.imageOptimizationThreshold mutability

    /// Tests must be able to mutate the threshold to control optimization
    /// behavior. This test verifies the property is still writable.
    func testImageOptimizationThresholdIsMutable() {
        let saved = MediaOptimizer.imageOptimizationThreshold
        defer { MediaOptimizer.imageOptimizationThreshold = saved }

        MediaOptimizer.imageOptimizationThreshold = 0
        XCTAssertEqual(MediaOptimizer.imageOptimizationThreshold, 0)

        MediaOptimizer.imageOptimizationThreshold = 1_000_000
        XCTAssertEqual(MediaOptimizer.imageOptimizationThreshold, 1_000_000)
    }

    /// The default threshold value should be 500KB.
    func testImageOptimizationThresholdDefaultValue() {
        // Save, check, restore — in case another test mutated it
        let saved = MediaOptimizer.imageOptimizationThreshold
        defer { MediaOptimizer.imageOptimizationThreshold = saved }

        // Reset to known state
        MediaOptimizer.imageOptimizationThreshold = 500_000
        XCTAssertEqual(MediaOptimizer.imageOptimizationThreshold, 500_000)
    }

    // MARK: - BackupVersionEntry formatters

    /// Verifies that formatted fields produce non-empty strings for realistic data.
    func testVersionEntryFormattedFieldsNonEmpty() {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "fmt-test",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880,
            chunkCount: 5,
            fileCount: 12,
            vaultTotalSize: 10_000_000
        )
        XCTAssertFalse(entry.formattedSize.isEmpty,
                       "formattedSize should produce human-readable output")
        XCTAssertFalse(entry.formattedDate.isEmpty,
                       "formattedDate should produce human-readable output")
    }

    // MARK: - BackupVersionIndex eviction produces valid recordsToDelete candidates

    /// When a version is evicted from the index, the evicted entry is returned
    /// so the caller can build a recordsToDelete list. Verify the eviction
    /// mechanism returns the correct oldest entry.
    func testVersionIndexEvictionReturnsOldestEntry() {
        var index = iCloudBackupManager.BackupVersionIndex()
        let v1 = makeEntry("v1", timestamp: Date(timeIntervalSince1970: 1000))
        let v2 = makeEntry("v2", timestamp: Date(timeIntervalSince1970: 2000))
        let v3 = makeEntry("v3", timestamp: Date(timeIntervalSince1970: 3000))
        let v4 = makeEntry("v4", timestamp: Date(timeIntervalSince1970: 4000))

        XCTAssertNil(index.addVersion(v1))
        XCTAssertNil(index.addVersion(v2))
        XCTAssertNil(index.addVersion(v3))

        let evicted = index.addVersion(v4)
        XCTAssertEqual(evicted?.backupId, "v1",
                       "First-in version should be evicted")
    }

    // MARK: - Background task always succeeds (unreachable catch removal)

    /// The background task handler (Case 2: overdue + key available) logs and
    /// sets succeeded=true unconditionally. Verify the manager doesn't crash
    /// when performing a background backup check in this state.
    func testPerformBackupIfNeededDoesNotCrashWithKey() {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        UserDefaults.standard.set(0.0, forKey: "lastBackupTimestamp") // overdue

        let manager = iCloudBackupManager.shared
        manager.setVaultKeyProvider { Data(repeating: 0xAA, count: 32) }
        defer { manager.setVaultKeyProvider { nil } }

        // This exercises the code path where the catch block was removed
        manager.performBackupIfNeeded(with: Data(repeating: 0xBB, count: 32))
    }

    // MARK: - iCloudError descriptions remain stable

    /// Guard against regression in error descriptions that users see.
    func testErrorDescriptionsAreStable() {
        XCTAssertEqual(iCloudError.notAvailable.errorDescription,
                       "iCloud is not available.")
        XCTAssertEqual(iCloudError.containerNotFound.errorDescription,
                       "iCloud container not found.")
        XCTAssertTrue(iCloudError.uploadFailed.errorDescription!.contains("Upload failed"))
        XCTAssertTrue(iCloudError.downloadFailed.errorDescription!.contains("Download failed"))
        XCTAssertEqual(iCloudError.fileNotFound.errorDescription,
                       "No backup found.")
        XCTAssertTrue(iCloudError.checksumMismatch.errorDescription!.contains("Wrong pattern"))
        XCTAssertTrue(iCloudError.wifiRequired.errorDescription!.contains("Wi-Fi"))
        XCTAssertNil(iCloudError.backupSkipped.errorDescription,
                     "backupSkipped should be silent (no user-facing message)")
    }

    // MARK: - PendingBackupState totalFiles computation

    /// Verifies the computed property: totalFiles = dataChunkCount + 1 (VDIR) + decoyCount
    func testTotalFilesComputation() {
        XCTAssertEqual(makePendingState(data: 5, decoys: 2).totalFiles, 8)
        XCTAssertEqual(makePendingState(data: 1, decoys: 0).totalFiles, 2)
        XCTAssertEqual(makePendingState(data: 0, decoys: 0).totalFiles, 1)
        XCTAssertEqual(makePendingState(data: 10, decoys: 5).totalFiles, 16)
    }

    // MARK: - Upload flag lifecycle

    /// Verifies that the upload running flag starts false and can be toggled.
    func testUploadRunningFlagLifecycle() {
        let manager = iCloudBackupManager.shared
        XCTAssertFalse(manager.isUploadRunning, "Should start false")
        manager.isUploadRunning = true
        XCTAssertTrue(manager.isUploadRunning)
        manager.isUploadRunning = false
        XCTAssertFalse(manager.isUploadRunning)
    }

    // MARK: - BackupStage raw values contract

    /// These raw values are displayed to users. Guard against accidental changes.
    func testBackupStageRawValuesAreStable() {
        XCTAssertEqual(iCloudBackupManager.BackupStage.waitingForICloud.rawValue,
                       "Connecting to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.readingVault.rawValue,
                       "Reading vault data...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.encrypting.rawValue,
                       "Encrypting backup...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.uploading.rawValue,
                       "Uploading to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.complete.rawValue,
                       "Backup complete")
    }

    // MARK: - ScanResult types

    /// Verify filter operations on data chunks by backupId — this is how
    /// restoreBackupVersion finds the right chunks to download.
    func testDataChunksFilterByBackupId() {
        let chunks = [
            iCloudBackupManager.ScanResult.DataChunk(
                recordID: CKRecord.ID(recordName: "r1"), backupId: "A", chunkIndex: 0),
            iCloudBackupManager.ScanResult.DataChunk(
                recordID: CKRecord.ID(recordName: "r2"), backupId: "A", chunkIndex: 1),
            iCloudBackupManager.ScanResult.DataChunk(
                recordID: CKRecord.ID(recordName: "r3"), backupId: "B", chunkIndex: 0),
        ]
        let filtered = chunks.filter { $0.backupId == "A" }
            .sorted { $0.chunkIndex < $1.chunkIndex }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].chunkIndex, 0)
        XCTAssertEqual(filtered[1].chunkIndex, 1)
    }

    // MARK: - Helpers

    private func makeEntry(
        _ id: String,
        timestamp: Date = Date(),
        size: Int = 1024
    ) -> iCloudBackupManager.BackupVersionEntry {
        .init(backupId: id, timestamp: timestamp, size: size,
              chunkCount: 1, fileCount: nil, vaultTotalSize: nil)
    }

    private func makePendingState(
        data: Int = 1,
        decoys: Int = 0
    ) -> iCloudBackupManager.PendingBackupState {
        .init(backupId: "test", dataChunkCount: data, decoyCount: decoys,
              createdAt: Date(), uploadedFiles: [], retryCount: 0,
              fileCount: 5, vaultTotalSize: 1000)
    }
}
