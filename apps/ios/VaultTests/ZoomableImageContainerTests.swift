import XCTest
import UIKit
@testable import Vault

final class ZoomableImageContainerTests: XCTestCase {

    // MARK: - centerImageView

    func testCenterImageViewCentersSmallContent() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        scrollView.addSubview(imageView)
        scrollView.contentSize = CGSize(width: 200, height: 300)
        scrollView.zoomScale = 1.0

        ZoomableImageContainer.centerImageView(imageView, in: scrollView)

        // Horizontal: (400 - 200) / 2 = 100 offset, center.x = 100 + 100 = 200
        XCTAssertEqual(imageView.center.x, 200, accuracy: 0.5)
        // Vertical: (800 - 300) / 2 = 250 offset, center.y = 150 + 250 = 400
        XCTAssertEqual(imageView.center.y, 400, accuracy: 0.5)
    }

    func testCenterImageViewAtZoomScale() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        // At 2x zoom, imageView.frame is already scaled by UIScrollView
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.addSubview(imageView)
        scrollView.contentSize = CGSize(width: 400, height: 600)
        scrollView.zoomScale = 2.0

        ZoomableImageContainer.centerImageView(imageView, in: scrollView)

        // At 2x zoom: frame is 400x600, fits in 400x800
        // Horizontal: max(0, (400 - 400)/2) = 0, center.x = 200
        XCTAssertEqual(imageView.center.x, 200, accuracy: 0.5)
        // Vertical: max(0, (800 - 600)/2) = 100, center.y = 300 + 100 = 400
        XCTAssertEqual(imageView.center.y, 400, accuracy: 0.5)
    }

    func testCenterImageViewFullWidthContent() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        scrollView.addSubview(imageView)
        scrollView.contentSize = CGSize(width: 400, height: 400)
        scrollView.zoomScale = 1.0

        ZoomableImageContainer.centerImageView(imageView, in: scrollView)

        XCTAssertEqual(imageView.center.x, 200, accuracy: 0.5)
        // Vertical: (800 - 400) / 2 = 200, center.y = 200 + 200 = 400
        XCTAssertEqual(imageView.center.y, 400, accuracy: 0.5)
    }

    func testCenterImageViewOverflowingContent() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 600, height: 1200))
        scrollView.addSubview(imageView)
        scrollView.contentSize = CGSize(width: 600, height: 1200)
        scrollView.zoomScale = 1.0

        ZoomableImageContainer.centerImageView(imageView, in: scrollView)

        // Content bigger than bounds: offsets should be 0 (max(0, negative))
        // center.x = 600/2 + 0 = 300
        XCTAssertEqual(imageView.center.x, 300, accuracy: 0.5)
        // center.y = 1200/2 + 0 = 600
        XCTAssertEqual(imageView.center.y, 600, accuracy: 0.5)
    }

    // MARK: - Coordinator

    func testCoordinatorViewForZooming() {
        let image = UIImage(systemName: "photo")!
        let container = ZoomableImageContainer(
            image: image,
            containerSize: CGSize(width: 400, height: 800),
            onSingleTap: {
                // No-op: unused in test
            },
            onVerticalDrag: { _ in
                // No-op: unused in test
            },
            onVerticalDragEnd: { _, _ in
                // No-op: unused in test
            },
            onZoomChange: { _ in
                // No-op: unused in test
            }
        )

        let coordinator = container.makeCoordinator()
        let scrollView = UIScrollView()
        let imageView = UIImageView()
        coordinator.scrollView = scrollView
        coordinator.imageView = imageView

        let result = coordinator.viewForZooming(in: scrollView)
        XCTAssertIdentical(result, imageView)
    }

    func testCoordinatorZoomChangeCallback() {
        var reportedScale: CGFloat = 0
        let image = UIImage(systemName: "photo")!
        let container = ZoomableImageContainer(
            image: image,
            containerSize: CGSize(width: 400, height: 800),
            onSingleTap: {
                // No-op: unused in test
            },
            onVerticalDrag: { _ in
                // No-op: unused in test
            },
            onVerticalDragEnd: { _, _ in
                // No-op: unused in test
            },
            onZoomChange: { scale in reportedScale = scale }
        )

        let coordinator = container.makeCoordinator()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        scrollView.addSubview(imageView)
        coordinator.scrollView = scrollView
        coordinator.imageView = imageView

        coordinator.scrollViewDidEndZooming(scrollView, with: imageView, atScale: 3.0)
        XCTAssertEqual(reportedScale, 3.0)
    }

    func testPanGestureBlockedWhenZoomed() {
        let image = UIImage(systemName: "photo")!
        let container = ZoomableImageContainer(
            image: image,
            containerSize: CGSize(width: 400, height: 800),
            onSingleTap: {
                // No-op: unused in test
            },
            onVerticalDrag: { _ in
                // No-op: unused in test
            },
            onVerticalDragEnd: { _, _ in
                // No-op: unused in test
            },
            onZoomChange: { _ in
                // No-op: unused in test
            }
        )

        let coordinator = container.makeCoordinator()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.zoomScale = 2.0
        coordinator.scrollView = scrollView

        let pan = UIPanGestureRecognizer()
        coordinator.panGesture = pan

        let shouldBegin = coordinator.gestureRecognizerShouldBegin(pan)
        XCTAssertFalse(shouldBegin)
    }

    func testSimultaneousGestureRecognitionDisabled() {
        let image = UIImage(systemName: "photo")!
        let container = ZoomableImageContainer(
            image: image,
            containerSize: CGSize(width: 400, height: 800),
            onSingleTap: {
                // No-op: unused in test
            },
            onVerticalDrag: { _ in
                // No-op: unused in test
            },
            onVerticalDragEnd: { _, _ in
                // No-op: unused in test
            },
            onZoomChange: { _ in
                // No-op: unused in test
            }
        )

        let coordinator = container.makeCoordinator()
        let gesture1 = UITapGestureRecognizer()
        let gesture2 = UITapGestureRecognizer()

        let result = coordinator.gestureRecognizer(gesture1, shouldRecognizeSimultaneouslyWith: gesture2)
        XCTAssertFalse(result)
    }

    // MARK: - Image identity check (used for zoom reset)

    func testDifferentImagesAreNotIdentical() {
        // The zoom-reset logic uses `!==` (identity check) on UIImage.
        // Different UIImage instances from different symbols should not be identical.
        let image1 = UIImage(systemName: "photo")!
        let image2 = UIImage(systemName: "star")!
        XCTAssertFalse(image1 === image2, "Different images should not be identical")
    }

    func testSameImageReferenceIsIdentical() {
        let image = UIImage(systemName: "photo")!
        let sameRef = image
        XCTAssertTrue(image === sameRef, "Same reference should be identical")
    }

    // MARK: - Zoom threshold constant

    func testZoomThresholdIsReasonable() {
        XCTAssertGreaterThan(ZoomableImageContainer.zoomThreshold, 1.0)
        XCTAssertLessThan(ZoomableImageContainer.zoomThreshold, 1.2)
    }
}
