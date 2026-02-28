import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers
import UIKit
import os.log

private let optimizerLogger = Logger(subsystem: "app.vaultaire.ios", category: "MediaOptimizer")

/// Wraps a non-Sendable value so it can cross isolation boundaries in task groups.
/// Safety: callers must ensure the wrapped value is not accessed concurrently.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Optimizes media files before vault storage using modern codecs.
/// Images → HEIC (ImageIO). Videos → HEVC 1080p via two paths:
/// - AVAssetExportSession for HEVC 4K→1080p downscale (fast hardware path)
/// - AVAssetReader/Writer for non-HEVC→HEVC codec change (sample-buffer path)
/// Non-media files pass through unchanged.
///
/// Not an actor — all methods operate on temp files with no shared mutable state.
/// Actor isolation was serializing parallel import workers through a single executor,
/// defeating the 4-worker concurrency design in ParallelImporter.
final class MediaOptimizer: Sendable {
    static let shared = MediaOptimizer()

    enum Mode: String, Sendable {
        case optimized
        case original
    }

    /// Result of media optimization, replacing the old tuple return.
    struct Result: Sendable {
        let url: URL
        let mimeType: String
        let wasOptimized: Bool
        let thumbnailData: Data?
        let duration: TimeInterval?
        let creationDate: Date?
    }

    /// Determines which optimization path to use for a video.
    enum VideoOptimizationStrategy: Sendable, Equatable {
        case skip           // Already optimal (HEVC ≤1080p)
        case exportSession  // HEVC >1080p — fast hardware downscale
        case readerWriter   // Non-HEVC — codec change via sample buffers
    }

    /// Optimizes media for storage. If `wasOptimized` is true, caller must delete the temp file.
    /// For images, `thumbnailData` contains a pre-generated thumbnail from the in-memory CGImage,
    /// avoiding a redundant decode from disk after HEIC conversion.
    func optimize(fileURL: URL, mimeType: String, mode: Mode) async throws -> Result {
        guard mode == .optimized else {
            return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
        }

        if mimeType.hasPrefix("image/") {
            return try optimizeImage(fileURL: fileURL, mimeType: mimeType)
        } else if mimeType.hasPrefix("video/") {
            return try await optimizeVideo(fileURL: fileURL, mimeType: mimeType)
        }

        // Non-media: passthrough
        return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
    }

    /// Optimizes a UIImage (e.g., from camera) to HEIC temp file.
    /// Returns (tempFileURL, mimeType). Caller must delete temp file.
    func optimizeImage(_ image: UIImage, mode: Mode) async throws -> (URL, String) {
        if mode == .original {
            // Write as JPEG to temp file (avoids holding jpegData in memory alongside UIImage)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                throw OptimizationError.imageConversionFailed
            }
            try data.write(to: tempURL, options: [.atomic])
            return (tempURL, "image/jpeg")
        }

        // Write HEIC via ImageIO — avoids large Data intermediary
        guard let cgImage = image.cgImage else {
            throw OptimizationError.imageConversionFailed
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heic")

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            AVFileType.heic as CFString,
            1,
            nil
        ) else {
            throw OptimizationError.heicEncodingFailed
        }

        // Check if image has alpha to optimize file size and memory
        let hasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipFirst && cgImage.alphaInfo != .noneSkipLast
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.6,
            kCGImagePropertyHasAlpha: hasAlpha
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            FileUtilities.cleanupTemporaryFile(at: tempURL)
            throw OptimizationError.heicEncodingFailed
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        optimizerLogger.info("Camera image → HEIC: \(fileSize) bytes")

