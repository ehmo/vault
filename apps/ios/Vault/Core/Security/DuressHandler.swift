import Foundation
import os.log

/// Handles duress pattern functionality.
/// When the duress pattern is entered, all other vaults are silently destroyed.
actor DuressHandler {
    static let shared = DuressHandler()

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "Duress")

    private let secureEnclave = SecureEnclaveManager.shared
    private let storage = VaultStorage.shared

    private init() { /* No-op */ }

    // MARK: - Duress Pattern Setup

    /// Sets a vault as the duress vault.
    /// When this pattern is entered, all OTHER vault data will be destroyed.
    func setAsDuressVault(key: Data) async throws {
        let fingerprint = KeyDerivation.keyFingerprint(from: key)
        try secureEnclave.setDuressKeyFingerprint(fingerprint)
    }

    /// Checks if a key corresponds to the duress vault.
    func isDuressKey(_ key: Data) -> Bool {
        guard let storedFingerprint = secureEnclave.getDuressKeyFingerprint() else {
            return false
        }
        let keyFingerprint = KeyDerivation.keyFingerprint(from: key)
        return keyFingerprint == storedFingerprint
    }

    /// Clears the duress vault setting.
    func clearDuressVault() {
        secureEnclave.clearDuressKeyFingerprint()
    }

    /// Whether a duress vault is currently configured.
    var hasDuressVault: Bool {
        secureEnclave.getDuressKeyFingerprint() != nil
    }

    // MARK: - Duress Trigger

    /// Triggers duress mode: destroys all vault data EXCEPT the duress vault.
    /// This happens silently - no UI indication.
    /// The duress vault remains fully functional to appear legitimate.
    /// After triggering, the vault is no longer marked as the duress vault.
    func triggerDuress(preservingKey duressKey: Data) async {
        Self.logger.info("Triggering duress mode")
        
        // Strategy: The duress vault's encrypted index and blob data are stored per-key.
        // We need to:
        // 1. Backup the duress vault's encrypted index file (it's already encrypted with the vault key)
        // 2. Destroy all vault data and recovery phrases
        // 3. Regenerate device salt (invalidates all keys)
        // 4. Restore the duress vault's encrypted index
        // 5. The duress pattern will still derive the same key (salt is per-device, not per-pattern)
        
        // Actually, regenerating the salt will break the key derivation!
        // Better strategy: Just destroy all OTHER vault indexes, but leave the duress one intact
        
        // 1. Load and backup the duress vault's index data before destruction
        guard let duressIndex = try? storage.loadIndex(with: duressKey) else {
            Self.logger.error("Could not load duress vault index")
            await destroyAllNonDuressData(duressKey: nil)
            return
        }
        
        Self.logger.debug("Duress vault index backed up: \(duressIndex.files.count) files")
        
        // 2. Destroy all recovery phrase data EXCEPT for the duress vault
        // Actually, destroy ALL recovery data - we'll regenerate for duress vault only
        do {
            try RecoveryPhraseManager.shared.destroyAllRecoveryData()
            Self.logger.debug("All recovery data destroyed")
        } catch {
            Self.logger.error("Error destroying recovery data: \(error.localizedDescription, privacy: .public)")
        }
        
        // 3. The blob file contains data for ALL vaults
        // We can't selectively destroy other vaults' data without breaking the duress vault
        // Solution: Keep the blob intact, but all other indexes will be destroyed
        // Only the duress vault's index will exist, so only it can be accessed
        
        // Don't regenerate salt - that would invalidate the duress key too!
        // Instead, just delete all index files except the duress vault's index
        storage.destroyAllIndexesExcept(duressKey)
        
        Self.logger.debug("All vault indexes destroyed except duress vault")
        
        // 5. Regenerate recovery phrase for duress vault only
        let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
        do {
            try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                phrase: newPhrase,
                pattern: [], // We don't know the pattern, but the phrase is what matters
                gridSize: 5,
                patternKey: duressKey
            )
            
            // 6. Clear the duress vault designation
            // This allows the user to continue using this vault normally after duress is triggered
            clearDuressVault()
            
            Self.logger.info("Duress mode complete, \(duressIndex.files.count) files preserved, designation cleared")
        } catch {
            Self.logger.error("Error creating new recovery phrase: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func destroyAllNonDuressData(duressKey: Data?) async {
        Self.logger.info("Destroying all vault data")
        
        // Destroy all recovery data (continue wipe even if this fails)
        do {
            try RecoveryPhraseManager.shared.destroyAllRecoveryData()
        } catch {
            // Wipe must proceed regardless — log for debugging
        }
        
        // If we have a duress key, preserve its index
        if let key = duressKey {
            storage.destroyAllIndexesExcept(key)
        } else {
            // Otherwise destroy everything
            storage.destroyAllVaultData()
        }

        // Clear the wipe counter
        secureEnclave.resetWipeCounter()
    }

    // MARK: - Nuclear Option

    /// Complete wipe of all data including the duress vault.
    /// User must confirm this action through UI.
    /// - Parameter secure: If true, overwrites all blob files with random data (~3s/blob).
    ///   If false (default), just deletes indexes + keychain — keys gone = data unrecoverable.
    func performNuclearWipe(secure: Bool = false) async {
        // 1. Destroy all keychain data
        secureEnclave.performNuclearWipe()

        // 2. Destroy all vault data (indexes)
        storage.destroyAllVaultData()

        // 3. Secure overwrite all blobs if requested
        if secure {
            storage.secureWipeAllBlobs()
        }

        // 4. Clear all user defaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // 5. Clear this handler's state
        clearDuressVault()
    }
}
