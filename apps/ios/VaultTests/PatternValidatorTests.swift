import XCTest
@testable import Vault

final class PatternValidatorTests: XCTestCase {

    private let validator = PatternValidator.shared
    private let gridSize = 5

    // MARK: - Minimum Node Requirement

    func testPatternShorterThanSixNodesReturnsError() {
        let shortPatterns: [[Int]] = [
            [],
            [0],
            [0, 1],
            [0, 1, 2],
            [0, 1, 2, 3],
            [0, 1, 2, 3, 4],
        ]

        for pattern in shortPatterns {
            let result = validator.validate(pattern, gridSize: gridSize)
            XCTAssertFalse(result.isValid, "Pattern of length \(pattern.count) should be invalid")
            let hasTooFewNodesError = result.errors.contains { error in
                if case .tooFewNodes = error { return true }
                return false
            }
            XCTAssertTrue(hasTooFewNodesError, "Pattern of length \(pattern.count) should have tooFewNodes error")
        }
    }

    // MARK: - Direction Changes Requirement

    func testPatternWithZeroDirectionChangesReturnsError() {
        // Straight line down column 0 on 5x5 grid: 0, 5, 10, 15, 20 + one more
        // 0(r0,c0)->5(r1,c0)->10(r2,c0)->15(r3,c0)->20(r4,c0): all "down", 0 changes
        // Need 6+ nodes, so extend with column 1 but keep direction constant
        // Actually, a 5x5 grid only has 5 rows in one column. Use row-based instead:
        // Nodes along row 0 and continuing into row 1: but 4->5 wraps.
        // Safest: use 6 nodes down one direction.
        // 0, 5, 10, 15, 20 = only 5 nodes (not enough).
        // Use diagonal: 0, 6, 12, 18, 24 = 5 nodes (not enough).
        // Use two columns going down: 0, 5, 10, 15, 20 (5 nodes) -- not 6.
        // Just use the column approach and accept tooFewNodes also fires:
        // Or use a 6x6 grid for this test to get 6 nodes in a straight line.
        // Simplest: go right along row 0 staying in bounds: 0,1,2,3,4 is only 5.
        // Best approach: test on a larger grid or accept both errors.
        let straightDown = [0, 5, 10, 15, 20] // 5 nodes, all "down"
        let result = validator.validate(straightDown, gridSize: gridSize)
        // This will have both tooFewNodes AND tooFewDirectionChanges
        let hasTooFewChanges = result.errors.contains { error in
            if case .tooFewDirectionChanges = error { return true }
            return false
        }
        XCTAssertTrue(hasTooFewChanges, "Straight-line pattern should have tooFewDirectionChanges error")
    }

    func testSixNodeStraightLineReturnsDirectionChangeError() {
        // 6 nodes in a straight line on a 6-column grid to get 0 direction changes
        // Using gridSize 6: nodes 0,1,2,3,4,5 are all in row 0
        let straightRight = [0, 1, 2, 3, 4, 5]
        let result = validator.validate(straightRight, gridSize: 6)
        // 6 nodes meets minimum, but 0 direction changes should fail
        let hasTooFewChanges = result.errors.contains { error in
            if case .tooFewDirectionChanges = error { return true }
            return false
        }
        XCTAssertTrue(hasTooFewChanges, "6-node straight line should have tooFewDirectionChanges error")
        // Should not have tooFewNodes error since count == 6
        let hasTooFewNodes = result.errors.contains { error in
            if case .tooFewNodes = error { return true }
            return false
        }
        XCTAssertFalse(hasTooFewNodes, "6-node pattern should not have tooFewNodes error")
    }

