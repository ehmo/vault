import UIKit
import ImageIO

enum FileUtilities {
    static func generateThumbnail(from data: Data, maxSize: CGFloat = 200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.7)
    }

    /// Memory-efficient thumbnail generation directly from file URL.
    /// Uses ImageIO downsampling to avoid decoding full-size images into memory.
    static func generateThumbnail(fromFileURL fileURL: URL, maxPixelSize: CGFloat = 400) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        
        // Read EXIF orientation from source to preserve it in thumbnail
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap { UIImage.Orientation(rawValue: Int($0)) } ?? .up
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        return image.jpegData(compressionQuality: 0.7)
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    /// Best-effort cleanup of temporary files.
    /// Silently ignores errors - use only for non-critical temp file cleanup.
    static func cleanupTemporaryFile(at url: URL?) {
        guard let url = url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
