import Foundation
import Security
import CryptoKit
import os.log

/// Manages random letter assignments for grid nodes.
/// Letters are randomly assigned once and persist in the keychain.
/// They are reset when the app is deleted/reinstalled (keychain is cleared).
final class GridLetterManager {
    static let shared = GridLetterManager()

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "GridLetters")

    private let letterAssignmentTag = "app.vaultaire.ios.grid.letters"
    private let gridSize = 5 // 5x5 grid
    private let totalNodes = 25 // 5x5 = 25 nodes
    
    private init() {
        // No-op: singleton
    }

    // MARK: - Letter Assignment
    
    /// Gets the current letter assignments for all grid nodes.
    /// If no assignments exist, generates new random ones.
    func getLetterAssignments() -> [Character] {
        // Try to retrieve existing assignments
        if let existingLetters = try? retrieveLetterAssignments() {
            return existingLetters
        }
        
        // Generate and store new random letter assignments
        let newLetters = generateRandomLetters()
        try? storeLetterAssignments(newLetters)
        return newLetters
    }
    
    /// Maximum number of letters used from the pattern for auto-generated vault names.
    /// 4 letters gives 456,976 combinations (26^4) — plenty for differentiation
    /// while keeping the toolbar title compact (e.g. "Vault DKVS").
    static let maxNameLetters = 4

    /// Generates a vault name from a pattern using the letter assignments.
    /// Pattern is a sequence of node indices (0-24 for 5x5 grid).
    /// Only the first `maxNameLetters` nodes are used to keep names short.
    func vaultName(for pattern: [Int]) -> String {
        let letters = getLetterAssignments()

        var name = ""
        for nodeIndex in pattern.prefix(Self.maxNameLetters) {
            guard nodeIndex >= 0 && nodeIndex < letters.count else {
                continue
            }
            name.append(letters[nodeIndex])
        }

        return name
    }
    
    // MARK: - Private Methods
    
    private func generateRandomLetters() -> [Character] {
        let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var letters: [Character] = []
        
        for _ in 0..<totalNodes {
            // Pick a random letter
            let randomLetter = alphabet.randomElement() ?? "A"
            letters.append(randomLetter)
        }
        
        Self.logger.debug("Generated new random letter assignments")
        
        return letters
    }
    
    private func retrieveLetterAssignments() throws -> [Character] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: letterAssignmentTag,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: "GridLetterManager", code: 1, userInfo: nil)
        }
        
        // Decode the letter assignments
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GridLetterManager", code: 2, userInfo: nil)
        }
        
        let letters = Array(string)
        
        Self.logger.debug("Retrieved existing letter assignments from keychain")
        
        return letters
    }
    
    private func storeLetterAssignments(_ letters: [Character]) throws {
        let letterString = String(letters)
        let data = Data(letterString.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: letterAssignmentTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing if any
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "GridLetterManager", code: 3, userInfo: nil)
        }
        
        Self.logger.debug("Stored letter assignments in keychain")
    }
    
    /// Clears all letter assignments (used during nuclear wipe).
    /// Letter assignments will be regenerated on next access.
    func clearLetterAssignments() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: letterAssignmentTag
        ]
        SecItemDelete(query as CFDictionary)
        
        Self.logger.debug("Cleared all letter assignments")
    }
}
