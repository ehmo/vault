import Foundation
import CryptoKit
import Security

/// Manages recovery phrases for all vaults in a privacy-preserving way.
/// Stores all recovery data in a single encrypted blob in Keychain to prevent vault enumeration.
final class RecoveryPhraseManager {
    static let shared = RecoveryPhraseManager()
    
    private let keychainService = "com.vault.recovery"
    private let keychainAccount = "recovery_data"
    
    private init() {}
    
    // MARK: - Data Structures
    
    /// Contains all recovery data for all vaults in a single encrypted structure
    private struct RecoveryDatabase: Codable {
        var vaults: [VaultRecoveryInfo]
        
        struct VaultRecoveryInfo: Codable {
            let vaultKeyHash: String // SHA256 hash of vault key for identification
            let phrase: String
            let pattern: [Int]
            let gridSize: Int
            let patternKey: Data
            let createdAt: Date
        }
    }
    
    // MARK: - Save Recovery Phrase
    
    /// Saves recovery phrase and mapping for a vault
    func saveRecoveryPhrase(
        phrase: String,
        pattern: [Int],
        gridSize: Int,
        patternKey: Data
    ) async throws {
        #if DEBUG
        print("💾 [RecoveryManager] Saving recovery phrase for vault")
        #endif
        
        // Load existing database
        var database = try await loadDatabase()
        
        // Create vault key hash for identification (privacy-preserving)
        let keyHash = SHA256.hash(data: patternKey)
        let keyHashString = keyHash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Remove existing entry if present (for regeneration)
        database.vaults.removeAll { $0.vaultKeyHash == keyHashString }
        
        // Add new entry
        let info = RecoveryDatabase.VaultRecoveryInfo(
            vaultKeyHash: keyHashString,
            phrase: phrase,
            pattern: pattern,
            gridSize: gridSize,
            patternKey: patternKey,
            createdAt: Date()
        )
        database.vaults.append(info)
        
        // Save database
        try await saveDatabase(database)
        
        #if DEBUG
        print("✅ [RecoveryManager] Recovery phrase saved. Total vaults: \(database.vaults.count)")
        #endif
    }
    
    // MARK: - Load Recovery Phrase
    
    /// Loads the recovery phrase for a specific vault
    func loadRecoveryPhrase(for vaultKey: Data) async throws -> String? {
        let database = try await loadDatabase()
        
        let keyHash = SHA256.hash(data: vaultKey)
        let keyHashString = keyHash.compactMap { String(format: "%02x", $0) }.joined()
        
        guard let info = database.vaults.first(where: { $0.vaultKeyHash == keyHashString }) else {
            #if DEBUG
            print("⚠️ [RecoveryManager] No recovery phrase found for this vault")
            #endif
            return nil
        }
        
        return info.phrase
    }
    
    // MARK: - Recover Vault
    
    /// Attempts to recover a vault using a recovery phrase
    func recoverVault(using phrase: String) async throws -> Data {
        #if DEBUG
        print("🔑 [RecoveryManager] Attempting vault recovery with phrase")
        #endif
        
        let database = try await loadDatabase()
        
        // Find vault with matching phrase
        guard let info = database.vaults.first(where: { $0.phrase.lowercased() == phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }) else {
            #if DEBUG
            print("❌ [RecoveryManager] No vault found with this phrase")
            #endif
            throw RecoveryError.invalidPhrase
        }
        
        #if DEBUG
        print("✅ [RecoveryManager] Vault found! Returning pattern key")
        #endif
        
        return info.patternKey
    }
    
    // MARK: - Regenerate Recovery Phrase
    
    /// Regenerates the recovery phrase for a vault (keeping the same vault key)
    func regenerateRecoveryPhrase(for vaultKey: Data, customPhrase: String? = nil) async throws -> String {
        #if DEBUG
        print("🔄 [RecoveryManager] Regenerating recovery phrase")
        #endif
        
        var database = try await loadDatabase()
        
        let keyHash = SHA256.hash(data: vaultKey)
        let keyHashString = keyHash.compactMap { String(format: "%02x", $0) }.joined()
        
        guard let index = database.vaults.firstIndex(where: { $0.vaultKeyHash == keyHashString }) else {
            throw RecoveryError.vaultNotFound
        }
        
        let oldInfo = database.vaults[index]
        
        // Generate new phrase or use custom
        let newPhrase: String
        if let customPhrase = customPhrase {
            // Validate custom phrase
            let validation = RecoveryPhraseGenerator.shared.validatePhrase(customPhrase)
            guard validation.isAcceptable else {
                throw RecoveryError.weakPhrase(message: validation.message)
            }
            newPhrase = customPhrase
        } else {
            newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
        }
        
        // Update with new phrase
        database.vaults[index] = RecoveryDatabase.VaultRecoveryInfo(
            vaultKeyHash: oldInfo.vaultKeyHash,
            phrase: newPhrase,
            pattern: oldInfo.pattern,
            gridSize: oldInfo.gridSize,
            patternKey: oldInfo.patternKey,
            createdAt: Date() // Update creation date
        )
        
        try await saveDatabase(database)
        
        #if DEBUG
        print("✅ [RecoveryManager] Recovery phrase regenerated")
        #endif
        
        return newPhrase
    }
    
