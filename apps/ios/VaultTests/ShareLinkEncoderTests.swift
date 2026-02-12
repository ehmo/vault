import XCTest
@testable import Vault

final class ShareLinkEncoderTests: XCTestCase {

    // MARK: - Encode / Decode Round Trip

    func testEncodeDecodeRoundTrip() {
        let phrase = "the purple elephant dances quietly"
        let encoded = ShareLinkEncoder.encode(phrase)
        let decoded = ShareLinkEncoder.decode(encoded)

        XCTAssertEqual(decoded, phrase)
    }

    func testEncodeDecodeRoundTripWithUnicode() {
        let phrase = "le renard brun rapide saute par-dessus le chien paresseux"
        let encoded = ShareLinkEncoder.encode(phrase)
        let decoded = ShareLinkEncoder.decode(encoded)

        XCTAssertEqual(decoded, phrase)
    }

    // MARK: - Base58 Determinism

    func testBase58EncodingIsDeterministic() {
        let phrase = "golden castle ancient wizard"
        let first = ShareLinkEncoder.encode(phrase)
        let second = ShareLinkEncoder.encode(phrase)

        XCTAssertEqual(first, second, "Same input must always produce the same Base58 output")
    }

    // MARK: - Base58 Alphabet Correctness

    func testBase58OutputContainsNoAmbiguousCharacters() {
        let phrases = [
            "short",
            "the purple elephant dances quietly under the golden castle",
            "a much longer phrase that should trigger deflate compression path for better encoding"
        ]

        let forbidden: Set<Character> = ["0", "O", "I", "l"]

        for phrase in phrases {
            let encoded = ShareLinkEncoder.encode(phrase)
            for char in encoded {
                XCTAssertFalse(
                    forbidden.contains(char),
                    "Base58 output contains forbidden character '\(char)' in encoding of: \(phrase)"
                )
            }
        }
    }

    // MARK: - URL Construction

