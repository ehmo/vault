import UIKit
import ImageIO

enum FileUtilities {
    static func generateThumbnail(from data: Data, maxSize: CGFloat = 400) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Use UIGraphicsImageRenderer which properly handles orientation
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            // Draw the UIImage (not CGImage) - this automatically applies orientation
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.7)
    }

    /// Memory-efficient thumbnail generation directly from file URL.
    /// Uses ImageIO downsampling to avoid decoding full-size images into memory.
    static func generateThumbnail(fromFileURL fileURL: URL, maxPixelSize: CGFloat = 400) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        // kCGImageSourceCreateThumbnailWithTransform already rotates pixels to correct
        // orientation, so use .up to avoid applying the EXIF rotation a second time.
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
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

    static func fileExtension(forMimeType mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "image/webp": return "webp"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        case "application/json": return "json"
        case "application/zip": return "zip"
        default: return nil
        }
    }

    /// Ensures a filename has an extension, deriving one from the MIME type if missing.
    static func filenameWithExtension(_ filename: String, mimeType: String?) -> String {
        let url = URL(fileURLWithPath: filename)
        if !url.pathExtension.isEmpty { return filename }
        guard let mimeType, let ext = fileExtension(forMimeType: mimeType) else { return filename }
        return "\(filename).\(ext)"
    }

    /// Extracts the original creation date from an image file's EXIF metadata.
    /// Returns nil if no EXIF date is found.
    static func extractImageCreationDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        guard let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    /// Best-effort cleanup of temporary files.
    /// Silently ignores errors - use only for non-critical temp file cleanup.
    static func cleanupTemporaryFile(at url: URL?) {
        guard let url = url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