    func testPatternWithExactlyOneDirectionChangeReturnsError() {
        // Right then down: one direction change
        // Row 0: 0, 1, 2, 3 (right, right, right) then down: 3, 8, 13 (down, down)
        let oneChange = [0, 1, 2, 3, 8, 13]
        let result = validator.validate(oneChange, gridSize: gridSize)
        let hasTooFewChanges = result.errors.contains { error in
            if case .tooFewDirectionChanges = error { return true }
            return false
        }
        XCTAssertTrue(hasTooFewChanges, "Pattern with 1 direction change should have tooFewDirectionChanges error")
    }

    // MARK: - Valid Pattern

    func testValidPatternPassesValidation() {
        // Zigzag pattern across the grid with 6 nodes and multiple direction changes
        // 0 -> 6 -> 2 -> 8 -> 4 -> 10 (downRight, upRight, downRight, upRight, downRight)
        // That's 4 direction changes? Let me compute:
        // 0(0,0) -> 6(1,1): downRight
        // 6(1,1) -> 2(0,2): upRight
        // 2(0,2) -> 8(1,3): downRight
        // 8(1,3) -> 4(0,4): upRight
        // 4(0,4) -> 10(2,0): downLeft
        // Direction changes: dR->uR (1), uR->dR (2), dR->uR (3), uR->dL (4)
        let zigzag = [0, 6, 2, 8, 4, 10]
        let result = validator.validate(zigzag, gridSize: gridSize)
        XCTAssertTrue(result.isValid, "Zigzag pattern with 6 nodes and multiple changes should be valid")
        XCTAssertTrue(result.errors.isEmpty, "Valid pattern should have no errors")
    }

    func testValidPatternHasNoNodeOrDirectionErrors() {
        // A pattern that clearly has enough nodes and direction changes
        // 0 -> 1 -> 6 -> 11 -> 10 -> 5 -> 12 (multiple direction changes)
        let pattern = [0, 1, 6, 11, 10, 5, 12]
        let result = validator.validate(pattern, gridSize: gridSize)
        XCTAssertTrue(result.isValid)
        let hasNodeError = result.errors.contains { if case .tooFewNodes = $0 { return true }; return false }
        let hasChangeError = result.errors.contains { if case .tooFewDirectionChanges = $0 { return true }; return false }
        XCTAssertFalse(hasNodeError)
        XCTAssertFalse(hasChangeError)
    }

    // MARK: - Common Pattern Detection

    func testSequentialPatternDetected() {
        // 0, 1, 2, 3, 4, 5 is sequential
        let sequential = [0, 1, 2, 3, 4, 5]
        let result = validator.validate(sequential, gridSize: gridSize)
        XCTAssertTrue(result.warnings.contains(.commonShape),
                       "Sequential pattern should trigger commonShape warning")
    }

    func testReverseSequentialPatternDetected() {
        let reverseSeq = [6, 5, 4, 3, 2, 1]
        let result = validator.validate(reverseSeq, gridSize: gridSize)
        XCTAssertTrue(result.warnings.contains(.commonShape),
                       "Reverse sequential pattern should trigger commonShape warning")
    }

    func testLShapePatternDetected() {
        // L-shape: go right along row 0, then down along col 3
        // 0, 1, 2, 3 (right), then 3, 8 (down) -- 5 nodes, short L
        // For isLShape to trigger, need >= 4 nodes and < 8 nodes
        // horizontal moves: 0->1, 1->2, 2->3 = 3 horizontal
        // vertical moves: 3->8 = 1 vertical
        // total = 4, horizontalCount=3 > 4/2=2, verticalCount=1 > 0 => true
        // But this pattern also needs validation: 5 nodes < 6, so it will have tooFewNodes error too.
        // Let's make it 6 nodes: 0, 1, 2, 3, 8, 13 (right, right, right, down, down)
        // horizontal=3, vertical=2, total=5, 3 > 5/2=2, vertical=2 > 0 => true, count=6 < 8 => L detected
        let lShape = [0, 1, 2, 3, 8, 13]
        let result = validator.validate(lShape, gridSize: gridSize)
        XCTAssertTrue(result.warnings.contains(.commonShape),
                       "L-shape pattern should trigger commonShape warning")
    }

