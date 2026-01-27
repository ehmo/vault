import Foundation
import UniformTypeIdentifiers

/// Handles importing files from various sources into the vault.
final class FileImporter {
    static let shared = FileImporter()

    private let storage = VaultStorage.shared
    private let crypto = CryptoEngine.shared

    private init() {}

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

    func importFromURL(_ url: URL, with key: Data) async throws -> UUID {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent
        let mimeType = mimeTypeFor(url: url)

        return try storage.storeFile(data: data, filename: filename, mimeType: mimeType, with: key)
    }

    func importData(_ data: Data, filename: String, mimeType: String, with key: Data) throws -> UUID {
        return try storage.storeFile(data: data, filename: filename, mimeType: mimeType, with: key)
    }

    func importImageData(_ imageData: Data, with key: Data) throws -> UUID {
        let filename = "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
        return try storage.storeFile(data: imageData, filename: filename, mimeType: "image/jpeg", with: key)
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
    func importLivePhoto(imageData: Data, videoData: Data, with key: Data) throws -> (imageId: UUID, videoId: UUID) {
        let imageFilename = "LIVE_\(Int(Date().timeIntervalSince1970)).jpg"
        let videoFilename = "LIVE_\(Int(Date().timeIntervalSince1970)).mov"

        let imageId = try storage.storeFile(data: imageData, filename: imageFilename, mimeType: "image/jpeg", with: key)
        let videoId = try storage.storeFile(data: videoData, filename: videoFilename, mimeType: "video/quicktime", with: key)

        return (imageId, videoId)
    }
}
