import XCTest
@testable import Vault

final class RecoveryPhraseGeneratorTests: XCTestCase {

    private let generator = RecoveryPhraseGenerator.shared

    // MARK: - All Valid Words (superset for membership checks)

    private var allValidWords: Set<String> {
        Set(
            WordLists.articles
            + WordLists.possessives
            + WordLists.numbers
            + WordLists.adjectives
            + WordLists.nouns
            + WordLists.pluralNouns
            + WordLists.verbs
            + WordLists.pastVerbs
            + WordLists.adverbs
            + WordLists.prepositions
        )
    }

    // MARK: - Phrase Generation

    func testGeneratePhraseProducesNonEmptyResult() {
        let phrase = generator.generatePhrase()

        XCTAssertFalse(phrase.isEmpty, "Generated phrase must not be empty")
    }

    func testGeneratePhraseProducesNineWords() {
        // All templates produce exactly 9 words
        for _ in 0..<20 {
            let phrase = generator.generatePhrase()
            let words = phrase.components(separatedBy: " ").filter { !$0.isEmpty }
            XCTAssertEqual(words.count, 9, "Generated phrase should have exactly 9 words. Got: \(phrase)")
        }
    }

    func testGeneratePhraseContainsOnlyValidWords() {
        let valid = allValidWords

        // Generate several phrases to cover different templates
        for _ in 0..<20 {
            let phrase = generator.generatePhrase()
            let words = phrase.lowercased().components(separatedBy: " ").filter { !$0.isEmpty }
            for word in words {
                XCTAssertTrue(
                    valid.contains(word),
                    "Word '\(word)' in generated phrase is not in any word list. Phrase: \(phrase)"
                )
            }
        }
    }

    func testGeneratedPhraseAlwaysPassesValidation() {
        // Every generated phrase must be at least "acceptable" (50+ bits entropy)
        for i in 0..<50 {
            let phrase = generator.generatePhrase()
            let validation = generator.validatePhrase(phrase)
            XCTAssertTrue(
                validation.isAcceptable,
                "Generated phrase #\(i) failed validation: \(validation.message). Phrase: \(phrase)"
            )
        }
    }

    func testGeneratePhraseVariesAcrossInvocations() {
        // Generate 10 phrases; at least 2 should be different (extremely high probability)
        let phrases = (0..<10).map { _ in generator.generatePhrase() }
        let unique = Set(phrases)

        XCTAssertGreaterThan(unique.count, 1, "Multiple generated phrases should not all be identical")
    }

    // MARK: - Entropy Estimation

    func testEstimateEntropyWithKnownWords() {
        // "the" = article (pool 9), "purple" = adjective (pool 184), "elephant" = noun (pool 272)
        // entropy = int(log2(9) + log2(184) + log2(272)) = int(3.17 + 7.52 + 8.09) = int(18.78) = 18
        let phrase = "the purple elephant"
        let entropy = generator.estimateEntropy(of: phrase)

        XCTAssertEqual(entropy, 18, "Entropy should match sum of log2 pool sizes (truncated)")
    }

    func testEstimateEntropyWithUnknownWordsUsesDefaultPool() {
        // "xylophone" is not in any word list -> default pool = 100, log2(100) ~= 6.64
        // "quasar" also unknown -> 6.64
        // Total = int(13.29) = 13
        let entropy = generator.estimateEntropy(of: "xylophone quasar")

        XCTAssertEqual(entropy, 13, "Unknown words should use pool size of 100")
    }

    func testEstimateEntropyOfEmptyPhraseIsZero() {
        let entropy = generator.estimateEntropy(of: "")

        XCTAssertEqual(entropy, 0)
    }

    func testEstimateEntropyWithVerbsUsesCombinedPool() {
        // "dances" is in verbs, poolSize = verbs.count + pastVerbs.count = 184
        // "walked" is in pastVerbs, same combined pool = 184
        // Each contributes log2(184) ~= 7.52
        // Total = int(15.05) = 15
        let entropy = generator.estimateEntropy(of: "dances walked")

        XCTAssertEqual(entropy, 15)
    }

    func testEstimateEntropyHandlesExtraWhitespace() {
        // The code splits on whitespace and filters empty strings
        let normal = generator.estimateEntropy(of: "the purple elephant")
        let spaced = generator.estimateEntropy(of: "  the   purple   elephant  ")

        XCTAssertEqual(normal, spaced, "Extra whitespace should not affect entropy calculation")
    }

    func testEstimateEntropyOfGeneratedPhraseIsPositive() {
        let phrase = generator.generatePhrase()
        let entropy = generator.estimateEntropy(of: phrase)

        XCTAssertGreaterThan(entropy, 0, "Generated phrase should have positive entropy")
    }

    func testEstimateEntropyWithPluralNouns() {
        // "elephants" is in pluralNouns (pool 82), "tigers" is in pluralNouns (pool 82)
        // Each contributes log2(82) ~= 6.36
        // Total = int(12.71) = 12
        let entropy = generator.estimateEntropy(of: "elephants tigers castles rivers gardens bridges")

        // 6 plural nouns: int(6 * log2(82)) = int(38.15) = 38
        XCTAssertEqual(entropy, 38, "Plural nouns should use pluralNouns pool size")
    }

