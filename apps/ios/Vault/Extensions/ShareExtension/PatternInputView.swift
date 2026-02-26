import UIKit

// MARK: - Delegate Protocol

@MainActor protocol PatternInputDelegate: AnyObject {
    func patternComplete(_ pattern: [Int])
}

// MARK: - PatternInputView

/// UIKit 5x5 pattern grid for the share extension.
/// Visual style matches the main app's SwiftUI PatternGridView exactly:
/// same node size, colors, border, line style, and spacing.
final class PatternInputView: UIView {

    weak var delegate: PatternInputDelegate?

    private let gridSize = VaultCoreConstants.gridSize
    private let minimumNodes = VaultCoreConstants.minimumPatternNodes
    private let nodeRadius: CGFloat = 16
    private let hitRadius: CGFloat = 24 // ≥22pt per HIG
    private let lineWidth: CGFloat = 4

    private var nodeViews: [UIView] = []
    private var nodeBorderLayers: [CAShapeLayer] = []
    private var nodeCenters: [CGPoint] = []
    private var selectedNodes: [Int] = []
    private var currentPoint: CGPoint?
    private var isDrawing = false
    private var isAnimating = false

    private let lineLayer = CAShapeLayer()
    private let trailingLineLayer = CAShapeLayer()
    private let feedbackGenerator = UISelectionFeedbackGenerator()

    // Match main app theme colors
    // AccentColor: rgb(0.384, 0.275, 0.918) = ~(98, 70, 234)
    private let accentColor = UIColor(red: 0.384, green: 0.275, blue: 0.918, alpha: 1.0)
    // VaultSecondaryText light: rgb(0.169, 0.173, 0.204) @ 0.7 alpha
    // VaultSecondaryText dark:  rgb(0.910, 0.910, 0.941) @ 0.7 alpha
    private var nodeColor: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.910, green: 0.910, blue: 0.941, alpha: 0.7 * 0.5)
            } else {
                return UIColor(red: 0.169, green: 0.173, blue: 0.204, alpha: 0.7 * 0.5)
            }
        }
    }
    private var nodeBorderColor: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.910, green: 0.910, blue: 0.941, alpha: 0.7 * 0.3)
            } else {
                return UIColor(red: 0.169, green: 0.173, blue: 0.204, alpha: 0.7 * 0.3)
            }
        }
    }

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

        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineWidth = lineWidth
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        layer.addSublayer(lineLayer)

        trailingLineLayer.fillColor = UIColor.clear.cgColor
        trailingLineLayer.lineWidth = lineWidth
        trailingLineLayer.lineCap = .round
        layer.addSublayer(trailingLineLayer)

        updateLineColors()

        // Use a long-press gesture (minDuration=0) instead of raw touches so our
        // gesture recognizer claims the touch before the sheet's pan gesture can.
        let drawGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDrawGesture(_:)))
        drawGesture.minimumPressDuration = 0
        drawGesture.delegate = self
        addGestureRecognizer(drawGesture)

        feedbackGenerator.prepare()
        registerTraitObservers()
    }

    private func registerTraitObservers() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: PatternInputView, _) in
            self.updateLineColors()
            self.updateNodeAppearances()
        }
    }

    private func updateLineColors() {
        lineLayer.strokeColor = accentColor.withAlphaComponent(0.7).cgColor
        trailingLineLayer.strokeColor = accentColor.withAlphaComponent(0.5).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutNodes()
    }

    private func layoutNodes() {
        // Remove old nodes
        nodeViews.forEach { $0.removeFromSuperview() }
        nodeViews.removeAll()
        nodeBorderLayers.removeAll()
        nodeCenters.removeAll()

        // Match main app spacing: spacing = size / gridSize, centered
        let size = min(bounds.width, bounds.height)
        let spacing = size / CGFloat(gridSize)
        let startX = (bounds.width - spacing * CGFloat(gridSize - 1)) / 2
        let startY = (bounds.height - spacing * CGFloat(gridSize - 1)) / 2

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cx = startX + CGFloat(col) * spacing
                let cy = startY + CGFloat(row) * spacing
                let center = CGPoint(x: cx, y: cy)
                nodeCenters.append(center)

                let nodeView = UIView()
                nodeView.frame = CGRect(
                    x: cx - nodeRadius,
                    y: cy - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
                nodeView.layer.cornerRadius = nodeRadius
                nodeView.isUserInteractionEnabled = false

                // 1pt stroke border matching main app
                let borderLayer = CAShapeLayer()
                borderLayer.path = UIBezierPath(
                    ovalIn: nodeView.bounds.insetBy(dx: 0.5, dy: 0.5)
                ).cgPath
                borderLayer.fillColor = UIColor.clear.cgColor
                borderLayer.strokeColor = nodeBorderColor.cgColor
                borderLayer.lineWidth = 1
                nodeView.layer.addSublayer(borderLayer)

                let index = row * gridSize + col
                let isSelected = selectedNodes.contains(index)
                nodeView.backgroundColor = isSelected ? accentColor : nodeColor

                addSubview(nodeView)
                nodeViews.append(nodeView)
                nodeBorderLayers.append(borderLayer)
            }
        }
    }

    // MARK: - Gesture Handling

    @objc private func handleDrawGesture(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            guard !isAnimating else { return }
            isDrawing = true
            currentPoint = point
            handleTouch(at: point)

        case .changed:
            guard isDrawing else { return }
            currentPoint = point
            handleTouch(at: point)
            updateLines()

        case .ended:
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

        case .cancelled, .failed:
            isDrawing = false
            currentPoint = nil
            resetPattern()

        default:
            break
        }
    }

    private func handleTouch(at point: CGPoint) {
        for (index, center) in nodeCenters.enumerated() {
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance < hitRadius && !selectedNodes.contains(index) {
                selectedNodes.append(index)
                // Animate color change to match main app's easeInOut(0.1)
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                    self.nodeViews[index].backgroundColor = self.accentColor
                }
                feedbackGenerator.selectionChanged()
                feedbackGenerator.prepare()
                updateLines()
            }
        }
    }

    private func updateNodeAppearances() {
        for (index, nodeView) in nodeViews.enumerated() {
            let isSelected = selectedNodes.contains(index)
            nodeView.backgroundColor = isSelected ? accentColor : nodeColor
            nodeBorderLayers[index].strokeColor = nodeBorderColor.cgColor
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

        // Turn lines and all selected nodes green immediately.
        // Use performWithoutAnimation to cancel any in-flight color
        // animations from handleTouch that would override the green.
        let confirmColor = UIColor.systemGreen
        lineLayer.strokeColor = confirmColor.cgColor
        UIView.performWithoutAnimation {
            for nodeIndex in selectedNodes {
                nodeViews[nodeIndex].layer.removeAllAnimations()
                nodeViews[nodeIndex].backgroundColor = confirmColor
            }
        }

        let impactGenerator = UIImpactFeedbackGenerator(style: .light)
        impactGenerator.prepare()

        // Sequential scale pulse: 50ms per node
        for (i, nodeIndex) in selectedNodes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                UIView.animate(withDuration: 0.1) {
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
        updateLineColors()
        trailingLineLayer.path = nil
        for (index, nodeView) in nodeViews.enumerated() {
            nodeView.backgroundColor = nodeColor
            nodeView.transform = .identity
            nodeBorderLayers[index].strokeColor = nodeBorderColor.cgColor
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PatternInputView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        false // Don't allow the sheet's pan gesture to run alongside ours
    }
}
