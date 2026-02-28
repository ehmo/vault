import XCTest
@testable import Vault

/// Tests for staging directory operations, pending backup state persistence,
/// local version index files, and TTL expiration.
@MainActor
final class ICloudBackupStorageTests: XCTestCase {

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
        cleanupAll()
        super.tearDown()
    }

    // MARK: - hasPendingBackup

    func testHasPendingBackupFalseWhenClean() {
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testHasPendingBackupTrueWhenStateExists() throws {
        try writePendingState()
        XCTAssertTrue(manager.hasPendingBackup)
    }

    func testHasPendingBackupFalseWhenExpired() throws {
        try writePendingState(createdAt: Date().addingTimeInterval(-49 * 3600))
        XCTAssertFalse(manager.hasPendingBackup)
    }

    // MARK: - Load Pending State

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(manager.loadPendingBackupState())
    }

    func testLoadReturnsValidState() throws {
        try writePendingState(backupId: "valid", dataChunkCount: 7)
        let loaded = manager.loadPendingBackupState()
        XCTAssertEqual(loaded?.backupId, "valid")
        XCTAssertEqual(loaded?.dataChunkCount, 7)
    }

    func testLoadPreservesAllFields() throws {
        try writePendingState(
            backupId: "full", dataChunkCount: 10, decoyCount: 2,
            uploadedFiles: ["a.bin", "b.bin"], retryCount: 5,
            fileCount: 20, vaultTotalSize: 50_000
        )
        let loaded = manager.loadPendingBackupState()
        XCTAssertEqual(loaded?.backupId, "full")
        XCTAssertEqual(loaded?.dataChunkCount, 10)
        XCTAssertEqual(loaded?.decoyCount, 2)
        XCTAssertEqual(loaded?.uploadedFiles, ["a.bin", "b.bin"])
        XCTAssertEqual(loaded?.retryCount, 5)
        XCTAssertEqual(loaded?.totalFiles, 13) // 10 + 1 + 2
    }

    func testLoadReturnsNilForExpiredState() throws {
        try writePendingState(createdAt: Date().addingTimeInterval(-49 * 3600))
        XCTAssertNil(manager.loadPendingBackupState())
        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path), "Expired dir should be cleaned up")
    }

    func testLoadAcceptsStateJustBeforeTTL() throws {
        try writePendingState(createdAt: Date().addingTimeInterval(-47 * 3600))
        XCTAssertNotNil(manager.loadPendingBackupState())
    }

    func testLoadReturnsNilForMalformedJSON() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try? "not json".data(using: .utf8)?.write(to: stagingDir.appendingPathComponent("state.json"))
        XCTAssertNil(manager.loadPendingBackupState())
    }

    func testLoadReturnsNilForEmptyFile() {
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try? Data().write(to: stagingDir.appendingPathComponent("state.json"))
        XCTAssertNil(manager.loadPendingBackupState())
    }

    // MARK: - Clear Staging Directory

    func testClearRemovesAllFiles() throws {
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: stagingDir.appendingPathComponent("chunk_0.bin"))
        manager.clearStagingDirectory()
        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
    }

    func testClearSafeWhenAlreadyClean() {
        manager.clearStagingDirectory()
        manager.clearStagingDirectory() // should not crash
    }

    func testClearWithFingerprint() throws {
        let fp = "fp_clear"
        let dir = documentsDir.appendingPathComponent("pending_backup_\(fp)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)!.write(to: dir.appendingPathComponent("state.json"))

        manager.clearStagingDirectory(fingerprint: fp)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    // MARK: - Local Version Index

    func testLocalVersionIndexCreateAndLoad() throws {
        let fp = "idx_test"
        let url = documentsDir.appendingPathComponent("backup_index_\(fp).json")

        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry("v1"))
        index.addVersion(makeEntry("v2"))
        try JSONEncoder().encode(index).write(to: url, options: .atomic)

        let loaded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionIndex.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(loaded.versions.count, 2)
        XCTAssertEqual(loaded.versions.map(\.backupId), ["v1", "v2"])
    }

    // MARK: - Per-Vault Staging Directory

    func testPerVaultStagingDirCreateAndLoad() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "staging", dataChunkCount: 1, decoyCount: 0,
            createdAt: Date(), uploadedFiles: [], retryCount: 0,
            fileCount: 5, vaultTotalSize: 1000, vaultFingerprint: "fp_staging"
        )
        let dir = documentsDir.appendingPathComponent("pending_backup_fp_staging", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: dir.appendingPathComponent("state.json"), options: .atomic)

        let loaded = manager.loadPendingBackupState()
        XCTAssertEqual(loaded?.backupId, "staging")
        XCTAssertEqual(loaded?.vaultFingerprint, "fp_staging")
    }

    // MARK: - Helpers

    private var stagingDir: URL {
        documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
    }

    private func cleanupAll() {
        manager.clearStagingDirectory()
        if let contents = try? fm.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("pending_backup")
                || url.lastPathComponent.hasPrefix("backup_index_") {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func writePendingState(
        backupId: String = "test", dataChunkCount: Int = 3, decoyCount: Int = 0,
        createdAt: Date = Date(), uploadedFiles: Set<String> = [],
        retryCount: Int = 0, fileCount: Int = 10, vaultTotalSize: Int = 102400
    ) throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: backupId, dataChunkCount: dataChunkCount, decoyCount: decoyCount,
            createdAt: createdAt, uploadedFiles: uploadedFiles, retryCount: retryCount,
            fileCount: fileCount, vaultTotalSize: vaultTotalSize
        )
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stagingDir.appendingPathComponent("state.json"))
    }

    private func makeEntry(_ id: String) -> iCloudBackupManager.BackupVersionEntry {
        .init(backupId: id, timestamp: Date(), size: 1024,
              chunkCount: 1, fileCount: nil, vaultTotalSize: nil)
    }
}