    // MARK: - Phrase Validation: tooShort

    func testValidateEmptyPhraseIsTooShort() {
        let result = generator.validatePhrase("")

        if case .tooShort(let minWords) = result {
            XCTAssertEqual(minWords, 6)
        } else {
            XCTFail("Empty phrase should be .tooShort, got \(result)")
        }
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSingleWordIsTooShort() {
        let result = generator.validatePhrase("elephant")

        if case .tooShort(let minWords) = result {
            XCTAssertEqual(minWords, 6)
        } else {
            XCTFail("Single-word phrase should be .tooShort, got \(result)")
        }
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateFiveWordsIsTooShort() {
        let result = generator.validatePhrase("purple elephant golden castle ancient")

        if case .tooShort(let minWords) = result {
            XCTAssertEqual(minWords, 6)
        } else {
            XCTFail("Five-word phrase should be .tooShort, got \(result)")
        }
        XCTAssertFalse(result.isAcceptable)
    }

    // MARK: - Phrase Validation: weakEntropy

    func testValidateSixArticlesIsWeakEntropy() {
        // 6 articles: entropy = int(6 * log2(9)) = int(19.02) = 19 < 50
        let result = generator.validatePhrase("the a an that this one")

        if case .weakEntropy(let bits, let recommended) = result {
            XCTAssertEqual(bits, 19)
            XCTAssertEqual(recommended, 70)
        } else {
            XCTFail("Six articles should be .weakEntropy, got \(result)")
        }
        XCTAssertFalse(result.isAcceptable)
    }

    // MARK: - Phrase Validation: acceptable

    func testValidateNineWordMixedPhraseIsAcceptable() {
        // "the purple elephant dances quietly under the golden castle"
        // article(9) + adj(184) + noun(272) + verb(184) + adverb(67) + prep(26) + article(9) + adj(184) + noun(272)
        // = int(55.85) = 55 -> >= 50 and < 70 -> acceptable
        let result = generator.validatePhrase(
            "the purple elephant dances quietly under the golden castle"
        )

        if case .acceptable(let bits) = result {
            XCTAssertEqual(bits, 55)
        } else {
            XCTFail("Expected .acceptable, got \(result)")
        }
        XCTAssertTrue(result.isAcceptable)
    }

    // MARK: - Phrase Validation: strong

    func testValidateManyHighEntropyWordsIsStrong() {
        // 11 words from large pools: adjectives(184) and nouns(272) mostly
        // "purple elephant golden castle ancient wizard dances quietly under silver mountain"
        // adj + noun + adj + noun + adj + noun + verb(184) + adverb(67) + prep(26) + adj + noun
        // = 4*log2(184) + 4*log2(272) + log2(184) + log2(67) + log2(26) = int(80.73) = 80
        let result = generator.validatePhrase(
            "purple elephant golden castle ancient wizard dances quietly under silver mountain"
        )

        if case .strong(let bits) = result {
            XCTAssertEqual(bits, 80)
        } else {
            XCTFail("Expected .strong, got \(result)")
        }
        XCTAssertTrue(result.isAcceptable)
    }

    // MARK: - Phrase Validation: isAcceptable property

    func testIsAcceptableForAllCategories() {
        let tooShort = generator.validatePhrase("one two")
        let weak = generator.validatePhrase("the a an that this one")
        let acceptable = generator.validatePhrase(
            "the purple elephant dances quietly under the golden castle"
        )
        let strong = generator.validatePhrase(
            "purple elephant golden castle ancient wizard dances quietly under silver mountain"
        )

        XCTAssertFalse(tooShort.isAcceptable)
        XCTAssertFalse(weak.isAcceptable)
        XCTAssertTrue(acceptable.isAcceptable)
        XCTAssertTrue(strong.isAcceptable)
    }

    // MARK: - Phrase Validation: message property

    func testValidationMessagesAreNonEmpty() {
        let cases: [RecoveryPhraseGenerator.PhraseValidation] = [
            generator.validatePhrase("one two"),
            generator.validatePhrase("the a an that this one"),
            generator.validatePhrase("the purple elephant dances quietly under the golden castle"),
            generator.validatePhrase(
                "purple elephant golden castle ancient wizard dances quietly under silver mountain"
            ),
        ]

        for validation in cases {
            XCTAssertFalse(validation.message.isEmpty, "Validation message should not be empty")
        }
    }

    // MARK: - Phrase Validation with Extra Whitespace

    func testValidationNormalizesWhitespace() {
        let normal = generator.validatePhrase("the a an that this one")
        let spaced = generator.validatePhrase("  the  a  an  that  this  one  ")

        // Both should yield the same category and bits
        if case .weakEntropy(let bitsA, _) = normal,
           case .weakEntropy(let bitsB, _) = spaced {
            XCTAssertEqual(bitsA, bitsB)
        } else {
            XCTFail("Both should be .weakEntropy but got normal=\(normal), spaced=\(spaced)")
        }
    }
}
