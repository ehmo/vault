import Foundation
import UniformTypeIdentifiers
import UIKit

/// Handles importing files from various sources into the vault.
final class FileImporter {
    static let shared = FileImporter()

    private let storage = VaultStorage.shared

    private init() { /* No-op */ }

    // MARK: - Supported Types

    static let supportedImageTypes: [UTType] = [
        .jpeg, .png, .gif, .heic, .webP, .bmp, .tiff
    ]

    static let supportedVideoTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie, .avi, .movie
    ]

    static let supportedDocumentTypes: [UTType] = [
        .pdf, .plainText, .rtf
    ]

    static var allSupportedTypes: [UTType] {
        supportedImageTypes + supportedVideoTypes + supportedDocumentTypes + [.item]
    }

    // MARK: - Import Methods

    func importFromURL(_ url: URL, with key: VaultKey) async throws -> UUID {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent
        let mimeType = mimeTypeFor(url: url)

        // Generate thumbnail if it's an image
        let thumbnail = generateThumbnail(from: data, mimeType: mimeType)

        return try storage.storeFile(data: data, filename: filename, mimeType: mimeType, with: key, thumbnailData: thumbnail)
    }

    func importData(_ data: Data, filename: String, mimeType: String, with key: VaultKey) throws -> UUID {
        let thumbnail = generateThumbnail(from: data, mimeType: mimeType)
        return try storage.storeFile(data: data, filename: filename, mimeType: mimeType, with: key, thumbnailData: thumbnail)
    }

    func importImageData(_ imageData: Data, with key: VaultKey) throws -> UUID {
        let filename = "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
        let thumbnail = generateThumbnail(from: imageData, mimeType: "image/jpeg")
        return try storage.storeFile(data: imageData, filename: filename, mimeType: "image/jpeg", with: key, thumbnailData: thumbnail)
    }

    // MARK: - MIME Type Detection

    private func mimeTypeFor(url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        // Images
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"

        // Videos
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"

        // Documents
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "rtf": return "text/rtf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

        default: return "application/octet-stream"
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generates a thumbnail from image data
    /// Returns JPEG data at 200x200 max size, or nil if not an image
    private func generateThumbnail(from data: Data, mimeType: String) -> Data? {
        // Only generate thumbnails for images
        guard mimeType.hasPrefix("image/") else { return nil }
        
        // Use UIImage(data:) which reads EXIF orientation
        guard let image = UIImage(data: data) else { return nil }
        
        // Calculate thumbnail size (max 200x200, maintaining aspect ratio)
        let maxSize: CGFloat = 200
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        // Generate thumbnail with proper orientation handling
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { context in
            // Apply orientation transform before drawing
            Self.applyOrientationTransform(for: image, in: newSize, context: context.cgContext)
            // Draw the CGImage (raw pixels)
            if let cgImage = image.cgImage {
                context.cgContext.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
            }
        }
        
        // Convert to JPEG with moderate compression
        return thumbnail.jpegData(compressionQuality: 0.7)
    }
    
    /// Applies the necessary transform to the CGContext based on UIImage's orientation
    private static func applyOrientationTransform(for image: UIImage, in size: CGSize, context: CGContext) {
        // Apply transform without save/restore since we need it active for drawing
        switch image.imageOrientation {
        case .up:
            break
        case .down:
            context.translateBy(x: size.width, y: size.height)
            context.rotate(by: .pi)
        case .left:
            context.translateBy(x: 0, y: size.height)
            context.rotate(by: -.pi / 2)
        case .right:
            context.translateBy(x: size.width, y: 0)
            context.rotate(by: .pi / 2)
        case .upMirrored:
            context.translateBy(x: size.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .downMirrored:
            context.translateBy(x: size.width, y: size.height)
            context.scaleBy(x: -1, y: -1)
        case .leftMirrored:
            context.translateBy(x: 0, y: size.height)
            context.rotate(by: -.pi / 2)
            context.scaleBy(x: 1, y: -1)
        case .rightMirrored:
            context.translateBy(x: size.width, y: size.height)
            context.rotate(by: .pi / 2)
            context.scaleBy(x: -1, y: 1)
        @unknown default:
            break
        }
    }

    // MARK: - Error Types

    enum ImportError: Error {
        case accessDenied
        case unsupportedType
        case fileTooLarge
        case readFailed
        case encryptionFailed
    }
}

// MARK: - Live Photo Support

extension FileImporter {
    func importLivePhoto(imageData: Data, videoData: Data, with key: VaultKey) throws -> (imageId: UUID, videoId: UUID) {
        let imageFilename = "LIVE_\(Int(Date().timeIntervalSince1970)).jpg"
        let videoFilename = "LIVE_\(Int(Date().timeIntervalSince1970)).mov"

        let imageThumbnail = generateThumbnail(from: imageData, mimeType: "image/jpeg")

        let imageId = try storage.storeFile(data: imageData, filename: imageFilename, mimeType: "image/jpeg", with: key, thumbnailData: imageThumbnail)
        let videoId = try storage.storeFile(data: videoData, filename: videoFilename, mimeType: "video/quicktime", with: key, thumbnailData: nil)

        return (imageId, videoId)
    }
}
