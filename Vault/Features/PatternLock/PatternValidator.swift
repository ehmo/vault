import Foundation

struct PatternValidationResult {
    let isValid: Bool
    let errors: [PatternValidationError]
    let warnings: [PatternValidationWarning]
    let metrics: PatternSerializer.PatternMetrics
}

enum PatternValidationError {
    case tooFewNodes
    case tooFewDirectionChanges
    case custom(String)
    
    var message: String {
        switch self {
        case .tooFewNodes:
            return "Pattern must connect at least 6 nodes"
        case .tooFewDirectionChanges:
            return "Pattern must have at least 2 direction changes"
        case .custom(let message):
            return message
        }
    }
}

enum PatternValidationWarning: String {
    case cornerToCorner = "Corner-to-corner patterns are common and easier to guess"
    case noCenter = "Patterns that cross the center are stronger"
    case notAllQuadrants = "Touching all quadrants increases security"
    case commonShape = "This pattern resembles a common shape"
}

final class PatternValidator {
    static let shared = PatternValidator()

    private init() {}

    // MARK: - Minimum Requirements

    let minimumNodes = 6
    let minimumDirectionChanges = 2

    // MARK: - Validation

    func validate(_ pattern: [Int], gridSize: Int = 5) -> PatternValidationResult {
        var errors: [PatternValidationError] = []
        var warnings: [PatternValidationWarning] = []

        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: gridSize)

        // Check minimum nodes
        if pattern.count < minimumNodes {
            errors.append(.tooFewNodes)
        }

        // Check direction changes
        if metrics.directionChanges < minimumDirectionChanges {
            errors.append(.tooFewDirectionChanges)
        }

        // Warnings (don't block, just inform)
        if metrics.startsAtCorner && metrics.endsAtCorner {
            warnings.append(.cornerToCorner)
        }

        if !metrics.crossesCenter {
            warnings.append(.noCenter)
        }

        if !metrics.touchesAllQuadrants {
            warnings.append(.notAllQuadrants)
        }

        if isCommonPattern(pattern, gridSize: gridSize) {
            warnings.append(.commonShape)
        }

        return PatternValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            metrics: metrics
        )
    }

    // MARK: - Common Pattern Detection

    private func isCommonPattern(_ pattern: [Int], gridSize: Int) -> Bool {
        // Check against known weak patterns

        // L shapes
        if isLShape(pattern, gridSize: gridSize) { return true }

        // Z shapes
        if isZShape(pattern, gridSize: gridSize) { return true }

        // Simple spirals
        if isSimpleSpiral(pattern, gridSize: gridSize) { return true }

        // Sequential patterns (1-2-3-4-5-6)
        if isSequential(pattern) { return true }

        // Common letters (S, N, M, W)
        if isCommonLetter(pattern, gridSize: gridSize) { return true }

        return false
    }

    private func isLShape(_ pattern: [Int], gridSize: Int) -> Bool {
        // Simple L detection - all nodes in same row OR same column transition
        guard pattern.count >= 4 else { return false }

        var horizontalCount = 0
        var verticalCount = 0

        for i in 0..<(pattern.count - 1) {
            let row1 = pattern[i] / gridSize
            let col1 = pattern[i] % gridSize
            let row2 = pattern[i + 1] / gridSize
            let col2 = pattern[i + 1] % gridSize

            if row1 == row2 { horizontalCount += 1 }
            if col1 == col2 { verticalCount += 1 }
        }

        // L shape has mostly horizontal + some vertical or vice versa
        let total = pattern.count - 1
        let isL = (horizontalCount > total / 2 && verticalCount > 0) ||
                  (verticalCount > total / 2 && horizontalCount > 0)

        return isL && pattern.count < 8 // Short L shapes only
    }

    private func isZShape(_ pattern: [Int], gridSize: Int) -> Bool {
        // Z has horizontal-diagonal-horizontal structure
        guard pattern.count >= 5 else { return false }

        // Check for zig-zag pattern
        var directions: [PatternSerializer.Direction] = []
        for i in 0..<(pattern.count - 1) {
            directions.append(PatternSerializer.computeDirection(
                from: pattern[i],
                to: pattern[i + 1],
                gridSize: gridSize
            ))
        }

        // Simple Z: right, downLeft, right (or variations)
        let hasZigZag = directions.contains(.downRight) || directions.contains(.downLeft) ||
                        directions.contains(.upRight) || directions.contains(.upLeft)

        return hasZigZag && pattern.count < 7
    }

    private func isSimpleSpiral(_ pattern: [Int], gridSize: Int) -> Bool {
        // Spiral patterns go around the edges
        guard pattern.count >= 6 else { return false }

        // Check if pattern stays on edges
        var edgeCount = 0
        for node in pattern {
            let row = node / gridSize
            let col = node % gridSize
            if row == 0 || row == gridSize - 1 || col == 0 || col == gridSize - 1 {
                edgeCount += 1
            }
        }

        return edgeCount > pattern.count * 3 / 4
    }

    private func isSequential(_ pattern: [Int]) -> Bool {
        // Check for simple sequential patterns like 0,1,2,3,4,5
        guard pattern.count >= 6 else { return false }

        var isIncreasing = true
        var isDecreasing = true

        for i in 0..<(pattern.count - 1) {
            let diff = pattern[i + 1] - pattern[i]
            if diff != 1 { isIncreasing = false }
            if diff != -1 { isDecreasing = false }
        }

        return isIncreasing || isDecreasing
    }

    private func isCommonLetter(_ pattern: [Int], gridSize: Int) -> Bool {
        // This is a simplified check - real implementation would have
        // templates for common letters
        return false // Placeholder
    }

    // MARK: - Complexity Score

    func complexityScore(for pattern: [Int], gridSize: Int = 5) -> Int {
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: gridSize)
        return metrics.complexityScore
    }

    func complexityDescription(for score: Int) -> String {
        switch score {
        case 0..<10: return "Very Weak"
        case 10..<20: return "Weak"
        case 20..<30: return "Fair"
        case 30..<40: return "Good"
        case 40..<50: return "Strong"
        default: return "Very Strong"
        }
    }
}
