import SwiftUI

struct PatternGridView: View {
    @ObservedObject var state: PatternState
    @Binding var showFeedback: Bool
    @Binding var randomizeGrid: Bool

    let onPatternComplete: ([Int]) -> Void

    private let nodeRadius: CGFloat = 16
    private let lineWidth: CGFloat = 4

    @State private var viewSize: CGSize = .zero
    @State private var gridMapping: [Int: Int] = [:] // Visual position -> actual node ID

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Connection lines (only if feedback enabled)
                if showFeedback {
                    connectionLines(in: geometry.size)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: lineWidth)

                    // Current drawing line
                    if let currentPoint = state.currentPoint,
                       let lastNode = state.selectedNodes.last {
                        currentLine(from: lastNode, to: currentPoint, in: geometry.size)
                            .stroke(Color.accentColor.opacity(0.4), lineWidth: lineWidth)
                    }
                }

                // Nodes
                ForEach(state.nodes) { node in
                    nodeView(for: node, in: geometry.size)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geometry.size))
            .onAppear {
                viewSize = geometry.size
                setupGridMapping()
            }
            .onChange(of: randomizeGrid) { _, _ in
                setupGridMapping()
            }
            .onChange(of: state.gridSize) { _, _ in
                setupGridMapping()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Node View

    private func nodeView(for node: PatternNode, in size: CGSize) -> some View {
        let position = nodePosition(for: node, in: size)
        let isSelected = state.selectedNodes.contains(getMappedNodeId(node.id))

        return Circle()
            .fill(isSelected && showFeedback ? Color.accentColor : Color.secondary.opacity(0.5))
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
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

                guard let fromNode = state.nodes.first(where: { getMappedNodeId($0.id) == fromId }),
                      let toNode = state.nodes.first(where: { getMappedNodeId($0.id) == toId }) else {
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
            guard let node = state.nodes.first(where: { getMappedNodeId($0.id) == nodeId }) else {
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

                if let visualNodeId = state.nodeAt(point: value.location, in: size, nodeRadius: nodeRadius) {
                    let actualNodeId = getMappedNodeId(visualNodeId)
                    #if DEBUG
                    print("🟡 Found node - visual: \(visualNodeId), actual: \(actualNodeId)")
                    #endif
                    state.addNode(actualNodeId)
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

    // MARK: - Grid Randomization (for smudge attack defense)

    private func setupGridMapping() {
        #if DEBUG
        print("🔧 Setting up grid mapping - gridSize: \(state.gridSize), randomize: \(randomizeGrid)")
        #endif
        
        if randomizeGrid {
            // Create a random permutation
            let nodeCount = state.gridSize * state.gridSize
            var mapping = Array(0..<nodeCount)
            mapping.shuffle()
            gridMapping = Dictionary(uniqueKeysWithValues: zip(0..<nodeCount, mapping))
        } else {
            // When not randomizing, create identity mapping for consistency
            let nodeCount = state.gridSize * state.gridSize
            gridMapping = Dictionary(uniqueKeysWithValues: zip(0..<nodeCount, 0..<nodeCount))
        }
        
        #if DEBUG
        print("📊 Grid mapping created with \(gridMapping.count) entries")
        #endif
    }

    private func getMappedNodeId(_ visualId: Int) -> Int {
        return gridMapping[visualId] ?? visualId
    }
}

#Preview {
    PatternGridView(
        state: PatternState(),
        showFeedback: .constant(true),
        randomizeGrid: .constant(false),
        onPatternComplete: { _ in }
    )
    .padding(40)
}
