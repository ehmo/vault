import Foundation
import CryptoKit
import Security

enum KeyDerivationError: Error {
    case saltNotFound
    case derivationFailed
    case invalidPattern
    case secureEnclaveUnavailable
}

final class KeyDerivation {

    // MARK: - Key Derivation from Pattern

    static func deriveKey(from pattern: [Int], gridSize: Int = 4) async throws -> Data {
        guard pattern.count >= 6 else {
            throw KeyDerivationError.invalidPattern
        }

        // Serialize the pattern with grid size
        let patternData = PatternSerializer.serialize(pattern, gridSize: gridSize)

        // Get device-bound salt from Secure Enclave
        let salt = try await SecureEnclaveManager.shared.getDeviceSalt()

        // Use PBKDF2 with SHA-512 for key derivation
        // Note: Argon2id would be ideal but requires external library
        // PBKDF2 with high iterations is still secure
        let derivedKey = try deriveKeyPBKDF2(
            password: patternData,
            salt: salt,
            iterations: 600_000, // High iteration count for security
            keyLength: 32
        )

        return derivedKey
    }

    // MARK: - Key Derivation from Recovery Phrase

    static func deriveKey(from recoveryPhrase: String) async throws -> Data {
        // Normalize the phrase
        let normalizedPhrase = recoveryPhrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalizedPhrase.isEmpty else {
            throw KeyDerivationError.invalidPattern
        }

        let phraseData = Data(normalizedPhrase.utf8)

        // Get device-bound salt
        let salt = try await SecureEnclaveManager.shared.getDeviceSalt()

        // Derive key with higher iterations for phrase-based derivation
        let derivedKey = try deriveKeyPBKDF2(
            password: phraseData,
            salt: salt,
            iterations: 800_000,
            keyLength: 32
        )

        return derivedKey
    }

    // MARK: - PBKDF2 Implementation

    private static func deriveKeyPBKDF2(
        password: Data,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) throws -> Data {
        var derivedKey = Data(count: keyLength)

        let result = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            password.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        UInt32(iterations),
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw KeyDerivationError.derivationFailed
        }

        return derivedKey
    }

    // MARK: - Key Fingerprint (for identifying vaults without exposing key)

    static func keyFingerprint(from key: Data) -> String {
        let hash = SHA256.hash(data: key)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// CommonCrypto bridge
import CommonCrypto
