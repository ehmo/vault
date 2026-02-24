import XCTest
@testable import Vault

final class DuressHandlerTests: XCTestCase {

    private let handler = DuressHandler.shared
    private let storage = VaultStorage.shared
    private let secureEnclave = SecureEnclaveManager.shared
    private var testKeys: [Data] = []

    override func setUp() {
        super.setUp()
        testKeys = []
    }

    override func tearDown() async throws {
        // Clear duress state
        await handler.clearDuressVault()
        // Clean up all vault indexes created during tests
        for key in testKeys {
            try? storage.deleteVaultIndex(for: VaultKey(key))
        }
        secureEnclave.resetWipeCounter()
        try await super.tearDown()
    }

    private func makeKey() -> Data {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        testKeys.append(key)
        return key
    }

    private func createVaultWithFiles(key: Data, fileCount: Int = 1) async throws {
        let vaultKey = VaultKey(key)
        var index = try await storage.loadIndex(with: vaultKey)
        for i in 0..<fileCount {
            let entry = VaultStorage.VaultIndex.VaultFileEntry(
                fileId: UUID(),
                offset: i * 100,
                size: 100,
                encryptedHeaderPreview: Data(),
                isDeleted: false,
                thumbnailData: nil,
                mimeType: "text/plain",
                filename: "test\(i).txt",
                blobId: nil,
                createdAt: Date(),
                duration: nil
            )
            index.files.append(entry)
        }
        try await storage.saveIndex(index, with: vaultKey)
    }

    // MARK: - setAsDuressVault / isDuressKey

    func testSetAsDuressVaultAndIsDuressKey() async throws {
        let duressKey = makeKey()
        try await handler.setAsDuressVault(key: duressKey)
        let isDuress = await handler.isDuressKey(duressKey)
        XCTAssertTrue(isDuress, "Key set as duress should be recognized as duress")
    }

    func testIsDuressKeyReturnsFalseForNonDuressKey() async {
        let normalKey = makeKey()
        let isDuress = await handler.isDuressKey(normalKey)
        XCTAssertFalse(isDuress, "Random key should not be recognized as duress")
    }

    func testIsDuressKeyReturnsFalseWhenNoDuressConfigured() async {
        let key = makeKey()
        let isDuress = await handler.isDuressKey(key)
        XCTAssertFalse(isDuress, "No duress configured should return false")
    }

    // MARK: - clearDuressVault

    func testClearDuressVault() async throws {
        let duressKey = makeKey()
        try await handler.setAsDuressVault(key: duressKey)

        let before = await handler.hasDuressVault
        XCTAssertTrue(before)

        await handler.clearDuressVault()

        let after = await handler.hasDuressVault
        XCTAssertFalse(after, "Duress vault should be cleared")
    }

    // MARK: - hasDuressVault

    func testHasDuressVaultReturnsFalseInitially() async {
        let has = await handler.hasDuressVault
        XCTAssertFalse(has)
    }

    func testHasDuressVaultReturnsTrueAfterSetup() async throws {
        let key = makeKey()
        try await handler.setAsDuressVault(key: key)
        let has = await handler.hasDuressVault
        XCTAssertTrue(has)
    }

    // MARK: - triggerDuress

    func testTriggerDuressDestroysOtherVaultsPreservesDuressVault() async throws {
        let duressKey = makeKey()
        let normalKey1 = makeKey()
        let normalKey2 = makeKey()

        try await createVaultWithFiles(key: duressKey, fileCount: 2)
        try await createVaultWithFiles(key: normalKey1, fileCount: 3)
        try await createVaultWithFiles(key: normalKey2, fileCount: 1)

        try await handler.setAsDuressVault(key: duressKey)

        XCTAssertTrue(storage.vaultExists(for: VaultKey(duressKey)))
        XCTAssertTrue(storage.vaultExists(for: VaultKey(normalKey1)))
        XCTAssertTrue(storage.vaultExists(for: VaultKey(normalKey2)))

        await handler.triggerDuress(preservingKey: duressKey)

        XCTAssertTrue(storage.vaultExists(for: VaultKey(duressKey)), "Duress vault should survive trigger")
        XCTAssertFalse(storage.vaultExists(for: VaultKey(normalKey1)), "Normal vault 1 should be destroyed")
        XCTAssertFalse(storage.vaultExists(for: VaultKey(normalKey2)), "Normal vault 2 should be destroyed")

        let duressIndex = try await storage.loadIndex(with: VaultKey(duressKey))
        XCTAssertEqual(duressIndex.files.count, 2, "Duress vault should retain all files")
    }

    func testTriggerDuressClearsDuressDesignation() async throws {
        let duressKey = makeKey()
        try await createVaultWithFiles(key: duressKey)
        try await handler.setAsDuressVault(key: duressKey)

        await handler.triggerDuress(preservingKey: duressKey)

        let stillDuress = await handler.hasDuressVault
        XCTAssertFalse(stillDuress, "Duress designation should be cleared after trigger")
    }

    func testTriggerDuressHandlesMissingDuressIndex() async throws {
        let duressKey = makeKey()
        try await handler.setAsDuressVault(key: duressKey)

        let normalKey = makeKey()
        try await createVaultWithFiles(key: normalKey)

        await handler.triggerDuress(preservingKey: duressKey)

        XCTAssertFalse(storage.vaultExists(for: VaultKey(normalKey)), "Normal vault should be destroyed even when duress vault missing")
    }

    // MARK: - performNuclearWipe

    func testPerformNuclearWipeDestroysEverything() async throws {
        let key1 = makeKey()
        let key2 = makeKey()
        try await createVaultWithFiles(key: key1)
        try await createVaultWithFiles(key: key2)
        try await handler.setAsDuressVault(key: key1)

        await handler.performNuclearWipe(secure: false)

        XCTAssertFalse(storage.vaultExists(for: VaultKey(key1)), "Vault 1 should be destroyed")
        XCTAssertFalse(storage.vaultExists(for: VaultKey(key2)), "Vault 2 should be destroyed")

        let hasDuress = await handler.hasDuressVault
        XCTAssertFalse(hasDuress, "Duress should be cleared")
    }

    // MARK: - Different keys produce different fingerprints

    func testDifferentKeysProduceDifferentFingerprints() async throws {
        let key1 = makeKey()
        let key2 = makeKey()

        try await handler.setAsDuressVault(key: key1)
        let isDuress1 = await handler.isDuressKey(key1)
        let isDuress2 = await handler.isDuressKey(key2)

        XCTAssertTrue(isDuress1)
        XCTAssertFalse(isDuress2, "Different key should not match duress fingerprint")
    }
}
