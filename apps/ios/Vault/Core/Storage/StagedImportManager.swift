import Foundation

// MARK: - Manifest Models

struct StagedImportManifest: Codable {
    let batchId: UUID
    let keyFingerprint: String
    let timestamp: Date
    let sourceAppBundleId: String?
    let files: [StagedFileMetadata]
    var retryCount: Int = 0
}

struct StagedFileMetadata: Codable {
    let fileId: UUID
    let filename: String
    let mimeType: String
    let utType: String
    let originalSize: Int
    let encryptedSize: Int
    let hasThumbnail: Bool
    let timestamp: Date
}

// MARK: - StagedImportManager

/// Manages the pending_imports/ directory in the app group container.
/// Used by both the share extension (write) and the main app (read + cleanup).
enum StagedImportManager {

    private static let fm = FileManager.default
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Directory Access

    private static var pendingImportsURL: URL? {
        VaultCoreConstants.pendingImportsURL
    }

    static func batchDirectory(for batchId: UUID) -> URL? {
        pendingImportsURL?.appendingPathComponent(batchId.uuidString)
    }

    /// Ensures the pending_imports directory exists.
    static func ensureDirectoryExists() throws {
        guard let url = pendingImportsURL else { return }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Write (used by share extension)

    /// Creates a new batch directory and returns its URL and UUID.
    static func createBatch() throws -> (url: URL, batchId: UUID) {
        let batchId = UUID()
        guard let batchURL = batchDirectory(for: batchId) else {
            throw StagedImportError.appGroupUnavailable
        }
        try fm.createDirectory(at: batchURL, withIntermediateDirectories: true)
        return (batchURL, batchId)
    }

    /// Writes the manifest as the last step (atomic visibility marker).
    static func writeManifest(_ manifest: StagedImportManifest, to batchURL: URL) throws {
        let data = try encoder.encode(manifest)
        let manifestURL = batchURL.appendingPathComponent(VaultCoreConstants.manifestFilename)
        try data.write(to: manifestURL, options: .atomic)
    }

    /// Writes an encrypted file to the batch directory.
    static func writeEncryptedFile(_ data: Data, fileId: UUID, to batchURL: URL) throws {
        let fileURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
        try data.write(to: fileURL)
    }

    /// Writes an encrypted thumbnail to the batch directory.
    static func writeEncryptedThumbnail(_ data: Data, fileId: UUID, to batchURL: URL) throws {
        let fileURL = batchURL.appendingPathComponent("\(fileId.uuidString).thumb.enc")
        try data.write(to: fileURL)
    }

    // MARK: - Read (used by main app)

    /// Returns all pending batches that match a given key fingerprint.
    static func pendingBatches(for fingerprint: String) -> [StagedImportManifest] {
        guard let baseURL = pendingImportsURL,
              let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [StagedImportManifest] = []
        for dir in contents where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent(VaultCoreConstants.manifestFilename)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(StagedImportManifest.self, from: data),
                  manifest.keyFingerprint == fingerprint else {
                continue
            }
            results.append(manifest)
        }
        return results.sorted { $0.timestamp < $1.timestamp }
    }

    /// Returns the total file count across all pending batches for a fingerprint.
    static func pendingFileCount(for fingerprint: String) -> Int {
        pendingBatches(for: fingerprint).reduce(0) { $0 + $1.files.count }
    }

