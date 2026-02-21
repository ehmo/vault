import XCTest
@testable import Vault

final class SecureEnclaveManagerTests: XCTestCase {

    private let manager = SecureEnclaveManager.shared

    override func tearDown() {
        // Clean up test state to avoid polluting other tests
        manager.resetWipeCounter()
        manager.clearDuressKeyFingerprint()
        super.tearDown()
    }

    // MARK: - Wipe Counter

    func testWipeCounter_initiallyZero() {
        manager.resetWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testWipeCounter_incrementOnce() {
        manager.resetWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 1)
    }

    func testWipeCounter_incrementMultiple() {
        manager.resetWipeCounter()
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 3)
    }

    func testWipeCounter_reset() {
        manager.resetWipeCounter()
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 2)

        manager.resetWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testWipeCounter_doubleResetIsSafe() {
        manager.resetWipeCounter()
        manager.resetWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testWipeCounter_highValue() {
        manager.resetWipeCounter()
        for _ in 0..<50 {
            manager.incrementWipeCounter()
        }
        XCTAssertEqual(manager.getWipeCounter(), 50)
    }

    // MARK: - Duress Key Fingerprint

    func testDuressFingerprint_initiallyNil() {
        manager.clearDuressKeyFingerprint()
        XCTAssertNil(manager.getDuressKeyFingerprint())
    }

    func testDuressFingerprint_setAndGet() throws {
        let fingerprint = "abc123def456"
        try manager.setDuressKeyFingerprint(fingerprint)
        XCTAssertEqual(manager.getDuressKeyFingerprint(), fingerprint)
    }

    func testDuressFingerprint_overwrite() throws {
        try manager.setDuressKeyFingerprint("first")
        try manager.setDuressKeyFingerprint("second")
        XCTAssertEqual(manager.getDuressKeyFingerprint(), "second")
    }

    func testDuressFingerprint_clear() throws {
        try manager.setDuressKeyFingerprint("will-be-cleared")
        XCTAssertNotNil(manager.getDuressKeyFingerprint())

        manager.clearDuressKeyFingerprint()
        XCTAssertNil(manager.getDuressKeyFingerprint())
    }

    func testDuressFingerprint_emptyString() throws {
        try manager.setDuressKeyFingerprint("")
        XCTAssertEqual(manager.getDuressKeyFingerprint(), "")
    }

    func testDuressFingerprint_longString() throws {
        let long = String(repeating: "a", count: 1000)
        try manager.setDuressKeyFingerprint(long)
        XCTAssertEqual(manager.getDuressKeyFingerprint(), long)
    }

    // MARK: - Blob Cursor XOR Key

    func testBlobCursorXORKey_returns16Bytes() {
        let key = manager.getBlobCursorXORKey()
        XCTAssertEqual(key.count, 16)
    }

    func testBlobCursorXORKey_consistentOnRepeatedCalls() {
        let key1 = manager.getBlobCursorXORKey()
        let key2 = manager.getBlobCursorXORKey()
        XCTAssertEqual(key1, key2, "Should return same key on repeated calls")
    }

    // MARK: - Device Salt

    func testDeviceSalt_returns32Bytes() async throws {
        let salt = try await manager.getDeviceSalt()
        XCTAssertEqual(salt.count, 32)
    }

    func testDeviceSalt_consistentOnRepeatedCalls() async throws {
        let salt1 = try await manager.getDeviceSalt()
        let salt2 = try await manager.getDeviceSalt()
        XCTAssertEqual(salt1, salt2, "Should return same salt on repeated calls")
    }

    // MARK: - Nuclear Wipe

    func testNuclearWipe_clearsWipeCounter() {
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 2)

        manager.performNuclearWipe()

        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testNuclearWipe_clearsDuressFingerprint() throws {
        try manager.setDuressKeyFingerprint("test-fingerprint")
        XCTAssertNotNil(manager.getDuressKeyFingerprint())

        manager.performNuclearWipe()

        XCTAssertNil(manager.getDuressKeyFingerprint())
    }

    func testNuclearWipe_doubleWipeIsSafe() {
        manager.performNuclearWipe()
        manager.performNuclearWipe() // Should not crash
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    // MARK: - Secure Enclave Availability

    func testSecureEnclaveAvailability_returnsBoolean() {
        // On simulator, Secure Enclave is typically not available
        // but the check itself should not crash
        _ = manager.isSecureEnclaveAvailable
    }
}