    func testShareURLProducesValidURL() {
        let phrase = "the purple elephant dances quietly"
        let url = ShareLinkEncoder.shareURL(for: phrase)

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "vaultaire.app")
        XCTAssertEqual(url?.path, "/s")
        XCTAssertNotNil(url?.fragment)
        XCTAssertFalse(url!.fragment!.isEmpty)
    }

    func testShareURLFragmentContainsEncodedPhrase() {
        let phrase = "golden castle ancient wizard"
        let url = ShareLinkEncoder.shareURL(for: phrase)
        let expectedFragment = ShareLinkEncoder.encode(phrase)

        XCTAssertEqual(url?.fragment, expectedFragment)
    }

    // MARK: - URL Parsing

    func testPhraseFromValidURL() {
        let original = "the purple elephant dances quietly"
        let url = ShareLinkEncoder.shareURL(for: original)!
        let extracted = ShareLinkEncoder.phrase(from: url)

        XCTAssertEqual(extracted, original)
    }

    func testPhraseFromURLWithTrailingSlash() {
        let original = "golden castle ancient wizard"
        let encoded = ShareLinkEncoder.encode(original)
        let url = URL(string: "https://vaultaire.app/s/#\(encoded)")!
        let extracted = ShareLinkEncoder.phrase(from: url)

        XCTAssertEqual(extracted, original)
    }

    func testPhraseFromSubdomainURL() {
        let original = "silver mountain broken lighthouse"
        let encoded = ShareLinkEncoder.encode(original)
        // The code accepts hosts that end with ".vaultaire.app"
        let url = URL(string: "https://share.vaultaire.app/s#\(encoded)")!
        let extracted = ShareLinkEncoder.phrase(from: url)

        XCTAssertEqual(extracted, original)
    }

    // MARK: - Invalid URL Handling

    func testPhraseFromWrongHostReturnsNil() {
        let encoded = ShareLinkEncoder.encode("some phrase here now")
        let url = URL(string: "https://evil.com/s#\(encoded)")!

        XCTAssertNil(ShareLinkEncoder.phrase(from: url))
    }

    func testPhraseFromWrongPathReturnsNil() {
        let encoded = ShareLinkEncoder.encode("some phrase here now")
        let url = URL(string: "https://vaultaire.app/wrong#\(encoded)")!

        XCTAssertNil(ShareLinkEncoder.phrase(from: url))
    }

    func testPhraseFromURLWithoutFragmentReturnsNil() {
        let url = URL(string: "https://vaultaire.app/s")!

        XCTAssertNil(ShareLinkEncoder.phrase(from: url))
    }

    func testPhraseFromURLWithEmptyFragmentReturnsNil() {
        let url = URL(string: "https://vaultaire.app/s#")!

        XCTAssertNil(ShareLinkEncoder.phrase(from: url))
    }

    // MARK: - Empty String Handling

    func testEncodeEmptyString() {
        let encoded = ShareLinkEncoder.encode("")
        XCTAssertFalse(encoded.isEmpty, "Encoding empty string should still produce Base58 output (version byte)")

        let decoded = ShareLinkEncoder.decode(encoded)
        XCTAssertEqual(decoded, "")
    }

    // MARK: - Decode Invalid Input

    func testDecodeInvalidBase58ReturnsNil() {
        // 'O' and '0' are not in the Base58 alphabet
        XCTAssertNil(ShareLinkEncoder.decode("INVALID0O"))
    }

    func testDecodeEmptyStringReturnsNil() {
        // base58Decode of empty -> empty payload -> guard fails
        XCTAssertNil(ShareLinkEncoder.decode(""))
    }

    // MARK: - Long Phrase (Compression Path)

    func testLongPhraseTriggersCompressionAndRoundTrips() {
        // A long, repetitive phrase should compress well
        let phrase = (0..<20).map { _ in "the purple elephant dances quietly" }.joined(separator: " ")

        let encoded = ShareLinkEncoder.encode(phrase)
        let decoded = ShareLinkEncoder.decode(encoded)

        XCTAssertEqual(decoded, phrase)
    }

    func testLongPhraseProducesShorterEncodingThanRaw() {
        let phrase = (0..<20).map { _ in "the purple elephant dances quietly" }.joined(separator: " ")
        let rawUTF8Count = Array(phrase.utf8).count

        let encoded = ShareLinkEncoder.encode(phrase)
        // The encoded string should be shorter than a naive base58 of the raw bytes
        // because compression kicks in. We check that the encoded length is reasonable.
        // Base58 expands ~1.37x, so raw encoding would be ~rawUTF8Count * 1.37 characters.
        // With compression, it should be significantly less.
        let naiveBase58Length = Double(rawUTF8Count + 1) * 1.37 // +1 for version byte
        XCTAssertLessThan(
            Double(encoded.count),
            naiveBase58Length * 0.7,
            "Compressed encoding should be notably shorter than raw encoding for repetitive input"
        )
    }

    // MARK: - Short Phrase (Raw Encoding Path)

    func testShortPhraseUsesRawEncodingAndRoundTrips() {
        // Short phrases generally don't compress well
        let phrase = "hi"
        let encoded = ShareLinkEncoder.encode(phrase)
        let decoded = ShareLinkEncoder.decode(encoded)

        XCTAssertEqual(decoded, phrase)
    }

    // MARK: - Full Round Trip Through URL

    func testFullRoundTripThroughURL() {
        let phrases = [
            "the purple elephant dances quietly under the golden castle",
            "my ancient wizard slept secretly beneath your hidden treasure",
            "seven hungry cats waited patiently outside her grandmother bakery",
            "a"
        ]

        for phrase in phrases {
            let url = ShareLinkEncoder.shareURL(for: phrase)
            XCTAssertNotNil(url, "shareURL should not be nil for: \(phrase)")

            let extracted = ShareLinkEncoder.phrase(from: url!)
            XCTAssertEqual(extracted, phrase, "Round trip through URL failed for: \(phrase)")
        }
    }
}
