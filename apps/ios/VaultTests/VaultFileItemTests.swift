import XCTest
@testable import Vault

final class VaultFileItemTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(mimeType: String?, duration: TimeInterval? = nil) -> VaultFileItem {
        VaultFileItem(
            id: UUID(),
            size: 1024,
            hasThumbnail: false,
            mimeType: mimeType,
            filename: "test",
            createdAt: nil,
            duration: duration
        )
    }

    // MARK: - isImage

    func testIsImageTrueForImageMimeTypes() {
        XCTAssertTrue(makeItem(mimeType: "image/png").isImage)
        XCTAssertTrue(makeItem(mimeType: "image/jpeg").isImage)
        XCTAssertTrue(makeItem(mimeType: "image/heic").isImage)
        XCTAssertTrue(makeItem(mimeType: "image/gif").isImage)
    }

    func testIsImageFalseForNonImageMimeTypes() {
        XCTAssertFalse(makeItem(mimeType: "video/mp4").isImage)
        XCTAssertFalse(makeItem(mimeType: "application/pdf").isImage)
        XCTAssertFalse(makeItem(mimeType: "text/plain").isImage)
    }

    func testIsImageFalseForNilMimeType() {
        XCTAssertFalse(makeItem(mimeType: nil).isImage)
    }

    // MARK: - isMedia

    func testIsMediaTrueForImages() {
        XCTAssertTrue(makeItem(mimeType: "image/png").isMedia)
        XCTAssertTrue(makeItem(mimeType: "image/jpeg").isMedia)
    }

    func testIsMediaTrueForVideos() {
        XCTAssertTrue(makeItem(mimeType: "video/mp4").isMedia)
        XCTAssertTrue(makeItem(mimeType: "video/quicktime").isMedia)
    }

    func testIsMediaFalseForDocuments() {
        XCTAssertFalse(makeItem(mimeType: "application/pdf").isMedia)
        XCTAssertFalse(makeItem(mimeType: "text/plain").isMedia)
        XCTAssertFalse(makeItem(mimeType: "application/zip").isMedia)
    }

    func testIsMediaFalseForNilMimeType() {
        XCTAssertFalse(makeItem(mimeType: nil).isMedia)
    }

    // MARK: - Duration

    func testDurationDefaultsToNil() {
        let item = VaultFileItem(
            id: UUID(), size: 100, hasThumbnail: false,
            mimeType: "video/mp4", filename: "clip.mp4"
        )
        XCTAssertNil(item.duration)
    }

    func testDurationPreservedWhenSet() {
        let item = makeItem(mimeType: "video/mp4", duration: 120.5)
        XCTAssertEqual(item.duration, 120.5)
    }
}
