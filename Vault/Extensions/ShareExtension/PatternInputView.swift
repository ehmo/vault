import UIKit

// MARK: - Delegate Protocol

protocol PatternInputDelegate: AnyObject {
    func patternComplete(_ pattern: [Int])
}

// MARK: - PatternInputView

/// UIKit 5x5 pattern grid for the share extension.
/// Uses CAShapeLayer for performant connection lines and supports
/// confirmation animation with sequential node highlights and haptics.
final class PatternInputView: UIView {

    weak var delegate: PatternInputDelegate?

    private let gridSize = VaultCoreConstants.gridSize
    private let minimumNodes = VaultCoreConstants.minimumPatternNodes
    private let nodeRadius: CGFloat = 14
    private let hitRadius: CGFloat = 24 // ≥22pt per HIG
    private let lineWidth: CGFloat = 4

    private var nodeViews: [UIView] = []
    private var nodeCenters: [CGPoint] = []
    private var selectedNodes: [Int] = []
    private var currentPoint: CGPoint?
    private var isDrawing = false
    private var isAnimating = false

    private let lineLayer = CAShapeLayer()
    private let trailingLineLayer = CAShapeLayer()
    private let feedbackGenerator = UISelectionFeedbackGenerator()

    // Colors
    private let nodeColor = UIColor.secondaryLabel
    private let selectedColor = UIColor.systemBlue
    private let confirmColor = UIColor.systemGreen
    private let lineColor = UIColor.systemBlue.withAlphaComponent(0.6)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        lineLayer.strokeColor = lineColor.cgColor
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineWidth = lineWidth
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        layer.addSublayer(lineLayer)

        trailingLineLayer.strokeColor = lineColor.cgColor
        trailingLineLayer.fillColor = UIColor.clear.cgColor
        trailingLineLayer.lineWidth = lineWidth
        trailingLineLayer.lineCap = .round
        layer.addSublayer(trailingLineLayer)

        feedbackGenerator.prepare()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutNodes()
    }

    private func layoutNodes() {
        // Remove old nodes
        nodeViews.forEach { $0.removeFromSuperview() }
        nodeViews.removeAll()
        nodeCenters.removeAll()

        let size = min(bounds.width, bounds.height)
        let spacing = size / CGFloat(gridSize + 1)
        let offsetX = (bounds.width - size) / 2
        let offsetY = (bounds.height - size) / 2

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cx = offsetX + spacing * CGFloat(col + 1)
                let cy = offsetY + spacing * CGFloat(row + 1)
                let center = CGPoint(x: cx, y: cy)
                nodeCenters.append(center)

                let nodeView = UIView()
                nodeView.backgroundColor = nodeColor
                nodeView.layer.cornerRadius = nodeRadius
                nodeView.frame = CGRect(
                    x: cx - nodeRadius,
                    y: cy - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
                nodeView.isUserInteractionEnabled = false
                addSubview(nodeView)
                nodeViews.append(nodeView)
            }
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isAnimating, let touch = touches.first else { return }
        isDrawing = true
        currentPoint = touch.location(in: self)
        handleTouch(at: currentPoint!)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawing, let touch = touches.first else { return }
        currentPoint = touch.location(in: self)
        handleTouch(at: currentPoint!)
        updateLines()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawing else { return }
        isDrawing = false
        currentPoint = nil
        trailingLineLayer.path = nil

        if selectedNodes.count >= minimumNodes {
            let pattern = selectedNodes
            playConfirmationAnimation {
                self.delegate?.patternComplete(pattern)
            }
        } else {
            resetPattern()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDrawing = false
        currentPoint = nil
        resetPattern()
    }

    private func handleTouch(at point: CGPoint) {
        for (index, center) in nodeCenters.enumerated() {
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance < hitRadius && !selectedNodes.contains(index) {
                selectedNodes.append(index)
                nodeViews[index].backgroundColor = selectedColor
                nodeViews[index].transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                UIView.animate(withDuration: 0.15) {
                    self.nodeViews[index].transform = .identity
                }
                feedbackGenerator.selectionChanged()
                feedbackGenerator.prepare()
                updateLines()
            }
        }
    }

    // MARK: - Line Drawing

    private func updateLines() {
        guard selectedNodes.count > 0 else {
            lineLayer.path = nil
            trailingLineLayer.path = nil
            return
        }

        // Draw confirmed lines between selected nodes
        let path = UIBezierPath()
        for (i, nodeIndex) in selectedNodes.enumerated() {
            let center = nodeCenters[nodeIndex]
            if i == 0 {
                path.move(to: center)
            } else {
                path.addLine(to: center)
            }
        }
        lineLayer.path = path.cgPath

        // Draw trailing line from last node to current touch point
        if let point = currentPoint, let lastNode = selectedNodes.last {
            let trailingPath = UIBezierPath()
            trailingPath.move(to: nodeCenters[lastNode])
            trailingPath.addLine(to: point)
            trailingLineLayer.path = trailingPath.cgPath
        } else {
            trailingLineLayer.path = nil
        }
    }

    // MARK: - Confirmation Animation

    private func playConfirmationAnimation(completion: @escaping () -> Void) {
        isAnimating = true
        lineLayer.strokeColor = confirmColor.cgColor

        let impactGenerator = UIImpactFeedbackGenerator(style: .light)
        impactGenerator.prepare()

        // Sequential node highlight: 50ms per node
        for (i, nodeIndex) in selectedNodes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                UIView.animate(withDuration: 0.1) {
                    self.nodeViews[nodeIndex].backgroundColor = self.confirmColor
                    self.nodeViews[nodeIndex].transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
                }
                UIView.animate(withDuration: 0.15, delay: 0.1) {
                    self.nodeViews[nodeIndex].transform = .identity
                }
                impactGenerator.impactOccurred()
                impactGenerator.prepare()
            }
        }

        // After animation completes, wait briefly then call completion
        let totalAnimationTime = Double(selectedNodes.count) * 0.05 + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + totalAnimationTime) {
            completion()
        }
    }

    // MARK: - Reset

    func resetPattern() {
        selectedNodes.removeAll()
        currentPoint = nil
        isDrawing = false
        isAnimating = false
        lineLayer.path = nil
        lineLayer.strokeColor = lineColor.cgColor
        trailingLineLayer.path = nil
        for nodeView in nodeViews {
            nodeView.backgroundColor = nodeColor
            nodeView.transform = .identity
        }
    }
}
