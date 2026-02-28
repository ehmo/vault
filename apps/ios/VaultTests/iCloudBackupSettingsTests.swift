import XCTest
@testable import Vault

/// Tests for per-vault UserDefaults keys, global default inheritance,
/// pattern change migration, vault fingerprint, and backup trigger guards.
@MainActor
final class ICloudBackupSettingsTests: XCTestCase {

    private var manager: iCloudBackupManager!
    private let defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        manager = iCloudBackupManager.shared
    }

    override func tearDown() {
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("iCloudBackup") || key.hasPrefix("lastBackupTimestamp") {
                defaults.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    // MARK: - Per-Vault Key Isolation

    func testPerVaultKeysAreIsolated() {
        defaults.set(true, forKey: "iCloudBackupEnabled_vaultA")
        defaults.set(false, forKey: "iCloudBackupEnabled_vaultB")
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_vaultA"))
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_vaultB"))
    }

    func testPerVaultKeyDoesNotAffectGlobalKey() {
        defaults.set(false, forKey: "iCloudBackupEnabled")
        defaults.set(true, forKey: "iCloudBackupEnabled_test_fp")
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled"))
    }

    // MARK: - Global Default Inheritance

    func testNewVaultInheritsGlobalTrue() {
        defaults.set(true, forKey: "iCloudBackupDefault")
        simulateFirstUnlock("new_vault")
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_new_vault"))
    }

    func testNewVaultInheritsGlobalFalse() {
        defaults.set(false, forKey: "iCloudBackupDefault")
        simulateFirstUnlock("vault_disabled")
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_vault_disabled"))
    }

    func testInitializedVaultDoesNotReInherit() {
        defaults.set(false, forKey: "iCloudBackupEnabled_existing")
        defaults.set(true, forKey: "iCloudBackupInitialized_existing")
        defaults.set(true, forKey: "iCloudBackupDefault")

        simulateFirstUnlock("existing")
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_existing"),
                       "Should not re-inherit after initialization")
    }

    func testMultipleVaultsInheritIndependently() {
        defaults.set(true, forKey: "iCloudBackupDefault")
        simulateFirstUnlock("vaultA")
        defaults.set(false, forKey: "iCloudBackupEnabled_vaultA") // user disables A
        simulateFirstUnlock("vaultB")

        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_vaultA"))
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_vaultB"))
    }

    // MARK: - Pattern Change Migration

    func testPatternChangeMigratesKeys() {
        defaults.set(true, forKey: "iCloudBackupEnabled_oldFP")
        defaults.set(1700000000.0, forKey: "lastBackupTimestamp_oldFP")

        simulatePatternMigration(from: "oldFP", to: "newFP")

        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_newFP"))
        XCTAssertEqual(defaults.double(forKey: "lastBackupTimestamp_newFP"), 0)
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_oldFP"))
    }

    func testPatternChangeFallsBackToLegacyKey() {
        defaults.set(true, forKey: "iCloudBackupEnabled") // legacy only
        simulatePatternMigration(from: "oldFP", to: "newFP")
        XCTAssertTrue(defaults.bool(forKey: "iCloudBackupEnabled_newFP"))
    }

    func testPatternChangeNoMigrationWhenDisabled() {
        defaults.set(false, forKey: "iCloudBackupEnabled_disabledFP")
        defaults.removeObject(forKey: "iCloudBackupEnabled")
        simulatePatternMigration(from: "disabledFP", to: "newFP")
        XCTAssertFalse(defaults.bool(forKey: "iCloudBackupEnabled_newFP"))
    }

    // MARK: - Vault Fingerprint

    func testFingerprintIsDeterministic() {
        let key = Data(repeating: 0x42, count: 32)
        XCTAssertEqual(
            iCloudBackupManager.vaultFingerprint(from: key),
            iCloudBackupManager.vaultFingerprint(from: key)
        )
    }

    func testFingerprintDiffersForDifferentKeys() {
        XCTAssertNotEqual(
            iCloudBackupManager.vaultFingerprint(from: Data(repeating: 0x01, count: 32)),
            iCloudBackupManager.vaultFingerprint(from: Data(repeating: 0x02, count: 32))
        )
    }

    func testFingerprintIs16CharHex() {
        let fp = iCloudBackupManager.vaultFingerprint(from: Data(repeating: 0xAA, count: 32))
        XCTAssertEqual(fp.count, 16)
        XCTAssertTrue(fp.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testFingerprintMatchesKeyDerivation() {
        let key = Data(repeating: 0xFF, count: 32)
        XCTAssertEqual(
            KeyDerivation.keyFingerprint(from: key),
            iCloudBackupManager.vaultFingerprint(from: key)
        )
    }

    // MARK: - performBackupIfNeeded Guards

    func testSkipsWhenPerVaultDisabled() {
        defaults.set(false, forKey: "iCloudBackupEnabled_test_fp")
        manager.performBackupIfNeeded(with: Data(repeating: 0xAA, count: 32), vaultFingerprint: "test_fp")
    }

    func testFallsBackToGlobalKeyWhenNoFingerprint() {
        defaults.set(false, forKey: "iCloudBackupEnabled")
        manager.performBackupIfNeeded(with: Data(repeating: 0xBB, count: 32), vaultFingerprint: nil)
    }

    func testSkipsWhenTimestampRecent() {
        defaults.set(true, forKey: "iCloudBackupEnabled_recent_fp")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastBackupTimestamp_recent_fp")
        manager.performBackupIfNeeded(with: Data(repeating: 0xCC, count: 32), vaultFingerprint: "recent_fp")
    }

    // MARK: - Helpers

    private func simulateFirstUnlock(_ fp: String) {
        let initKey = "iCloudBackupInitialized_\(fp)"
        if !defaults.bool(forKey: initKey) {
            defaults.set(defaults.bool(forKey: "iCloudBackupDefault"), forKey: "iCloudBackupEnabled_\(fp)")
            defaults.set(true, forKey: initKey)
        }
    }

    private func simulatePatternMigration(from oldFP: String, to newFP: String) {
        let wasEnabled = defaults.bool(forKey: "iCloudBackupEnabled_\(oldFP)")
            || defaults.bool(forKey: "iCloudBackupEnabled")
        if wasEnabled {
            defaults.set(true, forKey: "iCloudBackupEnabled_\(newFP)")
            defaults.set(0, forKey: "lastBackupTimestamp_\(newFP)")
            defaults.removeObject(forKey: "iCloudBackupEnabled_\(oldFP)")
            defaults.removeObject(forKey: "lastBackupTimestamp_\(oldFP)")
        }
    }
}
