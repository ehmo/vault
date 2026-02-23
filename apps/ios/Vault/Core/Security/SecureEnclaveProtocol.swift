import Foundation

/// Protocol abstracting SecureEnclaveManager for testability.
/// Covers the public API surface used by DuressHandler, AppState, and KeyDerivation.
protocol SecureEnclaveProtocol {
    func getDeviceSalt() async throws -> Data
    func getWipeCounter() -> Int
    func incrementWipeCounter()
    func resetWipeCounter()
    func setDuressKeyFingerprint(_ fingerprint: String) throws
    func getDuressKeyFingerprint() -> String?
    func clearDuressKeyFingerprint()
    func getBlobCursorXORKey() -> Data
    func performNuclearWipe()
    var isSecureEnclaveAvailable: Bool { get }
}

extension SecureEnclaveManager: SecureEnclaveProtocol {}
