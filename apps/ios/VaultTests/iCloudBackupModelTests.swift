import XCTest
import CloudKit
@testable import Vault

/// Pure data structure tests: version entries, version index, pending state,
/// scan result types, backup stages, and error descriptions.
@MainActor
final class ICloudBackupModelTests: XCTestCase {

    // MARK: - BackupVersionEntry

    func testCodableRoundTrip() throws {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "test-001",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880, chunkCount: 5,
            fileCount: 12, vaultTotalSize: 10_000_000
        )
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertEqual(decoded.backupId, "test-001")
        XCTAssertEqual(decoded.size, 5_242_880)
        XCTAssertEqual(decoded.chunkCount, 5)
        XCTAssertEqual(decoded.fileCount, 12)
        XCTAssertEqual(decoded.vaultTotalSize, 10_000_000)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1700000000, accuracy: 1.0)
    }

    func testNilOptionalsSurviveCodable() throws {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "no-opt", timestamp: Date(), size: 1024,
            chunkCount: 1, fileCount: nil, vaultTotalSize: nil
        )
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertNil(decoded.fileCount)
        XCTAssertNil(decoded.vaultTotalSize)
    }

    func testDecodesMinimalJSON() throws {
        let json = """
        {"backupId":"min-001","timestamp":1700000000,"size":1000,"chunkCount":1}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(iCloudBackupManager.BackupVersionEntry.self, from: json)
        XCTAssertEqual(entry.backupId, "min-001")
        XCTAssertNil(entry.fileCount)
        XCTAssertNil(entry.vaultTotalSize)
    }

    func testFormattedFieldsNonEmpty() {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "fmt", timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880, chunkCount: 1, fileCount: nil, vaultTotalSize: nil
        )
        XCTAssertFalse(entry.formattedSize.isEmpty)
        XCTAssertFalse(entry.formattedDate.isEmpty)
    }

    // MARK: - BackupVersionIndex

    func testIndexStartsEmpty() {
        XCTAssertTrue(iCloudBackupManager.BackupVersionIndex().versions.isEmpty)
    }

    func testIndexAddsAndEvictsOldest() {
        var index = iCloudBackupManager.BackupVersionIndex()
        XCTAssertNil(index.addVersion(makeEntry("v1")))
        XCTAssertNil(index.addVersion(makeEntry("v2")))
        XCTAssertNil(index.addVersion(makeEntry("v3")))

        let evicted = index.addVersion(makeEntry("v4"))
        XCTAssertEqual(evicted?.backupId, "v1")
        XCTAssertEqual(index.versions.count, 3)
        XCTAssertEqual(index.versions.map(\.backupId), ["v2", "v3", "v4"])
    }

    func testIndexNeverExceedsThree() {
        var index = iCloudBackupManager.BackupVersionIndex()
        for i in 0..<10 { index.addVersion(makeEntry("v\(i)")) }
        XCTAssertEqual(index.versions.count, 3)
        XCTAssertEqual(index.versions.map(\.backupId), ["v7", "v8", "v9"])
    }

    func testIndexCodableRoundTrip() throws {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry("a", size: 100))
        index.addVersion(makeEntry("b", size: 200))

        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionIndex.self,
            from: JSONEncoder().encode(index)
        )
        XCTAssertEqual(decoded.versions.count, 2)
        XCTAssertEqual(decoded.versions[0].backupId, "a")
        XCTAssertEqual(decoded.versions[0].size, 100)
    }

    func testIndexRemoveById() {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry("keep1"))
        index.addVersion(makeEntry("remove"))
        index.addVersion(makeEntry("keep2"))

        index.versions.removeAll { $0.backupId == "remove" }
        XCTAssertEqual(index.versions.map(\.backupId), ["keep1", "keep2"])
    }

    func testVersionsSortByTimestampDescending() {
        let old = makeEntry("old", timestamp: Date(timeIntervalSince1970: 1000))
        let mid = makeEntry("mid", timestamp: Date(timeIntervalSince1970: 2000))
        let new = makeEntry("new", timestamp: Date(timeIntervalSince1970: 3000))

        let sorted = [mid, old, new].sorted { $0.timestamp > $1.timestamp }
        XCTAssertEqual(sorted.map(\.backupId), ["new", "mid", "old"])
    }

    // MARK: - PendingBackupState

    func testTotalFilesComputed() {
        // totalFiles = dataChunkCount + 1 (VDIR) + decoyCount
        XCTAssertEqual(makePendingState(dataChunks: 5, decoys: 2).totalFiles, 8)
        XCTAssertEqual(makePendingState(dataChunks: 3, decoys: 0).totalFiles, 4)
    }

    func testPendingStateCodableRoundTrip() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "codable", dataChunkCount: 4, decoyCount: 2,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            uploadedFiles: ["f1", "f2"], retryCount: 3,
            fileCount: 20, vaultTotalSize: 100_000,
            wasTerminated: true, vaultFingerprint: "fp123",
            recordsToDelete: ["r1", "r2"]
        )
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.PendingBackupState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded.backupId, "codable")
        XCTAssertEqual(decoded.dataChunkCount, 4)
        XCTAssertEqual(decoded.decoyCount, 2)
        XCTAssertEqual(decoded.uploadedFiles, ["f1", "f2"])
        XCTAssertEqual(decoded.retryCount, 3)
        XCTAssertEqual(decoded.fileCount, 20)
        XCTAssertEqual(decoded.vaultTotalSize, 100_000)
        XCTAssertTrue(decoded.wasTerminated)
        XCTAssertEqual(decoded.vaultFingerprint, "fp123")
        XCTAssertEqual(decoded.recordsToDelete, ["r1", "r2"])
        XCTAssertEqual(decoded.totalFiles, 7)
    }

    func testPendingStateDefaults() {
        let state = makePendingState()
        XCTAssertFalse(state.wasTerminated)
        XCTAssertNil(state.vaultFingerprint)
        XCTAssertTrue(state.recordsToDelete.isEmpty)
    }

    func testUploadProgressTracking() {
        var state = makePendingState(dataChunks: 3, decoys: 1)
        state.uploadedFiles.insert("vdat_0")
        state.uploadedFiles.insert("vdir")
        XCTAssertEqual(state.uploadedFiles.count, 2)
        state.uploadedFiles.insert("vdat_0") // duplicate
        XCTAssertEqual(state.uploadedFiles.count, 2, "Set should deduplicate")
    }

    func testPendingStateDecodesWithoutVaultFingerprint() throws {
        // Backward compat: old states may lack vaultFingerprint
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "legacy", dataChunkCount: 3, decoyCount: 0,
            createdAt: Date(), uploadedFiles: [], retryCount: 0,
            fileCount: 5, vaultTotalSize: 10000, vaultFingerprint: "fp"
        )
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        dict.removeValue(forKey: "vaultFingerprint")
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.PendingBackupState.self,
            from: JSONSerialization.data(withJSONObject: dict)
        )
        XCTAssertNil(decoded.vaultFingerprint)
    }

    // MARK: - ScanResult Types

    func testScanResultStartsEmpty() {
        let result = iCloudBackupManager.ScanResult()
        XCTAssertTrue(result.dataChunks.isEmpty)
        XCTAssertTrue(result.dirChunks.isEmpty)
        XCTAssertTrue(result.decoyChunks.isEmpty)
        XCTAssertEqual(result.totalScanned, 0)
    }

    func testDecoyChunkFilterByGroupId() {
        let decoys = [
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d1"), groupId: "A"),
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d2"), groupId: "A"),
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d3"), groupId: "B"),
        ]
        XCTAssertEqual(decoys.filter { $0.groupId == "A" }.count, 2)
        XCTAssertEqual(decoys.filter { $0.groupId == "B" }.count, 1)
    }

    func testDataChunkFilterByBackupId() {
        let mk = { (name: String, bid: String, idx: Int) in
            iCloudBackupManager.ScanResult.DataChunk(
                recordID: CKRecord.ID(recordName: name), backupId: bid, chunkIndex: idx
            )
        }
        let chunks = [mk("1", "A", 0), mk("2", "A", 1), mk("3", "B", 0), mk("4", "B", 1), mk("5", "B", 2)]
        XCTAssertEqual(chunks.filter { $0.backupId == "A" }.count, 2)
        XCTAssertEqual(chunks.filter { $0.backupId == "B" }.count, 3)
    }

    // MARK: - BackupStage & iCloudError

    func testBackupStageRawValues() {
        XCTAssertEqual(iCloudBackupManager.BackupStage.waitingForICloud.rawValue, "Connecting to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.readingVault.rawValue, "Reading vault data...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.encrypting.rawValue, "Encrypting backup...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.uploading.rawValue, "Uploading to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.complete.rawValue, "Backup complete")
    }

    func testICloudErrorDescriptions() {
        XCTAssertEqual(iCloudError.notAvailable.errorDescription, "iCloud is not available.")
        XCTAssertEqual(iCloudError.containerNotFound.errorDescription, "iCloud container not found.")
        XCTAssertTrue(iCloudError.uploadFailed.errorDescription!.contains("Upload failed"))
        XCTAssertTrue(iCloudError.downloadFailed.errorDescription!.contains("Download failed"))
        XCTAssertEqual(iCloudError.fileNotFound.errorDescription, "No backup found.")
        XCTAssertTrue(iCloudError.checksumMismatch.errorDescription!.contains("Wrong pattern"))
        XCTAssertTrue(iCloudError.wifiRequired.errorDescription!.contains("Wi-Fi"))
        XCTAssertNil(iCloudError.backupSkipped.errorDescription, "backupSkipped should be silent")
    }

    func testICloudErrorLocalizedDescriptionUsesErrorDescription() {
        let error: Error = iCloudError.checksumMismatch
        XCTAssertTrue(error.localizedDescription.contains("Wrong pattern"))
    }

    func testBackgroundTaskIdentifier() {
        XCTAssertEqual(
            iCloudBackupManager.backgroundBackupTaskIdentifier,
            "app.vaultaire.ios.backup.resume"
        )
    }

    // MARK: - Helpers

    private func makeEntry(
        _ id: String, timestamp: Date = Date(), size: Int = 1024, chunkCount: Int = 1
    ) -> iCloudBackupManager.BackupVersionEntry {
        .init(backupId: id, timestamp: timestamp, size: size,
              chunkCount: chunkCount, fileCount: nil, vaultTotalSize: nil)
    }

    private func makePendingState(
        dataChunks: Int = 1, decoys: Int = 0
    ) -> iCloudBackupManager.PendingBackupState {
        .init(backupId: "test", dataChunkCount: dataChunks, decoyCount: decoys,
              createdAt: Date(), uploadedFiles: [], retryCount: 0,
              fileCount: 5, vaultTotalSize: 1000)
    }
}
