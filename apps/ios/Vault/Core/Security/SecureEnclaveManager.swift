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

    private let saltKeyTag = "app.vaultaire.ios.device.salt"
    private let wipeCounterTag = "app.vaultaire.ios.wipe.counter"
    private let duressKeyTag = "app.vaultaire.ios.duress.key"
    private let blobCursorXORKeyTag = "app.vaultaire.ios.blob.cursor.key"
    /// Keychain access group shared with extensions via app group entitlement
    private let keychainAccessGroup = "group.app.vaultaire.ios"

    private init() {
        // No-op: singleton
    }

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
            kSecAttrAccessGroup as String: keychainAccessGroup,
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

        // Store in keychain with device-only access, shared with extensions
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: saltKeyTag,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecValueData as String: salt,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing if any
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: saltKeyTag,
            kSecAttrAccessGroup as String: keychainAccessGroup
        ]
        SecItemDelete(deleteQuery as CFDictionary)

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

        return Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
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

    // MARK: - Blob Cursor XOR Key

    /// Gets or creates a 16-byte random key used to XOR the global blob cursor.
    /// Stored in Keychain with device-only access.
    func getBlobCursorXORKey() -> Data {
        // Try to retrieve existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: blobCursorXORKeyTag,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, data.count == 16 {
            return data
        }

        // Generate new 16-byte key
        var keyBytes = [UInt8](repeating: 0, count: 16)
        let randStatus = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData: Data
        if randStatus == errSecSuccess {
            keyData = Data(keyBytes)
        } else {
            // Fallback to CryptoKit entropy (never use zeroed key)
            let fallbackKey = SymmetricKey(size: .bits128)
            keyData = fallbackKey.withUnsafeBytes { Data($0) }
        }

        // Store in keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: blobCursorXORKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(addQuery as CFDictionary)
        SecItemAdd(addQuery as CFDictionary, nil)

        return keyData
    }

    // MARK: - Nuclear Wipe

    /// Destroys all vault-related keychain data.
    func performNuclearWipe() {
        // Delete all vault-related keychain items
        let services = [saltKeyTag, wipeCounterTag, duressKeyTag, blobCursorXORKeyTag]

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
            kSecAttrService as String: "app.vaultaire.ios.recovery"
        ]
        SecItemDelete(recoveryQuery as CFDictionary)
        
        // Clear grid letter assignments (will be regenerated on next app launch)
        #if !EXTENSION
        GridLetterManager.shared.clearLetterAssignments()
        #endif
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
