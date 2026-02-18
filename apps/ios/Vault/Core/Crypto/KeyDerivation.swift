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

    static nonisolated func deriveKey(from pattern: [Int], gridSize: Int = 5) async throws -> Data {
        #if !EXTENSION
        let span = EmbraceManager.shared.startTransaction(name: "crypto.pbkdf2", operation: "crypto.pbkdf2")
        span.setTag(value: "600000", key: "iterations")
        #endif

        guard pattern.count >= 6 else {
            #if !EXTENSION
            span.finish(status: .invalidArgument)
            #endif
            throw KeyDerivationError.invalidPattern
        }

        // Serialize the pattern with grid size
        let patternData = PatternSerializer.serialize(pattern, gridSize: gridSize)

        // Get device-bound salt from Secure Enclave
        let salt: Data
        do {
            salt = try await SecureEnclaveManager.shared.getDeviceSalt()
        } catch {
            #if !EXTENSION
            EmbraceManager.shared.captureError(error)
            span.finish(status: .internalError)
            #endif
            throw error
        }

        // Use PBKDF2 with SHA-512 for key derivation
        // Note: Argon2id would be ideal but requires external library
        // PBKDF2 with high iterations is still secure
        do {
            let derivedKey = try deriveKeyPBKDF2(
                password: patternData,
                salt: salt,
                iterations: 600_000, // High iteration count for security
                keyLength: 32
            )
            #if !EXTENSION
            span.finish(status: .ok)
            #endif
            return derivedKey
        } catch {
            #if !EXTENSION
            EmbraceManager.shared.captureError(error)
            span.finish(status: .internalError)
            #endif
            throw error
        }
    }

    // MARK: - Key Derivation from Recovery Phrase

    #if !EXTENSION
    static nonisolated func deriveKey(from recoveryPhrase: String) throws -> Data {
        let span = EmbraceManager.shared.startTransaction(name: "crypto.pbkdf2_recovery", operation: "crypto.pbkdf2_recovery")
        span.setTag(value: "800000", key: "iterations")

        // Normalize the phrase
        let normalizedPhrase = recoveryPhrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalizedPhrase.isEmpty else {
            span.finish(status: .invalidArgument)
            throw KeyDerivationError.invalidPattern
        }

        let phraseData = Data(normalizedPhrase.utf8)

        // Use a fixed, phrase-derived salt for recovery phrases
        // This allows the phrase to work across devices and app reinstalls
        // The salt is derived from a fixed prefix + the phrase itself
        let saltString = "vault-recovery-v1-\(normalizedPhrase)"
        let salt = SHA256.hash(data: Data(saltString.utf8))
        let saltData = Data(salt)

        // Derive key with higher iterations for phrase-based derivation
        do {
            let derivedKey = try deriveKeyPBKDF2(
                password: phraseData,
                salt: saltData,
                iterations: 800_000,
                keyLength: 32
            )
            span.finish(status: .ok)
            return derivedKey
        } catch {
            EmbraceManager.shared.captureError(error)
            span.finish(status: .internalError)
            throw error
        }
    }
    #endif

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

    // MARK: - Share Key Derivation (Device-Independent)

    #if !EXTENSION
    /// Derives a share key from a share phrase using per-phrase salt.
    /// The salt is SHA256("vault-share-v2-" + normalized_phrase), ensuring
    /// each phrase gets a unique salt while remaining device-independent.
    static func deriveShareKey(from phrase: String) throws -> Data {
        let span = EmbraceManager.shared.startTransaction(name: "crypto.pbkdf2_share", operation: "crypto.pbkdf2_share")
        span.setTag(value: "800000", key: "iterations")

        let normalized = normalizeSharePhrase(phrase)
        let phraseData = Data(normalized.utf8)

        // Per-phrase salt: SHA256 of a versioned prefix + the normalized phrase
        let saltInput = "vault-share-v2-" + normalized
        let salt = Data(SHA256.hash(data: Data(saltInput.utf8)))

        do {
            let derivedKey = try deriveKeyPBKDF2(
                password: phraseData,
                salt: salt,
                iterations: 800_000,
                keyLength: 32
            )
            span.finish(status: .ok)
            return derivedKey
        } catch {
            EmbraceManager.shared.captureError(error)
            span.finish(status: .internalError)
            throw error
        }
    }

    /// Legacy share key derivation using the fixed salt from v1.
    /// Used as a fallback when syncing existing shares created before per-phrase salt.
    static func deriveShareKeyLegacy(from phrase: String) throws -> Data {
        let normalized = normalizeSharePhrase(phrase)
        let phraseData = Data(normalized.utf8)
        let salt = "vault-share-v1-salt".data(using: .utf8)!
        return try deriveKeyPBKDF2(
            password: phraseData,
            salt: salt,
            iterations: 800_000,
            keyLength: 32
        )
    }

    /// Generates a vault ID from a share phrase for CloudKit lookup.
    static func shareVaultId(from phrase: String) -> String {
        let normalized = normalizeSharePhrase(phrase)
        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)
        // Use first 16 bytes (32 hex chars) as vault ID
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Normalizes a share phrase for consistent key derivation.
    private static func normalizeSharePhrase(_ phrase: String) -> String {
        phrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    #endif
}

// CommonCrypto bridge
import CommonCrypto
