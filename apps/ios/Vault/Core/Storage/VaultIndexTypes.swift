import Foundation

// MARK: - Index Types (namespaced under VaultStorage)

extension VaultStorage {

    // MARK: - Share Policy & Records

    struct SharePolicy: Codable, Equatable, Sendable {
        var expiresAt: Date?        // nil = never
        var maxOpens: Int?          // nil = unlimited
        var allowScreenshots: Bool  // default false
        var allowDownloads: Bool    // default true

        init(expiresAt: Date? = nil, maxOpens: Int? = nil, allowScreenshots: Bool = false, allowDownloads: Bool = true) {
            self.expiresAt = expiresAt
            self.maxOpens = maxOpens
            self.allowScreenshots = allowScreenshots
            self.allowDownloads = allowDownloads
        }
    }

    struct ShareRecord: Codable, Identifiable, Sendable {
        let id: String              // share vault ID in CloudKit
        let createdAt: Date
        let policy: SharePolicy
        var lastSyncedAt: Date?
        var shareKeyData: Data?     // phrase-derived share key (stored in encrypted index)
        var syncSequence: Int?      // incremental sync counter (nil = never synced with SVDF)

        var shareId: String { id }
    }

    struct BlobDescriptor: Codable, Sendable {
        let blobId: String      // "primary" or random hex
        let fileName: String    // "vault_data.bin" or "vd_<hex>.bin"
        let capacity: Int       // usable bytes (blob size minus reserved footer for primary)
        var cursor: Int         // next write offset in this blob
    }

    // MARK: - Vault Index

    struct VaultIndex: Codable, Sendable {
        var files: [VaultFileEntry]
        var nextOffset: Int
        var totalSize: Int
        var encryptedMasterKey: Data? // Master key encrypted with vault key (32 bytes encrypted)
        var version: Int // Index format version for future migrations

        // Multi-blob pool (nil = v2 single-blob mode)
        var blobs: [BlobDescriptor]?

        // Owner side: active shares for this vault
        var activeShares: [ShareRecord]?

        // Recipient side: marks this as a received shared vault
        var isSharedVault: Bool?
        var sharedVaultId: String?       // CloudKit vault ID for update checks
        var sharePolicy: SharePolicy?    // restrictions set by owner
        var openCount: Int?              // track opens for maxOpens
        var shareKeyData: Data?          // phrase-derived share key for update downloads
        var sharedVaultVersion: Int?     // last known remote version for update checks

        // User-set vault name (nil = use auto-generated from pattern letters)
        var customName: String?

        // Legacy initializer for backward compatibility
        init(files: [VaultFileEntry], nextOffset: Int, totalSize: Int) {
            self.files = files
            self.nextOffset = nextOffset
            self.totalSize = totalSize
            self.encryptedMasterKey = nil
            self.version = 1
        }

        // New initializer with master key
        init(files: [VaultFileEntry], nextOffset: Int, totalSize: Int, encryptedMasterKey: Data, version: Int = 2) {
            self.files = files
            self.nextOffset = nextOffset
            self.totalSize = totalSize
            self.encryptedMasterKey = encryptedMasterKey
            self.version = version
        }

        struct VaultFileEntry: Codable, Sendable {
            let fileId: UUID
            let offset: Int
            let size: Int
            let encryptedHeaderPreview: Data // First 64 bytes for quick lookup
            let isDeleted: Bool
            let thumbnailData: Data? // Encrypted thumbnail data (JPEG, 200x200 max)
            let mimeType: String?
            let filename: String?
            let blobId: String? // nil = primary blob (backward compat)
            let createdAt: Date? // When the file was added to the vault
            let duration: TimeInterval? // Video duration in seconds (nil for non-video)
            let originalDate: Date? // Original file creation date (EXIF, video metadata, or filesystem)

            // Legacy initializer for backward compatibility
            init(fileId: UUID, offset: Int, size: Int, encryptedHeaderPreview: Data, isDeleted: Bool) {
                self.fileId = fileId
                self.offset = offset
                self.size = size
                self.encryptedHeaderPreview = encryptedHeaderPreview
                self.isDeleted = isDeleted
                self.thumbnailData = nil
                self.mimeType = nil
                self.filename = nil
                self.blobId = nil
                self.createdAt = nil
                self.duration = nil
                self.originalDate = nil
            }

            // Full initializer with thumbnail and blobId
            init(fileId: UUID, offset: Int, size: Int, encryptedHeaderPreview: Data, isDeleted: Bool,
                 thumbnailData: Data?, mimeType: String?, filename: String?, blobId: String? = nil,
                 createdAt: Date? = nil, duration: TimeInterval? = nil, originalDate: Date? = nil) {
                self.fileId = fileId
                self.offset = offset
                self.size = size
                self.encryptedHeaderPreview = encryptedHeaderPreview
                self.isDeleted = isDeleted
                self.thumbnailData = thumbnailData
                self.mimeType = mimeType
                self.filename = filename
                self.blobId = blobId
                self.createdAt = createdAt
                self.duration = duration
                self.originalDate = originalDate
            }
        }
    }
}
