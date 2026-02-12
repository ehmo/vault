import XCTest
@testable import Vault

final class PatternSerializerTests: XCTestCase {

    // MARK: - Deterministic Serialization

    func testSerializeIsDeterministic() {
        let pattern = [0, 6, 12, 18, 13, 8, 3]

        let hash1 = PatternSerializer.serialize(pattern, gridSize: 5)
        let hash2 = PatternSerializer.serialize(pattern, gridSize: 5)

        XCTAssertEqual(hash1, hash2, "Same pattern should always produce the same hash")
    }

    func testSerializeProducesSHA256SizedOutput() {
        let pattern = [0, 1, 2, 3, 4, 5]
        let hash = PatternSerializer.serialize(pattern, gridSize: 5)
        XCTAssertEqual(hash.count, 32, "SHA-256 output should be 32 bytes")
    }

    // MARK: - Different Patterns Produce Different Hashes

    func testDifferentPatternsProduceDifferentHashes() {
        let patternA = [0, 1, 2, 3, 4, 5]
        let patternB = [5, 4, 3, 2, 1, 0]

        let hashA = PatternSerializer.serialize(patternA, gridSize: 5)
        let hashB = PatternSerializer.serialize(patternB, gridSize: 5)

        XCTAssertNotEqual(hashA, hashB, "Different patterns should produce different hashes")
    }

    func testPatternsWithDifferentGridSizesProduceDifferentHashes() {
        let pattern = [0, 1, 2, 3, 4, 5]

        let hash4 = PatternSerializer.serialize(pattern, gridSize: 4)
        let hash5 = PatternSerializer.serialize(pattern, gridSize: 5)

        XCTAssertNotEqual(hash4, hash5, "Same pattern on different grid sizes should produce different hashes")
    }

    func testSingleNodeDifferenceProducesDifferentHash() {
        let patternA = [0, 1, 2, 3, 4, 5]
        let patternB = [0, 1, 2, 3, 4, 6]

        let hashA = PatternSerializer.serialize(patternA, gridSize: 5)
        let hashB = PatternSerializer.serialize(patternB, gridSize: 5)

        XCTAssertNotEqual(hashA, hashB, "Patterns differing by one node should produce different hashes")
    }

    // MARK: - Empty Pattern

    func testEmptyPatternReturnsEmptyData() {
        let hash = PatternSerializer.serialize([], gridSize: 5)
        XCTAssertTrue(hash.isEmpty, "Empty pattern should produce empty data")
    }

    // MARK: - analyzePattern Metrics: Node Count and Direction Changes

    func testAnalyzePatternNodeCount() {
        let pattern = [0, 1, 6, 11, 16, 21]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertEqual(metrics.nodeCount, 6)
    }

    func testAnalyzePatternDirectionChanges() {
        // 0 -> 1: right
        // 1 -> 6: downRight (row 0->1, col 1->1 ... wait, 1/5=0 col=1, 6/5=1 col=1, so that's down)
        // Let me recompute: gridSize=5
        // 0(r0,c0) -> 1(r0,c1): right
        // 1(r0,c1) -> 6(r1,c1): down  -- change 1
        // 6(r1,c1) -> 11(r2,c1): down
        // 11(r2,c1) -> 16(r3,c1): down
        // 16(r3,c1) -> 21(r4,c1): down
        // Direction changes: right->down = 1 change total
        let pattern = [0, 1, 6, 11, 16, 21]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertEqual(metrics.directionChanges, 1)
    }

    func testAnalyzePatternMultipleDirectionChanges() {
        // Zigzag: right, downLeft, right, downLeft, right
        // 0(0,0)->1(0,1): right
        // 1(0,1)->5(1,0): downLeft -- change 1
        // 5(1,0)->6(1,1): right -- change 2
        // 6(1,1)->10(2,0): downLeft -- change 3
        // 10(2,0)->11(2,1): right -- change 4
        let zigzag = [0, 1, 5, 6, 10, 11]
        let metrics = PatternSerializer.analyzePattern(zigzag, gridSize: 5)
        XCTAssertEqual(metrics.directionChanges, 4)
    }