    /// Returns the URL of an encrypted file in a batch, or nil if the batch directory is unavailable.
    static func encryptedFileURL(batchId: UUID, fileId: UUID) -> URL? {
        guard let batchURL = batchDirectory(for: batchId) else { return nil }
        let fileURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// Reads encrypted file data for a specific file in a batch.
    static func readEncryptedFile(batchId: UUID, fileId: UUID) -> Data? {
        guard let batchURL = batchDirectory(for: batchId) else { return nil }
        let fileURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
        return try? Data(contentsOf: fileURL)
    }

    /// Reads encrypted thumbnail data for a specific file in a batch.
    static func readEncryptedThumbnail(batchId: UUID, fileId: UUID) -> Data? {
        guard let batchURL = batchDirectory(for: batchId) else { return nil }
        let fileURL = batchURL.appendingPathComponent("\(fileId.uuidString).thumb.enc")
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Cleanup

    /// Deletes a completed batch directory.
    static func deleteBatch(_ batchId: UUID) {
        guard let batchURL = batchDirectory(for: batchId) else { return }
        try? fm.removeItem(at: batchURL)
    }

    /// Increments the retry count for a batch. If retryCount >= 2, deletes the batch.
    /// Returns true if the batch was deleted.
    @discardableResult
    static func incrementRetryOrDelete(batchId: UUID) -> Bool {
        guard let batchURL = batchDirectory(for: batchId) else { return false }
        let manifestURL = batchURL.appendingPathComponent(VaultCoreConstants.manifestFilename)

        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? decoder.decode(StagedImportManifest.self, from: data) else {
            // No manifest = orphaned batch, delete it
            try? fm.removeItem(at: batchURL)
            return true
        }

        manifest.retryCount += 1
        if manifest.retryCount >= 2 {
            try? fm.removeItem(at: batchURL)
            return true
        }

        // Rewrite manifest with updated retry count
        if let updated = try? encoder.encode(manifest) {
            try? updated.write(to: manifestURL, options: .atomic)
        }
        return false
    }

    /// Cleans up orphaned batch directories (directories without a manifest).
    static func cleanupOrphans() {
        guard let baseURL = pendingImportsURL,
              let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return
        }

        for dir in contents where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent(VaultCoreConstants.manifestFilename)
            if !fm.fileExists(atPath: manifestURL.path) {
                try? fm.removeItem(at: dir)
            }
        }
    }

    /// Deletes all batches older than the given time interval (default 24 hours).
    /// Returns the number of batches deleted.
    @discardableResult
    static func cleanupExpiredBatches(olderThan interval: TimeInterval = 24 * 60 * 60) -> Int {
        guard let baseURL = pendingImportsURL,
              let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return 0
        }

        let cutoff = Date().addingTimeInterval(-interval)
        var deletedCount = 0

        for dir in contents where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent(VaultCoreConstants.manifestFilename)

            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? decoder.decode(StagedImportManifest.self, from: data) {
                if manifest.timestamp < cutoff {
                    try? fm.removeItem(at: dir)
                    deletedCount += 1
                }
            } else {
                // No manifest or unreadable — check directory modification date
                if let attrs = try? fm.attributesOfItem(atPath: dir.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < cutoff {
                    try? fm.removeItem(at: dir)
                    deletedCount += 1
                }
            }
        }
        return deletedCount
    }

    /// Returns all pending batches regardless of fingerprint, for management UI.
    static func allPendingBatches() -> [(manifest: StagedImportManifest, directoryURL: URL)] {
        guard let baseURL = pendingImportsURL,
              let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [(manifest: StagedImportManifest, directoryURL: URL)] = []
        for dir in contents where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent(VaultCoreConstants.manifestFilename)
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? decoder.decode(StagedImportManifest.self, from: data) {
                results.append((manifest, dir))
            }
        }
        return results.sorted { $0.manifest.timestamp < $1.manifest.timestamp }
    }

    /// Deletes all pending batches. Returns the number deleted.
    @discardableResult
    static func deleteAllBatches() -> Int {
        guard let baseURL = pendingImportsURL,
              let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return 0
        }

        var count = 0
        for dir in contents where dir.hasDirectoryPath {
            try? fm.removeItem(at: dir)
            count += 1
        }
        return count
    }

    /// Returns the total size in bytes of all pending batches.
    static func totalPendingSize() -> Int64 {
        guard let baseURL = pendingImportsURL,
              let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return 0
        }

        var totalSize: Int64 = 0
        for dir in contents where dir.hasDirectoryPath {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for file in files {
                    if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]),
                       let size = attrs.fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }
        return totalSize
    }
}

// MARK: - Errors

enum StagedImportError: Error {
    case appGroupUnavailable
    case encryptionFailed
    case manifestWriteFailed
    case freeTierLimitExceeded
}
