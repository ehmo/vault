import Foundation

struct PatternSetupCoordinator {
    var deriveKey: ([Int], Int) async throws -> Data = { pattern, gridSize in
        try await KeyDerivation.deriveKey(from: pattern, gridSize: gridSize)
    }
    var vaultExists: (Data) -> Bool = { key in
        VaultStorage.shared.vaultHasFiles(for: VaultKey(key))
    }
    var saveIndex: (VaultStorage.VaultIndex, Data) throws -> Void = { index, key in
        try VaultStorage.shared.saveIndex(index, with: VaultKey(key))
    }
    var saveRecoveryPhrase: (String, [Int], Int, Data) async throws -> Void = { phrase, pattern, gridSize, key in
        try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
            phrase: phrase, pattern: pattern, gridSize: gridSize, patternKey: key
        )
    }

    enum SetupResult {
        case success(key: Data)
        case duplicatePattern
        case error(String)
    }

    /// Save a new pattern: derive key, check uniqueness, create vault index, save recovery phrase.
    func savePattern(_ pattern: [Int], gridSize: Int, phrase: String) async -> SetupResult {
        do {
            let key = try await deriveKey(pattern, gridSize)

            if vaultExists(key) {
                return .duplicatePattern
            }

            // Create empty vault index. loadIndex auto-creates a proper v3 index with master key when none exists.
            let emptyIndex = try VaultStorage.shared.loadIndex(with: VaultKey(key))
            try saveIndex(emptyIndex, key)

            try await saveRecoveryPhrase(phrase, pattern, gridSize, key)

            return .success(key: key)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Save a custom recovery phrase for an already-created vault.
    func saveCustomPhrase(_ phrase: String, pattern: [Int], gridSize: Int, key: Data) async -> SetupResult {
        do {
            try await saveRecoveryPhrase(phrase, pattern, gridSize, key)
            return .success(key: key)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
