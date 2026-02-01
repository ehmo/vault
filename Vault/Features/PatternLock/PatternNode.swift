import Foundation
import SwiftUI

struct PatternNode: Identifiable, Equatable {
    let id: Int
    let row: Int
    let col: Int
    let gridSize: Int

    var position: CGPoint {
        CGPoint(x: CGFloat(col), y: CGFloat(row))
    }

    var isCorner: Bool {
        let isTopLeft = row == 0 && col == 0
        let isTopRight = row == 0 && col == gridSize - 1
        let isBottomLeft = row == gridSize - 1 && col == 0
        let isBottomRight = row == gridSize - 1 && col == gridSize - 1
        return isTopLeft || isTopRight || isBottomLeft || isBottomRight
    }

    var isCenter: Bool {
        let half = gridSize / 2
        return (row == half - 1 || row == half) && (col == half - 1 || col == half)
    }

    static func == (lhs: PatternNode, rhs: PatternNode) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@Observable
final class PatternState {
    var selectedNodes: [Int] = []
    var currentPoint: CGPoint?
    var isDrawing = false
    let gridSize: Int = 5  // Fixed 5x5 grid

    let nodes: [PatternNode] = {
        var result: [PatternNode] = []
        for row in 0..<5 {
            for col in 0..<5 {
                let id = row * 5 + col
                result.append(PatternNode(id: id, row: row, col: col, gridSize: 5))
            }
        }
        return result
    }()

    func reset() {
        selectedNodes = []
        currentPoint = nil
        isDrawing = false
    }

    func addNode(_ nodeId: Int) {
        guard !selectedNodes.contains(nodeId) else { return }
        selectedNodes.append(nodeId)
    }

    func nodeAt(point: CGPoint, in size: CGSize, nodeRadius: CGFloat) -> Int? {
        let spacing = min(size.width, size.height) / CGFloat(gridSize)
        let startX = (size.width - spacing * CGFloat(gridSize - 1)) / 2
        let startY = (size.height - spacing * CGFloat(gridSize - 1)) / 2

        for node in nodes {
            let nodeCenter = CGPoint(
                x: startX + CGFloat(node.col) * spacing,
                y: startY + CGFloat(node.row) * spacing
            )

            let distance = hypot(point.x - nodeCenter.x, point.y - nodeCenter.y)
            if distance <= nodeRadius * 1.5 { // Slightly larger hit area
                return node.id
            }
        }
        return nil
    }
}