    func testAnalyzePatternStraightLineHasZeroDirectionChanges() {
        // All right: 0, 1, 2, 3, 4
        let straightLine = [0, 1, 2, 3, 4]
        let metrics = PatternSerializer.analyzePattern(straightLine, gridSize: 5)
        XCTAssertEqual(metrics.directionChanges, 0, "Straight line should have 0 direction changes")
    }

    // MARK: - analyzePattern Metrics: Corner Detection

    func testStartsAtCorner() {
        // 5x5 corners: 0, 4, 20, 24
        let patternFromCorner = [0, 1, 2, 3, 4, 9]
        let metrics = PatternSerializer.analyzePattern(patternFromCorner, gridSize: 5)
        XCTAssertTrue(metrics.startsAtCorner, "Pattern starting at node 0 should report startsAtCorner")
    }

    func testEndsAtCorner() {
        let patternEndingAtCorner = [5, 6, 7, 8, 9, 4]
        let metrics = PatternSerializer.analyzePattern(patternEndingAtCorner, gridSize: 5)
        XCTAssertTrue(metrics.endsAtCorner, "Pattern ending at node 4 should report endsAtCorner")
    }

    func testDoesNotStartOrEndAtCorner() {
        // 5x5 corners: 0, 4, 20, 24. Nodes 1 and 3 are not corners.
        let pattern = [1, 2, 7, 12, 17, 22, 23]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertFalse(metrics.startsAtCorner, "Pattern starting at node 1 should not be a corner")
        XCTAssertFalse(metrics.endsAtCorner, "Pattern ending at node 23 should not be a corner")
    }

    func testAllFourCornersRecognized() {
        // Verify all four corners are detected
        for corner in [0, 4, 20, 24] {
            let pattern = [corner, 12, 6, 7, 8, 13] // start at corner
            let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
            XCTAssertTrue(metrics.startsAtCorner, "Node \(corner) should be recognized as a corner")
        }
    }

    // MARK: - analyzePattern Metrics: Center Crossing

    func testCrossesCenterDetected() {
        // 5x5 grid: center nodes are computed with half=2, rows 1-2, cols 1-2
        // Center nodes: 1*5+1=6, 1*5+2=7, 2*5+1=11, 2*5+2=12
        let pattern = [0, 1, 6, 11, 16, 21] // hits node 6 and 11 (center nodes)
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertTrue(metrics.crossesCenter, "Pattern hitting center nodes should report crossesCenter")
    }

    func testDoesNotCrossCenter() {
        // Avoid all center nodes (6, 7, 11, 12 for 5x5)
        // Use only edge/corner nodes
        let pattern = [0, 1, 2, 3, 4, 9, 14]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertFalse(metrics.crossesCenter, "Pattern avoiding center nodes should not report crossesCenter")
    }

    // MARK: - analyzePattern Metrics: Quadrant Coverage

    func testTouchesAllQuadrants() {
        // 5x5 grid, half=2
        // TL (r<2,c<2): node 0
        // TR (r<2,c>=2): node 3
        // BL (r>=2,c<2): node 10
        // BR (r>=2,c>=2): node 18
        let pattern = [0, 3, 18, 10, 12, 7]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertTrue(metrics.touchesAllQuadrants, "Pattern hitting all four quadrants should report touchesAllQuadrants")
    }

    func testDoesNotTouchAllQuadrants() {
        // Only top half: rows 0-1, all in quadrants 0 and 1
        let pattern = [0, 1, 2, 3, 5, 6]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertFalse(metrics.touchesAllQuadrants, "Pattern in only top half should not touch all quadrants")
    }

    // MARK: - Direction Calculation

    func testDirectionUp() {
        // From node 10(r2,c0) to node 5(r1,c0): up
        let direction = PatternSerializer.computeDirection(from: 10, to: 5, gridSize: 5)
        XCTAssertEqual(direction, .up)
    }

    func testDirectionUpRight() {
        // From node 10(r2,c0) to node 6(r1,c1): upRight
        let direction = PatternSerializer.computeDirection(from: 10, to: 6, gridSize: 5)
        XCTAssertEqual(direction, .upRight)
    }

