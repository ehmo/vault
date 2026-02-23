import Foundation
@testable import Vault

/// Mock SecureEnclaveManager for testing. In-memory storage, no Keychain access.
final class MockSecureEnclave: SecureEnclaveProtocol {
    private var salt: Data?
    private var wipeCounter = 0
    private var duressFingerprint: String?
    private var blobXORKey: Data?

    func getDeviceSalt() async throws -> Data {
        if let salt { return salt }
        let newSalt = Data(repeating: 0xAA, count: 32)
        salt = newSalt
        return newSalt
    }

    func getWipeCounter() -> Int { wipeCounter }
    func incrementWipeCounter() { wipeCounter += 1 }
    func resetWipeCounter() { wipeCounter = 0 }

    func setDuressKeyFingerprint(_ fingerprint: String) throws {
        duressFingerprint = fingerprint
    }

    func getDuressKeyFingerprint() -> String? { duressFingerprint }
    func clearDuressKeyFingerprint() { duressFingerprint = nil }

    func getBlobCursorXORKey() -> Data {
        if let key = blobXORKey { return key }
        let key = Data(repeating: 0xBB, count: 16)
        blobXORKey = key
        return key
    }

    func performNuclearWipe() {
        salt = nil
        wipeCounter = 0
        duressFingerprint = nil
        blobXORKey = nil
    }

    var isSecureEnclaveAvailable: Bool { true }
}
