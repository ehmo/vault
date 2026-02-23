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

    func testWipeCounterInitiallyZero() {
        manager.resetWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testWipeCounterIncrementOnce() {
        manager.resetWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 1)
    }

    func testWipeCounterIncrementMultiple() {
        manager.resetWipeCounter()
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 3)
    }

    func testWipeCounterReset() {
        manager.resetWipeCounter()
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 2)

        manager.resetWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testWipeCounterDoubleResetIsSafe() {
        manager.resetWipeCounter()
        manager.resetWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testWipeCounterHighValue() {
        manager.resetWipeCounter()
        for _ in 0..<50 {
            manager.incrementWipeCounter()
        }
        XCTAssertEqual(manager.getWipeCounter(), 50)
    }

    // MARK: - Duress Key Fingerprint

    func testDuressFingerprintInitiallyNil() {
        manager.clearDuressKeyFingerprint()
        XCTAssertNil(manager.getDuressKeyFingerprint())
    }

    func testDuressFingerprintSetAndGet() throws {
        let fingerprint = "abc123def456"
        try manager.setDuressKeyFingerprint(fingerprint)
        XCTAssertEqual(manager.getDuressKeyFingerprint(), fingerprint)
    }

    func testDuressFingerprintOverwrite() throws {
        try manager.setDuressKeyFingerprint("first")
        try manager.setDuressKeyFingerprint("second")
        XCTAssertEqual(manager.getDuressKeyFingerprint(), "second")
    }

    func testDuressFingerprintClear() throws {
        try manager.setDuressKeyFingerprint("will-be-cleared")
        XCTAssertNotNil(manager.getDuressKeyFingerprint())

        manager.clearDuressKeyFingerprint()
        XCTAssertNil(manager.getDuressKeyFingerprint())
    }

    func testDuressFingerprintEmptyString() throws {
        try manager.setDuressKeyFingerprint("")
        XCTAssertEqual(manager.getDuressKeyFingerprint(), "")
    }

    func testDuressFingerprintLongString() throws {
        let long = String(repeating: "a", count: 1000)
        try manager.setDuressKeyFingerprint(long)
        XCTAssertEqual(manager.getDuressKeyFingerprint(), long)
    }

    // MARK: - Blob Cursor XOR Key

    func testBlobCursorXorKeyReturns16Bytes() {
        let key = manager.getBlobCursorXORKey()
        XCTAssertEqual(key.count, 16)
    }

    func testBlobCursorXorKeyConsistentOnRepeatedCalls() {
        let key1 = manager.getBlobCursorXORKey()
        let key2 = manager.getBlobCursorXORKey()
        XCTAssertEqual(key1, key2, "Should return same key on repeated calls")
    }

    // MARK: - Device Salt

    func testDeviceSaltReturns32Bytes() async throws {
        let salt = try await manager.getDeviceSalt()
        XCTAssertEqual(salt.count, 32)
    }

    func testDeviceSaltConsistentOnRepeatedCalls() async throws {
        let salt1 = try await manager.getDeviceSalt()
        let salt2 = try await manager.getDeviceSalt()
        XCTAssertEqual(salt1, salt2, "Should return same salt on repeated calls")
    }

    // MARK: - Nuclear Wipe

    func testNuclearWipeClearsWipeCounter() {
        manager.incrementWipeCounter()
        manager.incrementWipeCounter()
        XCTAssertEqual(manager.getWipeCounter(), 2)

        manager.performNuclearWipe()

        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    func testNuclearWipeClearsDuressFingerprint() throws {
        try manager.setDuressKeyFingerprint("test-fingerprint")
        XCTAssertNotNil(manager.getDuressKeyFingerprint())

        manager.performNuclearWipe()

        XCTAssertNil(manager.getDuressKeyFingerprint())
    }

    func testNuclearWipeDoubleWipeIsSafe() {
        manager.performNuclearWipe()
        manager.performNuclearWipe() // Should not crash
        XCTAssertEqual(manager.getWipeCounter(), 0)
    }

    // MARK: - Secure Enclave Availability

    func testSecureEnclaveAvailabilityReturnsBoolean() {
        // On simulator, Secure Enclave is typically not available
        // but the check itself should not crash
        _ = manager.isSecureEnclaveAvailable
    }
}
