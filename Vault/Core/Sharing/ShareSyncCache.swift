import Foundation
import CryptoKit

/// Per-share sync state and encrypted file cache.
///
/// Directory structure: `Documents/share_cache/{shareVaultId}/`
/// - `encrypted_files/{fileId}.enc` — file re-encrypted with shareKey
/// - `encrypted_thumbs/{fileId}.enc` — thumbnail re-encrypted with shareKey
/// - `sync_state.json` — chunk hashes, file manifest, synced file IDs, sync sequence
/// - `last_svdf.bin` — full SVDF blob from last sync (for incremental append)
final class ShareSyncCache: Sendable {

    let shareVaultId: String

    private let cacheDir: URL
    private let filesDir: URL
    private let thumbsDir: URL
    private let syncStateURL: URL
    private let svdfURL: URL
    private let fm = FileManager.default

    // MARK: - Sync State

    struct SyncState: Codable {
        var syncedFileIds: Set<String>      // UUIDs in last sync
        var chunkHashes: [String]           // SHA256 hex per 2MB chunk
        var manifest: [SVDFSerializer.FileManifestEntry]
        var syncSequence: Int
        var deletedFileIds: Set<String>
        var totalDeletedBytes: Int
        var totalBytes: Int

        static var empty: SyncState {
            SyncState(
                syncedFileIds: [],
                chunkHashes: [],
                manifest: [],
                syncSequence: 0,
                deletedFileIds: [],
                totalDeletedBytes: 0,
                totalBytes: 0
            )
        }
    }

    // MARK: - Init

    init(shareVaultId: String) {
        self.shareVaultId = shareVaultId
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.cacheDir = docs.appendingPathComponent("share_cache/\(shareVaultId)", isDirectory: true)
        self.filesDir = cacheDir.appendingPathComponent("encrypted_files", isDirectory: true)
        self.thumbsDir = cacheDir.appendingPathComponent("encrypted_thumbs", isDirectory: true)
        self.syncStateURL = cacheDir.appendingPathComponent("sync_state.json")
        self.svdfURL = cacheDir.appendingPathComponent("last_svdf.bin")
    }

    // MARK: - Directory Management

    func ensureDirectories() throws {
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }

    /// Removes the entire cache directory for this share.
    func purge() throws {
        if fm.fileExists(atPath: cacheDir.path) {
            try fm.removeItem(at: cacheDir)
        }
    }

    // MARK: - Sync State

    func loadSyncState() -> SyncState? {
        guard let data = try? Data(contentsOf: syncStateURL) else { return nil }
        return try? JSONDecoder().decode(SyncState.self, from: data)
    }

    func saveSyncState(_ state: SyncState) throws {
        try ensureDirectories()
        let data = try JSONEncoder().encode(state)
        try data.write(to: syncStateURL, options: .atomic)
    }

    // MARK: - SVDF Blob

    func loadSVDF() -> Data? {
        try? Data(contentsOf: svdfURL)
    }

    func saveSVDF(_ data: Data) throws {
        try ensureDirectories()
        try data.write(to: svdfURL, options: .atomic)
    }

    // MARK: - Encrypted File Cache

    func hasEncryptedFile(_ fileId: String) -> Bool {
        fm.fileExists(atPath: filesDir.appendingPathComponent("\(fileId).enc").path)
    }

    func loadEncryptedFile(_ fileId: String) -> Data? {
        try? Data(contentsOf: filesDir.appendingPathComponent("\(fileId).enc"))
    }

    func saveEncryptedFile(_ fileId: String, data: Data) throws {
        try ensureDirectories()
        try data.write(to: filesDir.appendingPathComponent("\(fileId).enc"), options: .atomic)
    }

    func hasEncryptedThumb(_ fileId: String) -> Bool {
        fm.fileExists(atPath: thumbsDir.appendingPathComponent("\(fileId).enc").path)
    }

    func loadEncryptedThumb(_ fileId: String) -> Data? {
        try? Data(contentsOf: thumbsDir.appendingPathComponent("\(fileId).enc"))
    }

    func saveEncryptedThumb(_ fileId: String, data: Data) throws {
        try ensureDirectories()
        try data.write(to: thumbsDir.appendingPathComponent("\(fileId).enc"), options: .atomic)
    }

    /// Removes cached encrypted files for IDs no longer in the vault.
    func pruneFiles(keeping activeIds: Set<String>) {
        let allCached = (try? fm.contentsOfDirectory(atPath: filesDir.path)) ?? []
        for filename in allCached {
            let id = filename.replacingOccurrences(of: ".enc", with: "")
            if !activeIds.contains(id) {
                try? fm.removeItem(at: filesDir.appendingPathComponent(filename))
                try? fm.removeItem(at: thumbsDir.appendingPathComponent(filename))
            }
        }
    }

    // MARK: - Chunk Hashing

    /// Computes SHA-256 hashes for each 2MB chunk of the given data.
    static func computeChunkHashes(_ data: Data, chunkSize: Int = 2 * 1024 * 1024) -> [String] {
        stride(from: 0, to: data.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, data.count)
            let chunk = data[start..<end]
            let hash = SHA256.hash(data: chunk)
            return hash.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Returns true if the deleted space ratio warrants a full rebuild.
    func needsCompaction(_ state: SyncState) -> Bool {
        guard state.totalBytes > 0 else { return false }
        let ratio = Double(state.totalDeletedBytes) / Double(state.totalBytes)
        return ratio > SVDFSerializer.compactionThreshold
    }
}
