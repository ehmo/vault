import XCTest
@testable import Vault

/// Tests for VaultIndexManager covering caching, migration, and basic operations.
/// These tests catch common mistakes like:
/// - Using bare VaultIndex() init instead of loadIndex(with:)
/// - Missing master key in index creation
final class VaultIndexManagerTests: XCTestCase {

    private var manager: VaultIndexManager!
    private var testKey: VaultKey!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()

        // Create temporary directory for test isolation
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Initialize manager with test configuration
        manager = VaultIndexManager(
            documentsURL: tempDirectory,
            blobFileName: "test_blob.bin",
            defaultBlobSize: 50 * 1024 * 1024,
            cursorBlockOffset: 50 * 1024 * 1024
        )

        // Mock cursor closures
        manager.readGlobalCursor = { 0 }
        manager.cursorFooterOffset = { 50 * 1024 * 1024 }

        testKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - New Vault Creation

    /// Tests that loadIndex creates a proper v3 index with master key for new vaults.
    /// Catches: Using bare VaultIndex() init without master key
    func testLoadIndexCreatesNewVaultWithMasterKey() async throws {
        let index = try await manager.loadIndex(with: testKey)

        XCTAssertEqual(index.version, 3, "New vault should be v3")
        XCTAssertNotNil(index.encryptedMasterKey, "New vault must have encrypted master key")
        XCTAssertEqual(index.files.count, 0, "New vault should have no files")
        XCTAssertNotNil(index.blobs, "v3 index should have blob descriptors")
    }

    /// Tests that the master key can be extracted and decrypted.
    func testGetMasterKeyExtractsSuccessfully() async throws {
        let index = try await manager.loadIndex(with: testKey)
        let masterKey = try manager.getMasterKey(from: index, vaultKey: testKey)

        XCTAssertEqual(masterKey.rawBytes.count, 32, "Master key should be 32 bytes")
    }

    /// Tests that getMasterKey throws when encryptedMasterKey is nil.
    /// Catches: Creating v1 index without migration
    func testGetMasterKeyThrowsWhenNil() throws {
        // Create v1 index manually (without master key)
        let v1Index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 50 * 1024 * 1024)

        XCTAssertThrowsError(try manager.getMasterKey(from: v1Index, vaultKey: testKey)) { error in
            XCTAssertEqual(error as? VaultStorageError, .corruptedData)
        }
    }

    // MARK: - Caching

    /// Tests that cached index is returned for the same key.
    func testLoadIndexUsesCachedIndexForSameKey() async throws {
        let index1 = try await manager.loadIndex(with: testKey)
        let index2 = try await manager.loadIndex(with: testKey)

        // Should return same data due to caching (VaultIndex is a struct, so we compare values)
        XCTAssertEqual(index1.files.count, index2.files.count)
        XCTAssertEqual(index1.version, index2.version)
    }

    /// Tests that cache is updated after save.
    func testSaveIndexUpdatesCache() async throws {
        let index = try await manager.loadIndex(with: testKey)

        // Save
        try await manager.saveIndex(index, with: testKey)

        // Load again - should get cached version
        let cached = try await manager.loadIndex(with: testKey)
        XCTAssertNotNil(cached)
    }

    /// Tests explicit cache invalidation.
    func testInvalidateCache() async throws {
        _ = try await manager.loadIndex(with: testKey)

        await manager.invalidateCache()

        // After invalidation, should load from disk (new instance)
        let index2 = try await manager.loadIndex(with: testKey)
        XCTAssertNotNil(index2)
    }

    // MARK: - Migration

    /// Tests v1 to v3 migration (through v2).
    func testLoadIndexMigrationV1ToV3() async throws {
        // Create v1 index manually
        let v1Index = VaultStorage.VaultIndex(files: [], nextOffset: 0, totalSize: 50 * 1024 * 1024)
        let encoded = try JSONEncoder().encode(v1Index)
        let encrypted = try CryptoEngine.encrypt(encoded, with: testKey.rawBytes)
        try encrypted.write(to: manager.indexURL(for: testKey))

        // Load should migrate to v3
        let migrated = try await manager.loadIndex(with: testKey)
        XCTAssertEqual(migrated.version, 3, "Should migrate through v2 to v3")
        XCTAssertNotNil(migrated.encryptedMasterKey, "Should have master key after migration")
    }

    // MARK: - Error Handling

    /// Tests that corrupted data throws appropriate error.
    func testLoadIndexCorruptedDataThrows() async throws {
        // Write garbage data
        let garbage = Data("not a valid encrypted index".utf8)
        try garbage.write(to: manager.indexURL(for: testKey))

        do {
            _ = try await manager.loadIndex(with: testKey)
            XCTFail("Expected indexDecryptionFailed error")
        } catch {
            XCTAssertEqual(error as? VaultStorageError, .indexDecryptionFailed)
        }
    }

    /// Tests that wrong key throws decryption error.
    func testLoadIndexWrongKeyThrows() async throws {
        // Create and persist index with testKey
        let index = try await manager.loadIndex(with: testKey)
        try await manager.saveIndex(index, with: testKey)

        // Copy testKey's encrypted file to wrongKey's path so decryption is attempted
        let wrongKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        let srcURL = manager.indexURL(for: testKey)
        let dstURL = manager.indexURL(for: wrongKey)
        try FileManager.default.copyItem(at: srcURL, to: dstURL)

        // Invalidate cache so it reads from disk
        await manager.invalidateCache()

        do {
            _ = try await manager.loadIndex(with: wrongKey)
            XCTFail("Expected indexDecryptionFailed error")
        } catch {
            XCTAssertEqual(error as? VaultStorageError, .indexDecryptionFailed)
        }
    }

    // MARK: - Key Fingerprint

    func testKeyFingerprintIsDeterministic() {
        let fp1 = manager.keyFingerprint(testKey)
        let fp2 = manager.keyFingerprint(testKey)

        XCTAssertEqual(fp1, fp2, "Fingerprint should be deterministic")
        XCTAssertEqual(fp1.count, 32, "Fingerprint should be 32 hex characters (16 bytes)")
    }

    func testKeyFingerprintDifferentKeys() {
        let key2 = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)

        let fp1 = manager.keyFingerprint(testKey)
        let fp2 = manager.keyFingerprint(key2)

        XCTAssertNotEqual(fp1, fp2, "Different keys should have different fingerprints")
    }
}
