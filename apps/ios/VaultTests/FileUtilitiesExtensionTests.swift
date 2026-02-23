import XCTest
@testable import Vault

final class FileUtilitiesExtensionTests: XCTestCase {

    // MARK: - fileExtension(forMimeType:)

    func testFileExtensionImageTypes() {
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/jpeg"), "jpg")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/png"), "png")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/gif"), "gif")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/heic"), "heic")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/webp"), "webp")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/tiff"), "tiff")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "image/bmp"), "bmp")
    }

    func testFileExtensionVideoTypes() {
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "video/mp4"), "mp4")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "video/quicktime"), "mov")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "video/x-m4v"), "m4v")
    }

    func testFileExtensionDocumentTypes() {
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "application/pdf"), "pdf")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "text/plain"), "txt")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "text/csv"), "csv")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "application/json"), "json")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "application/zip"), "zip")
    }

    func testFileExtensionCaseInsensitive() {
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "IMAGE/JPEG"), "jpg")
        XCTAssertEqual(FileUtilities.fileExtension(forMimeType: "Video/MP4"), "mp4")
    }

    func testFileExtensionUnknownTypeReturnsNil() {
        XCTAssertNil(FileUtilities.fileExtension(forMimeType: "application/octet-stream"))
        XCTAssertNil(FileUtilities.fileExtension(forMimeType: "something/unknown"))
    }

    // MARK: - filenameWithExtension(_:mimeType:)

    func testFilenameWithExtensionAlreadyHasExtensionUnchanged() {
        let result = FileUtilities.filenameWithExtension("photo.jpg", mimeType: "image/jpeg")
        XCTAssertEqual(result, "photo.jpg")
    }

    func testFilenameWithExtensionNoExtensionAppendsFromMimeType() {
        let result = FileUtilities.filenameWithExtension("Gemini_Generated_Image", mimeType: "image/jpeg")
        XCTAssertEqual(result, "Gemini_Generated_Image.jpg")
    }

    func testFilenameWithExtensionNoExtensionPngMimeType() {
        let result = FileUtilities.filenameWithExtension("screenshot", mimeType: "image/png")
        XCTAssertEqual(result, "screenshot.png")
    }

    func testFilenameWithExtensionNoExtensionPdfMimeType() {
        let result = FileUtilities.filenameWithExtension("document", mimeType: "application/pdf")
        XCTAssertEqual(result, "document.pdf")
    }

    func testFilenameWithExtensionNoExtensionVideoMimeType() {
        let result = FileUtilities.filenameWithExtension("recording", mimeType: "video/mp4")
        XCTAssertEqual(result, "recording.mp4")
    }

    func testFilenameWithExtensionNoExtensionNilMimeTypeUnchanged() {
        let result = FileUtilities.filenameWithExtension("mystery_file", mimeType: nil)
        XCTAssertEqual(result, "mystery_file")
    }

    func testFilenameWithExtensionNoExtensionUnknownMimeTypeUnchanged() {
        let result = FileUtilities.filenameWithExtension("binary_blob", mimeType: "application/octet-stream")
        XCTAssertEqual(result, "binary_blob")
    }

    func testFilenameWithExtensionDotInNameButNoRealExtension() {
        // "file.backup" has an extension "backup" — URL(fileURLWithPath:) treats it as an extension.
        // This is correct behavior — we should NOT double-append.
        let result = FileUtilities.filenameWithExtension("file.backup", mimeType: "image/jpeg")
        XCTAssertEqual(result, "file.backup")
    }

    func testFilenameWithExtensionSpacesInName() {
        let result = FileUtilities.filenameWithExtension("My Photo 2026", mimeType: "image/heic")
        XCTAssertEqual(result, "My Photo 2026.heic")
    }

    // MARK: - Round-trip: mimeType ↔ fileExtension

    func testRoundTripExtensionToMimeToExtension() {
        let extensions = ["jpg", "png", "gif", "heic", "mp4", "mov", "pdf"]
        for ext in extensions {
            let mime = FileUtilities.mimeType(forExtension: ext)
            let backToExt = FileUtilities.fileExtension(forMimeType: mime)
            XCTAssertNotNil(backToExt, "Round-trip failed for extension '\(ext)' → mime '\(mime)'")
        }
    }
}
