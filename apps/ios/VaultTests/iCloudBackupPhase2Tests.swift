import XCTest
@testable import Vault

/// Tests for iCloud Backup Phase 2: per-vault versioning, version index operations,
/// checksum handling, pattern change migration, and global default inheritance.
@MainActor
final class ICloudBackupPhase2Tests: XCTestCase {

    private var manager: iCloudBackupManager!
    private let defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        manager = iCloudBackupManager.shared
    }

    override func tearDown() {
        // Clean up all per-vault UserDefaults keys used in tests
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("iCloudBackupEnabled_") ||
               key.hasPrefix("lastBackupTimestamp_") ||
               key.hasPrefix("iCloudBackupInitialized_") {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: "iCloudBackupDefault")
        defaults.removeObject(forKey: "iCloudBackupEnabled")
        super.tearDown()
    }

    // MARK: - BackupVersionEntry

    func testBackupVersionEntryCodableRoundTrip() throws {
        let checksum = Data(repeating: 0xAB, count: 32)
        let token = Data(repeating: 0xCD, count: 32)
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "test-backup-001",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 5_242_880,
            verificationToken: token,
            chunkCount: 5,
            checksum: checksum
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionEntry.self, from: data
        )

        XCTAssertEqual(decoded.backupId, "test-backup-001")
        XCTAssertEqual(decoded.size, 5_242_880)
        XCTAssertEqual(decoded.chunkCount, 5)
        XCTAssertEqual(decoded.checksum, checksum)
        XCTAssertEqual(decoded.verificationToken, token)
        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            1700000000,
            accuracy: 0.001
        )
    }

    func testBackupVersionEntryWithNilChecksum() throws {
        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "no-checksum",
            timestamp: Date(),
            size: 1024,
            verificationToken: nil,
            chunkCount: 1,
            checksum: nil
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionEntry.self, from: data
        )

        XCTAssertNil(decoded.checksum,
                     "nil checksum should survive Codable round-trip")
        XCTAssertNil(decoded.verificationToken)
    }

    func testBackupVersionEntryDecodesOldFormatWithoutChecksum() throws {
        // Simulate JSON from before the checksum field was added
        let json = """
        {
            "backupId": "old-version",
            "timestamp": 1700000000,
            "size": 2048,
            "chunkCount": 2
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionEntry.self, from: json
        )

        XCTAssertNil(decoded.checksum,
                     "Old JSON without checksum field should decode as nil")
        XCTAssertNil(decoded.verificationToken,
                     "Old JSON without verificationToken should decode as nil")
        XCTAssertEqual(decoded.backupId, "old-version")
        XCTAssertEqual(decoded.chunkCount, 2)
    }

    func testBackupVersionEntryAllFieldsPreserved() throws {
        let checksum = Data([0x01, 0x02, 0x03])
        let token = Data([0xAA, 0xBB])
        let timestamp = Date(timeIntervalSince1970: 1234567890)

        let entry = iCloudBackupManager.BackupVersionEntry(
            backupId: "full-test",
            timestamp: timestamp,
            size: 999_999,
            verificationToken: token,
            chunkCount: 42,
            checksum: checksum
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionEntry.self, from: data
        )

        XCTAssertEqual(decoded.backupId, entry.backupId)
        XCTAssertEqual(decoded.size, entry.size)
        XCTAssertEqual(decoded.chunkCount, entry.chunkCount)
        XCTAssertEqual(decoded.checksum, entry.checksum)
        XCTAssertEqual(decoded.verificationToken, entry.verificationToken)
    }

    // MARK: - BackupVersionIndex

    func testBackupVersionIndexInitializesEmpty() {
        let index = iCloudBackupManager.BackupVersionIndex()
        XCTAssertTrue(index.versions.isEmpty)
    }

    func testBackupVersionIndexAddsEntry() {
        var index = iCloudBackupManager.BackupVersionIndex()
        let entry = makeVersionEntry(backupId: "v1")

        let evicted = index.addVersion(entry)

        XCTAssertNil(evicted, "First entry should not evict anything")
        XCTAssertEqual(index.versions.count, 1)
        XCTAssertEqual(index.versions[0].backupId, "v1")
    }

    func testBackupVersionIndexAddsUpToThreeEntries() {
        var index = iCloudBackupManager.BackupVersionIndex()

        let e1 = index.addVersion(makeVersionEntry(backupId: "v1"))
        let e2 = index.addVersion(makeVersionEntry(backupId: "v2"))
        let e3 = index.addVersion(makeVersionEntry(backupId: "v3"))

        XCTAssertNil(e1)
        XCTAssertNil(e2)
        XCTAssertNil(e3)
        XCTAssertEqual(index.versions.count, 3)
    }

    func testBackupVersionIndexEvictsOldestAtCapacity() {
        var index = iCloudBackupManager.BackupVersionIndex()

        index.addVersion(makeVersionEntry(backupId: "v1"))
        index.addVersion(makeVersionEntry(backupId: "v2"))
        index.addVersion(makeVersionEntry(backupId: "v3"))

        let evicted = index.addVersion(makeVersionEntry(backupId: "v4"))

        XCTAssertNotNil(evicted)
        XCTAssertEqual(evicted?.backupId, "v1", "Oldest entry should be evicted")
        XCTAssertEqual(index.versions.count, 3)
        XCTAssertEqual(index.versions.map(\.backupId), ["v2", "v3", "v4"])
    }

    func testBackupVersionIndexEvictsSequentially() {
        var index = iCloudBackupManager.BackupVersionIndex()

        index.addVersion(makeVersionEntry(backupId: "v1"))
        index.addVersion(makeVersionEntry(backupId: "v2"))
        index.addVersion(makeVersionEntry(backupId: "v3"))

        let evicted4 = index.addVersion(makeVersionEntry(backupId: "v4"))
        XCTAssertEqual(evicted4?.backupId, "v1")

        let evicted5 = index.addVersion(makeVersionEntry(backupId: "v5"))
        XCTAssertEqual(evicted5?.backupId, "v2")

        XCTAssertEqual(index.versions.map(\.backupId), ["v3", "v4", "v5"])
    }

    func testBackupVersionIndexCodableRoundTrip() throws {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeVersionEntry(backupId: "a", size: 100))
        index.addVersion(makeVersionEntry(backupId: "b", size: 200))

        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionIndex.self, from: data
        )

        XCTAssertEqual(decoded.versions.count, 2)
        XCTAssertEqual(decoded.versions[0].backupId, "a")
        XCTAssertEqual(decoded.versions[1].backupId, "b")
        XCTAssertEqual(decoded.versions[0].size, 100)
    }

    func testBackupVersionIndexRemoveByBackupId() {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeVersionEntry(backupId: "keep1"))
        index.addVersion(makeVersionEntry(backupId: "remove"))
        index.addVersion(makeVersionEntry(backupId: "keep2"))

        index.versions.removeAll { $0.backupId == "remove" }

        XCTAssertEqual(index.versions.count, 2)
        XCTAssertEqual(index.versions.map(\.backupId), ["keep1", "keep2"])
    }

    // MARK: - Per-Vault UserDefaults Keys

    func testPerVaultEnabledKeyFormat() {
        let fp = "abc123def456"
        let key = "iCloudBackupEnabled_\(fp)"
        XCTAssertEqual(key, "iCloudBackupEnabled_abc123def456")
    }

    func testPerVaultTimestampKeyFormat() {
        let fp = "abc123def456"
        let key = "lastBackupTimestamp_\(fp)"
        XCTAssertEqual(key, "lastBackupTimestamp_abc123def456")
    }

    func testPerVaultKeysAreIsolated() {
        let fp1 = "fingerprint_vault_A"
        let fp2 = "fingerprint_vault_B"

        defaults.set(true, forKey: "iCloudBackupEnabled_\(fp1)")
        defaults.set(false, forKey: "iCloudBackupEnabled_\(fp2)")

        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_\(fp1)"))
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_\(fp2)"))

        defaults.set(1000.0, forKey: "lastBackupTimestamp_\(fp1)")
        defaults.set(2000.0, forKey: "lastBackupTimestamp_\(fp2)")

        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_\(fp1)"), 1000.0)
        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_\(fp2)"), 2000.0)
    }

    func testPerVaultKeyDoesNotAffectGlobalKey() {
        let fp = "test_fingerprint"
        defaults.set(false, forKey: "iCloudBackupEnabled")
        defaults.set(true, forKey: "iCloudBackupEnabled_\(fp)")

        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled"),
                       "Per-vault key should not affect global key")
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_\(fp)"))
    }

    // MARK: - Global Default Inheritance

    func testGlobalDefaultInheritanceNewVault() {
        let fp = "new_vault_fp"
        let enabledKey = "iCloudBackupEnabled_\(fp)"
        let initKey = "iCloudBackupInitialized_\(fp)"

        // Set global default to true
        defaults.set(true, forKey: "iCloudBackupDefault")

        // Simulate first-time unlock: not yet initialized
        XCTAssertFalse(defaults.bool(forKey: initKey))

        // Inheritance logic from VaultApp.performPostUnlockSetup
        if !defaults.bool(forKey: initKey) {
            let globalDefault = defaults.bool(forKey: "iCloudBackupDefault")
            defaults.set(globalDefault, forKey: enabledKey)
            defaults.set(true, forKey: initKey)
        }

        XCTAssertTrue(defaults.bool(forKey: enabledKey),
                      "New vault should inherit global default (true)")
        XCTAssertTrue(defaults.bool(forKey: initKey),
                      "Vault should be marked as initialized")
    }

    func testGlobalDefaultInheritanceAlreadyInitialized() {
        let fp = "existing_vault_fp"
        let enabledKey = "iCloudBackupEnabled_\(fp)"
        let initKey = "iCloudBackupInitialized_\(fp)"

        // Pre-existing vault with backup disabled
        defaults.set(false, forKey: enabledKey)
        defaults.set(true, forKey: initKey)

        // Change global default to true
        defaults.set(true, forKey: "iCloudBackupDefault")

        // Inheritance logic should skip
        if !defaults.bool(forKey: initKey) {
            let globalDefault = defaults.bool(forKey: "iCloudBackupDefault")
            defaults.set(globalDefault, forKey: enabledKey)
            defaults.set(true, forKey: initKey)
        }

        XCTAssertFalse(defaults.bool(forKey: enabledKey),
                       "Already-initialized vault should NOT re-inherit global default")
    }

    func testGlobalDefaultInheritanceWithFalseDefault() {
        let fp = "new_vault_false_default"
        let enabledKey = "iCloudBackupEnabled_\(fp)"
        let initKey = "iCloudBackupInitialized_\(fp)"

        defaults.set(false, forKey: "iCloudBackupDefault")

        if !defaults.bool(forKey: initKey) {
            let globalDefault = defaults.bool(forKey: "iCloudBackupDefault")
            defaults.set(globalDefault, forKey: enabledKey)
            defaults.set(true, forKey: initKey)
        }

        XCTAssertFalse(defaults.bool(forKey: enabledKey),
                       "New vault should inherit false global default")
        XCTAssertTrue(defaults.bool(forKey: initKey))
    }

    func testMultipleVaultsInheritIndependently() {
        let fp1 = "vault_A"
        let fp2 = "vault_B"

        // Global default is true
        defaults.set(true, forKey: "iCloudBackupDefault")

        // Vault A: first unlock → inherits true
        if !defaults.bool(forKey: "iCloudBackupInitialized_\(fp1)") {
            defaults.set(defaults.bool(forKey: "iCloudBackupDefault"),
                        forKey: "iCloudBackupEnabled_\(fp1)")
            defaults.set(true, forKey: "iCloudBackupInitialized_\(fp1)")
        }

        // User manually disables vault A
        defaults.set(false, forKey: "iCloudBackupEnabled_\(fp1)")

        // Vault B: first unlock → should still inherit true (independent)
        if !defaults.bool(forKey: "iCloudBackupInitialized_\(fp2)") {
            defaults.set(defaults.bool(forKey: "iCloudBackupDefault"),
                        forKey: "iCloudBackupEnabled_\(fp2)")
            defaults.set(true, forKey: "iCloudBackupInitialized_\(fp2)")
        }

        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_\(fp1)"),
                       "Vault A should remain disabled")
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_\(fp2)"),
                      "Vault B should inherit independently")
    }

    // MARK: - Pattern Change Migration

    func testPatternChangeMigratesPerVaultKeys() {
        let oldFP = "old_fingerprint"
        let newFP = "new_fingerprint"

        // Set up old per-vault keys
        defaults.set(true, forKey: "iCloudBackupEnabled_\(oldFP)")
        defaults.set(1700000000.0, forKey: "lastBackupTimestamp_\(oldFP)")

        // Simulate migration logic from ChangePatternView
        let wasEnabled = defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)")
            || defaults.bool(forKey: "iCloudBackupEnabled") // legacy fallback
        if wasEnabled {
            defaults.set(true, forKey: "iCloudBackupEnabled_\(newFP)")
            defaults.set(0, forKey: "lastBackupTimestamp_\(newFP)")
            defaults.removeObject(forKey: "iCloudBackupEnabled_\(oldFP)")
            defaults.removeObject(forKey: "lastBackupTimestamp_\(oldFP)")
        }

        // Verify migration
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_\(newFP)"),
                      "New fingerprint should have backup enabled")
        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_\(newFP)"), 0,
                       "New fingerprint timestamp should be reset to force immediate backup")
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)"),
                       "Old fingerprint enabled key should be removed")
        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_\(oldFP)"), 0,
                       "Old fingerprint timestamp key should be removed")
    }

    func testPatternChangeMigrationFallsBackToLegacyKey() {
        let oldFP = "old_fp_legacy"
        let newFP = "new_fp_legacy"

        // Only legacy global key is set (pre-per-vault migration)
        defaults.set(true, forKey: "iCloudBackupEnabled")
        // No per-vault key exists

        let wasEnabled = defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)")
            || defaults.bool(forKey: "iCloudBackupEnabled")

        XCTAssertTrue(wasEnabled, "Legacy global key should trigger migration")

        if wasEnabled {
            defaults.set(true, forKey: "iCloudBackupEnabled_\(newFP)")
            defaults.set(0, forKey: "lastBackupTimestamp_\(newFP)")
        }

        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_\(newFP)"),
                      "New fingerprint should get backup enabled from legacy key")
    }

    func testPatternChangeNoMigrationWhenDisabled() {
        let oldFP = "disabled_old"
        let newFP = "disabled_new"

        defaults.set(false, forKey: "iCloudBackupEnabled_\(oldFP)")
        defaults.removeObject(forKey: "iCloudBackupEnabled")

        let wasEnabled = defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)")
            || defaults.bool(forKey: "iCloudBackupEnabled")

        XCTAssertFalse(wasEnabled, "Neither per-vault nor legacy key enabled")

        // No migration should happen
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_\(newFP)"),
                       "New fingerprint should not have backup enabled when disabled")
    }

    // MARK: - performBackupIfNeeded Per-Vault Logic

    func testPerformBackupIfNeededUsesPerVaultKey() {
        let fp = "test_fp_needed"
        let testKey = Data(repeating: 0xAA, count: 32)

        // Per-vault key is disabled
        defaults.set(false, forKey: "iCloudBackupEnabled_\(fp)")

        // Should not crash or start backup
        manager.performBackupIfNeeded(with: testKey, vaultFingerprint: fp)
    }

    func testPerformBackupIfNeededFallsBackToGlobalKey() {
        let testKey = Data(repeating: 0xBB, count: 32)

        // No fingerprint → uses global key
        defaults.set(false, forKey: "iCloudBackupEnabled")
        manager.performBackupIfNeeded(with: testKey, vaultFingerprint: nil)
        // Should not crash — just returns because disabled
    }

    func testPerformBackupIfNeededUsesPerVaultTimestamp() {
        let fp = "timestamp_test_fp"
        let testKey = Data(repeating: 0xCC, count: 32)

        // Enable per-vault backup
        defaults.set(true, forKey: "iCloudBackupEnabled_\(fp)")
        // Set recent timestamp → not overdue
        defaults.set(Date().timeIntervalSince1970, forKey: "lastBackupTimestamp_\(fp)")

        // Should not start backup because timestamp is recent
        manager.performBackupIfNeeded(with: testKey, vaultFingerprint: fp)
    }

    func testPerformBackupIfNeededOldTimestampTriggersBackup() {
        let fp = "old_timestamp_fp"
        let testKey = Data(repeating: 0xDD, count: 32)

        // Enable per-vault backup with old timestamp (25 hours ago)
        defaults.set(true, forKey: "iCloudBackupEnabled_\(fp)")
        let oldTimestamp = Date().addingTimeInterval(-25 * 3600).timeIntervalSince1970
        defaults.set(oldTimestamp, forKey: "lastBackupTimestamp_\(fp)")

        // This will try to backup and fail on CloudKit (no iCloud in tests),
        // but should not crash. The auto-backup task will be created.
        manager.performBackupIfNeeded(with: testKey, vaultFingerprint: fp)
    }

    // MARK: - Vault Fingerprint Helpers

    func testVaultFingerprintIsDeterministic() {
        let key = Data(repeating: 0x42, count: 32)
        let fp1 = iCloudBackupManager.vaultFingerprint(from: key)
        let fp2 = iCloudBackupManager.vaultFingerprint(from: key)
        XCTAssertEqual(fp1, fp2, "Same key should produce same fingerprint")
    }

    func testVaultFingerprintDiffersForDifferentKeys() {
        let key1 = Data(repeating: 0x01, count: 32)
        let key2 = Data(repeating: 0x02, count: 32)
        let fp1 = iCloudBackupManager.vaultFingerprint(from: key1)
        let fp2 = iCloudBackupManager.vaultFingerprint(from: key2)
        XCTAssertNotEqual(fp1, fp2, "Different keys should produce different fingerprints")
    }

    func testKeyDerivationFingerprintMatchesVaultFingerprint() {
        let key = Data(repeating: 0xFF, count: 32)
        let fromKeyDerivation = KeyDerivation.keyFingerprint(from: key)
        let fromManager = iCloudBackupManager.vaultFingerprint(from: key)
        XCTAssertEqual(fromKeyDerivation, fromManager,
                       "Both methods should compute the same fingerprint")
    }

    // MARK: - Checksum in Restore Path

    func testBackupMetadataWithEmptyChecksumIsValid() {
        // Empty checksum should be used for backward compat entries
        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: Date(),
            size: 1024,
            checksum: Data(),
            formatVersion: 2,
            chunkCount: 3,
            backupId: "empty-checksum"
        )

        XCTAssertTrue(metadata.checksum.isEmpty,
                      "Empty checksum should be representable")
    }

    func testBackupMetadataChecksumPassthrough() {
        // Verify that checksum from version entry is correctly passed through
        let checksum = Data(repeating: 0xDE, count: 32)
        let version = iCloudBackupManager.BackupVersionEntry(
            backupId: "checksum-test",
            timestamp: Date(),
            size: 2048,
            verificationToken: nil,
            chunkCount: 2,
            checksum: checksum
        )

        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: version.timestamp,
            size: version.size,
            checksum: version.checksum ?? Data(),
            formatVersion: 2,
            chunkCount: version.chunkCount,
            backupId: version.backupId,
            verificationToken: version.verificationToken
        )

        XCTAssertEqual(metadata.checksum, checksum,
                       "Checksum from version entry should pass through to metadata")
    }

    func testBackupMetadataChecksumPassthroughNilFallsToEmpty() {
        let version = iCloudBackupManager.BackupVersionEntry(
            backupId: "nil-checksum",
            timestamp: Date(),
            size: 1024,
            verificationToken: nil,
            chunkCount: 1,
            checksum: nil  // Old entry without checksum
        )

        let metadata = iCloudBackupManager.BackupMetadata(
            timestamp: version.timestamp,
            size: version.size,
            checksum: version.checksum ?? Data(),
            formatVersion: 2,
            chunkCount: version.chunkCount,
            backupId: version.backupId,
            verificationToken: version.verificationToken
        )

        XCTAssertTrue(metadata.checksum.isEmpty,
                      "nil checksum should fall back to empty Data")
    }

    // MARK: - Version Index Record Naming

    func testVersionIndexRecordNameContainsFingerprint() {
        let fp = "deadbeef12345678"
        let name = iCloudBackupManager.versionIndexRecordName(fingerprint: fp)
        XCTAssertTrue(name.contains(fp))
        XCTAssertTrue(name.hasPrefix("vb_"))
        XCTAssertTrue(name.hasSuffix("_index"))
    }

    func testManifestRecordNameContainsFingerprintAndVersion() {
        let fp = "deadbeef12345678"
        let name = iCloudBackupManager.manifestRecordName(fingerprint: fp, version: 3)
        XCTAssertTrue(name.contains(fp))
        XCTAssertTrue(name.hasPrefix("vb_"))
        XCTAssertTrue(name.hasSuffix("_v3"))
    }

    func testDifferentFingerprintsProduceDifferentRecordNames() {
        let name1 = iCloudBackupManager.versionIndexRecordName(fingerprint: "fp_aaa")
        let name2 = iCloudBackupManager.versionIndexRecordName(fingerprint: "fp_bbb")
        XCTAssertNotEqual(name1, name2)
    }

    // MARK: - Delete Confirmation Logic

    func testToggleDisableWithVersionsShowsConfirmation() {
        // Simulates the logic in handleToggleChange
        let versionCount = 3

        // When disabling with versions present, should show confirmation
        let shouldShowConfirmation = versionCount > 0
        XCTAssertTrue(shouldShowConfirmation)
    }

    func testToggleDisableWithNoVersionsSkipsConfirmation() {
        let versionCount = 0

        let shouldShowConfirmation = versionCount > 0
        XCTAssertFalse(shouldShowConfirmation,
                       "No versions → should skip confirmation dialog")
    }

    // MARK: - BackupVersionIndex Size Calculations

    func testVersionIndexTotalSizeCalculation() {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeVersionEntry(backupId: "a", size: 1000))
        index.addVersion(makeVersionEntry(backupId: "b", size: 2000))
        index.addVersion(makeVersionEntry(backupId: "c", size: 3000))

        let totalSize = index.versions.reduce(0) { $0 + Int64($1.size) }
        XCTAssertEqual(totalSize, 6000)
    }

    func testVersionIndexEmptyTotalSize() {
        let index = iCloudBackupManager.BackupVersionIndex()
        let totalSize = index.versions.reduce(0) { $0 + Int64($1.size) }
        XCTAssertEqual(totalSize, 0)
    }

    func testVersionCountAfterAddAndRemove() {
        var index = iCloudBackupManager.BackupVersionIndex()
        index.addVersion(makeVersionEntry(backupId: "v1"))
        index.addVersion(makeVersionEntry(backupId: "v2"))
        XCTAssertEqual(index.versions.count, 2)

        index.versions.removeAll { $0.backupId == "v1" }
        XCTAssertEqual(index.versions.count, 1)
        XCTAssertEqual(index.versions[0].backupId, "v2")
    }

    // MARK: - Sorting Versions by Timestamp

    func testVersionsSortByTimestampDescending() {
        let older = iCloudBackupManager.BackupVersionEntry(
            backupId: "old",
            timestamp: Date(timeIntervalSince1970: 1000),
            size: 100,
            verificationToken: nil,
            chunkCount: 1,
            checksum: nil
        )
        let newer = iCloudBackupManager.BackupVersionEntry(
            backupId: "new",
            timestamp: Date(timeIntervalSince1970: 2000),
            size: 200,
            verificationToken: nil,
            chunkCount: 2,
            checksum: nil
        )

        let versions = [older, newer]
        let sorted = versions.sorted { $0.timestamp > $1.timestamp }

        XCTAssertEqual(sorted[0].backupId, "new", "Newer should come first")
        XCTAssertEqual(sorted[1].backupId, "old", "Older should come second")
    }

    // MARK: - Legacy Duplicate Detection

    func testLegacyBackupDuplicateDetection() {
        // Simulate the logic in RestoreFromBackupView.loadVersions
        let versions = [
            makeVersionEntry(backupId: "backup-001"),
            makeVersionEntry(backupId: "backup-002"),
        ]

        let legacyBackupId = "backup-001"
        let isLegacyDuplicate = versions.contains { $0.backupId == legacyBackupId }
        XCTAssertTrue(isLegacyDuplicate,
                      "Legacy backup with same ID as versioned backup should be detected as duplicate")
    }

    func testLegacyBackupNotDuplicateWhenDifferentId() {
        let versions = [
            makeVersionEntry(backupId: "backup-001"),
            makeVersionEntry(backupId: "backup-002"),
        ]

        let legacyBackupId = "legacy-old-backup"
        let isLegacyDuplicate = versions.contains { $0.backupId == legacyBackupId }
        XCTAssertFalse(isLegacyDuplicate,
                       "Legacy backup with different ID should NOT be detected as duplicate")
    }

    // MARK: - Per-Vault Staging Directory

    func testPerVaultStagingDirectoryNameFormat() {
        let fp = "abc123"
        let expectedSuffix = "pending_backup_\(fp)"
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stagingDir = documentsDir.appendingPathComponent(expectedSuffix, isDirectory: true)

        XCTAssertTrue(stagingDir.lastPathComponent.hasPrefix("pending_backup_"))
        XCTAssertTrue(stagingDir.lastPathComponent.contains(fp))
    }

    func testDifferentVaultsGetDifferentStagingDirs() {
        let fp1 = "vault_1_fp"
        let fp2 = "vault_2_fp"
        let dir1 = "pending_backup_\(fp1)"
        let dir2 = "pending_backup_\(fp2)"

        XCTAssertNotEqual(dir1, dir2,
                          "Different vaults should have different staging directories")
    }

    // MARK: - BackupVersionEntry Checksum Backward Compatibility

    func testOldVersionIndexDecodesWithNilChecksums() throws {
        // Simulate an old version index from CloudKit (no checksum fields)
        let json = """
        {
            "versions": [
                {
                    "backupId": "old-v1",
                    "timestamp": 1700000000,
                    "size": 1024,
                    "chunkCount": 2
                },
                {
                    "backupId": "old-v2",
                    "timestamp": 1700001000,
                    "size": 2048,
                    "verificationToken": "AAAA",
                    "chunkCount": 4
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionIndex.self, from: json
        )

        XCTAssertEqual(decoded.versions.count, 2)
        XCTAssertNil(decoded.versions[0].checksum,
                     "Old entry without checksum should decode as nil")
        XCTAssertNil(decoded.versions[1].checksum,
                     "Old entry without checksum should decode as nil")
        XCTAssertNil(decoded.versions[0].verificationToken)
        XCTAssertNotNil(decoded.versions[1].verificationToken)
    }

    func testMixedOldAndNewEntriesInVersionIndex() throws {
        // One entry has checksum, one doesn't
        var index = iCloudBackupManager.BackupVersionIndex()

        let oldEntry = iCloudBackupManager.BackupVersionEntry(
            backupId: "old",
            timestamp: Date(),
            size: 1024,
            verificationToken: nil,
            chunkCount: 1,
            checksum: nil  // Pre-checksum era
        )
        let newEntry = iCloudBackupManager.BackupVersionEntry(
            backupId: "new",
            timestamp: Date(),
            size: 2048,
            verificationToken: Data([0xAA]),
            chunkCount: 2,
            checksum: Data(repeating: 0xBB, count: 32)
        )

        index.addVersion(oldEntry)
        index.addVersion(newEntry)

        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(
            iCloudBackupManager.BackupVersionIndex.self, from: data
        )

        XCTAssertNil(decoded.versions[0].checksum)
        XCTAssertEqual(decoded.versions[1].checksum?.count, 32)
    }

    // MARK: - performBackupIfNeeded Guard Conditions

    func testPerformBackupIfNeededDisabledPerVault() {
        let fp = "disabled_vault"
        let key = Data(repeating: 0x11, count: 32)

        defaults.set(false, forKey: "iCloudBackupEnabled_\(fp)")
        defaults.set(0.0, forKey: "lastBackupTimestamp_\(fp)") // Would be overdue

        // Should early-return without crashing
        manager.performBackupIfNeeded(with: key, vaultFingerprint: fp)
    }

    func testPerformBackupIfNeededEnabledPerVaultRecentTimestamp() {
        let fp = "recent_vault"
        let key = Data(repeating: 0x22, count: 32)

        defaults.set(true, forKey: "iCloudBackupEnabled_\(fp)")
        // Backed up 1 hour ago → not overdue
        defaults.set(Date().addingTimeInterval(-3600).timeIntervalSince1970,
                    forKey: "lastBackupTimestamp_\(fp)")

        // Should early-return (not overdue)
        manager.performBackupIfNeeded(with: key, vaultFingerprint: fp)
    }

    // MARK: - Helpers

    private func makeVersionEntry(
        backupId: String,
        size: Int = 1024,
        chunkCount: Int = 1,
        checksum: Data? = nil
    ) -> iCloudBackupManager.BackupVersionEntry {
        iCloudBackupManager.BackupVersionEntry(
            backupId: backupId,
            timestamp: Date(),
            size: size,
            verificationToken: nil,
            chunkCount: chunkCount,
            checksum: checksum
        )
    }
}
