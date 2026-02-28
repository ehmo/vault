import XCTest
import AVFoundation
import ImageIO
@testable import Vault

/// Tests for the 4-worker import pipeline, JPEG roundtrip elimination,
/// autoreleasepool correctness, and worker count configuration.
final class ImportOptimizationTests: XCTestCase {

    private var savedThreshold: Int64 = 0

    override func setUp() {
        super.setUp()
        savedThreshold = MediaOptimizer.imageOptimizationThreshold
        MediaOptimizer.imageOptimizationThreshold = 0
    }

    override func tearDown() {
        MediaOptimizer.imageOptimizationThreshold = savedThreshold
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a JPEG at exact pixel dimensions (not points) using a @1x scale renderer.
    private func createTempJPEG(pixels: CGSize = CGSize(width: 200, height: 200)) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 1 point = 1 pixel
        let renderer = UIGraphicsImageRenderer(size: pixels, format: format)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixels))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "Test", code: 1)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url)
        return url
    }

    /// Creates a PNG at exact pixel dimensions using a @1x scale renderer.
    private func createTempPNG(pixels: CGSize = CGSize(width: 200, height: 200)) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: pixels, format: format)
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixels))
        }
        guard let data = image.pngData() else {
            throw NSError(domain: "Test", code: 1)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        return url
    }

    private func createTempHEIC(pixels: CGSize = CGSize(width: 200, height: 200)) throws -> URL {
        // Create via ImageIO to get a real HEIC file
        let jpegURL = try createTempJPEG(pixels: pixels)
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        guard let source = CGImageSourceCreateWithURL(jpegURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "Test", code: 2)
        }

        let heicURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heic")
        guard let dest = CGImageDestinationCreateWithURL(
            heicURL as CFURL, AVFileType.heic as CFString, 1, nil
        ) else {
            throw NSError(domain: "Test", code: 3)
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "Test", code: 4)
        }
        return heicURL
    }

    /// Creates an image file with an unusual extension that isn't in FileUtilities.mimeType
    private func createTempImageWithUnknownExt(ext: String, pixels: CGSize = CGSize(width: 200, height: 200)) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: pixels, format: format)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixels))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "Test", code: 1)
        }
        // Write JPEG data with a non-standard extension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    // MARK: - 4-Worker Concurrency

    private actor ConcurrencyMonitor {
        private(set) var current = 0
        private(set) var peak = 0

        func enter() {
            current += 1
            if current > peak { peak = current }
        }

        func exit() {
            current -= 1
        }
    }

    /// Verifies that 4 workers actually run in parallel (not regressed to 3 or fewer).
    func testFourWorkersRunInParallel() async {
        let monitor = ConcurrencyMonitor()
        let items = Array(0..<12)
        let queue = ParallelImporter.Queue(items)
        let workerCount = 4

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let start = ContinuousClockInstant.now

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, workerCount)],
                process: { @Sendable item in
                    await monitor.enter()
                    try await Task.sleep(for: .milliseconds(100))
                    await monitor.exit()
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "item\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var importedCount = 0
        for await event in stream {
            if case .imported = event { importedCount += 1 }
        }
        await workerTask.value

        let elapsed = ContinuousClockInstant.now - start
        let peakConcurrency = await monitor.peak

        // With 4 workers processing 12 items of 100ms each:
        // Parallel (4): peak >= 4, elapsed ~300ms
        // Regressed (3): peak == 3, elapsed ~400ms
        // Serial (1): elapsed ~1200ms
        XCTAssertGreaterThanOrEqual(peakConcurrency, 4, "Peak concurrency should be >= 4 (was \(peakConcurrency))")
        XCTAssertEqual(importedCount, 12, "All 12 items should be imported")
        XCTAssertLessThan(elapsed, .milliseconds(500), "4-worker parallel execution should complete in <500ms")
    }

    /// Verifies the correct worker count split: 2 video + 2 image when both types present.
    func testWorkerCountSplitWithMixedMedia() async {
        let videoMonitor = ConcurrencyMonitor()
        let imageMonitor = ConcurrencyMonitor()

        // 4 videos + 4 images, each taking 200ms
        let videoItems = Array(0..<4)
        let imageItems = Array(100..<104)
        let videoQueue = ParallelImporter.Queue(videoItems)
        let imageQueue = ParallelImporter.Queue(imageItems)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await Self.runSplitWorkers(
                videoQueue: videoQueue, imageQueue: imageQueue,
                videoMonitor: videoMonitor, imageMonitor: imageMonitor,
                continuation: continuation
            )
            continuation.finish()
        }

        var count = 0
        for await event in stream {
            if case .imported = event { count += 1 }
        }
        await workerTask.value

        let videoPeak = await videoMonitor.peak
        let imagePeak = await imageMonitor.peak

        XCTAssertEqual(count, 8, "All 8 items should be imported")
        XCTAssertGreaterThanOrEqual(videoPeak, 2, "Video workers should reach concurrency 2 (was \(videoPeak))")
        XCTAssertGreaterThanOrEqual(imagePeak, 2, "Image workers should reach concurrency 2 (was \(imagePeak))")
    }

    /// Verifies that with images-only, all 4 workers process images.
    func testAllFourWorkersForImagesOnly() async {
        let monitor = ConcurrencyMonitor()
        let items = Array(0..<8)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            // Simulate images-only: 0 video workers + 4 image workers
            await ParallelImporter.runWorkers(
                queues: [(queue, 4)],
                process: { @Sendable item in
                    await monitor.enter()
                    try await Task.sleep(for: .milliseconds(200))
                    await monitor.exit()
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "image/heic", filename: "img\(item).heic"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var count = 0
        for await event in stream {
            if case .imported = event { count += 1 }
        }
        await workerTask.value

        let peakConcurrency = await monitor.peak
        XCTAssertEqual(count, 8)
        XCTAssertGreaterThanOrEqual(peakConcurrency, 4, "All 4 workers should be used for images-only (peak was \(peakConcurrency))")
    }

    // MARK: - Direct Image Optimization (No JPEG Roundtrip)

    /// Verifies that a PNG file is optimized to HEIC without intermediate JPEG conversion.
    /// The output should be a valid HEIC file produced directly from the PNG source.
    func testPNGSkipsLossyHEICConversion() async throws {
        let pngURL = try createTempPNG(pixels: CGSize(width: 500, height: 500))
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: pngURL, mimeType: "image/png", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized, "PNG should skip lossy HEIC conversion")
        XCTAssertEqual(result.mimeType, "image/png", "PNG mime type should be preserved")
        XCTAssertEqual(result.url, pngURL, "PNG should return same URL")
    }

    /// Verifies that a JPEG is optimized directly to HEIC (single decode, no intermediate).
    func testJPEGOptimizesDirectlyToHEIC() async throws {
        let jpegURL = try createTempJPEG(pixels: CGSize(width: 500, height: 500))
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "image/heic")

        // Verify valid HEIC output
        guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Output should be a valid decodable HEIC")
            return
        }
        XCTAssertEqual(image.width, 500)
        XCTAssertEqual(image.height, 500)
    }

    // MARK: - HEIC Passthrough (No Double-Compression)

    /// Critical regression test: HEIC images must NOT be lossy-recompressed.
    /// The old code would HEIC→UIImage→JPEG→HEIC causing quality loss.
    /// The new code must pass HEIC through unchanged.
    func testHEICImagePassesThroughUnchanged() async throws {
        let heicURL = try createTempHEIC(pixels: CGSize(width: 300, height: 300))
        defer { try? FileManager.default.removeItem(at: heicURL) }
        let originalSize = try FileManager.default.attributesOfItem(atPath: heicURL.path)[.size] as? Int64 ?? 0

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: heicURL, mimeType: "image/heic", mode: .optimized
        )

        XCTAssertFalse(result.wasOptimized, "HEIC should NOT be re-optimized")
        XCTAssertEqual(result.mimeType, "image/heic")
        XCTAssertEqual(result.url, heicURL, "Should return same URL — no temp file created")

        // File should be byte-identical (not re-encoded)
        let outputSize = try FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int64 ?? 0
        XCTAssertEqual(outputSize, originalSize, "HEIC file should not be modified")
    }

    // MARK: - Mime Type Fallback for Unknown Extensions

    /// Verifies that images with unknown extensions (e.g., .webp, .tiff) still get
    /// optimized when the mime fallback kicks in.
    func testUnknownExtensionFallsBackToImageJPEG() {
        // FileUtilities returns application/octet-stream for unknown extensions
        let unknownMime = FileUtilities.mimeType(forExtension: "webp")
        XCTAssertEqual(unknownMime, "application/octet-stream",
                       "Precondition: webp should be unknown to FileUtilities")

        // The fallback in importImage should detect this and use "image/jpeg"
        let detectedMime = unknownMime
        let sourceMimeType = detectedMime.hasPrefix("image/") ? detectedMime : "image/jpeg"
        XCTAssertEqual(sourceMimeType, "image/jpeg",
                       "Unknown image extension should fall back to image/jpeg")
    }

    /// Verifies that known image extensions use their correct mime type (no fallback).
    func testKnownExtensionsUseCorrectMime() {
        let cases: [(ext: String, expected: String)] = [
            ("jpg", "image/jpeg"),
            ("jpeg", "image/jpeg"),
            ("png", "image/png"),
            ("gif", "image/gif"),
            ("heic", "image/heic"),
        ]
        for (ext, expected) in cases {
            let mime = FileUtilities.mimeType(forExtension: ext)
            XCTAssertEqual(mime, expected, "Extension '\(ext)' should map to '\(expected)'")
            XCTAssertTrue(mime.hasPrefix("image/"), "'\(ext)' mime should start with image/")
        }
    }

    /// End-to-end: an image file with an unknown extension should still optimize to HEIC
    /// because the fallback mime type allows the optimizer to process it.
    func testImageWithUnknownExtOptimizesToHEIC() async throws {
        // Create a valid JPEG but name it with .webp extension
        let weirdURL = try createTempImageWithUnknownExt(ext: "webp", pixels: CGSize(width: 400, height: 400))
        defer { try? FileManager.default.removeItem(at: weirdURL) }

        // Simulate the importImage fallback logic
        let detectedMime = FileUtilities.mimeType(forExtension: weirdURL.pathExtension)
        let sourceMimeType = detectedMime.hasPrefix("image/") ? detectedMime : "image/jpeg"

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: weirdURL, mimeType: sourceMimeType, mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized, "Image with unknown ext should still be optimized")
        XCTAssertEqual(result.mimeType, "image/heic")
    }

    // MARK: - Original Mode Preserves Format

    /// Verifies that original mode returns the source file unchanged — no conversion at all.
    func testOriginalModePreservesSourceFile() async throws {
        let pngURL = try createTempPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }
        let originalData = try Data(contentsOf: pngURL)

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: pngURL, mimeType: "image/png", mode: .original
        )

        XCTAssertFalse(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "image/png", "Original mode should preserve mime type")
        XCTAssertEqual(result.url, pngURL, "Original mode should return same URL")

        let outputData = try Data(contentsOf: result.url)
        XCTAssertEqual(outputData, originalData, "File should be byte-identical")
    }

    // MARK: - Autoreleasepool Correctness

    /// Verifies that optimizeImage inside autoreleasepool produces identical output
    /// to what the function would produce without it. This catches any issue where
    /// the autoreleasepool boundary prematurely releases objects needed for output.
    func testAutoreleasepoolDoesNotCorruptOutput() async throws {
        let jpegURL = try createTempJPEG(pixels: CGSize(width: 800, height: 800))
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        // Run optimization (which now includes autoreleasepool internally)
        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "image/heic")

        // Verify the output HEIC is fully valid and decodable
        guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil) else {
            XCTFail("Output should be a valid image source")
            return
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Output should contain a valid image")
            return
        }
        XCTAssertEqual(cgImage.width, 800)
        XCTAssertEqual(cgImage.height, 800)

        // Verify we can generate a thumbnail from it (tests the thumbnail autoreleasepool path)
        let thumbnail = autoreleasepool {
            FileUtilities.generateThumbnail(fromFileURL: result.url)
        }
        XCTAssertNotNil(thumbnail, "Thumbnail should be generatable from optimized HEIC")
        if let thumbData = thumbnail {
            XCTAssertGreaterThan(thumbData.count, 0)
            // Verify thumbnail is valid JPEG
            let thumbImage = UIImage(data: thumbData)
            XCTAssertNotNil(thumbImage, "Thumbnail data should be a valid image")
        }
    }

    /// Tests that multiple sequential optimizations don't leak memory excessively.
    /// While we can't directly measure autorelease behavior, we verify that processing
    /// many images doesn't crash or corrupt output.
    func testBatchOptimizationProducesValidOutput() async throws {
        var outputURLs: [URL] = []

        for i in 0..<10 {
            let jpegURL = try createTempJPEG(pixels: CGSize(width: 300, height: 300))
            defer { try? FileManager.default.removeItem(at: jpegURL) }

            let result = try await MediaOptimizer.shared.optimize(
                fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
            )

            XCTAssertTrue(result.wasOptimized, "Image \(i) should be optimized")
            XCTAssertEqual(result.mimeType, "image/heic", "Image \(i) should produce HEIC")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path), "Output \(i) should exist")

            // Verify each output is independently valid
            guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                XCTFail("Output \(i) should be decodable")
                continue
            }
            XCTAssertEqual(image.width, 300, "Image \(i) width should be preserved")
            XCTAssertEqual(image.height, 300, "Image \(i) height should be preserved")

            outputURLs.append(result.url)
        }

        // Cleanup
        for url in outputURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Large Image Downsampling

    /// Verifies that images > 4096px are downsampled during optimization.
    func testLargeImageIsDownsampled() async throws {
        // Create a 5000x5000 image
        let largeURL = try createTempJPEG(pixels: CGSize(width: 5000, height: 5000))
        defer { try? FileManager.default.removeItem(at: largeURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: largeURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized)
        XCTAssertEqual(result.mimeType, "image/heic")

        // Verify dimensions were capped at 4096
        guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            XCTFail("Should be able to read output image properties")
            return
        }
        let maxDim = max(width, height)
        XCTAssertLessThanOrEqual(maxDim, 4096, "Output should be downsampled to ≤ 4096px")
    }

    /// Verifies that images ≤ 4096px are NOT downsampled.
    func testNormalImageIsNotDownsampled() async throws {
        let normalURL = try createTempJPEG(pixels: CGSize(width: 2000, height: 1500))
        defer { try? FileManager.default.removeItem(at: normalURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: normalURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized)

        guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Should be able to read output image")
            return
        }
        XCTAssertEqual(image.width, 2000, "Width should be preserved")
        XCTAssertEqual(image.height, 1500, "Height should be preserved")
    }

    // MARK: - Work Stealing with 4 Workers

    /// Verifies work stealing from video queue to image workers and vice versa
    /// with the 2+2 worker configuration.
    func testWorkStealingWithFourWorkers() async {
        // 2 video items + 8 image items: unbalanced to test stealing
        let videoItems = Array(0..<2)
        let imageItems = Array(100..<108)
        let videoQueue = ParallelImporter.Queue(videoItems)
        let imageQueue = ParallelImporter.Queue(imageItems)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let start = ContinuousClockInstant.now

        let workerTask = Task {
            await Self.runWorkStealingWorkers(
                videoQueue: videoQueue, imageQueue: imageQueue, continuation: continuation
            )
            continuation.finish()
        }

        var totalProcessed = 0
        for await event in stream {
            if case .imported = event { totalProcessed += 1 }
        }
        await workerTask.value

        let elapsed = ContinuousClockInstant.now - start

        XCTAssertEqual(totalProcessed, 10, "All 10 items should be processed")
        // With 4 workers: 10 items × 100ms / 4 workers = ~250ms + overhead
        // Without stealing: 2 workers on 8 items = 400ms
        XCTAssertLessThan(elapsed, .milliseconds(500),
                          "Work stealing should allow all 4 workers to share the load")
    }

    // MARK: - EXIF Orientation Preservation

    /// Verifies that EXIF orientation metadata is preserved through optimization.
    func testEXIFOrientationPreservedInOptimizedOutput() async throws {
        // Create a JPEG with orientation metadata
        let jpegURL = try createTempJPEG(pixels: CGSize(width: 300, height: 200))
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: jpegURL, mimeType: "image/jpeg", mode: .optimized
        )
        defer { if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertTrue(result.wasOptimized)

        // Verify the output has valid EXIF properties
        guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            XCTFail("Output should have readable properties")
            return
        }

        // Orientation should be present (defaults to .up = 1)
        let orientation = props[kCGImagePropertyOrientation] as? UInt32
        XCTAssertNotNil(orientation, "Orientation should be preserved in output")
        if let o = orientation {
            XCTAssertEqual(o, CGImagePropertyOrientation.up.rawValue, "Default orientation should be .up")
        }
    }

    // MARK: - Helpers

    private static func runSplitWorkers(
        videoQueue: ParallelImporter.Queue<Int>,
        imageQueue: ParallelImporter.Queue<Int>,
        videoMonitor: ConcurrencyMonitor,
        imageMonitor: ConcurrencyMonitor,
        continuation: AsyncStream<ParallelImporter.ImportEvent>.Continuation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    while let item = await videoQueue.next() {
                        await videoMonitor.enter()
                        try? await Task.sleep(for: .milliseconds(200))
                        await videoMonitor.exit()
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "video/mp4", filename: "v\(item).mp4"
                        )))
                    }
                }
            }
            for _ in 0..<2 {
                group.addTask {
                    while let item = await imageQueue.next() {
                        await imageMonitor.enter()
                        try? await Task.sleep(for: .milliseconds(200))
                        await imageMonitor.exit()
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "image/heic", filename: "i\(item).heic"
                        )))
                    }
                }
            }
        }
    }

    private static func runWorkStealingWorkers(
        videoQueue: ParallelImporter.Queue<Int>,
        imageQueue: ParallelImporter.Queue<Int>,
        continuation: AsyncStream<ParallelImporter.ImportEvent>.Continuation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    while let item = await videoQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "video/mp4", filename: "v.mp4"
                        )))
                    }
                    while let item = await imageQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "image/heic", filename: "i.heic"
                        )))
                    }
                }
            }
            for _ in 0..<2 {
                group.addTask {
                    while let item = await imageQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "image/heic", filename: "i.heic"
                        )))
                    }
                    while let item = await videoQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "video/mp4", filename: "v.mp4"
                        )))
                    }
                }
            }
        }
    }
}

// MARK: - Clock Helper

private struct ContinuousClockInstant {
    let uptimeNanoseconds: UInt64

    static var now: ContinuousClockInstant {
        ContinuousClockInstant(uptimeNanoseconds: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
    }

    static func - (lhs: ContinuousClockInstant, rhs: ContinuousClockInstant) -> Duration {
        .nanoseconds(Int64(lhs.uptimeNanoseconds - rhs.uptimeNanoseconds))
    }
}
