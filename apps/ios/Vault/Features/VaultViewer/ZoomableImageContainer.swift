import SwiftUI
import UIKit

/// UIScrollView-based zoomable image view with pinch-to-zoom, double-tap zoom,
/// single-tap for controls toggle, and vertical drag-to-dismiss when not zoomed.
struct ZoomableImageContainer: UIViewRepresentable {
    /// Zoom scale considered "not zoomed" — accounts for floating-point imprecision.
    static let zoomThreshold: CGFloat = 1.05

    let image: UIImage
    let containerSize: CGSize
    let onSingleTap: () -> Void
    let onVerticalDrag: (CGFloat) -> Void
    let onVerticalDragEnd: (_ velocity: CGFloat, _ offset: CGFloat) -> Void
    let onZoomChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.tag = 100
        scrollView.addSubview(imageView)

        // Double-tap to zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single-tap for controls toggle (waits for double-tap failure)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        // Vertical pan for drag-to-dismiss (only when not zoomed)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        context.coordinator.panGesture = pan
        scrollView.addGestureRecognizer(pan)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = scrollView.viewWithTag(100) as? UIImageView else { return }

        let imageChanged = imageView.image !== image
        let sizeChanged = context.coordinator.lastContainerSize != containerSize

        // Update image if changed
        if imageChanged {
            imageView.image = image
            scrollView.zoomScale = 1.0
        }

        context.coordinator.parent = self

        // Only recompute layout when image or container size actually changed
        if imageChanged || sizeChanged {
            context.coordinator.lastContainerSize = containerSize
            layoutImageView(imageView, in: scrollView)
        }

        // Ensure final centering after Auto Layout has resolved scrollView bounds.
        // Without this pass, initial layout can run with stale/zero bounds and leave
        // portrait media visually pinned near the top.
        // Use a longer delay (0.1s) to ensure bounds are fully resolved, especially
        // after transitions or when view first appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let currentImageView = scrollView.viewWithTag(100) as? UIImageView else { return }
            Self.centerImageView(currentImageView, in: scrollView)
        }
    }

    private func layoutImageView(_ imageView: UIImageView, in scrollView: UIScrollView) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)

        let fittedWidth = imageSize.width * fitScale
        let fittedHeight = imageSize.height * fitScale

        imageView.frame = CGRect(x: 0, y: 0, width: fittedWidth, height: fittedHeight)
        scrollView.contentSize = CGSize(width: fittedWidth, height: fittedHeight)

        // Use containerSize directly — scrollView.bounds may not be resolved yet on first render,
        // which causes the image to appear pinned to the top (yOffset computed as 0).
        let xOffset = max(0, (containerSize.width - fittedWidth) / 2)
        let yOffset = max(0, (containerSize.height - fittedHeight) / 2)
        imageView.center = CGPoint(
            x: fittedWidth / 2 + xOffset,
            y: fittedHeight / 2 + yOffset
        )
    }

    static func centerImageView(_ imageView: UIImageView, in scrollView: UIScrollView) {
        let boundsSize = scrollView.bounds.size
        let frameSize = imageView.frame.size

        let xOffset = max(0, (boundsSize.width - frameSize.width) / 2)
        let yOffset = max(0, (boundsSize.height - frameSize.height) / 2)

        imageView.center = CGPoint(
            x: frameSize.width / 2 + xOffset,
            y: frameSize.height / 2 + yOffset
        )
    }

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImageContainer
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        weak var panGesture: UIPanGestureRecognizer?
        var lastContainerSize: CGSize = .zero

        init(parent: ZoomableImageContainer) {
            self.parent = parent
        }

        private var isZoomed: Bool {
            guard let scrollView else { return false }
            return scrollView.zoomScale > ZoomableImageContainer.zoomThreshold
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            ZoomableImageContainer.centerImageView(imageView, in: scrollView)
            parent.onZoomChange(scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.onZoomChange(scale)
        }

        // MARK: Gestures

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if isZoomed {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: scrollView.subviews.first)
                let zoomRect = zoomRectForScale(2.5, center: point, in: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        @objc func handleSingleTap() {
            parent.onSingleTap()
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView, !isZoomed else { return }

            switch gesture.state {
            case .changed:
                let translation = gesture.translation(in: scrollView)
                if translation.y > 0 {
                    parent.onVerticalDrag(translation.y)
                }
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: scrollView).y
                let translation = gesture.translation(in: scrollView)
                parent.onVerticalDragEnd(max(0, velocity), max(0, translation.y))
            default:
                break
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panGesture,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView else { return true }

            // Only begin if not zoomed and drag is predominantly downward
            guard !isZoomed else { return false }

            let velocity = pan.velocity(in: scrollView)
            let isVertical = abs(velocity.y) > abs(velocity.x) * 1.5
            let isDownward = velocity.y > 0
            return isVertical && isDownward
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Don't conflict with scroll view's own pan
            false
        }

        // MARK: Helpers

        private func zoomRectForScale(_ scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let width = scrollView.bounds.width / scale
            let height = scrollView.bounds.height / scale
            return CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            )
        }
    }
}
