import Foundation
import CryptoKit

struct PatternSerializer {

    // MARK: - Pattern Serialization

    /// Serializes a pattern into bytes for key derivation.
    /// Pattern is a sequence of node indices (0-15 for 4x4 grid).
    /// Also encodes direction changes for additional entropy.
    static func serialize(_ pattern: [Int], gridSize: Int = 5) -> Data {
        guard !pattern.isEmpty else { return Data() }

        var data = Data()

        // 1. Encode grid size (important for consistent key derivation)
        data.append(UInt8(gridSize))

        // 2. Encode node sequence
        for node in pattern {
            data.append(UInt8(node))
        }

        // 3. Encode directions between consecutive nodes
        for i in 0..<(pattern.count - 1) {
            let direction = computeDirection(from: pattern[i], to: pattern[i + 1], gridSize: gridSize)
            data.append(direction.rawValue)
        }

        // 4. Encode pattern length
        data.append(UInt8(pattern.count))

        // 5. Hash the combined data for fixed-length output
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }

    // MARK: - Direction Calculation

    enum Direction: UInt8 {
        case up = 0
        case upRight = 1
        case right = 2
        case downRight = 3
        case down = 4
        case downLeft = 5
        case left = 6
        case upLeft = 7
        case same = 8 // Should not happen in valid patterns
    }

    /// Compute direction from one node to another on the grid
    static func computeDirection(from: Int, to: Int, gridSize: Int = 5) -> Direction {
        let fromRow = from / gridSize
        let fromCol = from % gridSize
        let toRow = to / gridSize
        let toCol = to % gridSize

        let deltaRow = toRow - fromRow
        let deltaCol = toCol - fromCol

        switch (deltaRow.signum(), deltaCol.signum()) {
        case (-1,  0): return .up
        case (-1,  1): return .upRight
        case ( 0,  1): return .right
        case ( 1,  1): return .downRight
        case ( 1,  0): return .down
        case ( 1, -1): return .downLeft
        case ( 0, -1): return .left
        case (-1, -1): return .upLeft
        default:       return .same
        }
    }

    // MARK: - Pattern Metrics (for validation feedback, not security)

    struct PatternMetrics {
        let nodeCount: Int
        let directionChanges: Int
        let startsAtCorner: Bool
        let endsAtCorner: Bool
        let crossesCenter: Bool
        let touchesAllQuadrants: Bool

        var complexityScore: Int {
            var score = nodeCount * 2
            score += directionChanges * 3
            if crossesCenter { score += 5 }
            if touchesAllQuadrants { score += 5 }
            if startsAtCorner && endsAtCorner { score -= 3 }
            return max(0, score)
        }
    }

    static func analyzePattern(_ pattern: [Int], gridSize: Int = 5) -> PatternMetrics {
        guard pattern.count >= 2 else {
            return PatternMetrics(
                nodeCount: pattern.count,
                directionChanges: 0,
                startsAtCorner: false,
                endsAtCorner: false,
                crossesCenter: false,
                touchesAllQuadrants: false
            )
        }

        let corners = [0, gridSize - 1, gridSize * (gridSize - 1), gridSize * gridSize - 1]
        let centerNodes = computeCenterNodes(gridSize: gridSize)

        var directionChanges = 0
        var previousDirection: Direction?

        for i in 0..<(pattern.count - 1) {
            let direction = computeDirection(from: pattern[i], to: pattern[i + 1], gridSize: gridSize)
            if let prev = previousDirection, prev != direction {
                directionChanges += 1
            }
            previousDirection = direction
        }

        let quadrants = computeQuadrants(pattern: pattern, gridSize: gridSize)

        return PatternMetrics(
            nodeCount: pattern.count,
            directionChanges: directionChanges,
            startsAtCorner: pattern.first.map { corners.contains($0) } ?? false,
            endsAtCorner: pattern.last.map { corners.contains($0) } ?? false,
            crossesCenter: pattern.contains(where: { centerNodes.contains($0) }),
            touchesAllQuadrants: quadrants.count == 4
        )
    }

    private static func computeCenterNodes(gridSize: Int) -> Set<Int> {
        // For 4x4: nodes 5, 6, 9, 10
        let half = gridSize / 2
        var centers: Set<Int> = []
        for row in (half - 1)...half {
            for col in (half - 1)...half {
                centers.insert(row * gridSize + col)
            }
        }
        return centers
    }

    private static func computeQuadrants(pattern: [Int], gridSize: Int) -> Set<Int> {
        let half = gridSize / 2
        var quadrants: Set<Int> = []

        for node in pattern {
            let row = node / gridSize
            let col = node % gridSize

            let quadrant: Int
            if row < half && col < half { quadrant = 0 } // Top-left
            else if row < half && col >= half { quadrant = 1 } // Top-right
            else if row >= half && col < half { quadrant = 2 } // Bottom-left
            else { quadrant = 3 } // Bottom-right

            quadrants.insert(quadrant)
        }

        return quadrants
    }
}
