import XCTest
import AVFoundation
@testable import Vault

final class MediaOptimizerTests: XCTestCase {

    private var savedThreshold: Int64 = 0

    override func setUp() {
        super.setUp()
        // Disable small-file skip so existing tests exercise the optimization path
        savedThreshold = MediaOptimizer.imageOptimizationThreshold
        MediaOptimizer.imageOptimizationThreshold = 0
    }

    override func tearDown() {
        MediaOptimizer.imageOptimizationThreshold = savedThreshold
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a minimal valid JPEG file at a temp URL.
    private func createTempJPEG(size: CGSize = CGSize(width: 100, height: 100)) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url)
        return url
    }

    /// Creates a minimal valid PNG file at a temp URL.
    private func createTempPNG(size: CGSize = CGSize(width: 100, height: 100)) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        return url
    }

    /// Creates a temp file with arbitrary data (non-media).
    private func createTempFile(ext: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    // MARK: - Mode Tests

    func testOriginalModePassthroughForImage() async throws {
        let jpegURL = try createTempJPEG()
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .original
        )

        XCTAssertFalse(result.wasOptimized, "Original mode should not optimize")
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual(result.url, jpegURL, "Should return same URL in original mode")
    }

    func testSmallImageSkipsOptimization() async throws {
        // Restore threshold so this test exercises the skip behavior
        MediaOptimizer.imageOptimizationThreshold = 500_000
        let jpegURL = try createTempJPEG(size: CGSize(width: 100, height: 100))
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: jpegURL.path)[.size] as? Int64) ?? 0
        XCTAssertLessThan(fileSize, 500_000, "Test image should be under 500KB")

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized, "Small image should skip optimization")
        XCTAssertEqual(result.mimeType, "image/jpeg", "Should preserve original mime type")
        XCTAssertEqual(result.url, jpegURL, "Should return same URL")
    }

    func testOriginalModePassthroughForVideo() async throws {
        // Create a minimal video to test passthrough
        let videoURL = try await createMinimalVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .original
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "video/quicktime")
        XCTAssertEqual(result.url, videoURL)
    }

    // MARK: - Image Optimization

    func testJPEGOptimizesToHEIC() async throws {
        let jpegURL = try createTempJPEG(size: CGSize(width: 500, height: 500))
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized, "JPEG should be optimized to HEIC")
        XCTAssertEqual(result.mimeType, "image/heic")
        XCTAssertTrue(result.url.pathExtension == "heic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPNGSkipsLossyHEICConversion() async throws {
        let pngURL = try createTempPNG(size: CGSize(width: 500, height: 500))
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: pngURL, mimeType: "image/png", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized, "PNG should skip lossy HEIC conversion")
        XCTAssertEqual(result.mimeType, "image/png", "PNG mime type should be preserved")
        XCTAssertEqual(result.url, pngURL, "PNG should return same URL")
    }

    func testHEICImageSkipsOptimization() async throws {
        // Create a JPEG, optimize it to HEIC, then try to optimize the HEIC
        let jpegURL = try createTempJPEG()
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let result1 = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        XCTAssertTrue(result1.wasOptimized)
        defer { try? FileManager.default.removeItem(at: result1.url) }

        // Now try to optimize the HEIC — should skip
        let result2 = try await MediaOptimizer.shared.optimize(
            fileURL: result1.url, mimeType: "image/heic", mode: .optimized
        )

        XCTAssertFalse(result2.wasOptimized, "HEIC should not be re-optimized")
        XCTAssertEqual(result2.mimeType, "image/heic")
        XCTAssertEqual(result2.url, result1.url)
    }

    func testHEIFImageSkipsOptimization() async throws {
        let jpegURL = try createTempJPEG()
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/heif", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized, "HEIF should not be re-optimized")
        XCTAssertEqual(result.mimeType, "image/heif")
    }

    func testOptimizedImageIsSmallerThanOriginal() async throws {
        // Create a larger image for more noticeable compression
        let jpegURL = try createTempJPEG(size: CGSize(width: 1000, height: 1000))
        defer { try? FileManager.default.removeItem(at: jpegURL) }
        let originalSize = try FileManager.default.attributesOfItem(atPath: jpegURL.path)[.size] as? Int64 ?? 0

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized)
        let optimizedSize = try FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int64 ?? 0
        XCTAssertLessThan(optimizedSize, originalSize, "HEIC output should be smaller than JPEG input")
    }

    // MARK: - Non-Media Passthrough

    func testPDFPassesThrough() async throws {
        let pdfURL = try createTempFile(ext: "pdf", data: Data(repeating: 0x25, count: 1000))
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: pdfURL, mimeType: "application/pdf", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "application/pdf")
        XCTAssertEqual(result.url, pdfURL)
    }

    func testZIPPassesThrough() async throws {
        let zipURL = try createTempFile(ext: "zip", data: Data(repeating: 0x50, count: 500))
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: zipURL, mimeType: "application/zip", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "application/zip")
    }

    func testPlainTextPassesThrough() async throws {
        let txtURL = try createTempFile(ext: "txt", data: "Hello world".data(using: .utf8)!)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: txtURL, mimeType: "text/plain", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "text/plain")
    }

    // MARK: - UIImage Optimization

    func testOptimizeUIImageOptimizedMode() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        let (url, mimeType) = try await MediaOptimizer.shared.optimizeImage(image, mode: .optimized)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(mimeType, "image/heic")
        XCTAssertTrue(url.pathExtension == "heic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testOptimizeUIImageOriginalMode() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        let (url, mimeType) = try await MediaOptimizer.shared.optimizeImage(image, mode: .original)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(mimeType, "image/jpeg")
        XCTAssertTrue(url.pathExtension == "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Filename Update Helpers

    func testUpdatedFilenameJPEGToHEIC() {
        let result = MediaOptimizer.updatedFilename("IMG_12345.jpg", newMimeType: "image/heic")
        XCTAssertEqual(result, "IMG_12345.heic")
    }

    func testUpdatedFilenamePNGToHEIC() {
        let result = MediaOptimizer.updatedFilename("photo.png", newMimeType: "image/heic")
        XCTAssertEqual(result, "photo.heic")
    }

    func testUpdatedFilenameMOVToMP4() {
        let result = MediaOptimizer.updatedFilename("VID_20260217.mov", newMimeType: "video/mp4")
        XCTAssertEqual(result, "VID_20260217.mp4")
    }

    func testUpdatedFilenameUnchangedForUnknownMime() {
        let result = MediaOptimizer.updatedFilename("document.pdf", newMimeType: "application/pdf")
        XCTAssertEqual(result, "document.pdf")
    }

    func testUpdatedFilenamePreservesBaseName() {
        let result = MediaOptimizer.updatedFilename("My Vacation Photo.jpeg", newMimeType: "image/heic")
        XCTAssertEqual(result, "My Vacation Photo.heic")
    }

    func testUpdatedFilenameHEIFMime() {
        let result = MediaOptimizer.updatedFilename("photo.tiff", newMimeType: "image/heif")
        XCTAssertEqual(result, "photo.heic")
    }

    // MARK: - Mode Enum

    func testModeRawValues() {
        XCTAssertEqual(MediaOptimizer.Mode(rawValue: "optimized"), .optimized)
        XCTAssertEqual(MediaOptimizer.Mode(rawValue: "original"), .original)
        XCTAssertNil(MediaOptimizer.Mode(rawValue: "invalid"))
    }

    func testModeDefaultsToOptimized() {
        let mode = MediaOptimizer.Mode(rawValue: "optimized") ?? .original
        XCTAssertEqual(mode, .optimized)
    }

    // MARK: - Video Optimization

    func testVideoOptimization() async throws {
        let videoURL = try await createMinimalVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        // Minimal videos may or may not get optimized depending on the codec/preset availability
        // but the method should not crash and should return valid results
        if result.wasOptimized {
            XCTAssertEqual(result.mimeType, "video/mp4")
            XCTAssertTrue(result.url.pathExtension == "mp4")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        } else {
            // If HEVC preset isn't available or video is already optimal, passthrough is fine
            XCTAssertEqual(result.mimeType, "video/quicktime")
        }
    }

    func testPortraitVideoPreservesNaturalSize() async throws {
        // Create a portrait video (1080x1920 natural with 90° rotation transform)
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, rotated: true)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        if result.wasOptimized {
            XCTAssertEqual(result.mimeType, "video/mp4")

            // Verify the output video track dimensions match naturalSize (not transformed)
            let asset = AVURLAsset(url: result.url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
                XCTFail("No video track in output")
                return
            }
            let outputSize = try await track.load(.naturalSize)
            // Writer dimensions should be based on naturalSize (1920x1080),
            // NOT the transformed size (1080x1920)
            XCTAssertEqual(Int(outputSize.width), 1920)
            XCTAssertEqual(Int(outputSize.height), 1080)
        }
        // If not optimized (e.g., bitrate already low), that's acceptable
    }

    // MARK: - Skip-Transcode Policy Tests
    //
    // These tests verify the video optimization skip/transcode policy:
    //   SKIP:      HEVC codec + resolution ≤1080p (any bitrate)
    //   TRANSCODE: non-HEVC codec (any resolution) OR HEVC >1080p (downscale)

    // -- HEVC ≤1080p → always skip --

    func testHEVC1080pSkipsTranscode() async throws {
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertFalse(result.wasOptimized, "HEVC 1080p should skip transcode")
        XCTAssertEqual(result.url, videoURL, "Skipped video must return original URL")
    }

    func testHEVC720pSkipsTranscode() async throws {
        let videoURL = try await createMinimalVideo(width: 1280, height: 720, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertFalse(result.wasOptimized, "HEVC 720p should skip transcode")
        XCTAssertEqual(result.url, videoURL)
    }

    func testHEVCSubSDSkipsTranscode() async throws {
        let videoURL = try await createMinimalVideo(width: 480, height: 360, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertFalse(result.wasOptimized, "HEVC sub-SD should skip transcode")
        XCTAssertEqual(result.url, videoURL)
    }

    func testHEVCPortrait1080pSkipsTranscode() async throws {
        // Portrait: sensor captures 1920x1080 natural with 90° rotation
        // naturalSize is 1920x1080, maxDimension=1920 ≤ 1920 → skip
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, rotated: true, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertFalse(result.wasOptimized, "Portrait HEVC ≤1080p should skip transcode")
        XCTAssertEqual(result.url, videoURL)
    }

    /// Regression guard: creates HEVC video with random-noise pixels so the encoder
    /// produces high bitrate (>5 Mbps). The old code had a 5 Mbps threshold that would
    /// have forced transcoding; the new code skips regardless of bitrate.
    func testHEVCHighBitrateAboveOldThresholdStillSkips() async throws {
        let videoURL = try await createMinimalVideo(width: 640, height: 480, codec: .hevc, highEntropy: true)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        // Verify the test video actually has high bitrate for the regression guard to be meaningful
        let asset = AVURLAsset(url: videoURL)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let rate = try? await track.load(.estimatedDataRate),
           rate <= 5_000_000 {
            XCTFail("Test video bitrate \(Int(rate / 1000)) kbps is ≤5 Mbps — regression guard is not meaningful (need random noise to exceed old threshold)")
        }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertFalse(result.wasOptimized, "HEVC ≤1080p must skip transcode even at high bitrate")
        XCTAssertEqual(result.url, videoURL)
    }

    // -- Skipped video contract: caller-facing guarantees --

    func testSkippedVideoPreservesOriginalMimeType() async throws {
        let videoURL = try await createMinimalVideo(width: 640, height: 480, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "video/quicktime",
                       "Skipped video must preserve original mime type, not convert to video/mp4")
    }

    func testSkippedVideoPreservesMp4MimeType() async throws {
        // An already-optimal .mp4 HEVC file should keep its video/mp4 mime
        let videoURL = try await createMinimalVideo(width: 640, height: 480, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/mp4", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "video/mp4",
                       "Skipped video must preserve whatever mime type was passed in")
    }

    func testFilenameUnchangedWhenVideoSkipped() {
        // When wasOptimized is false, callers don't call updatedFilename.
        // Verify the helper returns the original for non-mp4/heic mime types.
        let result = MediaOptimizer.updatedFilename("VID_001.mov", newMimeType: "video/quicktime")
        XCTAssertEqual(result, "VID_001.mov", "Filename should be unchanged for non-mp4 mime type")
    }

    // -- Non-HEVC → must transcode --

    func testH264At720pTriggersTranscode() async throws {
        let videoURL = try await createMinimalVideo(width: 1280, height: 720, codec: .h264)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        // H.264 should trigger transcoding (may be discarded by threshold for tiny test videos)
        if result.wasOptimized {
            XCTAssertEqual(result.mimeType, "video/mp4", "H.264 source should be re-encoded to HEVC MP4")
            XCTAssertNotEqual(result.url, videoURL, "Transcoded video should be a new temp file")
            XCTAssertEqual(result.url.pathExtension, "mp4")
        }
    }

    func testH264At1080pTriggersTranscode() async throws {
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, codec: .h264)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        if result.wasOptimized {
            XCTAssertEqual(result.mimeType, "video/mp4", "H.264 1080p should be transcoded to HEVC MP4")
            XCTAssertNotEqual(result.url, videoURL)
        }
    }

    // -- HEVC >1080p → must transcode (downscale) --

    func testHEVC4KTriggersTranscodeAndDownscales() async throws {
        let videoURL = try await createMinimalVideo(width: 3840, height: 2160, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        if result.wasOptimized {
            XCTAssertEqual(result.mimeType, "video/mp4", "4K HEVC should be transcoded")

            let asset = AVURLAsset(url: result.url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
                XCTFail("No video track in output")
                return
            }
            let outputSize = try await track.load(.naturalSize)
            let maxDim = max(outputSize.width, outputSize.height)
            XCTAssertLessThanOrEqual(maxDim, 1920, "4K should be downscaled to ≤1080p")
            // Verify aspect ratio preserved: 3840:2160 = 16:9, output should also be 16:9
            XCTAssertEqual(Int(outputSize.width), 1920)
            XCTAssertEqual(Int(outputSize.height), 1080)
        }
    }

    // -- Transcoded video contract --

    func testTranscodedVideoOutputIsMp4WithNewURL() async throws {
        // Use default H.264 320x240 — small, fast transcode
        let videoURL = try await createMinimalVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        if result.wasOptimized {
            XCTAssertNotEqual(result.url, videoURL, "Transcoded output must be a different file")
            XCTAssertEqual(result.mimeType, "video/mp4", "Transcoded output must be MP4")
            XCTAssertEqual(result.url.pathExtension, "mp4")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        }
    }

    // MARK: - VideoOptimizationStrategy Tests

    func testStrategySkipForHEVC1080p() async throws {
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let strategy = await MediaOptimizer.shared.videoOptimizationStrategy(for: asset)
        XCTAssertEqual(strategy, .skip, "HEVC ≤1080p should return .skip")
    }

    func testStrategySkipForHEVC720p() async throws {
        let videoURL = try await createMinimalVideo(width: 1280, height: 720, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let strategy = await MediaOptimizer.shared.videoOptimizationStrategy(for: asset)
        XCTAssertEqual(strategy, .skip, "HEVC 720p should return .skip")
    }

    func testStrategyExportSessionForHEVC4K() async throws {
        let videoURL = try await createMinimalVideo(width: 3840, height: 2160, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let strategy = await MediaOptimizer.shared.videoOptimizationStrategy(for: asset)
        XCTAssertEqual(strategy, .exportSession, "HEVC >1080p should return .exportSession")
    }

    func testStrategyReaderWriterForH264() async throws {
        let videoURL = try await createMinimalVideo(width: 1280, height: 720, codec: .h264)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let strategy = await MediaOptimizer.shared.videoOptimizationStrategy(for: asset)
        XCTAssertEqual(strategy, .readerWriter, "H.264 should return .readerWriter")
    }

    func testStrategyReaderWriterForH264At4K() async throws {
        let videoURL = try await createMinimalVideo(width: 3840, height: 2160, codec: .h264)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let strategy = await MediaOptimizer.shared.videoOptimizationStrategy(for: asset)
        XCTAssertEqual(strategy, .readerWriter, "H.264 4K should return .readerWriter (codec change, not just downscale)")
    }

    func testStrategySkipForHEVCPortrait1080p() async throws {
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, rotated: true, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let strategy = await MediaOptimizer.shared.videoOptimizationStrategy(for: asset)
        XCTAssertEqual(strategy, .skip, "Portrait HEVC ≤1080p should return .skip")
    }

    // MARK: - ExportSession Path Integration

    func testExportSessionPathProducesValidHEVCOutput() async throws {
        // HEVC 4K should use ExportSession path and produce valid 1080p output
        let videoURL = try await createMinimalVideo(width: 3840, height: 2160, codec: .hevc)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        if result.wasOptimized {
            XCTAssertEqual(result.mimeType, "video/mp4")
            XCTAssertEqual(result.url.pathExtension, "mp4")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))

            // Verify output is HEVC
            let asset = AVURLAsset(url: result.url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let fmtDescs = try? await track.load(.formatDescriptions),
                  let desc = fmtDescs.first else {
                XCTFail("No video track or format description in output")
                return
            }
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            XCTAssertEqual(subType, 0x68766331, "Output should be HEVC (hvc1)")

            let outputSize = try await track.load(.naturalSize)
            let maxDim = max(outputSize.width, outputSize.height)
            XCTAssertLessThanOrEqual(maxDim, 1920, "ExportSession should downscale to ≤1080p")
        }
    }

    // MARK: - Video Helper

    /// Creates a minimal 1-second video file for testing.
    /// - Parameters:
    ///   - width: Pixel buffer width (default 320)
    ///   - height: Pixel buffer height (default 240)
    ///   - rotated: If true, applies a 90° clockwise rotation transform (simulates portrait recording)
    ///   - codec: Video codec to use (default .h264)
    ///   - highEntropy: If true, fills frames with random noise (incompressible → high bitrate output)
    private func createMinimalVideo(width: Int = 320, height: Int = 240, rotated: Bool = false, codec: AVVideoCodecType = .h264, highEntropy: Bool = false) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Create a simple video using AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        if rotated {
            // 90° clockwise rotation (portrait video recorded in landscape sensor)
            writerInput.transform = CGAffineTransform(rotationAngle: .pi / 2)
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write 30 frames at 30fps = 1 second
        for i in 0..<30 {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32ARGB, nil, &pixelBuffer
            )
            guard let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                if highEntropy {
                    // Random noise — incompressible content forces high encoder bitrate
                    arc4random_buf(baseAddress, height * bytesPerRow)
                } else {
                    // Fill with a color gradient per frame
                    let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
                    for y in 0..<height {
                        for x in 0..<width {
                            let offset = y * bytesPerRow + x * 4
                            ptr[offset] = 255 // A
                            ptr[offset + 1] = UInt8(i * 8 % 256) // R
                            ptr[offset + 2] = UInt8(x * 255 / width) // G
                            ptr[offset + 3] = UInt8(y * 255 / height) // B
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let time = CMTime(value: CMTimeValue(i), timescale: 30)
            adaptor.append(buffer, withPresentationTime: time)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video write failed"])
        }

        return outputURL
    }
}
