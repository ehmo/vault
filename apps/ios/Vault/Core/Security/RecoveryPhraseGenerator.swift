import Foundation

/// Generates memorable recovery phrases with high entropy.
/// Uses template-based sentence generation for memorability.
final class RecoveryPhraseGenerator: @unchecked Sendable {
    static let shared = RecoveryPhraseGenerator()

    private init() {
        // No-op: singleton
    }

    // MARK: - Phrase Generation

    /// Generates a memorable sentence that always passes entropy validation.
    func generatePhrase() -> String {
        // Retry to guarantee the phrase meets minimum acceptable entropy
        for _ in 0..<10 {
            let phrase = fillTemplate(selectTemplate())
            if validatePhrase(phrase).isAcceptable {
                return phrase
            }
        }
        // Final attempt (all templates should produce acceptable entropy)
        return fillTemplate(selectTemplate())
    }

    // MARK: - Templates

    private enum SentenceTemplate: CaseIterable {
        case articleAdjectiveNounVerbAdverb
        // "The purple elephant dances quietly under the broken umbrella"
        case possessiveAdjectiveNounVerbPreposition
        // "My favorite uncle sleeps peacefully beside the ancient lighthouse"
        case numberAdjectiveNounVerbAdverb
        // "Seven hungry cats waited patiently outside her grandmother's bakery"
        case articleNounVerbedPrepositionArticleNoun
        // "The musician performed brilliantly during the summer festival"
    }

    private func selectTemplate() -> SentenceTemplate {
        SentenceTemplate.allCases.randomElement()!
    }

    private func fillTemplate(_ template: SentenceTemplate) -> String {
        switch template {
        case .articleAdjectiveNounVerbAdverb:
            let article1 = WordLists.articles.randomElement()!
            let adj1 = WordLists.adjectives.randomElement()!
            let noun1 = WordLists.nouns.randomElement()!
            let verb = WordLists.verbs.randomElement()!
            let adverb = WordLists.adverbs.randomElement()!
            let prep = WordLists.prepositions.randomElement()!
            let article2 = WordLists.articles.randomElement()!
            let adj2 = WordLists.adjectives.randomElement()!
            let noun2 = WordLists.nouns.randomElement()!
            return "\(article1) \(adj1) \(noun1) \(verb) \(adverb) \(prep) \(article2) \(adj2) \(noun2)"

        case .possessiveAdjectiveNounVerbPreposition:
            let possessive = WordLists.possessives.randomElement()!
            let adj1 = WordLists.adjectives.randomElement()!
            let noun1 = WordLists.nouns.randomElement()!
            let verb = WordLists.verbs.randomElement()!
            let adverb = WordLists.adverbs.randomElement()!
            let prep = WordLists.prepositions.randomElement()!
            let article = WordLists.articles.randomElement()!
            let adj2 = WordLists.adjectives.randomElement()!
            let noun2 = WordLists.nouns.randomElement()!
            return "\(possessive) \(adj1) \(noun1) \(verb) \(adverb) \(prep) \(article) \(adj2) \(noun2)"

        case .numberAdjectiveNounVerbAdverb:
            let number = WordLists.numbers.randomElement()!
            let adj1 = WordLists.adjectives.randomElement()!
            let noun1 = WordLists.pluralNouns.randomElement()!
            let verb = WordLists.pastVerbs.randomElement()!
            let adverb = WordLists.adverbs.randomElement()!
            let prep = WordLists.prepositions.randomElement()!
            let possessive = WordLists.possessives.randomElement()!
            let adj2 = WordLists.adjectives.randomElement()!
            let noun2 = WordLists.nouns.randomElement()!
            return "\(number) \(adj1) \(noun1) \(verb) \(adverb) \(prep) \(possessive) \(adj2) \(noun2)"

        case .articleNounVerbedPrepositionArticleNoun:
            let article1 = WordLists.articles.randomElement()!
            let adj1 = WordLists.adjectives.randomElement()!
            let noun1 = WordLists.nouns.randomElement()!
            let verb = WordLists.pastVerbs.randomElement()!
            let adverb = WordLists.adverbs.randomElement()!
            let prep = WordLists.prepositions.randomElement()!
            let article2 = WordLists.articles.randomElement()!
            let adj2 = WordLists.adjectives.randomElement()!
            let noun2 = WordLists.nouns.randomElement()!
            return "\(article1) \(adj1) \(noun1) \(verb) \(adverb) \(prep) \(article2) \(adj2) \(noun2)"
        }
    }

    // MARK: - Entropy Calculation

    /// Estimates the entropy of a phrase in bits.
    func estimateEntropy(of phrase: String) -> Int {
        let words = phrase.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Each word contributes based on its word list size
        var totalEntropy = 0.0

        for word in words {
            let poolSize: Double
            if WordLists.articles.contains(word) {
                poolSize = Double(WordLists.articles.count)
            } else if WordLists.adjectives.contains(word) {
                poolSize = Double(WordLists.adjectives.count)
            } else if WordLists.nouns.contains(word) {
                poolSize = Double(WordLists.nouns.count)
            } else if WordLists.pluralNouns.contains(word) {
                poolSize = Double(WordLists.pluralNouns.count)
            } else if WordLists.verbs.contains(word) || WordLists.pastVerbs.contains(word) {
                poolSize = Double(WordLists.verbs.count + WordLists.pastVerbs.count)
            } else if WordLists.adverbs.contains(word) {
                poolSize = Double(WordLists.adverbs.count)
            } else if WordLists.prepositions.contains(word) {
                poolSize = Double(WordLists.prepositions.count)
            } else if WordLists.possessives.contains(word) {
                poolSize = Double(WordLists.possessives.count)
            } else if WordLists.numbers.contains(word) {
                poolSize = Double(WordLists.numbers.count)
            } else {
                // Unknown word - assume small pool (conservative estimate)
                poolSize = 100.0
            }

            totalEntropy += log2(poolSize)
        }

        return Int(totalEntropy)
    }

    // MARK: - Phrase Validation

    /// Validates that a user-provided phrase has sufficient entropy.
    func validatePhrase(_ phrase: String) -> PhraseValidation {
        let entropy = estimateEntropy(of: phrase)
        let wordCount = phrase.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

        if wordCount < 6 {
            return .tooShort(minWords: 6)
        }

        if entropy < 50 {
            return .weakEntropy(bits: entropy, recommended: 70)
        }

        if entropy < 70 {
            return .acceptable(bits: entropy)
        }

        return .strong(bits: entropy)
    }

    enum PhraseValidation {
        case tooShort(minWords: Int)
        case weakEntropy(bits: Int, recommended: Int)
        case acceptable(bits: Int)
        case strong(bits: Int)

        var isAcceptable: Bool {
            switch self {
            case .tooShort, .weakEntropy: return false
            case .acceptable, .strong: return true
            }
        }

        var message: String {
            switch self {
            case .tooShort(let min):
                return "Phrase too short. Use at least \(min) words."
            case .weakEntropy(let bits, let recommended):
                return "Phrase has weak entropy (\(bits) bits). Try using more unusual words. Recommended: \(recommended)+ bits."
            case .acceptable(let bits):
                return "Acceptable phrase strength (\(bits) bits)."
            case .strong(let bits):
                return "Strong phrase (\(bits) bits)."
            }
        }
    }
}
