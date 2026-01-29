import Foundation
import Security
import CryptoKit
import LocalAuthentication

enum SecureEnclaveError: Error {
    case notAvailable
    case keyGenerationFailed
    case keyNotFound
    case operationFailed
    case accessDenied
    case saltGenerationFailed
}

final class SecureEnclaveManager {
    static let shared = SecureEnclaveManager()

    private let saltKeyTag = "is.thevault.app.device.salt"
    private let wipeCounterTag = "is.thevault.app.wipe.counter"
    private let duressKeyTag = "is.thevault.app.duress.key"

    private init() {}

    // MARK: - Device Salt (for key derivation)

    /// Gets or creates a device-bound salt stored in the Secure Enclave.
    /// This salt is unique to the device and cannot be extracted.
    func getDeviceSalt() async throws -> Data {
        // Try to retrieve existing salt
        if let existingSalt = try? retrieveSalt() {
            return existingSalt
        }

        // Generate new salt and store it
        return try await generateAndStoreSalt()
    }

    private func retrieveSalt() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: saltKeyTag,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureEnclaveError.keyNotFound
        }

        return data
    }

    private func generateAndStoreSalt() async throws -> Data {
        // Generate 32 bytes of cryptographically secure random data
        var saltBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)

        guard status == errSecSuccess else {
            throw SecureEnclaveError.saltGenerationFailed
        }

        let salt = Data(saltBytes)

        // Store in keychain with device-only access
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: saltKeyTag,
            kSecValueData as String: salt,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing if any
        SecItemDelete(query as CFDictionary)

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureEnclaveError.operationFailed
        }

        return salt
    }

    // MARK: - Wipe Counter (survives app reinstall)

    /// Gets the current failed attempt count.
    func getWipeCounter() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: wipeCounterTag,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              data.count >= 4 else {
            return 0
        }

        return data.withUnsafeBytes { $0.load(as: Int32.self) }.hashValue
    }

    /// Increments the wipe counter.
    func incrementWipeCounter() {
        let currentCount = getWipeCounter()
        let newCount = Int32(currentCount + 1)

        var countData = Data(count: 4)
        countData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: newCount, as: Int32.self)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: wipeCounterTag,
            kSecValueData as String: countData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Resets the wipe counter (called on successful unlock).
    func resetWipeCounter() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: wipeCounterTag
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Duress Key Storage

    /// Stores the fingerprint of the duress pattern's derived key.
    func setDuressKeyFingerprint(_ fingerprint: String) throws {
        let data = Data(fingerprint.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: duressKeyTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveError.operationFailed
        }
    }

    /// Gets the duress key fingerprint if set.
    func getDuressKeyFingerprint() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: duressKeyTag,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Clears the duress key fingerprint.
    func clearDuressKeyFingerprint() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: duressKeyTag
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Nuclear Wipe

    /// Destroys all vault-related keychain data.
    func performNuclearWipe() {
        // Delete all vault-related keychain items
        let services = [saltKeyTag, wipeCounterTag, duressKeyTag]

        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]
            SecItemDelete(query as CFDictionary)
        }

        // Also delete all recovery phrase keys
        let recoveryQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "is.thevault.app.recovery"
        ]
        SecItemDelete(recoveryQuery as CFDictionary)
        
        // Clear grid letter assignments (will be regenerated on next app launch)
        GridLetterManager.shared.clearLetterAssignments()
    }

    // MARK: - Secure Enclave Availability

    var isSecureEnclaveAvailable: Bool {
        let context = LAContext()
        var error: NSError?

        // Check for biometric capability as proxy for Secure Enclave
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // Secure Enclave is available on A7+ chips (iPhone 5s and later)
        // All devices supporting iOS 17+ have Secure Enclave
        return canEvaluate || error?.code != LAError.biometryNotAvailable.rawValue
    }
}
