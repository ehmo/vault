import XCTest
@testable import Vault

/// Tests for background backup operations: resume triggers, concurrent upload
/// prevention, upload flag management, vault key provider, and notifications.
@MainActor
final class ICloudBackupBackgroundTests: XCTestCase {

    private var manager: iCloudBackupManager!
    private let fm = FileManager.default
    private var documentsDir: URL!

    override func setUp() {
        super.setUp()
        manager = iCloudBackupManager.shared
        documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cleanupAll()
    }

    override func tearDown() {
        manager.isUploadRunning = false
        cleanupAll()
        UserDefaults.standard.removeObject(forKey: "iCloudBackupEnabled")
        UserDefaults.standard.removeObject(forKey: "lastBackupTimestamp")
        super.tearDown()
    }

    // MARK: - Notifications

    func testNotificationsDoNotCrash() {
        manager.sendBackupCompleteNotification(success: true)
        manager.sendBackupCompleteNotification(success: false, errorMessage: "Network unavailable")
        manager.sendBackupCompleteNotification(success: false)
    }

    // MARK: - Vault Key Provider

    func testVaultKeyProviderCanBeSetAndCleared() {
        manager.setVaultKeyProvider { Data(repeating: 0xAA, count: 32) }
        manager.setVaultKeyProvider { nil }
    }

    // MARK: - Resume Triggers

    func testResumeNoOpWhenBackupDisabled() throws {
        UserDefaults.standard.set(false, forKey: "iCloudBackupEnabled")
        try writePendingState()
        manager.resumeBackupUploadIfNeeded(trigger: "test")
        XCTAssertTrue(manager.hasPendingBackup, "State should not be consumed")
    }

    func testResumeNoOpWhenNoPendingBackup() {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        manager.resumeBackupUploadIfNeeded(trigger: "test")
    }

    func testResumeSkipsWhenUploadRunning() throws {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        try writePendingState()
        manager.isUploadRunning = true
        manager.resumeBackupUploadIfNeeded(trigger: "test")
        XCTAssertTrue(manager.hasPendingBackup)
    }

    // MARK: - Concurrent Upload Prevention

    func testIsUploadRunningDefaultsFalse() {
        XCTAssertFalse(manager.isUploadRunning)
    }

    func testUploadStagedBackupSetsAndClearsFlag() async throws {
        try await manager.uploadStagedBackup()
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(manager.isUploadRunning)
    }

    func testUploadStagedBackupSkipsConcurrentCall() async throws {
        manager.isUploadRunning = true
        try writePendingState()
        writeDummyChunks(count: 3)
        try await manager.uploadStagedBackup()
        XCTAssertTrue(manager.hasPendingBackup, "Should not be consumed by skipped upload")
    }

    func testIsUploadRunningClearedOnError() async {
        try? writePendingState()
        writeDummyChunks(count: 3)
        do { try await manager.uploadStagedBackup() } catch {}
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(manager.isUploadRunning, "Must be cleared even when upload throws")
    }

    // MARK: - Guard Interaction Matrix

    func testResumeGuardsAreIndependent() throws {
        // Guard 1: Disabled
        UserDefaults.standard.set(false, forKey: "iCloudBackupEnabled")
        manager.resumeBackupUploadIfNeeded(trigger: "g1")

        // Guard 2: No pending
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        manager.resumeBackupUploadIfNeeded(trigger: "g2")

        // Guard 3: Upload running
        try writePendingState()
        manager.isUploadRunning = true
        manager.resumeBackupUploadIfNeeded(trigger: "g3")
    }

    func testPerformBackupIfNeededSkipsWhenUploadRunning() {
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled")
        UserDefaults.standard.set(0.0, forKey: "lastBackupTimestamp")
        manager.isUploadRunning = true
        manager.performBackupIfNeeded(with: Data(repeating: 0xAA, count: 32))
    }

    // MARK: - Schedule Background Resume

    func testScheduleBackgroundResumeDoesNotCrash() {
        manager.scheduleBackgroundResumeTask(earliestIn: 60)
        manager.scheduleBackgroundResumeTask()
    }

    // MARK: - Helpers

    private var stagingDir: URL {
        documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
    }

    private func cleanupAll() {
        manager.clearStagingDirectory()
        if let contents = try? fm.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("pending_backup") {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func writePendingState() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "test", dataChunkCount: 3, decoyCount: 0,
            createdAt: Date(), uploadedFiles: [], retryCount: 0,
            fileCount: 10, vaultTotalSize: 102400
        )
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stagingDir.appendingPathComponent("state.json"))
    }

    private func writeDummyChunks(count: Int) {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        for i in 0..<count {
            try? Data(repeating: UInt8(i), count: 1024).write(
                to: stagingDir.appendingPathComponent("chunk_\(i).bin")
            )
        }
    }
}
