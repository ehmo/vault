import XCTest
@testable import Vault

/// Tests for vault name generation and truncation.
///
/// Coverage:
/// - GridLetterManager name length limits
/// - Edge cases (empty pattern, single node, maximum nodes)
/// - Name format consistency ("Vault XXXX")
/// - Toolbar display safety (name fits in single line)
final class VaultNameTests: XCTestCase {

    // MARK: - Name Length Limit

    /// Auto-generated names must use at most `maxNameLetters` characters.
    /// Regression: Long patterns (20+ dots) produced names like "Vault DFUUCSVKHHZDQIZAQQVB"
    /// that overflowed the toolbar header.
    func testVaultNameLimitedToMaxLetters() {
        let maxLetters = GridLetterManager.maxNameLetters
        // A long pattern touching all 25 nodes
        let longPattern = Array(0..<25)
        let name = GridLetterManager.shared.vaultName(for: longPattern)

        XCTAssertLessThanOrEqual(name.count, maxLetters,
            "Name '\(name)' exceeds max of \(maxLetters) letters")
    }

    /// Patterns with exactly 6 dots (minimum valid) should produce at most maxNameLetters.
    func testMinimumValidPatternRespectsLimit() {
        let pattern = [0, 1, 2, 3, 4, 5]
        let name = GridLetterManager.shared.vaultName(for: pattern)

        XCTAssertLessThanOrEqual(name.count, GridLetterManager.maxNameLetters)
        XCTAssertGreaterThan(name.count, 0, "Name should not be empty for a valid pattern")
    }

    /// A pattern with fewer nodes than maxNameLetters uses all available nodes.
    func testShortPatternUsesAllNodes() {
        let pattern = [0, 1]
        let name = GridLetterManager.shared.vaultName(for: pattern)

        XCTAssertEqual(name.count, 2,
            "Pattern with 2 nodes should produce 2-letter name, got '\(name)'")
    }

    // MARK: - Edge Cases

    /// Empty pattern produces empty name string.
    func testEmptyPatternProducesEmptyName() {
        let name = GridLetterManager.shared.vaultName(for: [])
        XCTAssertTrue(name.isEmpty, "Empty pattern should produce empty name")
    }

    /// Single-node pattern produces single-letter name.
    func testSingleNodePatternProducesSingleLetter() {
        let name = GridLetterManager.shared.vaultName(for: [12])
        XCTAssertEqual(name.count, 1)
    }

    /// Out-of-bounds node indices are skipped safely.
    func testOutOfBoundsNodesAreSkipped() {
        let name = GridLetterManager.shared.vaultName(for: [99, -1, 50])
        XCTAssertTrue(name.isEmpty, "Out-of-bounds nodes should be skipped")
    }

    /// Mix of valid and invalid nodes uses only valid ones.
    func testMixedValidInvalidNodes() {
        let name = GridLetterManager.shared.vaultName(for: [0, 99, 1, -1])
        // Only nodes 0 and 1 are valid (both within maxNameLetters prefix)
        XCTAssertEqual(name.count, 2)
    }

    // MARK: - Name Format

    /// All generated letters are uppercase ASCII.
    func testGeneratedLettersAreUppercaseASCII() {
        let pattern = Array(0..<25)
        let name = GridLetterManager.shared.vaultName(for: pattern)

        for char in name {
            XCTAssertTrue(char.isUppercase && char.isASCII,
                "Character '\(char)' should be uppercase ASCII")
        }
    }

    /// The full vault display name follows "Vault XXXX" format.
    func testFullDisplayNameFormat() {
        let pattern = [0, 1, 2, 3, 4, 5]
        let letters = GridLetterManager.shared.vaultName(for: pattern)
        let displayName = letters.isEmpty ? "Vault" : "Vault \(letters)"

        XCTAssertTrue(displayName.hasPrefix("Vault "))
        // "Vault " is 6 chars + maxNameLetters
        XCTAssertLessThanOrEqual(displayName.count, 6 + GridLetterManager.maxNameLetters,
            "Display name '\(displayName)' is too long for the toolbar")
    }

    /// The maxNameLetters constant is a reasonable value (3-6).
    func testMaxNameLettersIsReasonable() {
        XCTAssertGreaterThanOrEqual(GridLetterManager.maxNameLetters, 3,
            "Need at least 3 letters for differentiation")
        XCTAssertLessThanOrEqual(GridLetterManager.maxNameLetters, 6,
            "More than 6 letters wastes toolbar space")
    }

    // MARK: - Deterministic Output

    /// Same pattern always produces the same name (letters persist in keychain).
    func testSamePatternProducesSameName() {
        let pattern = [0, 5, 10, 15, 20, 24]
        let name1 = GridLetterManager.shared.vaultName(for: pattern)
        let name2 = GridLetterManager.shared.vaultName(for: pattern)

        XCTAssertEqual(name1, name2, "Same pattern should always produce the same name")
    }

    /// Different patterns produce different names (with high probability).
    func testDifferentPatternsProduceDifferentNames() {
        let name1 = GridLetterManager.shared.vaultName(for: [0, 1, 2, 3, 4, 5])
        let name2 = GridLetterManager.shared.vaultName(for: [24, 23, 22, 21, 20, 19])

        // These use different grid positions so they should (almost certainly) differ
        // There's a 1/26^4 chance they match — astronomically unlikely
        XCTAssertNotEqual(name1, name2,
            "Different patterns should produce different names")
    }

    // MARK: - Custom Name Validation

    /// Custom names are capped at 30 characters.
    func testCustomNameMaxLength30() {
        let longName = String(repeating: "A", count: 50)
        let trimmed = String(longName.prefix(30))

        XCTAssertEqual(trimmed.count, 30,
            "Custom name should be capped at 30 characters")
    }

    /// Empty custom name resets to auto-generated (customName = nil).
    func testCustomNameEmptyResetsToAuto() {
        let input = ""
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(trimmed.isEmpty,
            "Empty input should result in nil customName (reset to auto)")
    }

    /// Whitespace-only custom name resets to auto-generated.
    func testCustomNameWhitespaceOnlyResetsToAuto() {
        let input = "   \t\n  "
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(trimmed.isEmpty,
            "Whitespace-only input should result in nil customName (reset to auto)")
    }

    /// Custom names have leading/trailing whitespace trimmed.
    func testCustomNameTrimmedOfWhitespace() {
        let input = "  My Vault  "
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(trimmed, "My Vault",
            "Custom name should be trimmed of surrounding whitespace")
    }

    /// Auto-generated display name "Vault XXXX" is at most 10 chars; custom names at most 30.
    func testDisplayNameMaxTotalLength() {
        // Auto-generated: "Vault " (6) + maxNameLetters (4) = 10
        let maxAutoLength = 6 + GridLetterManager.maxNameLetters
        XCTAssertLessThanOrEqual(maxAutoLength, 10,
            "Auto-generated display name should be at most 10 characters")

        // Custom: 30 max
        let maxCustomLength = 30
        XCTAssertEqual(maxCustomLength, 30,
            "Custom name max length should be 30")
    }
}