    func testZShapePatternDetected() {
        // Z-shape needs >= 5 and < 7 nodes and contains diagonal directions
        // Row 0: right, then diagonal down-left, then right
        // 0(0,0) -> 1(0,1): right
        // 1(0,1) -> 2(0,2): right
        // 2(0,2) -> 6(1,1): downLeft
        // 6(1,1) -> 11(2,1): down -- wait, let me construct a proper Z
        // 1(0,1) -> 2(0,2): right
        // 2(0,2) -> 6(1,1): downLeft
        // 6(1,1) -> 10(2,0): downLeft
        // 10(2,0) -> 11(2,1): right
        // That's 5 nodes: [1, 2, 6, 10, 11] with downLeft present, count=5 < 7
        let zShape = [1, 2, 6, 10, 11]
        let result = validator.validate(zShape, gridSize: gridSize)
        // Note: this will also have tooFewNodes (5 < 6), but commonShape can still trigger
        XCTAssertTrue(result.warnings.contains(.commonShape),
                       "Z-shape pattern should trigger commonShape warning")
    }

    // MARK: - Complexity Score

    func testComplexityScoreIncreasesWithMoreNodes() {
        // Pattern A: 6 nodes with 2 direction changes
        let patternA = [0, 6, 2, 8, 4, 10]
        // Pattern B: 8 nodes with 2+ direction changes
        let patternB = [0, 6, 2, 8, 4, 10, 16, 22]

        let scoreA = validator.complexityScore(for: patternA, gridSize: gridSize)
        let scoreB = validator.complexityScore(for: patternB, gridSize: gridSize)

        XCTAssertGreaterThan(scoreB, scoreA,
                             "More nodes should produce a higher complexity score")
    }

    func testComplexityScoreIncreasesWithMoreDirectionChanges() {
        // Pattern with fewer direction changes (straight down, 0 changes)
        // On 5x5: 0(r0,c0)->5(r1,c0)->10(r2,c0)->15(r3,c0)->20(r4,c0)
        // Then continue right: 20(r4,c0)->21(r4,c1)->22(r4,c2)->23(r4,c3) -- 1 direction change
        let fewChanges = [0, 5, 10, 15, 20, 21, 22, 23]
        // Pattern with many direction changes (zigzag), same node count
        let zigzag = [0, 6, 2, 8, 4, 10, 16, 22]

        let scoreFew = validator.complexityScore(for: fewChanges, gridSize: gridSize)
        let scoreZigzag = validator.complexityScore(for: zigzag, gridSize: gridSize)

        XCTAssertGreaterThan(scoreZigzag, scoreFew,
                             "More direction changes should produce a higher complexity score")
    }

    // MARK: - Warning Generation

    func testCornerToCornerWarning() {
        // Starts at corner 0, ends at corner 24 (for 5x5 grid)
        // Corners: 0, 4, 20, 24
        // Build a pattern from 0 to 24 with enough nodes and changes
        let pattern = [0, 6, 2, 8, 14, 18, 24]
        let result = validator.validate(pattern, gridSize: gridSize)
        XCTAssertTrue(result.warnings.contains(.cornerToCorner),
                       "Pattern starting and ending at corners should warn about corner-to-corner")
    }

    func testNoCenterWarning() {
        // Center nodes for 5x5 grid: computeCenterNodes with half=2
        // rows 1..2, cols 1..2: nodes 6, 7, 11, 12
        // Build a pattern that avoids all center nodes
        // Use only edge/corner nodes: 0, 1, 2, 3, 4, 9, 14
        let pattern = [0, 1, 2, 3, 4, 9, 14]
        let result = validator.validate(pattern, gridSize: gridSize)
        XCTAssertTrue(result.warnings.contains(.noCenter),
                       "Pattern that never crosses center should warn about missing center")
    }

