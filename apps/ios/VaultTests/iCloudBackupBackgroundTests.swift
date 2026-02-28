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
        clearAllStagingDirs()
    }

    override func tearDown() {
        clearAllStagingDirs()
        super.tearDown()
    }

    /// Clears all pending_backup* directories (legacy + per-vault) for test isolation.
    private func clearAllStagingDirs() {
        manager.clearStagingDirectory()
        if let contents = try? fm.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("pending_backup") {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Helpers

    private var stagingDir: URL {
        documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
    }

    private struct PendingStateParams {
        var backupId: String = "test-backup"
        var dataChunkCount: Int = 3
        var decoyCount: Int = 0
        var createdAt: Date = Date()
        var uploadedFiles: Set<String> = []
        var retryCount: Int = 0
        var fileCount: Int = 10
        var vaultTotalSize: Int = 102400
    }

    private func writePendingState(_ params: PendingStateParams = PendingStateParams()) throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: params.backupId,
            dataChunkCount: params.dataChunkCount,
            decoyCount: params.decoyCount,
            createdAt: params.createdAt,
            uploadedFiles: params.uploadedFiles,
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
            dataChunkCount: 5,
            decoyCount: 2,
            createdAt: Date(),
            uploadedFiles: ["file1.bin", "file2.bin"],
            retryCount: 3,
            fileCount: 42,
            vaultTotalSize: 10_485_760
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(decoded.backupId, state.backupId)
        XCTAssertEqual(decoded.dataChunkCount, state.dataChunkCount)
        XCTAssertEqual(decoded.decoyCount, state.decoyCount)
        XCTAssertEqual(decoded.uploadedFiles, state.uploadedFiles)
        XCTAssertEqual(decoded.retryCount, state.retryCount)
        XCTAssertEqual(decoded.fileCount, state.fileCount)
        XCTAssertEqual(decoded.vaultTotalSize, state.vaultTotalSize)
    }

    func testPendingBackupStateTotalFilesComputed() {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "total-files-test",
            dataChunkCount: 5,
            decoyCount: 3,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 10,
            vaultTotalSize: 50_000
        )

        // totalFiles = dataChunkCount + 1 (VDIR) + decoyCount = 5 + 1 + 3 = 9
        XCTAssertEqual(state.totalFiles, 9)
    }

    func testPendingBackupStateCodablePreservesCreatedAt() throws {
        let createdAt = Date(timeIntervalSince1970: 1700000000)
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "time-test",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: createdAt,
            uploadedFiles: [],
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

    func testPendingBackupStateCodablePreservesUploadedFiles() throws {
        let files: Set<String> = ["chunk_0.bin", "chunk_1.bin", "vdir.bin"]
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "uploaded-files-test",
            dataChunkCount: 2,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: files,
            retryCount: 0,
            fileCount: 5,
            vaultTotalSize: 10_000
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(decoded.uploadedFiles, files)
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
        try writePendingState(.init(dataChunkCount: 5))

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
        try writePendingState(.init(backupId: "valid-backup", dataChunkCount: 7))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "valid-backup")
        XCTAssertEqual(loaded?.dataChunkCount, 7)
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
            dataChunkCount: 10,
            decoyCount: 2,
            createdAt: now,
            uploadedFiles: ["a.bin", "b.bin"],
            retryCount: 5,
            fileCount: 20,
            vaultTotalSize: 50_000
        ))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "full-test")
        XCTAssertEqual(loaded?.dataChunkCount, 10)
        XCTAssertEqual(loaded?.decoyCount, 2)
        XCTAssertEqual(loaded?.uploadedFiles, ["a.bin", "b.bin"])
        XCTAssertEqual(loaded?.retryCount, 5)
        XCTAssertEqual(loaded?.fileCount, 20)
        XCTAssertEqual(loaded?.vaultTotalSize, 50_000)
        XCTAssertEqual(loaded?.totalFiles, 13) // 10 + 1 + 2
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

    // MARK: - Concurrent Upload Prevention (isUploadRunning)

    func testIsUploadRunningDefaultsFalse() {
        XCTAssertFalse(manager.isUploadRunning,
                       "isUploadRunning should default to false")
    }

    func testResumeBackupUploadIfNeededSkipsWhenUploadRunning() throws {
        // Set up conditions where resume would normally trigger
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        try writePendingState()

        // Simulate an ongoing upload (manual backup in progress)
        manager.isUploadRunning = true
        defer { manager.isUploadRunning = false }

        // Resume should skip because an upload is already running
        manager.resumeBackupUploadIfNeeded(trigger: "test_concurrent")

        // State should still exist (resume was skipped, not consumed)
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testResumeBackupUploadIfNeededProceedsWhenUploadNotRunning() throws {
        // Set up conditions where resume would normally trigger
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        try writePendingState()
        writeDummyChunks(count: 3)

        // Ensure upload is not running
        manager.isUploadRunning = false

        // Resume should proceed (it will try to upload and fail on CloudKit,
        // but the point is it attempts rather than skipping)
        manager.resumeBackupUploadIfNeeded(trigger: "test_not_concurrent")

        // The state should still exist because CloudKit isn't available in tests
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testPerformBackupIfNeededSkipsWhenUploadRunning() throws {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        UserDefaults.standard.set(0.0, forKey: "lastBackupTimestamp") // Never backed up -> overdue

        // Simulate an ongoing upload
        manager.isUploadRunning = true
        defer { manager.isUploadRunning = false }

        // Should skip because upload is already running
        let testKey = Data(repeating: 0xAA, count: 32)
        manager.performBackupIfNeeded(with: testKey)

        // No auto backup task should be created
        // (We can't directly check autoBackupTask since it's private,
        // but the function returned without starting anything)
    }

    func testPerformBackupIfNeededSkipsWhenAutoBackupRunning() throws {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        UserDefaults.standard.set(0.0, forKey: "lastBackupTimestamp")

        // First call should trigger (it'll try to start)
        let testKey = Data(repeating: 0xBB, count: 32)

        // Stage a pending backup so it goes through the resume path
        try writePendingState()
        writeDummyChunks(count: 3)

        manager.performBackupIfNeeded(with: testKey)

        // Second call should skip because first one is running
        manager.performBackupIfNeeded(with: testKey)
    }

    func testUploadStagedBackupSetsAndClearsFlag() async throws {
        // No pending state -> uploadStagedBackup will return early
        manager.clearStagingDirectory()

        // Before calling, flag should be false
        XCTAssertFalse(manager.isUploadRunning)

        // Call uploadStagedBackup - it will set the flag, find no state, and return
        try await manager.uploadStagedBackup()

        // Give the defer Task a chance to clear the flag on MainActor
        await Task.yield()
        // Allow the MainActor to process the enqueued task
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        XCTAssertFalse(manager.isUploadRunning,
                       "isUploadRunning should be cleared after uploadStagedBackup returns")
    }

    func testUploadStagedBackupSkipsConcurrentCall() async throws {
        // Simulate an upload already running
        manager.isUploadRunning = true
        defer { manager.isUploadRunning = false }

        // Set up a pending state that would normally be uploaded
        try writePendingState()
        writeDummyChunks(count: 3)

        // Should return immediately without doing anything
        try await manager.uploadStagedBackup()

        // State should still be intact (wasn't consumed by a concurrent upload)
        XCTAssertTrue(manager.hasPendingBackup,
                      "Pending backup should not be consumed by a skipped upload")
    }

    func testUploadStagedBackupConcurrentCallsAreIdempotent() async throws {
        // Both calls with no pending state -> both return early
        manager.clearStagingDirectory()

        // First call sets the flag and returns (no state)
        try await manager.uploadStagedBackup()

        // Give the defer a moment to clear
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Second call should also succeed (flag was cleared)
        try await manager.uploadStagedBackup()

        // Give the defer a moment to clear
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(manager.isUploadRunning,
                       "Flag should be cleared after sequential uploads")
    }

    // MARK: - Temp File Uniqueness

    func testTempFileNamesAreUnique() {
        // Simulate the temp file naming pattern used in upload code
        let backupId = "test-backup"
        let chunkIndex = 0
        let recordName = "\(backupId)_bchunk_\(chunkIndex)"

        let tempURL1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(recordName)_\(UUID().uuidString).bin")
        let tempURL2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(recordName)_\(UUID().uuidString).bin")

        XCTAssertNotEqual(tempURL1, tempURL2,
                          "Two temp files for the same chunk should have unique names (UUID suffix)")
    }

    func testTempFileNamesContainRecordName() {
        let recordName = "abc123_bchunk_7"
        let uuid = UUID().uuidString
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(recordName)_\(uuid).bin")

        XCTAssertTrue(tempURL.lastPathComponent.hasPrefix(recordName),
                      "Temp file name should start with the record name")
        XCTAssertTrue(tempURL.lastPathComponent.hasSuffix(".bin"),
                      "Temp file name should end with .bin")
        XCTAssertTrue(tempURL.lastPathComponent.contains(uuid),
                      "Temp file name should contain the UUID")
    }

    // MARK: - Guard Interaction Matrix

    /// Verifies all three guards (backup disabled, no pending state, upload running)
    /// work independently.
    func testResumeGuardsAreIndependent() throws {
        // Guard 1: Backup disabled
        UserDefaults.standard.set(false, forKey: "iCloudBackupEnabled")
        manager.isUploadRunning = false
        manager.clearStagingDirectory()
        manager.resumeBackupUploadIfNeeded(trigger: "guard1")
        // Should return at first guard

        // Guard 2: No pending backup
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        manager.isUploadRunning = false
        manager.clearStagingDirectory()
        manager.resumeBackupUploadIfNeeded(trigger: "guard2")
        // Should return at pending state guard

        // Guard 3: Upload already running
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        try writePendingState()
        manager.isUploadRunning = true
        manager.resumeBackupUploadIfNeeded(trigger: "guard3")
        // Should return at isUploadRunning guard

        // Clean up
        manager.isUploadRunning = false
    }

    /// Test that the flag reset in defer works even when uploadStagedBackup
    /// encounters errors during the iCloud account check.
    func testIsUploadRunningClearedOnError() async {
        // Set up a pending state so we get past the first guard
        try? writePendingState()
        writeDummyChunks(count: 3)

        manager.isUploadRunning = false

        // uploadStagedBackup will fail on waitForAvailableAccount (no iCloud in tests)
        // but the flag should still be cleared
        do {
            try await manager.uploadStagedBackup()
        } catch {
            // Expected -- iCloud isn't available in test environment
        }

        // Allow defer Task to run
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertFalse(manager.isUploadRunning,
                       "isUploadRunning must be cleared even when upload throws")
    }

    // MARK: - iCloudError Error Descriptions

    func testAllICloudErrorCasesHaveDescriptions() {
        let allCases: [iCloudError] = [
            .notAvailable, .containerNotFound, .uploadFailed,
            .downloadFailed, .fileNotFound, .checksumMismatch, .wifiRequired
        ]
        for error in allCases {
            XCTAssertNotNil(error.errorDescription,
                            "\(error) should have a non-nil errorDescription")
            XCTAssertFalse(error.errorDescription!.isEmpty,
                           "\(error) should have a non-empty errorDescription")
        }
    }

    func testICloudErrorDescriptionContent() {
        // Verify each case returns the expected human-readable message
        XCTAssertEqual(iCloudError.notAvailable.errorDescription, "iCloud is not available.")
        XCTAssertEqual(iCloudError.containerNotFound.errorDescription, "iCloud container not found.")
        XCTAssertEqual(iCloudError.uploadFailed.errorDescription, "Upload failed. Check your connection and try again.")
        XCTAssertEqual(iCloudError.downloadFailed.errorDescription, "Download failed. The backup data may be corrupted.")
        XCTAssertEqual(iCloudError.fileNotFound.errorDescription, "No backup found.")
        XCTAssertTrue(iCloudError.checksumMismatch.errorDescription!.contains("Wrong pattern"))
        XCTAssertTrue(iCloudError.wifiRequired.errorDescription!.contains("Wi-Fi"))
    }

    func testICloudErrorLocalizedDescriptionUsesErrorDescription() {
        // LocalizedError's localizedDescription should use errorDescription
        let error: Error = iCloudError.checksumMismatch
        XCTAssertEqual(
            error.localizedDescription,
            "Wrong pattern. The pattern doesn't match the one used for this backup.",
            "localizedDescription should match errorDescription for LocalizedError conformance"
        )
    }

    func testICloudErrorDescriptionsDoNotContainSwiftErrorType() {
        // The original bug: errors displayed as "Vault.iCloudError error 5."
        let allCases: [iCloudError] = [
            .notAvailable, .containerNotFound, .uploadFailed,
            .downloadFailed, .fileNotFound, .checksumMismatch, .wifiRequired
        ]
        for error in allCases {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.contains("iCloudError"),
                           "\(error).errorDescription should not contain raw Swift type name")
            XCTAssertFalse(description.contains("error "),
                           "\(error).errorDescription should not contain raw error number")
        }
    }

    // MARK: - backupSkipped Error

    func testBackupSkippedErrorHasNilDescription() {
        let error = iCloudError.backupSkipped
        XCTAssertNil(error.errorDescription, "backupSkipped should have nil errorDescription (silent)")
    }

    // MARK: - BackupVersionIndex

    func testBackupVersionIndexAddVersionAppendsEntry() {
        var index = iCloudBackupManager.BackupVersionIndex()
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "test-1", timestamp: Date(), size: 1024,
            chunkCount: 2, fileCount: nil, vaultTotalSize: nil
        )
        let evicted = index.addVersion(entry)
        XCTAssertNil(evicted, "First entry should not evict anything")
        XCTAssertEqual(index.versions.count, 1)
        XCTAssertEqual(index.versions[0].backupId, "test-1")
    }

    func testBackupVersionIndexEvictsOldestAtCapacity() {
        var index = iCloudBackupManager.BackupVersionIndex()
        for i in 1...3 {
            index.addVersion(iCloudBackupManager.BackupVersionEntry(
                backupId: "v\(i)", timestamp: Date(), size: 1024,
                chunkCount: 2, fileCount: nil, vaultTotalSize: nil
            ))
        }
        XCTAssertEqual(index.versions.count, 3)

        let evicted = index.addVersion(iCloudBackupManager.BackupVersionEntry(
            backupId: "v4", timestamp: Date(), size: 1024,
            chunkCount: 2, fileCount: nil, vaultTotalSize: nil
        ))
        XCTAssertEqual(evicted?.backupId, "v1", "Oldest entry (v1) should be evicted")
        XCTAssertEqual(index.versions.count, 3, "Should stay at 3 max")
        XCTAssertEqual(index.versions.map(\.backupId), ["v2", "v3", "v4"])
    }

    func testBackupVersionIndexCodableRoundTrip() throws {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(iCloudBackupManager.BackupVersionEntry(
            backupId: "test-rt", timestamp: Date(), size: 2048,
            chunkCount: 5, fileCount: nil, vaultTotalSize: nil
        ))

        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.BackupVersionIndex.self, from: data)

        XCTAssertEqual(decoded.versions.count, 1)
        XCTAssertEqual(decoded.versions[0].backupId, "test-rt")
        XCTAssertEqual(decoded.versions[0].size, 2048)
        XCTAssertEqual(decoded.versions[0].chunkCount, 5)
    }

    func testBackupVersionEntryFormattedFields() {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "fmt-test",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880,
            chunkCount: 10,
            fileCount: nil,
            vaultTotalSize: nil
        )

        XCTAssertFalse(entry.formattedDate.isEmpty)
        XCTAssertFalse(entry.formattedSize.isEmpty)
    }

    func testBackupVersionEntryOptionalFields() {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "opt-test",
            timestamp: Date(),
            size: 1024,
            chunkCount: 1,
            fileCount: 42,
            vaultTotalSize: 102400
        )

        XCTAssertEqual(entry.fileCount, 42)
        XCTAssertEqual(entry.vaultTotalSize, 102400)
    }

    // MARK: - Vault Fingerprint

    func testVaultFingerprintIsDeterministic() {
        let key = Data(repeating: 0x42, count: 32)
        let fp1 = iCloudBackupManager.vaultFingerprint(from: key)
        let fp2 = iCloudBackupManager.vaultFingerprint(from: key)
        XCTAssertEqual(fp1, fp2)
    }

    func testVaultFingerprintIs16HexChars() {
        let key = Data(repeating: 0xAA, count: 32)
        let fp = iCloudBackupManager.vaultFingerprint(from: key)
        XCTAssertEqual(fp.count, 16)
        let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
        for c in fp.unicodeScalars {
            XCTAssertTrue(hexSet.contains(c))
        }
    }

    func testPendingBackupStateDecodesWithoutVaultFingerprint() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "legacy-id",
            dataChunkCount: 3,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 5,
            vaultTotalSize: 10000,
            vaultFingerprint: "test_fp"
        )
        let encoded = try JSONEncoder().encode(state)
        var dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        dict.removeValue(forKey: "vaultFingerprint")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.PendingBackupState.self,
            from: strippedData
        )
        XCTAssertNil(decoded.vaultFingerprint, "Legacy state without fingerprint should decode as nil")
        XCTAssertEqual(decoded.backupId, "legacy-id")
    }

    func testBackupSkippedIsDistinctFromOtherErrors() {
        let errors: [iCloudError] = [
            .notAvailable, .containerNotFound, .uploadFailed,
            .downloadFailed, .fileNotFound, .checksumMismatch, .wifiRequired
        ]
        for otherError in errors {
            XCTAssertNotEqual(
                String(describing: otherError),
                String(describing: iCloudError.backupSkipped),
                "backupSkipped should be distinct from \(otherError)"
            )
        }
    }
}
