import BackgroundTasks
import Foundation
import os.log

/// Handles duress pattern functionality.
/// When the duress pattern is entered, all other vaults are silently destroyed.
actor DuressHandler {
    static let shared = DuressHandler()

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "Duress")

    private let secureEnclave = SecureEnclaveManager.shared
    private let storage = VaultStorage.shared

    private init() {
        // No-op: singleton
    }

    // MARK: - Duress Pattern Setup

    /// Sets a vault as the duress vault.
    /// When this pattern is entered, all OTHER vault data will be destroyed.
    func setAsDuressVault(key: Data) async throws {
        let fingerprint = KeyDerivation.keyFingerprint(from: key)
        try secureEnclave.setDuressKeyFingerprint(fingerprint)
    }

    /// Type-safe overload accepting any SymmetricKeyData (VaultKey, MasterKey, ShareKey).
    func setAsDuressVault(key: some SymmetricKeyData) async throws {
        try await setAsDuressVault(key: key.rawBytes)
    }

    /// Checks if a key corresponds to the duress vault.
    func isDuressKey(_ key: Data) -> Bool {
        guard let storedFingerprint = secureEnclave.getDuressKeyFingerprint() else {
            return false
        }
        let keyFingerprint = KeyDerivation.keyFingerprint(from: key)
        return keyFingerprint == storedFingerprint
    }

    /// Type-safe overload accepting any SymmetricKeyData.
    func isDuressKey(_ key: some SymmetricKeyData) -> Bool {
        isDuressKey(key.rawBytes)
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
    /// All shared vaults created by this user are also revoked to prevent access.
    func triggerDuress(preservingKey duressKey: Data) async {
        Self.logger.info("Triggering duress mode")
        
        // Strategy: The duress vault's encrypted index and blob data are stored per-key.
        // We need to:
        // 1. Backup the duress vault's encrypted index file (it's already encrypted with the vault key)
        // 2. Revoke all active shares to prevent others from accessing shared data
        // 3. Destroy all vault data and recovery phrases
        // 4. Restore the duress vault's encrypted index
        // 5. The duress pattern will still derive the same key
        
        // 1. Load and backup the duress vault's index data before destruction
        guard let duressIndex = try? storage.loadIndex(with: VaultKey(duressKey)) else {
            Self.logger.error("Could not load duress vault index")
            await destroyAllNonDuressData(duressKey: nil)
            return
        }
        
        Self.logger.debug("Duress vault index backed up: \(duressIndex.files.count) files")
        
        // 2. REVOKE ALL ACTIVE SHARES
        // Before destroying data, revoke all shares to prevent User 2 from accessing data
        // Note: We can only decrypt the duress vault index (we have its key).
        // Non-duress indexes are encrypted with unknown keys and are destroyed in step 4.
        await revokeActiveShares(from: duressIndex)
        
        // 3. Reset iCloud backup clock to prevent auto-backup from overwriting
        // the full backup with duress-only data. Gives 24h restore window.
        resetBackupClock()

        // 4. Destroy all recovery phrase data EXCEPT for the duress vault
        do {
            try RecoveryPhraseManager.shared.destroyAllRecoveryData()
            Self.logger.debug("All recovery data destroyed")
        } catch {
            Self.logger.error("Error destroying recovery data: \(error.localizedDescription, privacy: .public)")
        }
        
        // 5. The blob file contains data for ALL vaults
        // Solution: Keep the blob intact, but all other indexes will be destroyed
        // Only the duress vault's index will exist, so only it can be accessed
        storage.destroyAllIndexesExcept(VaultKey(duressKey))

        Self.logger.debug("All vault indexes destroyed except duress vault")

        // 6. Regenerate recovery phrase for duress vault only
        let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
        do {
            try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                phrase: newPhrase,
                pattern: [],
                gridSize: 5,
                patternKey: duressKey
            )
            
            // 7. Clear the duress vault designation
            // This allows the user to continue using this vault normally after duress is triggered
            clearDuressVault()
            
            Self.logger.info("Duress mode complete, \(duressIndex.files.count) files preserved, \(duressIndex.activeShares?.count ?? 0) shares revoked, designation cleared")
        } catch {
            Self.logger.error("Error creating new recovery phrase: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Revokes active shares from the given vault index.
    /// Only the duress vault index is decryptable (we have its key);
    /// other vault indexes are encrypted and destroyed separately.
    private func revokeActiveShares(from index: VaultStorage.VaultIndex) async {
        guard let activeShares = index.activeShares, !activeShares.isEmpty else {
            Self.logger.debug("No active shares to revoke")
            return
        }

        for share in activeShares {
            do {
                try await CloudKitSharingManager.shared.revokeShare(shareVaultId: share.id)
                Self.logger.info("Revoked share \(share.id) during duress")
            } catch {
                Self.logger.error("Failed to revoke share \(share.id) during duress: \(error.localizedDescription)")
            }
        }
    }

    /// Resets iCloud backup state to prevent auto-backup from overwriting
    /// the existing full backup with post-duress (minimal) data.
    /// - Stamps lastBackupTimestamp to now → 24h before next auto-backup
    /// - Clears staged/pending backup chunks so they can't upload
    /// - Cancels scheduled background backup tasks
    private func resetBackupClock() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: "lastBackupTimestamp"
        )
        iCloudBackupManager.shared.clearStagingDirectory()
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: iCloudBackupManager.backgroundBackupTaskIdentifier
        )
        Self.logger.info("iCloud backup clock reset — 24h restore window active")
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
            storage.destroyAllIndexesExcept(VaultKey(key))
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
