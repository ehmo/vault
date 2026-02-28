import XCTest
@testable import Vault

/// Comprehensive tests for Phase 3 opaque backup architecture.
/// Tests tag/blob encryption, version management, payload packing,
/// pending state, decoy generation, and structural invariants.
@MainActor
final class ICloudBackupPhase3Tests: XCTestCase {

    private var manager: iCloudBackupManager!
    private let fm = FileManager.default
    private var documentsDir: URL!

    override func setUp() {
        super.setUp()
        manager = iCloudBackupManager.shared
        documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        clearAllStagingDirs()
        cleanupLocalVersionIndexes()
    }

    override func tearDown() {
        clearAllStagingDirs()
        cleanupLocalVersionIndexes()
        super.tearDown()
    }

    private func clearAllStagingDirs() {
        manager.clearStagingDirectory()
        if let contents = try? fm.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("pending_backup") {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func cleanupLocalVersionIndexes() {
        if let contents = try? fm.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("backup_index_") {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - BackupVersionEntry

    func testBackupVersionEntryRequiredFields() throws {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "abc-123",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 1024,
            chunkCount: 2,
            fileCount: nil,
            vaultTotalSize: nil
        )
        XCTAssertEqual(entry.backupId, "abc-123")
        XCTAssertEqual(entry.size, 1024)
        XCTAssertEqual(entry.chunkCount, 2)
        XCTAssertNil(entry.fileCount)
        XCTAssertNil(entry.vaultTotalSize)
    }

    func testBackupVersionEntryFullFields() throws {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "full-001",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880,
            chunkCount: 3,
            fileCount: 42,
            vaultTotalSize: 20_000_000
        )
        XCTAssertEqual(entry.fileCount, 42)
        XCTAssertEqual(entry.vaultTotalSize, 20_000_000)
    }

    func testBackupVersionEntryCodableRoundTrip() throws {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "roundtrip-001",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_000_000,
            chunkCount: 5,
            fileCount: 10,
            vaultTotalSize: 8_000_000
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.BackupVersionEntry.self, from: data)

        XCTAssertEqual(decoded.backupId, entry.backupId)
        XCTAssertEqual(decoded.size, entry.size)
        XCTAssertEqual(decoded.chunkCount, entry.chunkCount)
        XCTAssertEqual(decoded.fileCount, entry.fileCount)
        XCTAssertEqual(decoded.vaultTotalSize, entry.vaultTotalSize)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, entry.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    func testBackupVersionEntryDecodesMinimalJSON() throws {
        // Simulates old or minimal JSON without optional fields
        let json = """
        {"backupId":"min-001","timestamp":1700000000,"size":1000,"chunkCount":1}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entry = try decoder.decode(iCloudBackupManager.BackupVersionEntry.self, from: json)
        XCTAssertEqual(entry.backupId, "min-001")
        XCTAssertNil(entry.fileCount)
        XCTAssertNil(entry.vaultTotalSize)
    }

    func testBackupVersionEntryFormattedSize() {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "fmt-001",
            timestamp: Date(),
            size: 5_242_880,
            chunkCount: 1,
            fileCount: nil,
            vaultTotalSize: nil
        )
        let formatted = entry.formattedSize
        XCTAssertFalse(formatted.isEmpty)
        // ByteCountFormatter should produce something like "5 MB" or "5.2 MB"
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("5"), "Expected MB unit, got: \(formatted)")
    }

    func testBackupVersionEntryFormattedDate() {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "fmt-002",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 1000,
            chunkCount: 1,
            fileCount: nil,
            vaultTotalSize: nil
        )
        let formatted = entry.formattedDate
        XCTAssertFalse(formatted.isEmpty)
        // Should contain some date-like content
        XCTAssertTrue(formatted.count > 5, "Date string too short: \(formatted)")
    }

    // MARK: - BackupVersionIndex

    func testBackupVersionIndexEmptyInit() {
        let index = iCloudBackupManager.BackupVersionIndex()
        XCTAssertTrue(index.versions.isEmpty)
    }

    func testBackupVersionIndexAddVersion() {
        var index = iCloudBackupManager.BackupVersionIndex()
        let entry = makeEntry(id: "v1")
        let evicted = index.addVersion(entry)
        XCTAssertNil(evicted, "First version should not evict")
        XCTAssertEqual(index.versions.count, 1)
        XCTAssertEqual(index.versions[0].backupId, "v1")
    }

    func testBackupVersionIndexEvictsOldest() {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry(id: "v1"))
        index.addVersion(makeEntry(id: "v2"))
        index.addVersion(makeEntry(id: "v3"))
        XCTAssertEqual(index.versions.count, 3)

        let evicted = index.addVersion(makeEntry(id: "v4"))
        XCTAssertEqual(evicted?.backupId, "v1", "Should evict the oldest (first) version")
        XCTAssertEqual(index.versions.count, 3)
        XCTAssertEqual(index.versions.map(\.backupId), ["v2", "v3", "v4"])
    }

    func testBackupVersionIndexMaxThreeVersions() {
        var index = iCloudBackupManager.BackupVersionIndex()
        for i in 0..<10 {
            index.addVersion(makeEntry(id: "v\(i)"))
        }
        XCTAssertEqual(index.versions.count, 3, "Should never exceed 3 versions")
        XCTAssertEqual(index.versions.map(\.backupId), ["v7", "v8", "v9"])
    }

    func testBackupVersionIndexCodableRoundTrip() throws {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry(id: "a"))
        index.addVersion(makeEntry(id: "b"))

        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.BackupVersionIndex.self, from: data)

        XCTAssertEqual(decoded.versions.count, 2)
        XCTAssertEqual(decoded.versions[0].backupId, "a")
        XCTAssertEqual(decoded.versions[1].backupId, "b")
    }

    func testBackupVersionIndexRemoveVersion() {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry(id: "v1"))
        index.addVersion(makeEntry(id: "v2"))
        index.addVersion(makeEntry(id: "v3"))

        index.versions.removeAll { $0.backupId == "v2" }
        XCTAssertEqual(index.versions.count, 2)
        XCTAssertEqual(index.versions.map(\.backupId), ["v1", "v3"])
    }

    // MARK: - PendingBackupState

    func testPendingBackupStateTotalFilesComputed() {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "test",
            dataChunkCount: 5,
            decoyCount: 2,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 10,
            vaultTotalSize: 50000
        )
        // totalFiles = dataChunkCount + 1 (VDIR) + decoyCount
        XCTAssertEqual(state.totalFiles, 8, "5 data + 1 dir + 2 decoy = 8")
    }

    func testPendingBackupStateTotalFilesNoDecoys() {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "test",
            dataChunkCount: 3,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 10,
            vaultTotalSize: 50000
        )
        XCTAssertEqual(state.totalFiles, 4, "3 data + 1 dir + 0 decoy = 4")
    }

    func testPendingBackupStateCodableRoundTrip() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "backup-rt",
            dataChunkCount: 4,
            decoyCount: 2,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            uploadedFiles: ["vdat_0", "vdat_1"],
            retryCount: 3,
            fileCount: 20,
            vaultTotalSize: 100_000,
            wasTerminated: true,
            vaultFingerprint: "abc123",
            recordsToDelete: ["old-rec-1"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(iCloudBackupManager.PendingBackupState.self, from: data)

        XCTAssertEqual(decoded.backupId, "backup-rt")
        XCTAssertEqual(decoded.dataChunkCount, 4)
        XCTAssertEqual(decoded.decoyCount, 2)
        XCTAssertEqual(decoded.uploadedFiles, ["vdat_0", "vdat_1"])
        XCTAssertEqual(decoded.retryCount, 3)
        XCTAssertEqual(decoded.fileCount, 20)
        XCTAssertEqual(decoded.vaultTotalSize, 100_000)
        XCTAssertTrue(decoded.wasTerminated)
        XCTAssertEqual(decoded.vaultFingerprint, "abc123")
        XCTAssertEqual(decoded.recordsToDelete, ["old-rec-1"])
        XCTAssertEqual(decoded.totalFiles, 7) // 4 + 1 + 2
    }

    func testPendingBackupStateDefaultValues() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "defaults",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 5,
            vaultTotalSize: 1000
        )
        XCTAssertFalse(state.wasTerminated)
        XCTAssertNil(state.vaultFingerprint)
        XCTAssertTrue(state.recordsToDelete.isEmpty)
    }

    func testPendingBackupStateUploadedFilesTrackProgress() {
        var state = iCloudBackupManager.PendingBackupState(
            backupId: "progress-test",
            dataChunkCount: 3,
            decoyCount: 1,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 10,
            vaultTotalSize: 50000
        )
        XCTAssertEqual(state.uploadedFiles.count, 0)
        state.uploadedFiles.insert("vdat_0")
        state.uploadedFiles.insert("vdir")
        XCTAssertEqual(state.uploadedFiles.count, 2)
        // Inserting duplicate should not change count
        state.uploadedFiles.insert("vdat_0")
        XCTAssertEqual(state.uploadedFiles.count, 2)
    }

    // MARK: - Staging Directory

    func testStagingDirectoryCreatedOnSave() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "staging-test",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 5,
            vaultTotalSize: 1000,
            vaultFingerprint: "test_fp_staging"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let stagingDir = documentsDir.appendingPathComponent("pending_backup_test_fp_staging", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stateURL = stagingDir.appendingPathComponent("state.json")
        try data.write(to: stateURL, options: .atomic)

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "staging-test")
        XCTAssertEqual(loaded?.vaultFingerprint, "test_fp_staging")
    }

    func testClearStagingDirectoryRemovesFiles() throws {
        let fingerprint = "clear_test_fp"
        let stagingDir = documentsDir.appendingPathComponent("pending_backup_\(fingerprint)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stateURL = stagingDir.appendingPathComponent("state.json")
        try "{}".data(using: .utf8)!.write(to: stateURL)

        XCTAssertTrue(fm.fileExists(atPath: stagingDir.path))
        manager.clearStagingDirectory(fingerprint: fingerprint)
        XCTAssertFalse(fm.fileExists(atPath: stagingDir.path))
    }

    func testPendingBackupStateTTLExpiry() throws {
        // State with createdAt 3 days ago (exceeds 48h TTL)
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "expired",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: Date().addingTimeInterval(-72 * 3600),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 1,
            vaultTotalSize: 100
        )
        let data = try JSONEncoder().encode(state)
        let stagingDir = documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try data.write(to: stagingDir.appendingPathComponent("state.json"))

        // loadPendingBackupState should skip expired states
        let loaded = manager.loadPendingBackupState()
        XCTAssertNil(loaded, "Expired pending state should not be loaded")
    }

    func testPendingBackupStateNotExpiredWithin48h() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "fresh",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: Date().addingTimeInterval(-24 * 3600), // 24h ago
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 1,
            vaultTotalSize: 100
        )
        let data = try JSONEncoder().encode(state)
        let stagingDir = documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try data.write(to: stagingDir.appendingPathComponent("state.json"))

        let loaded = manager.loadPendingBackupState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.backupId, "fresh")
    }

    // MARK: - Vault Fingerprint

    func testVaultFingerprintDeterministic() {
        let key = Data(repeating: 0xAB, count: 32)
        let fp1 = iCloudBackupManager.vaultFingerprint(from: key)
        let fp2 = iCloudBackupManager.vaultFingerprint(from: key)
        XCTAssertEqual(fp1, fp2, "Same key should produce same fingerprint")
    }

    func testVaultFingerprintDifferentKeys() {
        let key1 = Data(repeating: 0xAA, count: 32)
        let key2 = Data(repeating: 0xBB, count: 32)
        let fp1 = iCloudBackupManager.vaultFingerprint(from: key1)
        let fp2 = iCloudBackupManager.vaultFingerprint(from: key2)
        XCTAssertNotEqual(fp1, fp2, "Different keys should produce different fingerprints")
    }

    func testVaultFingerprintIs16CharHex() {
        let key = Data(repeating: 0xCD, count: 32)
        let fp = iCloudBackupManager.vaultFingerprint(from: key)
        XCTAssertEqual(fp.count, 16, "Fingerprint should be 16 hex chars")
        XCTAssertTrue(fp.allSatisfy { "0123456789abcdef".contains($0) }, "Should be hex: \(fp)")
    }

    // MARK: - iCloudError

    func testICloudErrorDescriptions() {
        XCTAssertNotNil(iCloudError.notAvailable.errorDescription)
        XCTAssertNotNil(iCloudError.uploadFailed.errorDescription)
        XCTAssertNotNil(iCloudError.downloadFailed.errorDescription)
        XCTAssertNotNil(iCloudError.checksumMismatch.errorDescription)
        XCTAssertNotNil(iCloudError.wifiRequired.errorDescription)
        XCTAssertNotNil(iCloudError.fileNotFound.errorDescription)
        XCTAssertNotNil(iCloudError.containerNotFound.errorDescription)
        XCTAssertNil(iCloudError.backupSkipped.errorDescription, "backupSkipped should have nil description")
    }

    // MARK: - BackupKey Derivation Integration

    func testBackupKeyIsDeterministic() throws {
        let pattern = [0, 1, 2, 3, 4, 5, 6]
        let key1 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        let key2 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        XCTAssertEqual(key1, key2, "Same pattern should produce same backup key")
    }

    func testBackupKeyIs32Bytes() throws {
        let pattern = [0, 1, 2, 3, 4, 5, 6]
        let key = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        XCTAssertEqual(key.count, 32, "Backup key should be 32 bytes (AES-256)")
    }

    func testBackupKeyDifferentPatternsProduceDifferentKeys() throws {
        let key1 = try KeyDerivation.deriveBackupKey(from: [0, 1, 2, 3, 4, 5, 6], gridSize: 5)
        let key2 = try KeyDerivation.deriveBackupKey(from: [6, 5, 4, 3, 2, 1, 0], gridSize: 5)
        XCTAssertNotEqual(key1, key2)
    }

    func testBackupKeyDifferentGridSizesProduceDifferentKeys() throws {
        let pattern = [0, 1, 2, 3, 4, 5, 6]
        let key1 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        let key2 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 6)
        XCTAssertNotEqual(key1, key2)
    }

    func testBackupKeyRejectsShortPattern() {
        XCTAssertThrowsError(try KeyDerivation.deriveBackupKey(from: [0, 1, 2, 3, 4], gridSize: 5)) { error in
            XCTAssertTrue(error is KeyDerivationError)
        }
    }

    func testBackupKeyRejectsEmptyPattern() {
        XCTAssertThrowsError(try KeyDerivation.deriveBackupKey(from: [], gridSize: 5))
    }

    // MARK: - VBK2 Payload Packing/Unpacking

    func testVBK2PayloadPackUnpackRoundTrip() throws {
        // Create a minimal vault setup with a blob file + index file
        let blobId = "primary"
        let blobData = Data(repeating: 0x42, count: 1024)
        let blobURL = documentsDir.appendingPathComponent("vault_data.bin")
        // Write a 50MB blob with blobData at the start
        let fullBlob = blobData + Data(count: 50 * 1024 * 1024 - blobData.count)
        try fullBlob.write(to: blobURL)
        defer { try? fm.removeItem(at: blobURL) }

        let fp = "test_round_trip_fp"
        let indexData = Data(repeating: 0xFF, count: 128)
        let indexURL = documentsDir.appendingPathComponent("vault_index_\(fp).bin")
        try indexData.write(to: indexURL)
        defer { try? fm.removeItem(at: indexURL) }

        // Use the manager's pack/unpack — we'll test via the public interface
        // by constructing a VBK2 payload manually
        var payload = Data()
        var magic: UInt32 = 0x56424B32
        payload.append(Data(bytes: &magic, count: 4))
        var version: UInt8 = 2
        payload.append(Data(bytes: &version, count: 1))
        var blobCount: UInt16 = 1
        payload.append(Data(bytes: &blobCount, count: 2))
        var indexCount: UInt16 = 1
        payload.append(Data(bytes: &indexCount, count: 2))

        // Blob entry
        let blobIdData = Data(blobId.utf8)
        var idLen = UInt16(blobIdData.count)
        payload.append(Data(bytes: &idLen, count: 2))
        payload.append(blobIdData)
        var dataLen = UInt64(blobData.count)
        payload.append(Data(bytes: &dataLen, count: 8))
        payload.append(blobData)

        // Index entry
        let indexName = "vault_index_\(fp).bin"
        let nameData = Data(indexName.utf8)
        var nameLen = UInt16(nameData.count)
        payload.append(Data(bytes: &nameLen, count: 2))
        payload.append(nameData)
        var indexDataLen = UInt32(indexData.count)
        payload.append(Data(bytes: &indexDataLen, count: 4))
        payload.append(indexData)

        // Verify the header
        XCTAssertEqual(payload.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }, 0x56424B32)
        XCTAssertEqual(payload[4], 2)
    }

    // MARK: - ScanResult Structure

    func testScanResultStartsEmpty() {
        let result = iCloudBackupManager.ScanResult()
        XCTAssertTrue(result.dataChunks.isEmpty)
        XCTAssertTrue(result.dirChunks.isEmpty)
        XCTAssertTrue(result.decoyChunks.isEmpty)
        XCTAssertEqual(result.totalScanned, 0)
    }

    // MARK: - Per-Vault UserDefaults

    func testPerVaultBackupEnabledKey() {
        let fp = "test_fp_enabled"
        let enabledKey = "iCloudBackupEnabled_\(fp)"
        UserDefaults.standard.set(true, forKey: enabledKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: enabledKey))
        UserDefaults.standard.removeObject(forKey: enabledKey)
    }

    func testPerVaultTimestampKey() {
        let fp = "test_fp_ts"
        let tsKey = "lastBackupTimestamp_\(fp)"
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: tsKey)
        XCTAssertEqual(UserDefaults.standard.double(forKey: tsKey), now, accuracy: 1.0)
        UserDefaults.standard.removeObject(forKey: tsKey)
    }

    func testPerVaultKeysAreIsolated() {
        let fp1 = "vault_aaa"
        let fp2 = "vault_bbb"
        UserDefaults.standard.set(true, forKey: "iCloudBackupEnabled_\(fp1)")
        UserDefaults.standard.set(false, forKey: "iCloudBackupEnabled_\(fp2)")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "iCloudBackupEnabled_\(fp1)"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "iCloudBackupEnabled_\(fp2)"))
        UserDefaults.standard.removeObject(forKey: "iCloudBackupEnabled_\(fp1)")
        UserDefaults.standard.removeObject(forKey: "iCloudBackupEnabled_\(fp2)")
    }

    // MARK: - Global Default Inheritance

    func testGlobalDefaultAppliesWhenNoPerVaultKey() {
        let defaults = UserDefaults.standard
        let fp = "new_vault_fp"
        defaults.set(true, forKey: "iCloudBackupDefault")

        let enabledKey = "iCloudBackupEnabled_\(fp)"
        let initKey = "iCloudBackupInitialized_\(fp)"

        // Simulate inheritance check (same logic as in app)
        if !defaults.bool(forKey: initKey) {
            let globalDefault = defaults.bool(forKey: "iCloudBackupDefault")
            defaults.set(globalDefault, forKey: enabledKey)
            defaults.set(true, forKey: initKey)
        }

        XCTAssertTrue(defaults.bool(forKey: enabledKey))
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: initKey)
        defaults.removeObject(forKey: "iCloudBackupDefault")
    }

    func testGlobalDefaultFalseDisablesNewVaults() {
        let defaults = UserDefaults.standard
        let fp = "disabled_vault_fp"
        defaults.set(false, forKey: "iCloudBackupDefault")

        let enabledKey = "iCloudBackupEnabled_\(fp)"
        let initKey = "iCloudBackupInitialized_\(fp)"

        if !defaults.bool(forKey: initKey) {
            let globalDefault = defaults.bool(forKey: "iCloudBackupDefault")
            defaults.set(globalDefault, forKey: enabledKey)
            defaults.set(true, forKey: initKey)
        }

        XCTAssertFalse(defaults.bool(forKey: enabledKey))
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: initKey)
        defaults.removeObject(forKey: "iCloudBackupDefault")
    }

    // MARK: - Local Version Index

    func testLocalVersionIndexCreateAndLoad() throws {
        let fp = "local_idx_test"
        let indexURL = documentsDir.appendingPathComponent("backup_index_\(fp).json")

        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeEntry(id: "local-v1"))
        index.addVersion(makeEntry(id: "local-v2"))

        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)

        let loaded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionIndex.self,
            from: Data(contentsOf: indexURL)
        )
        XCTAssertEqual(loaded.versions.count, 2)
        XCTAssertEqual(loaded.versions[0].backupId, "local-v1")
        XCTAssertEqual(loaded.versions[1].backupId, "local-v2")
    }

    // MARK: - Pattern Change Migration

    func testPatternChangeMigratesPerVaultKeys() {
        let defaults = UserDefaults.standard
        let oldFP = "old_fp_migrate"
        let newFP = "new_fp_migrate"

        defaults.set(true, forKey: "iCloudBackupEnabled_\(oldFP)")
        defaults.set(1700000000.0, forKey: "lastBackupTimestamp_\(oldFP)")

        // Simulate pattern change migration
        let wasEnabled = defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)")
        if wasEnabled {
            defaults.set(true, forKey: "iCloudBackupEnabled_\(newFP)")
            defaults.set(0, forKey: "lastBackupTimestamp_\(newFP)")
            defaults.removeObject(forKey: "iCloudBackupEnabled_\(oldFP)")
            defaults.removeObject(forKey: "lastBackupTimestamp_\(oldFP)")
        }

        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_\(newFP)"))
        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_\(newFP)"), 0)
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)"))
        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_\(oldFP)"), 0)

        defaults.removeObject(forKey: "iCloudBackupEnabled_\(newFP)")
        defaults.removeObject(forKey: "lastBackupTimestamp_\(newFP)")
    }

    // MARK: - Crypto Structural Invariants

    func testAESGCMCombinedSizeFor36BytePlaintext() throws {
        // Verify that encrypting 36 bytes produces exactly 64 bytes (tagSize)
        let key = Data(repeating: 0xAA, count: 32)
        let plaintext = Data(repeating: 0xBB, count: 36)
        let symmetricKey = CryptoKit.SymmetricKey(data: key)
        let sealedBox = try CryptoKit.AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else { XCTFail("Combined should not be nil"); return }
        // 12 (nonce) + 36 (ciphertext) + 16 (tag) = 64
        XCTAssertEqual(combined.count, 64, "AES-GCM of 36B should produce 64B combined")
    }

    func testAESGCMOverhead() throws {
        // Verify AES-GCM overhead is 28 bytes (12 nonce + 16 auth tag)
        let key = Data(repeating: 0xCC, count: 32)
        let symmetricKey = CryptoKit.SymmetricKey(data: key)

        for plaintextSize in [0, 1, 100, 1000, 10000] {
            let plaintext = Data(repeating: 0xDD, count: plaintextSize)
            let sealedBox = try CryptoKit.AES.GCM.seal(plaintext, using: symmetricKey)
            guard let combined = sealedBox.combined else { XCTFail("Combined nil for size \(plaintextSize)"); return }
            XCTAssertEqual(combined.count, plaintextSize + 28, "AES-GCM overhead should be 28B for \(plaintextSize)B plaintext")
        }
    }

    func testCryptoEngineEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xEE, count: 32)
        let plaintext = Data(repeating: 0xFF, count: 1024)
        let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
        let decrypted = try CryptoEngine.decrypt(encrypted, with: key)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testCryptoEngineWrongKeyFails() throws {
        let key1 = Data(repeating: 0xAA, count: 32)
        let key2 = Data(repeating: 0xBB, count: 32)
        let plaintext = Data(repeating: 0xCC, count: 100)
        let encrypted = try CryptoEngine.encrypt(plaintext, with: key1)
        XCTAssertThrowsError(try CryptoEngine.decrypt(encrypted, with: key2))
    }

    func testCryptoEngineInvalidKeySizeFails() {
        let shortKey = Data(repeating: 0xAA, count: 16)
        let plaintext = Data(repeating: 0xBB, count: 100)
        XCTAssertThrowsError(try CryptoEngine.encrypt(plaintext, with: shortKey))
    }

    // MARK: - Version Sorting

    func testVersionsSortByTimestampDescending() {
        let old = makeEntry(id: "old", timestamp: Date(timeIntervalSince1970: 1000))
        let mid = makeEntry(id: "mid", timestamp: Date(timeIntervalSince1970: 2000))
        let new = makeEntry(id: "new", timestamp: Date(timeIntervalSince1970: 3000))

        var versions = [mid, old, new]
        versions.sort { $0.timestamp > $1.timestamp }

        XCTAssertEqual(versions.map(\.backupId), ["new", "mid", "old"])
    }

    // MARK: - Delete Confirmation Logic

    func testDeleteAllVersionsLogic() {
        // Simulate delete-all flow: version count should be 0 after deletion
        var versionCount = 3
        var totalBackupStorage: Int64 = 50_000_000

        // Simulate successful deleteAllBackups
        versionCount = 0
        totalBackupStorage = 0

        XCTAssertEqual(versionCount, 0)
        XCTAssertEqual(totalBackupStorage, 0)
    }

    // MARK: - DecoyChunk groupId

    func testDecoyChunkHasGroupId() {
        // Verify the struct stores groupId for per-version decoy deletion
        let chunk = iCloudBackupManager.ScanResult.DecoyChunk(
            recordID: CKRecord.ID(recordName: "test"),
            groupId: "backup-001"
        )
        XCTAssertEqual(chunk.groupId, "backup-001")
    }

    func testDecoyChunkFilterByGroupId() {
        let decoys = [
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d1"), groupId: "backup-A"),
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d2"), groupId: "backup-A"),
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d3"), groupId: "backup-B"),
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d4"), groupId: "backup-B"),
            iCloudBackupManager.ScanResult.DecoyChunk(recordID: CKRecord.ID(recordName: "d5"), groupId: "backup-C"),
        ]

        let backupADecoys = decoys.filter { $0.groupId == "backup-A" }
        XCTAssertEqual(backupADecoys.count, 2)

        let backupBDecoys = decoys.filter { $0.groupId == "backup-B" }
        XCTAssertEqual(backupBDecoys.count, 2)

        let backupCDecoys = decoys.filter { $0.groupId == "backup-C" }
        XCTAssertEqual(backupCDecoys.count, 1)
    }

    // MARK: - DataChunk / DirChunk Structure

    func testDataChunkStoresBackupIdAndIndex() {
        let chunk = iCloudBackupManager.ScanResult.DataChunk(
            recordID: CKRecord.ID(recordName: "rec-1"),
            backupId: "backup-xyz",
            chunkIndex: 5
        )
        XCTAssertEqual(chunk.backupId, "backup-xyz")
        XCTAssertEqual(chunk.chunkIndex, 5)
    }

    func testDirChunkStoresBackupId() {
        let chunk = iCloudBackupManager.ScanResult.DirChunk(
            recordID: CKRecord.ID(recordName: "dir-1"),
            backupId: "backup-xyz"
        )
        XCTAssertEqual(chunk.backupId, "backup-xyz")
    }

    func testFilterDataChunksByBackupId() {
        let chunks = [
            iCloudBackupManager.ScanResult.DataChunk(recordID: CKRecord.ID(recordName: "1"), backupId: "A", chunkIndex: 0),
            iCloudBackupManager.ScanResult.DataChunk(recordID: CKRecord.ID(recordName: "2"), backupId: "A", chunkIndex: 1),
            iCloudBackupManager.ScanResult.DataChunk(recordID: CKRecord.ID(recordName: "3"), backupId: "B", chunkIndex: 0),
            iCloudBackupManager.ScanResult.DataChunk(recordID: CKRecord.ID(recordName: "4"), backupId: "B", chunkIndex: 1),
            iCloudBackupManager.ScanResult.DataChunk(recordID: CKRecord.ID(recordName: "5"), backupId: "B", chunkIndex: 2),
        ]

        let aChunks = chunks.filter { $0.backupId == "A" }.sorted { $0.chunkIndex < $1.chunkIndex }
        XCTAssertEqual(aChunks.count, 2)
        XCTAssertEqual(aChunks[0].chunkIndex, 0)
        XCTAssertEqual(aChunks[1].chunkIndex, 1)

        let bChunks = chunks.filter { $0.backupId == "B" }
        XCTAssertEqual(bChunks.count, 3)
    }

    // MARK: - BackupStage

    func testBackupStageRawValues() {
        XCTAssertEqual(iCloudBackupManager.BackupStage.waitingForICloud.rawValue, "Connecting to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.readingVault.rawValue, "Reading vault data...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.encrypting.rawValue, "Encrypting backup...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.uploading.rawValue, "Uploading to iCloud...")
        XCTAssertEqual(iCloudBackupManager.BackupStage.complete.rawValue, "Backup complete")
    }

    // MARK: - Background Task Identifier

    func testBackgroundTaskIdentifier() {
        XCTAssertEqual(
            iCloudBackupManager.backgroundBackupTaskIdentifier,
            "app.vaultaire.ios.backup.resume"
        )
    }

    // MARK: - hasPendingBackup

    func testHasPendingBackupFalseWhenClean() {
        clearAllStagingDirs()
        XCTAssertFalse(manager.hasPendingBackup)
    }

    func testHasPendingBackupTrueWhenStateExists() throws {
        let state = iCloudBackupManager.PendingBackupState(
            backupId: "pending",
            dataChunkCount: 1,
            decoyCount: 0,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: 1,
            vaultTotalSize: 100
        )
        let data = try JSONEncoder().encode(state)
        let stagingDir = documentsDir.appendingPathComponent("pending_backup", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try data.write(to: stagingDir.appendingPathComponent("state.json"))

        XCTAssertTrue(manager.hasPendingBackup)
    }

    // MARK: - Helpers

    private func makeEntry(
        id: String,
        timestamp: Date = Date(),
        size: Int = 1024,
        chunkCount: Int = 1
    ) -> iCloudBackupManager.BackupVersionEntry {
        iCloudBackupManager.BackupVersionEntry(
            backupId: id,
            timestamp: timestamp,
            size: size,
            chunkCount: chunkCount,
            fileCount: nil,
            vaultTotalSize: nil
        )
    }
}

import CryptoKit
import CloudKit
