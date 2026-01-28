import Foundation
import CloudKit
import CryptoKit

enum CloudKitSharingError: Error {
    case notAvailable
    case uploadFailed(Error)
    case downloadFailed(Error)
    case vaultNotFound
    case encryptionFailed
    case decryptionFailed
    case invalidData
}

/// Manages shared vault storage in CloudKit's public database.
/// Vaults are stored encrypted and identified by a hash of the share phrase.
final class CloudKitSharingManager {
    static let shared = CloudKitSharingManager()

    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let recordType = "SharedVault"

    private init() {
        container = CKContainer(identifier: "iCloud.com.vault.shared")
        publicDatabase = container.publicCloudDatabase
    }

    // MARK: - Vault ID and Key Derivation from Phrase

    /// Derives a vault ID from the share phrase (for looking up in CloudKit).
    /// Uses SHA256 hash of normalized phrase.
    static func vaultId(from phrase: String) -> String {
        let normalized = normalizePhrase(phrase)
        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)
        // Use first 16 bytes (32 hex chars) as vault ID
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Derives an encryption key from the share phrase.
    /// Uses PBKDF2 with a fixed salt (since this key must be derivable on any device).
    static func deriveShareKey(from phrase: String) throws -> Data {
        let normalized = normalizePhrase(phrase)
        let password = Data(normalized.utf8)

        // Fixed salt for share keys (must be same across all devices)
        // This is intentionally not device-bound unlike the main vault key
        let salt = "vault-share-v1-salt".data(using: .utf8)!

        var derivedKey = Data(count: 32)

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
                        UInt32(800_000), // High iteration count
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw CloudKitSharingError.encryptionFailed
        }

        return derivedKey
    }

    /// Normalizes a phrase for consistent hashing/derivation.
    private static func normalizePhrase(_ phrase: String) -> String {
        phrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Upload Shared Vault

    /// Uploads an encrypted vault to CloudKit's public database.
    /// - Parameters:
    ///   - vaultData: The vault data to share (index + files)
    ///   - phrase: The share phrase (used to derive vault ID and encryption key)
    func uploadSharedVault(_ vaultData: SharedVaultData, phrase: String) async throws {
        let vaultId = Self.vaultId(from: phrase)
        let shareKey = try Self.deriveShareKey(from: phrase)

        // Serialize and encrypt the vault data
        let encoded = try JSONEncoder().encode(vaultData)
        let encrypted = try CryptoEngine.shared.encrypt(encoded, with: shareKey)

        // Create or update the CloudKit record
        let recordID = CKRecord.ID(recordName: vaultId)

        // Try to fetch existing record first
        let existingRecord: CKRecord?
        do {
            existingRecord = try await publicDatabase.record(for: recordID)
        } catch {
            existingRecord = nil
        }

        let record = existingRecord ?? CKRecord(recordType: recordType, recordID: recordID)

        // Store encrypted data as asset (better for large data)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try encrypted.write(to: tempURL)

        record["encryptedData"] = CKAsset(fileURL: tempURL)
        record["updatedAt"] = Date()
        record["version"] = 1

        do {
            try await publicDatabase.save(record)
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw CloudKitSharingError.uploadFailed(error)
        }
    }

    // MARK: - Download Shared Vault

    /// Downloads and decrypts a shared vault from CloudKit.
    /// - Parameter phrase: The share phrase
    /// - Returns: The decrypted vault data
    func downloadSharedVault(phrase: String) async throws -> SharedVaultData {
        let vaultId = Self.vaultId(from: phrase)
        let shareKey = try Self.deriveShareKey(from: phrase)

        let recordID = CKRecord.ID(recordName: vaultId)

        let record: CKRecord
        do {
            record = try await publicDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            throw CloudKitSharingError.vaultNotFound
        } catch {
            throw CloudKitSharingError.downloadFailed(error)
        }

        guard let asset = record["encryptedData"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudKitSharingError.invalidData
        }

        let encrypted = try Data(contentsOf: fileURL)

        do {
            let decrypted = try CryptoEngine.shared.decrypt(encrypted, with: shareKey)
            return try JSONDecoder().decode(SharedVaultData.self, from: decrypted)
        } catch {
            throw CloudKitSharingError.decryptionFailed
        }
    }

    // MARK: - Check Vault Exists

    /// Checks if a shared vault exists without downloading it.
    func sharedVaultExists(phrase: String) async -> Bool {
        let vaultId = Self.vaultId(from: phrase)
        let recordID = CKRecord.ID(recordName: vaultId)

        do {
            _ = try await publicDatabase.record(for: recordID)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Delete Shared Vault

    /// Deletes a shared vault from CloudKit.
    func deleteSharedVault(phrase: String) async throws {
        let vaultId = Self.vaultId(from: phrase)
        let recordID = CKRecord.ID(recordName: vaultId)

        do {
            try await publicDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Already deleted, that's fine
        } catch {
            throw CloudKitSharingError.downloadFailed(error)
        }
    }

    // MARK: - Check iCloud Availability

    func checkiCloudStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }
}

// MARK: - Shared Vault Data Structure

/// The data structure stored in CloudKit for a shared vault.
struct SharedVaultData: Codable {
    let files: [SharedFile]
    let metadata: SharedVaultMetadata
    let createdAt: Date
    let updatedAt: Date

    struct SharedFile: Codable, Identifiable {
        let id: UUID
        let filename: String
        let mimeType: String
        let size: Int
        let encryptedContent: Data
        let createdAt: Date
    }

    struct SharedVaultMetadata: Codable {
        let ownerFingerprint: String // Key fingerprint of original creator
        let sharedAt: Date
    }
}

// CommonCrypto bridge
import CommonCrypto