    func testNotAllQuadrantsWarning() {
        // Stay in top-left quadrant only (rows 0-1, cols 0-1 for half=2)
        // Nodes: 0, 1, 5, 6 -- only 4 nodes, too few
        // Add more from same quadrant area. For 5x5 with half=2:
        // TL quadrant: row < 2, col < 2 -> nodes 0, 1, 5, 6
        // We need 6 nodes, some direction changes. Let's repeat area: 0, 1, 5, 6, 0, 1
        // Patterns shouldn't repeat nodes in a real scenario, but validator doesn't check for that.
        // Actually let's use top-left and top-right but not bottom quadrants
        // TL: 0, 1, 5, 6; TR: 2, 3, 4, 7, 8, 9
        // This touches quadrants 0 and 1 only
        let pattern = [0, 1, 2, 7, 6, 5, 0]
        let result = validator.validate(pattern, gridSize: gridSize)
        XCTAssertTrue(result.warnings.contains(.notAllQuadrants),
                       "Pattern not touching all quadrants should have notAllQuadrants warning")
    }

    func testPatternCrossingCenterHasNoCenterWarning() {
        // Center nodes for 5x5: rows 1-2, cols 1-2 -> nodes 6, 7, 11, 12
        // Pattern that hits node 12 (center node)
        let pattern = [0, 6, 12, 18, 13, 8, 3]
        let result = validator.validate(pattern, gridSize: gridSize)
        XCTAssertFalse(result.warnings.contains(.noCenter),
                        "Pattern crossing center should not have noCenter warning")
    }

    func testPatternTouchingAllQuadrantsHasNoQuadrantWarning() {
        // 5x5 grid, half=2
        // TL (r<2,c<2): 0; TR (r<2,c>=2): 3; BL (r>=2,c<2): 10; BR (r>=2,c>=2): 18
        let pattern = [0, 3, 18, 10, 12, 7, 22]
        let result = validator.validate(pattern, gridSize: gridSize)
        XCTAssertFalse(result.warnings.contains(.notAllQuadrants),
                        "Pattern touching all quadrants should not have notAllQuadrants warning")
    }

    // MARK: - Complexity Description

    func testComplexityDescriptionVeryWeak() {
        XCTAssertEqual(validator.complexityDescription(for: 0), "Very Weak")
        XCTAssertEqual(validator.complexityDescription(for: 5), "Very Weak")
        XCTAssertEqual(validator.complexityDescription(for: 9), "Very Weak")
    }

    func testComplexityDescriptionWeak() {
        XCTAssertEqual(validator.complexityDescription(for: 10), "Weak")
        XCTAssertEqual(validator.complexityDescription(for: 15), "Weak")
        XCTAssertEqual(validator.complexityDescription(for: 19), "Weak")
    }

    func testComplexityDescriptionFair() {
        XCTAssertEqual(validator.complexityDescription(for: 20), "Fair")
        XCTAssertEqual(validator.complexityDescription(for: 25), "Fair")
        XCTAssertEqual(validator.complexityDescription(for: 29), "Fair")
    }

    func testComplexityDescriptionGood() {
        XCTAssertEqual(validator.complexityDescription(for: 30), "Good")
        XCTAssertEqual(validator.complexityDescription(for: 35), "Good")
        XCTAssertEqual(validator.complexityDescription(for: 39), "Good")
    }

    func testComplexityDescriptionStrong() {
        XCTAssertEqual(validator.complexityDescription(for: 40), "Strong")
        XCTAssertEqual(validator.complexityDescription(for: 45), "Strong")
        XCTAssertEqual(validator.complexityDescription(for: 49), "Strong")
    }

    func testComplexityDescriptionVeryStrong() {
        XCTAssertEqual(validator.complexityDescription(for: 50), "Very Strong")
        XCTAssertEqual(validator.complexityDescription(for: 75), "Very Strong")
        XCTAssertEqual(validator.complexityDescription(for: 100), "Very Strong")
    }
}