        return (tempURL, "image/heic")
    }

    // MARK: - Image Optimization

    /// Images below this size skip HEIC conversion — the CPU cost of decode+encode
    /// outweighs the negligible space savings on small files.
    static let imageOptimizationThreshold: Int64 = 500_000  // 500 KB

    private func optimizeImage(fileURL: URL, mimeType: String) throws -> Result {
        // Skip if already HEIC
        if mimeType == "image/heic" || mimeType == "image/heif" {
            return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
        }

        // Skip PNGs — they're typically screenshots/diagrams where lossy HEIC at 0.6
        // introduces visible artifacts on text and sharp edges, and often produces
        // larger output than the original PNG.
        if mimeType == "image/png" {
            optimizerLogger.info("PNG detected, skipping lossy HEIC conversion to preserve quality")
            return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
        }

        // Skip small images — HEIC conversion has fixed CPU overhead that isn't worth it
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        if originalSize > 0 && originalSize < Self.imageOptimizationThreshold {
            optimizerLogger.info("Image \(originalSize) bytes < \(Self.imageOptimizationThreshold) threshold, skipping HEIC conversion")
            return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
        }

        // autoreleasepool ensures CGImageSource, CGImage, and CGImageDestination temporaries
        // are released immediately. With 4 parallel workers, this prevents ~100-200MB of
        // accumulated ObjC objects between executor yields.
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
            }

            // Check image dimensions for potential downsampling
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let maxDimension = max(width, height)

            // Get source image — downsample if > 4096px
            // Read EXIF orientation to preserve it when writing output
            let orientation: CGImagePropertyOrientation
            let cgImage: CGImage
            if maxDimension > 4096 {
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096
                ]
                guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                    return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
                }
                cgImage = thumb
                // kCGImageSourceCreateThumbnailWithTransform already rotated the pixels,
                // so mark as .up to avoid double-rotation in the output HEIC.
                orientation = .up
            } else {
                guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
                }
                cgImage = full
                // Full-size path: pixels are unrotated, so preserve original EXIF orientation.
                orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap { CGImagePropertyOrientation(rawValue: $0) } ?? .up
            }

            // Generate thumbnail from in-memory CGImage BEFORE writing HEIC.
            // This avoids a redundant decode from disk after optimization.
            let thumbnail = Self.generateThumbnailFromCGImage(cgImage, orientation: orientation, maxPixelSize: 400)

            // Write HEIC to temp file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("heic")

            guard let destination = CGImageDestinationCreateWithURL(
                tempURL as CFURL,
                AVFileType.heic as CFString,
                1,
                nil
            ) else {
                return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
            }

            // Preserve EXIF orientation metadata when writing the output image
            // Check if image has alpha to optimize file size and memory
            let hasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipFirst && cgImage.alphaInfo != .noneSkipLast
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.6,
                kCGImagePropertyOrientation: orientation.rawValue,
                kCGImagePropertyHasAlpha: hasAlpha
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                FileUtilities.cleanupTemporaryFile(at: tempURL)
                return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: nil, creationDate: nil)
            }

            let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0

            // Discard HEIC if it didn't achieve at least 20% reduction (same logic as video)
            if originalSize > 0 && optimizedSize >= Int64(Double(originalSize) * 0.8) {
                FileUtilities.cleanupTemporaryFile(at: tempURL)
                optimizerLogger.info("Image HEIC \(optimizedSize) bytes >= 80% of original \(originalSize), keeping original")
                return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: thumbnail, duration: nil, creationDate: nil)
            }

            let reduction = originalSize > 0 ? Int(100 - (optimizedSize * 100 / originalSize)) : 0
            optimizerLogger.info("Image optimized: \(originalSize) → \(optimizedSize) bytes (\(reduction)% reduction)")

            return Result(url: tempURL, mimeType: "image/heic", wasOptimized: true, thumbnailData: thumbnail, duration: nil, creationDate: nil)
        }
    }

    /// Generates a JPEG thumbnail from an in-memory CGImage, applying EXIF orientation.
    private static func generateThumbnailFromCGImage(_ cgImage: CGImage, orientation: CGImagePropertyOrientation, maxPixelSize: CGFloat) -> Data? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let maxDim = max(w, h)
        guard maxDim > 0 else { return nil }
        let scale = maxDim <= maxPixelSize ? 1.0 : maxPixelSize / maxDim
        let thumbW = w * scale
        let thumbH = h * scale

        let uiOrientation = UIImage.Orientation(orientation)
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)
        let thumbSize = CGSize(width: thumbW, height: thumbH)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
        }
        return thumbImage.jpegData(compressionQuality: 0.7)
    }

    // MARK: - Video Optimization

    /// Target bitrate tiers for HEVC encoding (bits per second).
    /// Higher targets = less compression work = faster hardware encoding (~30-50% speed gain)
    /// while still achieving significant reduction vs 4K source footage.
    private static let bitrate1080p = 8_000_000  // 8 Mbps — fast encode, ~50-70% smaller than 4K source
    private static let bitrate720p  = 4_000_000  // 4 Mbps
    private static let bitrateSD    = 2_000_000  // 2 Mbps
    private static let audioBitrate = 128_000    // 128 kbps AAC

    private func optimizeVideo(fileURL: URL, mimeType: String) async throws -> Result {
        let asset = AVURLAsset(url: fileURL)
        let strategy = await videoOptimizationStrategy(for: asset)

        // Load duration and creation date from the already-opened asset
        // so callers don't need to re-open it
        var duration: TimeInterval?
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 { duration = seconds }
        }
        var creationDate: Date?
        if let metadataItems = try? await asset.load(.commonMetadata) {
            let dateItems = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierCreationDate)
            if let dateItem = dateItems.first, let dateValue = try? await dateItem.load(.dateValue) {
                creationDate = dateValue
            }
        }

        switch strategy {
        case .skip:
            optimizerLogger.info("Video already optimal, skipping")
            return Result(url: fileURL, mimeType: mimeType, wasOptimized: false, thumbnailData: nil, duration: duration, creationDate: creationDate)

        case .exportSession:
            optimizerLogger.info("HEVC >1080p — using AVAssetExportSession for fast downscale")
            if let (url, mime, optimized) = await optimizeVideoWithExportSession(fileURL: fileURL, mimeType: mimeType, asset: asset) {
                return Result(url: url, mimeType: mime, wasOptimized: optimized, thumbnailData: nil, duration: duration, creationDate: creationDate)
            }
            // ExportSession failed — fall back to reader/writer
            optimizerLogger.warning("ExportSession unavailable, falling back to AVAssetReader/Writer")
            let (url, mime, optimized) = try await optimizeVideoWithReaderWriter(fileURL: fileURL, mimeType: mimeType, asset: asset)
            return Result(url: url, mimeType: mime, wasOptimized: optimized, thumbnailData: nil, duration: duration, creationDate: creationDate)

        case .readerWriter:
            let (url, mime, optimized) = try await optimizeVideoWithReaderWriter(fileURL: fileURL, mimeType: mimeType, asset: asset)
            return Result(url: url, mimeType: mime, wasOptimized: optimized, thumbnailData: nil, duration: duration, creationDate: creationDate)
        }
    }

    /// Fast downscale path using AVAssetExportSession with hardware-accelerated HEVC 1080p preset.
    /// Returns nil if the preset is incompatible or export fails (caller should fall back to reader/writer).
    private func optimizeVideoWithExportSession(fileURL: URL, mimeType: String, asset: AVURLAsset) async -> (URL, String, Bool)? {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVC1920x1080) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        session.outputURL = tempURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            let errorDesc = session.error?.localizedDescription ?? "unknown"
            optimizerLogger.error("ExportSession failed: \(errorDesc, privacy: .public)")
            return nil
        }

        return applyThresholdCheck(originalURL: fileURL, optimizedURL: tempURL, originalMimeType: mimeType, label: "ExportSession")
    }

    /// Codec-change path using AVAssetReader/Writer with explicit bitrate and HEVC encoding.
    private func optimizeVideoWithReaderWriter(fileURL: URL, mimeType: String, asset: AVURLAsset) async throws -> (URL, String, Bool) {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return (fileURL, mimeType, false)
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        // Calculate output dimensions (max 1080p, preserve aspect ratio)
        let targetSize = Self.targetVideoSize(from: naturalSize, transform: preferredTransform)
        let targetBitrate = Self.targetBitrate(for: targetSize)

        optimizerLogger.info("Video transcode: \(Int(naturalSize.width))x\(Int(naturalSize.height)) → \(targetSize.width)x\(targetSize.height) @ \(targetBitrate / 1000) kbps")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            // Set up reader
            let reader = try AVAssetReader(asset: asset)

            let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
            videoReaderOutput.alwaysCopiesSampleData = false
            reader.add(videoReaderOutput)

            // Set up writer
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)

            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: targetSize.width,
                AVVideoHeightKey: targetSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: targetBitrate,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 60
                ]
            ])
            videoWriterInput.expectsMediaDataInRealTime = false
            videoWriterInput.transform = preferredTransform
            writer.add(videoWriterInput)

            // Audio track (if present)
            var audioReaderOutput: AVAssetReaderTrackOutput?
            var audioWriterInput: AVAssetWriterInput?
            if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ])
                audioOutput.alwaysCopiesSampleData = false
                reader.add(audioOutput)
                audioReaderOutput = audioOutput

                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVEncoderBitRateKey: Self.audioBitrate,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2
                ])
                audioInput.expectsMediaDataInRealTime = false
                writer.add(audioInput)
                audioWriterInput = audioInput
            }

            // Start reading/writing
            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            // Process video and audio tracks concurrently.
            // Per-transcode queues so parallel video workers don't serialize on shared queues.
            let id = UUID().uuidString.prefix(8)
            let videoXferQueue = DispatchQueue(label: "app.vaultaire.transcode.video.\(id)")
            let audioXferQueue = DispatchQueue(label: "app.vaultaire.transcode.audio.\(id)")
            // UncheckedBox: AVAssetReaderTrackOutput/AVAssetWriterInput are thread-safe for
            // the serial-queue callback pattern used in transferSamples.
            let vro = UncheckedBox(videoReaderOutput)
            let vwi = UncheckedBox(videoWriterInput)
            let aro = UncheckedBox(audioReaderOutput)
            let awi = UncheckedBox(audioWriterInput)
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await Self.transferSamples(from: vro.value, to: vwi.value, on: videoXferQueue)
                }
                if let audioOutput = aro.value, let audioInput = awi.value {
                    group.addTask {
                        await Self.transferSamples(from: audioOutput, to: audioInput, on: audioXferQueue)
                    }
                }
            }

            await writer.finishWriting()

            guard writer.status == .completed else {
                try? FileManager.default.removeItem(at: tempURL)
                let errorDesc = writer.error?.localizedDescription ?? "unknown"
                optimizerLogger.error("Video writer failed: \(errorDesc, privacy: .public)")
                return (fileURL, mimeType, false)
            }

            reader.cancelReading()
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            optimizerLogger.error("Video transcode setup failed: \(error.localizedDescription, privacy: .public)")
            return (fileURL, mimeType, false)
        }

        return applyThresholdCheck(originalURL: fileURL, optimizedURL: tempURL, originalMimeType: mimeType, label: "transcode")
    }

    /// Checks if the optimized file achieved at least 20% size reduction.
    /// Returns the original if reduction is insufficient, or the optimized result.
    private func applyThresholdCheck(originalURL: URL, optimizedURL: URL, originalMimeType: String, label: String) -> (URL, String, Bool) {
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: originalURL.path)[.size] as? Int64) ?? 0
        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int64) ?? 0

        if originalSize > 0 && optimizedSize >= Int64(Double(originalSize) * 0.8) {
            try? FileManager.default.removeItem(at: optimizedURL)
            optimizerLogger.info("\(label, privacy: .public) yielded < 20% reduction (\(originalSize) → \(optimizedSize)), keeping original")
            return (originalURL, originalMimeType, false)
        }

        let reduction = originalSize > 0 ? Int(100 - (optimizedSize * 100 / originalSize)) : 0
        optimizerLogger.info("Video optimized via \(label, privacy: .public): \(originalSize) → \(optimizedSize) bytes (\(reduction)% reduction)")
        return (optimizedURL, "video/mp4", true)
    }

    /// Transfer sample buffers from reader output to writer input using the proper callback pattern.
    /// Each transcode creates its own serial queue so parallel video workers don't serialize.
    private static func transferSamples(from output: AVAssetReaderTrackOutput, to input: AVAssetWriterInput, on queue: DispatchQueue) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // AVAssetWriterInput/AVAssetReaderTrackOutput are thread-safe for this callback pattern.
            // The requestMediaDataWhenReady callback is always called on the provided queue serially.
            nonisolated(unsafe) let output = output
            nonisolated(unsafe) let input = input
            nonisolated(unsafe) var resumed = false
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        if !resumed {
                            resumed = true
                            continuation.resume()
                        }
                        return
                    }
                    input.append(buffer)
                }
            }
        }
    }

    /// Calculate output video dimensions: cap at 1080p, preserve aspect ratio.
    /// Uses naturalSize directly — the writer's transform property handles orientation.
    private static func targetVideoSize(from naturalSize: CGSize, transform _: CGAffineTransform) -> (width: Int, height: Int) {
        // Use naturalSize directly — pixel buffers are in natural orientation,
        // and videoWriterInput.transform handles display rotation.
        let w = naturalSize.width
        let h = naturalSize.height
        let maxDim = max(w, h)

        if maxDim <= 1920 {
            // Already ≤ 1080p — keep original dimensions (rounded to even)
            return (Int(w / 2) * 2, Int(h / 2) * 2)
        }

        let scale = 1920.0 / maxDim
        // Round to nearest even number (required by video encoder)
        let newW = Int((w * scale) / 2) * 2
        let newH = Int((h * scale) / 2) * 2
        return (max(newW, 2), max(newH, 2))
    }

    /// Select target bitrate based on output resolution.
    private static func targetBitrate(for size: (width: Int, height: Int)) -> Int {
        let maxDim = max(size.width, size.height)
        if maxDim >= 1080 { return bitrate1080p }
        if maxDim >= 720 { return bitrate720p }
        return bitrateSD
    }

    /// Determines the optimization strategy for a video based on its codec and resolution.
    /// - skip: HEVC ≤1080p — already optimal
    /// - exportSession: HEVC >1080p — downscale via hardware-accelerated ExportSession
    /// - readerWriter: non-HEVC — codec change via sample-buffer pipeline
    func videoOptimizationStrategy(for asset: AVURLAsset) async -> VideoOptimizationStrategy {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return .skip
        }

        // Check codec
        guard let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
              let desc = formatDescriptions.first else {
            return .skip
        }

        let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
        // 'hvc1' FourCC = HEVC
        let isHEVC = mediaSubType == 0x68766331

        // Check resolution
        guard let naturalSize = try? await videoTrack.load(.naturalSize) else {
            return .skip
        }
        let maxDimension = max(naturalSize.width, naturalSize.height)

        if isHEVC {
            if maxDimension <= 1920 {
                let estimatedRate = (try? await videoTrack.load(.estimatedDataRate)) ?? 0
                optimizerLogger.info("HEVC ≤1080p @ \(Int(estimatedRate / 1000)) kbps — skipping transcode")
                return .skip
            } else {
                return .exportSession
            }
        } else {
            return .readerWriter
        }
    }

    // MARK: - Errors

    enum OptimizationError: LocalizedError {
        case imageConversionFailed
        case heicEncodingFailed

        var errorDescription: String? {
            if self == .imageConversionFailed { return "Could not process image for optimization" }
            return "HEIC encoding failed"
        }
    }
}

// MARK: - Filename Helpers

extension MediaOptimizer {
    /// Updates filename extension to match the optimized format.
    static func updatedFilename(_ filename: String, newMimeType: String) -> String {
        let ext: String
        switch newMimeType {
        case "image/heic", "image/heif": ext = "heic"
        case "video/mp4": ext = "mp4"
        default: return filename
        }

        let name = (filename as NSString).deletingPathExtension
        return "\(name).\(ext)"
    }
}

// MARK: - UIImage.Orientation from CGImagePropertyOrientation

private extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