    // MARK: - Delete Vault Recovery Data
    
    /// Removes recovery data for a specific vault
    func deleteRecoveryData(for vaultKey: Data) async throws {
        var database = try await loadDatabase()
        
        let keyHash = SHA256.hash(data: vaultKey)
        let keyHashString = keyHash.compactMap { String(format: "%02x", $0) }.joined()
        
        database.vaults.removeAll { $0.vaultKeyHash == keyHashString }
        
        try await saveDatabase(database)
        
        #if DEBUG
        print("🗑️ [RecoveryManager] Recovery data deleted. Remaining vaults: \(database.vaults.count)")
        #endif
    }
    
    // MARK: - Database Management
    
    private func loadDatabase() async throws -> RecoveryDatabase {
        // Try to load from Keychain
        guard let encryptedData = try loadFromKeychain() else {
            // No existing database - return empty
            return RecoveryDatabase(vaults: [])
        }
        
        // Decrypt database
        let masterKey = try await getMasterKey()
        let symmetricKey = SymmetricKey(data: masterKey)
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        return try JSONDecoder().decode(RecoveryDatabase.self, from: decryptedData)
    }
    
    private func saveDatabase(_ database: RecoveryDatabase) async throws {
        // Encode database
        let jsonData = try JSONEncoder().encode(database)
        
        // Encrypt with master key
        let masterKey = try await getMasterKey()
        let symmetricKey = SymmetricKey(data: masterKey)
        let sealedBox = try AES.GCM.seal(jsonData, using: symmetricKey)
        
        guard let combined = sealedBox.combined else {
            throw RecoveryError.encryptionFailed
        }
        
        // Save to Keychain
        try saveToKeychain(combined)
    }
    
    // MARK: - Keychain Operations
    
    private func loadFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw RecoveryError.keychainError(status: status)
        }
        
        return result as? Data
    }
    
    private func saveToKeychain(_ data: Data) throws {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw RecoveryError.keychainError(status: status)
        }
    }
    
    // MARK: - Master Key Management
    
    /// Gets or creates the master encryption key for the recovery database
    /// This key is stored in Keychain and never leaves the device
    private func getMasterKey() async throws -> Data {
        let masterKeyAccount = "recovery_master_key"
        
        // Try to load existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let keyData = result as? Data {
            return keyData
        }
        
        // Generate new master key
        var keyData = Data(count: 32)
        let result2 = keyData.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        
        guard result2 == errSecSuccess else {
            throw RecoveryError.keyGenerationFailed
        }
        
        // Save master key to Keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw RecoveryError.keychainError(status: addStatus)
        }
        
        return keyData
    }
    
    // MARK: - Destroy All Data (for duress)
    
    /// Completely destroys all recovery data (cannot be undone)
    func destroyAllRecoveryData() throws {
        #if DEBUG
        print("💣 [RecoveryManager] DESTROYING ALL RECOVERY DATA")
        #endif
        
        // Delete recovery database
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Delete master key
        let masterKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "recovery_master_key"
        ]
        SecItemDelete(masterKeyQuery as CFDictionary)
        
        #if DEBUG
        print("✅ [RecoveryManager] All recovery data destroyed")
        #endif
    }
}

// MARK: - Errors

enum RecoveryError: LocalizedError {
    case invalidPhrase
    case vaultNotFound
    case weakPhrase(message: String)
    case encryptionFailed
    case keychainError(status: OSStatus)
    case keyGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPhrase:
            return "The recovery phrase you entered is incorrect or doesn't match any vault."
        case .vaultNotFound:
            return "No recovery data found for this vault."
        case .weakPhrase(let message):
            return message
        case .encryptionFailed:
            return "Failed to encrypt recovery data."
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .keyGenerationFailed:
            return "Failed to generate encryption key."
        }
    }
}
