import XCTest
@testable import Vault

final class KeyDerivationTests: XCTestCase {

    // MARK: - keyFingerprint: Determinism

    func testKeyFingerprintIsDeterministic() {
        let key = Data(repeating: 0xAB, count: 32)

        let fingerprint1 = KeyDerivation.keyFingerprint(from: key)
        let fingerprint2 = KeyDerivation.keyFingerprint(from: key)

        XCTAssertEqual(fingerprint1, fingerprint2, "Same key should always produce the same fingerprint")
    }

    func testKeyFingerprintIsHexString() {
        let key = Data(repeating: 0x42, count: 32)
        let fingerprint = KeyDerivation.keyFingerprint(from: key)

        // Fingerprint uses first 8 bytes of SHA-256 hash, each as 2 hex chars = 16 hex chars
        XCTAssertEqual(fingerprint.count, 16, "Fingerprint should be 16 hex characters (8 bytes)")

        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        for char in fingerprint.unicodeScalars {
            XCTAssertTrue(hexCharacterSet.contains(char),
                          "Fingerprint should only contain lowercase hex characters, got '\(char)'")
        }
    }

    // MARK: - keyFingerprint: Different Keys Produce Different Fingerprints

    func testDifferentKeysProduceDifferentFingerprints() {
        let keyA = Data(repeating: 0xAA, count: 32)
        let keyB = Data(repeating: 0xBB, count: 32)

        let fingerprintA = KeyDerivation.keyFingerprint(from: keyA)
        let fingerprintB = KeyDerivation.keyFingerprint(from: keyB)

        XCTAssertNotEqual(fingerprintA, fingerprintB,
                           "Different keys should produce different fingerprints")
    }

    func testSlightlyDifferentKeysProduceDifferentFingerprints() {
        let keyA = Data(repeating: 0x00, count: 32)
        var keyB = Data(repeating: 0x00, count: 32)
        keyB[0] = 0x01 // Differ by a single bit flip

        let fingerprintA = KeyDerivation.keyFingerprint(from: keyA)
        let fingerprintB = KeyDerivation.keyFingerprint(from: keyB)

        XCTAssertNotEqual(fingerprintA, fingerprintB,
                           "Keys differing by one byte should produce different fingerprints")
    }

    func testKeyFingerprintEmptyKey() {
        let emptyKey = Data()
        let fingerprint = KeyDerivation.keyFingerprint(from: emptyKey)

        // Should still produce a valid fingerprint (SHA-256 of empty data)
        XCTAssertEqual(fingerprint.count, 16,
                       "Empty key should still produce a 16-char hex fingerprint")
    }

    // MARK: - normalizeSharePhrase (tested indirectly via shareVaultId)

    func testNormalizeSharePhraseHandlesExtraSpaces() {
        // Extra internal spaces should be collapsed
        let id1 = KeyDerivation.shareVaultId(from: "apple banana cherry")
        let id2 = KeyDerivation.shareVaultId(from: "apple  banana   cherry")

        XCTAssertEqual(id1, id2,
                       "Extra internal spaces should be normalized to produce the same vault ID")
    }

    func testNormalizeSharePhraseHandlesMixedCase() {
        let id1 = KeyDerivation.shareVaultId(from: "apple banana cherry")
        let id2 = KeyDerivation.shareVaultId(from: "Apple Banana Cherry")
        let id3 = KeyDerivation.shareVaultId(from: "APPLE BANANA CHERRY")

        XCTAssertEqual(id1, id2,
                       "Mixed case should be normalized to lowercase")
        XCTAssertEqual(id1, id3,
                       "Uppercase should be normalized to lowercase")
    }

    func testNormalizeSharePhraseHandlesLeadingTrailingWhitespace() {
        let id1 = KeyDerivation.shareVaultId(from: "apple banana cherry")
        let id2 = KeyDerivation.shareVaultId(from: "  apple banana cherry  ")
        let id3 = KeyDerivation.shareVaultId(from: "\tapple banana cherry\n")

        XCTAssertEqual(id1, id2,
                       "Leading/trailing spaces should be trimmed")
        XCTAssertEqual(id1, id3,
                       "Leading/trailing whitespace (tabs, newlines) should be trimmed")
    }

    func testNormalizeSharePhraseHandlesCombinedNormalization() {
        // Mix of leading whitespace, extra internal spaces, mixed case
        let id1 = KeyDerivation.shareVaultId(from: "apple banana cherry")
        let id2 = KeyDerivation.shareVaultId(from: "  Apple   BANANA  cherry  ")

        XCTAssertEqual(id1, id2,
                       "Combined normalization (case + spaces + trim) should produce the same result")
    }

    // MARK: - shareVaultId: Determinism

    func testShareVaultIdIsDeterministic() {
        let phrase = "test share phrase"

        let id1 = KeyDerivation.shareVaultId(from: phrase)
        let id2 = KeyDerivation.shareVaultId(from: phrase)

        XCTAssertEqual(id1, id2, "Same phrase should always produce the same vault ID")
    }

    func testShareVaultIdIsHexString() {
        let id = KeyDerivation.shareVaultId(from: "test phrase")

        // Uses first 16 bytes of SHA-256, each as 2 hex chars = 32 hex chars
        XCTAssertEqual(id.count, 32, "Share vault ID should be 32 hex characters (16 bytes)")

        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        for char in id.unicodeScalars {
            XCTAssertTrue(hexCharacterSet.contains(char),
                          "Vault ID should only contain lowercase hex characters, got '\(char)'")
        }
    }

    // MARK: - shareVaultId: Different Phrases Produce Different IDs

    func testDifferentPhrasesProduceDifferentVaultIds() {
        let idA = KeyDerivation.shareVaultId(from: "alpha bravo charlie")
        let idB = KeyDerivation.shareVaultId(from: "delta echo foxtrot")

        XCTAssertNotEqual(idA, idB,
                           "Different phrases should produce different vault IDs")
    }

    func testSimilarPhrasesProduceDifferentVaultIds() {
        let idA = KeyDerivation.shareVaultId(from: "apple banana cherry")
        let idB = KeyDerivation.shareVaultId(from: "apple banana cherries")

        XCTAssertNotEqual(idA, idB,
                           "Similar but different phrases should produce different vault IDs")
    }
}
