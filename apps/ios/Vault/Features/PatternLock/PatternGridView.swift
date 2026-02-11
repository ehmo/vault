import SwiftUI
import UIKit

struct PatternGridView: View {
    var state: PatternState
    @Binding var showFeedback: Bool

    let onPatternComplete: ([Int]) -> Void

    private let nodeRadius: CGFloat = 16
    private let lineWidth: CGFloat = 4
    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Connection lines (only if feedback enabled)
                if showFeedback {
                    connectionLines(in: geometry.size)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: lineWidth)

                    // Current drawing line
                    if let currentPoint = state.currentPoint,
                       let lastNode = state.selectedNodes.last {
                        currentLine(from: lastNode, to: currentPoint, in: geometry.size)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: lineWidth)
                    }
                }

                // Nodes
                ForEach(state.nodes) { node in
                    nodeView(for: node, in: geometry.size)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geometry.size))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier("pattern_grid")
        .accessibilityLabel("Pattern grid, \(state.gridSize) by \(state.gridSize)")
        .accessibilityHint("Draw a pattern by dragging across the dots. If using VoiceOver, use the recovery phrase option instead.")
        .accessibilityValue(state.selectedNodes.isEmpty ? "No dots selected" : "\(state.selectedNodes.count) dots connected")
    }

    // MARK: - Node View

    private func nodeView(for node: PatternNode, in size: CGSize) -> some View {
        let position = nodePosition(for: node, in: size)
        let isSelected = state.selectedNodes.contains(node.id)

        return Circle()
            .fill(isSelected && showFeedback ? Color.accentColor : Color.vaultSecondaryText.opacity(0.5))
            .overlay {
                Circle()
                    .strokeBorder(Color.vaultSecondaryText.opacity(0.3), lineWidth: 1)
            }
            .frame(width: nodeRadius * 2, height: nodeRadius * 2)
            .position(position)
            .animation(.easeInOut(duration: 0.1), value: isSelected)
    }

    // MARK: - Lines

    private func connectionLines(in size: CGSize) -> Path {
        Path { path in
            guard state.selectedNodes.count > 1 else { return }

            for i in 0..<(state.selectedNodes.count - 1) {
                let fromId = state.selectedNodes[i]
                let toId = state.selectedNodes[i + 1]

                guard let fromNode = state.nodes.first(where: { $0.id == fromId }),
                      let toNode = state.nodes.first(where: { $0.id == toId }) else {
                    continue
                }

                let fromPos = nodePosition(for: fromNode, in: size)
                let toPos = nodePosition(for: toNode, in: size)

                path.move(to: fromPos)
                path.addLine(to: toPos)
            }
        }
    }

    private func currentLine(from nodeId: Int, to point: CGPoint, in size: CGSize) -> Path {
        Path { path in
            guard let node = state.nodes.first(where: { $0.id == nodeId }) else {
                return
            }
            let fromPos = nodePosition(for: node, in: size)
            path.move(to: fromPos)
            path.addLine(to: point)
        }
    }

    // MARK: - Gestures

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                #if DEBUG
                print("🔵 Drag changed - location: \(value.location)")
                #endif

                if !state.isDrawing {
                    state.isDrawing = true
                    state.selectedNodes = []
                    #if DEBUG
                    print("🟢 Started drawing")
                    #endif
                }

                state.currentPoint = value.location

                if let nodeId = state.nodeAt(point: value.location, in: size, nodeRadius: nodeRadius) {
                    #if DEBUG
                    print("🟡 Found node: \(nodeId)")
                    #endif
                    let previousCount = state.selectedNodes.count
                    state.addNode(nodeId)
                    if state.selectedNodes.count > previousCount {
                        selectionFeedback.selectionChanged()
                    }
                }
            }
            .onEnded { _ in
                #if DEBUG
                print("🔴 Drag ended - selected nodes: \(state.selectedNodes)")
                #endif

                state.isDrawing = false
                state.currentPoint = nil

                if !state.selectedNodes.isEmpty {
                    onPatternComplete(state.selectedNodes)
                }
            }
    }

    // MARK: - Positioning

    private func nodePosition(for node: PatternNode, in size: CGSize) -> CGPoint {
        let gridSize = CGFloat(state.gridSize)
        let spacing = min(size.width, size.height) / gridSize
        let startX = (size.width - spacing * (gridSize - 1)) / 2
        let startY = (size.height - spacing * (gridSize - 1)) / 2

        return CGPoint(
            x: startX + CGFloat(node.col) * spacing,
            y: startY + CGFloat(node.row) * spacing
        )
    }
}

#Preview {
    PatternGridView(
        state: PatternState(),
        showFeedback: .constant(true),
        onPatternComplete: { _ in }
    )
    .padding(40)
}
