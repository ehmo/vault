import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers
import UIKit
import os.log

private let optimizerLogger = Logger(subsystem: "app.vaultaire.ios", category: "MediaOptimizer")

/// Optimizes media files before vault storage using modern codecs.
/// Images → HEIC (ImageIO), Videos → HEVC 1080p (AVAssetExportSession).
/// Non-media files pass through unchanged.
actor MediaOptimizer {
    static let shared = MediaOptimizer()

    enum Mode: String, Sendable {
        case optimized
        case original
    }

    /// Returns (outputURL, outputMimeType, wasOptimized).
    /// If `wasOptimized` is true, caller must delete the temp file after use.
    func optimize(fileURL: URL, mimeType: String, mode: Mode) async throws -> (URL, String, Bool) {
        guard mode == .optimized else {
            return (fileURL, mimeType, false)
        }

        if mimeType.hasPrefix("image/") {
            return try optimizeImage(fileURL: fileURL, mimeType: mimeType)
        } else if mimeType.hasPrefix("video/") {
            return try await optimizeVideo(fileURL: fileURL, mimeType: mimeType)
        }

        // Non-media: passthrough
        return (fileURL, mimeType, false)
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

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.6
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw OptimizationError.heicEncodingFailed
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        optimizerLogger.info("Camera image → HEIC: \(fileSize) bytes")

        return (tempURL, "image/heic")
    }

    // MARK: - Image Optimization

    private func optimizeImage(fileURL: URL, mimeType: String) throws -> (URL, String, Bool) {
        // Skip if already HEIC
        if mimeType == "image/heic" || mimeType == "image/heif" {
            return (fileURL, mimeType, false)
        }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return (fileURL, mimeType, false)
        }

        // Check image dimensions for potential downsampling
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maxDimension = max(width, height)

        // Get source image — downsample if > 4096px
        let cgImage: CGImage
        if maxDimension > 4096 {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                return (fileURL, mimeType, false)
            }
            cgImage = thumb
        } else {
            guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return (fileURL, mimeType, false)
            }
            cgImage = full
        }

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
            return (fileURL, mimeType, false)
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.6
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            return (fileURL, mimeType, false)
        }

        let originalSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        optimizerLogger.info("Image optimized: \(originalSize) → \(optimizedSize) bytes (\(originalSize > 0 ? Int(100 - (optimizedSize * 100 / originalSize)) : 0)% reduction)")

        return (tempURL, "image/heic", true)
    }

    // MARK: - Video Optimization

    private func optimizeVideo(fileURL: URL, mimeType: String) async throws -> (URL, String, Bool) {
        let asset = AVURLAsset(url: fileURL)

        // Check if already HEVC at ≤ 1080p — skip if so
        if await isAlreadyOptimalVideo(asset) {
            return (fileURL, mimeType, false)
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHEVC1920x1080
        ) else {
            // Preset not supported — passthrough
            optimizerLogger.warning("HEVC export preset not available, passing through")
            return (fileURL, mimeType, false)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            if let error = exportSession.error {
                optimizerLogger.error("Video export failed: \(error.localizedDescription, privacy: .public)")
            }
            // Fall back to passthrough on export failure
            return (fileURL, mimeType, false)
        }

        let originalSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        optimizerLogger.info("Video optimized: \(originalSize) → \(optimizedSize) bytes (\(originalSize > 0 ? Int(100 - (optimizedSize * 100 / originalSize)) : 0)% reduction)")

        return (tempURL, "video/mp4", true)
    }

    private func isAlreadyOptimalVideo(_ asset: AVURLAsset) async -> Bool {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return false
        }

        // Check codec
        guard let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
              let desc = formatDescriptions.first else {
            return false
        }

        let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
        // 'hvc1' FourCC = HEVC
        let isHEVC = mediaSubType == 0x68766331

        // Check resolution
        guard let naturalSize = try? await videoTrack.load(.naturalSize) else {
            return false
        }
        let maxDimension = max(naturalSize.width, naturalSize.height)
        let isAtMost1080p = maxDimension <= 1920

        return isHEVC && isAtMost1080p
    }

    // MARK: - Errors

    enum OptimizationError: LocalizedError {
        case imageConversionFailed
        case heicEncodingFailed

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed: return "Could not process image for optimization"
            case .heicEncodingFailed: return "HEIC encoding failed"
            }
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