    func testDirectionRight() {
        // From node 0(r0,c0) to node 1(r0,c1): right
        let direction = PatternSerializer.computeDirection(from: 0, to: 1, gridSize: 5)
        XCTAssertEqual(direction, .right)
    }

    func testDirectionDownRight() {
        // From node 0(r0,c0) to node 6(r1,c1): downRight
        let direction = PatternSerializer.computeDirection(from: 0, to: 6, gridSize: 5)
        XCTAssertEqual(direction, .downRight)
    }

    func testDirectionDown() {
        // From node 0(r0,c0) to node 5(r1,c0): down
        let direction = PatternSerializer.computeDirection(from: 0, to: 5, gridSize: 5)
        XCTAssertEqual(direction, .down)
    }

    func testDirectionDownLeft() {
        // From node 1(r0,c1) to node 5(r1,c0): downLeft
        let direction = PatternSerializer.computeDirection(from: 1, to: 5, gridSize: 5)
        XCTAssertEqual(direction, .downLeft)
    }

    func testDirectionLeft() {
        // From node 1(r0,c1) to node 0(r0,c0): left
        let direction = PatternSerializer.computeDirection(from: 1, to: 0, gridSize: 5)
        XCTAssertEqual(direction, .left)
    }

    func testDirectionUpLeft() {
        // From node 6(r1,c1) to node 0(r0,c0): upLeft
        let direction = PatternSerializer.computeDirection(from: 6, to: 0, gridSize: 5)
        XCTAssertEqual(direction, .upLeft)
    }

    func testDirectionSame() {
        // From node 6 to node 6: same
        let direction = PatternSerializer.computeDirection(from: 6, to: 6, gridSize: 5)
        XCTAssertEqual(direction, .same)
    }

    // MARK: - Complexity Score via Metrics

    func testComplexityScoreComputedCorrectly() {
        // Manually verify the formula:
        // score = nodeCount * 2 + directionChanges * 3
        //       + (crossesCenter ? 5 : 0)
        //       + (touchesAllQuadrants ? 5 : 0)
        //       - (startsAtCorner && endsAtCorner ? 3 : 0)
        //
        // Pattern: 0, 6, 12, 18, 13, 8, 3
        // 0(0,0)->6(1,1): downRight
        // 6(1,1)->12(2,2): downRight
        // 12(2,2)->18(3,3): downRight
        // 18(3,3)->13(2,3): up
        // 13(2,3)->8(1,3): up
        // 8(1,3)->3(0,3): up
        // Direction changes: dR=dR(0), dR=dR(0), dR->up(1), up=up(0), up=up(0) = 1 change
        // nodeCount=7, changes=1
        // corners: 0 is corner, 3 is not corner (5x5 corners: 0,4,20,24)
        // crossesCenter: 6,7,11,12 are center; pattern has 6 and 12 -> true
        // quadrants: 0(TL), 6(TL r1<2,c1<2), 12(BR r2>=2,c2>=2), 18(BR), 13(BR r2>=2,c3>=2), 8(TR r1<2,c3>=2), 3(TR)
        // quadrants = {TL, BR, TR} = 3, not all 4
        // Score = 7*2 + 1*3 + 5 + 0 - 0 = 14 + 3 + 5 = 22
        let pattern = [0, 6, 12, 18, 13, 8, 3]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertEqual(metrics.complexityScore, 22)
    }

    func testComplexityScoreNeverNegative() {
        // Very simple pattern: 2 nodes, starts and ends at corners
        // 0(corner) -> 4(corner): right
        // nodeCount=2, changes=0, crossesCenter=false, allQuadrants=false
        // startsAtCorner=true, endsAtCorner=true
        // Score = 2*2 + 0*3 + 0 + 0 - 3 = 1
        let pattern = [0, 4]
        let metrics = PatternSerializer.analyzePattern(pattern, gridSize: 5)
        XCTAssertGreaterThanOrEqual(metrics.complexityScore, 0)
    }
}
