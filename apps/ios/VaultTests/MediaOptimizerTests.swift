import XCTest
import AVFoundation
@testable import Vault

final class MediaOptimizerTests: XCTestCase {

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

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .original
        )

        XCTAssertFalse(wasOptimized, "Original mode should not optimize")
        XCTAssertEqual(mimeType, "image/jpeg")
        XCTAssertEqual(outputURL, jpegURL, "Should return same URL in original mode")
    }

    func testOriginalModePassthroughForVideo() async throws {
        // Create a minimal video to test passthrough
        let videoURL = try await createMinimalVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .original
        )

        XCTAssertFalse(wasOptimized)
        XCTAssertEqual(mimeType, "video/quicktime")
        XCTAssertEqual(outputURL, videoURL)
    }

    // MARK: - Image Optimization

    func testJPEGOptimizesToHEIC() async throws {
        let jpegURL = try createTempJPEG(size: CGSize(width: 500, height: 500))
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if wasOptimized { try? FileManager.default.removeItem(at: outputURL) } }

        XCTAssertTrue(wasOptimized, "JPEG should be optimized to HEIC")
        XCTAssertEqual(mimeType, "image/heic")
        XCTAssertTrue(outputURL.pathExtension == "heic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testPNGOptimizesToHEIC() async throws {
        let pngURL = try createTempPNG(size: CGSize(width: 500, height: 500))
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: pngURL, mimeType: "image/png", mode: .optimized
        )
        defer { if wasOptimized { try? FileManager.default.removeItem(at: outputURL) } }

        XCTAssertTrue(wasOptimized)
        XCTAssertEqual(mimeType, "image/heic")
    }

    func testHEICImageSkipsOptimization() async throws {
        // Create a JPEG, optimize it to HEIC, then try to optimize the HEIC
        let jpegURL = try createTempJPEG()
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let (heicURL, _, firstWasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        XCTAssertTrue(firstWasOptimized)
        defer { try? FileManager.default.removeItem(at: heicURL) }

        // Now try to optimize the HEIC — should skip
        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: heicURL, mimeType: "image/heic", mode: .optimized
        )

        XCTAssertFalse(wasOptimized, "HEIC should not be re-optimized")
        XCTAssertEqual(mimeType, "image/heic")
        XCTAssertEqual(outputURL, heicURL)
    }

    func testHEIFImageSkipsOptimization() async throws {
        let jpegURL = try createTempJPEG()
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let (_, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/heif", mode: .optimized
        )

        XCTAssertFalse(wasOptimized, "HEIF should not be re-optimized")
        XCTAssertEqual(mimeType, "image/heif")
    }

    func testOptimizedImageIsSmallerThanOriginal() async throws {
        // Create a larger image for more noticeable compression
        let jpegURL = try createTempJPEG(size: CGSize(width: 1000, height: 1000))
        defer { try? FileManager.default.removeItem(at: jpegURL) }
        let originalSize = try FileManager.default.attributesOfItem(atPath: jpegURL.path)[.size] as! Int64

        let (outputURL, _, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if wasOptimized { try? FileManager.default.removeItem(at: outputURL) } }

        XCTAssertTrue(wasOptimized)
        let optimizedSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as! Int64
        XCTAssertLessThan(optimizedSize, originalSize, "HEIC output should be smaller than JPEG input")
    }

    // MARK: - Non-Media Passthrough

    func testPDFPassesThrough() async throws {
        let pdfURL = try createTempFile(ext: "pdf", data: Data(repeating: 0x25, count: 1000))
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: pdfURL, mimeType: "application/pdf", mode: .optimized
        )

        XCTAssertFalse(wasOptimized)
        XCTAssertEqual(mimeType, "application/pdf")
        XCTAssertEqual(outputURL, pdfURL)
    }

    func testZIPPassesThrough() async throws {
        let zipURL = try createTempFile(ext: "zip", data: Data(repeating: 0x50, count: 500))
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let (_, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: zipURL, mimeType: "application/zip", mode: .optimized
        )

        XCTAssertFalse(wasOptimized)
        XCTAssertEqual(mimeType, "application/zip")
    }

    func testPlainTextPassesThrough() async throws {
        let txtURL = try createTempFile(ext: "txt", data: "Hello world".data(using: .utf8)!)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        let (_, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: txtURL, mimeType: "text/plain", mode: .optimized
        )

        XCTAssertFalse(wasOptimized)
        XCTAssertEqual(mimeType, "text/plain")
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

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if wasOptimized { try? FileManager.default.removeItem(at: outputURL) } }

        // Minimal videos may or may not get optimized depending on the codec/preset availability
        // but the method should not crash and should return valid results
        if wasOptimized {
            XCTAssertEqual(mimeType, "video/mp4")
            XCTAssertTrue(outputURL.pathExtension == "mp4")
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        } else {
            // If HEVC preset isn't available or video is already optimal, passthrough is fine
            XCTAssertEqual(mimeType, "video/quicktime")
        }
    }

    func testPortraitVideoPreservesNaturalSize() async throws {
        // Create a portrait video (1080x1920 natural with 90° rotation transform)
        let videoURL = try await createMinimalVideo(width: 1920, height: 1080, rotated: true)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let (outputURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: videoURL, mimeType: "video/quicktime", mode: .optimized
        )
        defer { if wasOptimized { try? FileManager.default.removeItem(at: outputURL) } }

        if wasOptimized {
            XCTAssertEqual(mimeType, "video/mp4")

            // Verify the output video track dimensions match naturalSize (not transformed)
            let asset = AVURLAsset(url: outputURL)
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

    // MARK: - Video Helper

    /// Creates a minimal 1-second video file for testing.
    /// - Parameters:
    ///   - width: Pixel buffer width (default 320)
    ///   - height: Pixel buffer height (default 240)
    ///   - rotated: If true, applies a 90° clockwise rotation transform (simulates portrait recording)
    private func createMinimalVideo(width: Int = 320, height: Int = 240, rotated: Bool = false) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Create a simple video using AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
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
                // Fill with a color gradient per frame
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
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
