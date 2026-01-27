import Foundation

/// Represents a file stored in the vault
struct VaultFile: Identifiable, Codable {
    let id: UUID
    let filename: String
    let mimeType: String
    let size: Int
    let createdAt: Date

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    var isDocument: Bool {
        mimeType.hasPrefix("application/") || mimeType.hasPrefix("text/")
    }

    var fileExtension: String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        default: return "bin"
        }
    }

    var iconName: String {
        if isImage { return "photo.fill" }
        if isVideo { return "video.fill" }
        if mimeType == "application/pdf" { return "doc.fill" }
        return "doc.fill"
    }

    var formattedSize: String {
        let kb = Double(size) / 1024
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1024
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
}

/// Lightweight reference to a file (for lists/grids)
struct VaultFileReference: Identifiable {
    let id: UUID
    let offset: Int
    let size: Int
}
