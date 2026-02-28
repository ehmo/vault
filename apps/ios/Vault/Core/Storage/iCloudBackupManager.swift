import Foundation
import UIKit
import CloudKit
import CryptoKit
import os.log
import BackgroundTasks

/// Single source of truth for opening iCloud settings.
/// Used by ShareVaultView and iCloudBackupSettingsView — keep in sync.
enum SettingsURLHelper {
    @MainActor static func openICloudSettings() {
        let iCloudURL = URL(string: "App-Prefs:root=APPLE_ACCOUNT")
        let fallbackURL = URL(string: UIApplication.openSettingsURLString)

        if let url = iCloudURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = fallbackURL {
            UIApplication.shared.open(url)
        }
    }
}

enum iCloudError: Error, LocalizedError {
    case notAvailable
    case containerNotFound
    case uploadFailed
    case downloadFailed
    case fileNotFound
    case checksumMismatch
    case wifiRequired
    case backupSkipped

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "iCloud is not available."
        case .containerNotFound:
            return "iCloud container not found."
        case .uploadFailed:
            return "Upload failed. Check your connection and try again."
        case .downloadFailed:
            return "Download failed. The backup data may be corrupted."
        case .fileNotFound:
            return "No backup found."
        case .checksumMismatch:
            return "Wrong pattern. The pattern doesn't match the one used for this backup."
        case .wifiRequired:
            return "Wi-Fi required. Change in Settings → Network to allow cellular."
        case .backupSkipped:
            return nil
        }
    }
}

// MARK: - Phase 3 Opaque Backup Manager

/// Backs up encrypted vault data to CloudKit private database using opaque BackupBlob records.
///
/// Every record is a fixed 10MB blob with a 64-byte encrypted tag. Record names are random UUIDs.
/// An attacker with CloudKit access sees N identical blobs with no grouping, no metadata, no
/// structure. Discovery requires the backup key (derived from the user's pattern).
///
/// Chunk types (identified by decrypted tag magic):
/// - VDAT: data chunk containing a piece of the backup payload
/// - VDIR: directory chunk containing the BackupVersionIndex
/// - VDCY: decoy chunk (random data, indistinguishable without key)
final class iCloudBackupManager: @unchecked Sendable {
    static let shared = iCloudBackupManager()
    nonisolated static let backgroundBackupTaskIdentifier = "app.vaultaire.ios.backup.resume"

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let fileManager = FileManager.default

    /// Custom zone for backup records — required for recordZoneChanges scanning.
    /// The default zone doesn't support change tracking or TRUEPREDICATE queries
    /// without manually-configured indexes in CloudKit Dashboard.
    private let backupZoneID = CKRecordZone.ID(zoneName: "BackupZone", ownerName: CKCurrentUserDefaultName)
    private var zoneCreated = false

    // MARK: - Constants

    /// Single opaque record type — all records look identical
    private let recordType = "BackupBlob"

    /// Fixed blob size — every record is exactly 10MB
    private static let blobSize = 10 * 1024 * 1024

    /// Encrypted tag size (AES-GCM sealed box with 36-byte plaintext)
    private static let tagSize = 64
    private static let tagPlaintextSize = 36 // 64 - 12 (nonce) - 16 (authTag)

    /// Max plaintext per VDAT chunk: blobSize - 4 (length prefix) - 28 (AES overhead) - 8 (magic + index)
    private static let maxPayloadPerChunk = blobSize - 4 - 28 - 8

    /// Max concurrent CloudKit operations
    private static let maxConcurrent = 4

    /// Decoy chunk ratio bounds (fraction of real chunk count)
    private static let minDecoyRatio = 0.2
    private static let maxDecoyRatio = 0.4

    /// Magic bytes for chunk types
    private static let vdatMagic: UInt32 = 0x56444154 // "VDAT"
    private static let vdirMagic: UInt32 = 0x56444952 // "VDIR"
    private static let vdcyMagic: UInt32 = 0x56444359 // "VDCY"

    /// 24-hour auto-backup interval
    private static let autoBackupInterval: TimeInterval = 24 * 60 * 60
    /// Max upload retry attempts
    private static let maxRetryCount: Int = 10
    /// Base delay for exponential backoff (seconds)
    private static let retryBaseDelay: TimeInterval = 60
    /// 48-hour TTL for staged backups
    private nonisolated static let pendingTTL: TimeInterval = 48 * 60 * 60

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "iCloudBackup")

    @MainActor private var autoBackupTask: Task<Void, Never>?
    @MainActor private var currentAutoBackupBgTaskId: UIBackgroundTaskIdentifier = .invalid
    @MainActor private var activeBgTaskIds: Set<UIBackgroundTaskIdentifier> = []
    @MainActor var isUploadRunning = false
    @MainActor private var currentBGProcessingTask: BGProcessingTask?

    private var vaultKeyProvider: (() -> Data?)?

    func setVaultKeyProvider(_ provider: @escaping () -> Data?) {
        vaultKeyProvider = provider
    }

    // MARK: - Data Types

    struct PendingBackupState: Codable {
        let backupId: String
        let dataChunkCount: Int
        let decoyCount: Int
        let createdAt: Date
        var uploadedFiles: Set<String>
        var retryCount: Int
        let fileCount: Int
        let vaultTotalSize: Int
        var wasTerminated: Bool = false
        var vaultFingerprint: String?
        /// Record names of old blobs to delete after successful upload
        var recordsToDelete: [String] = []
        /// BackupId of evicted version (when >3 versions exist) — cleaned up after upload
        var evictedBackupId: String?

        var totalFiles: Int { dataChunkCount + 1 + decoyCount } // +1 for VDIR
    }

    struct BackupVersionEntry: Codable {
        let backupId: String
        let timestamp: Date
        let size: Int
        let chunkCount: Int
        let fileCount: Int?
        let vaultTotalSize: Int?

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        }

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
    }

    struct BackupVersionIndex: Codable {
        var versions: [BackupVersionEntry]

        init(versions: [BackupVersionEntry] = []) {
            self.versions = versions
        }

        @discardableResult
        mutating func addVersion(_ entry: BackupVersionEntry) -> BackupVersionEntry? {
            let maxVersions = 3
            var evicted: BackupVersionEntry?
            if versions.count >= maxVersions {
                evicted = versions.removeFirst()
            }
            versions.append(entry)
            return evicted
        }
    }

    /// Result of scanning all BackupBlob tags with a backup key
    struct ScanResult {
        struct DataChunk {
            let recordID: CKRecord.ID
            let backupId: String
            let chunkIndex: Int
        }
        struct DirChunk {
            let recordID: CKRecord.ID
            let backupId: String
        }
        struct DecoyChunk {
            let recordID: CKRecord.ID
            let groupId: String
        }

        var dataChunks: [DataChunk] = []
        var dirChunks: [DirChunk] = []
        var decoyChunks: [DecoyChunk] = []
        var totalScanned: Int = 0
    }

    // MARK: - Init

    private init() {
        container = CKContainer(identifier: "iCloud.app.vaultaire.shared")
        privateDatabase = container.privateCloudDatabase
    }

    /// Ensures the custom BackupZone exists, creating it if needed.
    /// Called before any upload or scan operation. Idempotent — saving an
    /// existing zone is a no-op in CloudKit.
    private func ensureBackupZoneExists() async throws {
        guard !zoneCreated else { return }
        let zone = CKRecordZone(zoneID: backupZoneID)
        _ = try await privateDatabase.save(zone)
        zoneCreated = true
    }

    // MARK: - Tag Encryption

    /// Encrypts a 36-byte plaintext into a 64-byte tag (AES-GCM sealed box).
    private static func encryptTag(_ plaintext: Data, key: Data) throws -> Data {
        guard plaintext.count == tagPlaintextSize else { throw iCloudError.uploadFailed }
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined, combined.count == tagSize else {
            throw iCloudError.uploadFailed
        }
        return combined
    }

    /// Tries to decrypt a 64-byte tag. Returns 36-byte plaintext or nil.
    private static func decryptTag(_ data: Data, key: Data) -> Data? {
        guard data.count == tagSize, key.count == 32 else { return nil }
        let symmetricKey = SymmetricKey(data: key)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(sealedBox, using: symmetricKey) else {
            return nil
        }
        return plaintext
    }

    /// Builds a VDAT tag (36-byte plaintext) for a data chunk.
    private static func buildVDATTagPlaintext(backupId: String, chunkIndex: Int) -> Data {
        var data = Data(capacity: tagPlaintextSize)
        var magic = vdatMagic
        data.append(Data(bytes: &magic, count: 4))
        data.append(uuidBytes(from: backupId))
        var idx = UInt32(chunkIndex)
        data.append(Data(bytes: &idx, count: 4))
        // Pad to 36 bytes
        data.append(Data(count: tagPlaintextSize - data.count))
        return data
    }

    /// Builds a VDIR tag (36-byte plaintext) for a directory chunk.
    private static func buildVDIRTagPlaintext(backupId: String) -> Data {
        var data = Data(capacity: tagPlaintextSize)
        var magic = vdirMagic
        data.append(Data(bytes: &magic, count: 4))
        data.append(uuidBytes(from: backupId))
        data.append(Data(count: tagPlaintextSize - data.count))
        return data
    }

    /// Builds a VDCY tag (36-byte plaintext) for a decoy chunk.
    private static func buildVDCYTagPlaintext(groupId: String) -> Data {
        var data = Data(capacity: tagPlaintextSize)
        var magic = vdcyMagic
        data.append(Data(bytes: &magic, count: 4))
        data.append(uuidBytes(from: groupId))
        data.append(Data(count: tagPlaintextSize - data.count))
        return data
    }

    /// Parses a decrypted 36-byte tag plaintext.
    private static func parseTag(_ plaintext: Data) -> (magic: UInt32, backupId: String, chunkIndex: Int)? {
        guard plaintext.count == tagPlaintextSize else { return nil }
        let magic = plaintext.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let idBytes = plaintext.subdata(in: 4..<20)
        let backupId = uuidString(from: idBytes)
        let chunkIndex: Int
        if magic == vdatMagic {
            chunkIndex = Int(plaintext.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self) })
        } else {
            chunkIndex = 0
        }
        return (magic, backupId, chunkIndex)
    }

    // MARK: - Blob Encryption

    /// Encrypts plaintext into a fixed 10MB blob: [4B combinedLen][AES-GCM combined][random padding]
    private static func encryptBlob(_ plaintext: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else { throw iCloudError.uploadFailed }

        var blob = Data(capacity: blobSize)
        var combinedLen = UInt32(combined.count)
        blob.append(Data(bytes: &combinedLen, count: 4))
        blob.append(combined)

        let paddingSize = blobSize - 4 - combined.count
        if paddingSize > 0 {
            blob.append(CryptoEngine.generateRandomBytes(count: paddingSize) ?? Data(count: paddingSize))
        }
        return blob
    }

    /// Decrypts a 10MB blob: reads length prefix, extracts AES-GCM combined data, decrypts.
    private static func decryptBlob(_ data: Data, key: Data) throws -> Data {
        guard data.count >= 4 else { throw iCloudError.downloadFailed }
        let combinedLen = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let combinedEnd = 4 + Int(combinedLen)
        guard combinedEnd <= data.count else { throw iCloudError.downloadFailed }

        let combined = data.subdata(in: 4..<combinedEnd)
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - UUID Helpers

    private static func uuidBytes(from string: String) -> Data {
        guard let uuid = UUID(uuidString: string) else {
            return Data(count: 16)
        }
        return withUnsafePointer(to: uuid.uuid) { ptr in
            Data(bytes: ptr, count: 16)
        }
    }

    private static func uuidString(from data: Data) -> String {
        guard data.count >= 16 else { return UUID().uuidString }
        let uuid = data.withUnsafeBytes { ptr in
            UUID(uuid: ptr.load(as: uuid_t.self))
        }
        return uuid.uuidString
    }

    // MARK: - Staging Directories

    private nonisolated static func stagingDir(fingerprint: String?) -> URL {
        let dirName = fingerprint.map { "pending_backup_\($0)" } ?? "pending_backup"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated static func stateURL(fingerprint: String? = nil) -> URL {
        stagingDir(fingerprint: fingerprint).appendingPathComponent("state.json")
    }

    nonisolated func loadPendingBackupState() -> PendingBackupState? {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidates: [URL]
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: docsDir, includingPropertiesForKeys: nil
        ) {
            candidates = contents.filter {
                $0.lastPathComponent.hasPrefix("pending_backup") && $0.hasDirectoryPath
            }
        } else {
            candidates = []
        }

        for dir in candidates {
            let url = dir.appendingPathComponent("state.json")
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONDecoder().decode(PendingBackupState.self, from: data) else {
                continue
            }
            guard Date().timeIntervalSince(state.createdAt) < Self.pendingTTL else {
                try? FileManager.default.removeItem(at: dir)
                continue
            }
            return state
        }
        return nil
    }

    private nonisolated func savePendingBackupState(_ state: PendingBackupState) {
        let url = Self.stateURL(fingerprint: state.vaultFingerprint)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            Self.logger.error("[staging] Failed to save pending state: \(error.localizedDescription)")
        }
    }

    nonisolated func clearStagingDirectory(fingerprint: String? = nil) {
        try? FileManager.default.removeItem(at: Self.stagingDir(fingerprint: fingerprint))
    }

    var hasPendingBackup: Bool {
        loadPendingBackupState() != nil
    }

    // MARK: - Local Version Index

    private nonisolated static func localVersionIndexURL(fingerprint: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backup_index_\(fingerprint).json")
    }

    private nonisolated func loadLocalVersionIndex(fingerprint: String) -> BackupVersionIndex {
        let url = Self.localVersionIndexURL(fingerprint: fingerprint)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(BackupVersionIndex.self, from: data) else {
            return BackupVersionIndex()
        }
        return index
    }

    private nonisolated func saveLocalVersionIndex(_ index: BackupVersionIndex, fingerprint: String) {
        let url = Self.localVersionIndexURL(fingerprint: fingerprint)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Returns the locally cached version index for instant display, or nil if no cache exists.
    func getCachedVersionIndex(backupKey: Data) -> BackupVersionIndex? {
        guard let fp = Self.deriveFingerprint(backupKey: backupKey) else { return nil }
        let index = loadLocalVersionIndex(fingerprint: fp)
        return index.versions.isEmpty ? nil : index
    }

    // MARK: - Vault Fingerprint

    static func vaultFingerprint(from backupKey: Data) -> String {
        KeyDerivation.keyFingerprint(from: backupKey)
    }

    // MARK: - Account Status

    private func waitForAvailableAccount() async throws {
        for attempt in 0..<6 {
            let status = try await container.accountStatus()
            Self.logger.info("[backup] CKAccountStatus = \(status.rawValue) (attempt \(attempt))")
            if status == .available { return }
            if status == .temporarilyUnavailable || status == .couldNotDetermine {
                let delays: [UInt64] = [1, 2, 3, 5, 8, 13]
                try await Task.sleep(nanoseconds: delays[min(attempt, delays.count - 1)] * 1_000_000_000)
                continue
            }
            throw iCloudError.notAvailable
        }
        throw iCloudError.notAvailable
    }

    // MARK: - Backup

    enum BackupStage: String {
        case waitingForICloud = "Connecting to iCloud..."
        case readingVault = "Reading vault data..."
        case encrypting = "Encrypting backup..."
        case uploading = "Uploading to iCloud..."
        case complete = "Backup complete"
    }

    func performBackup(
        with key: Data,
        pattern: [Int]? = nil,
        gridSize: Int = 5,
        onProgress: @escaping (BackupStage) -> Void,
        onUploadProgress: @escaping (Double) -> Void = { _ in }
    ) async throws {
        guard CloudKitSharingManager.canProceedWithNetwork() else {
            throw iCloudError.wifiRequired
        }

        guard let pattern = pattern else {
            throw iCloudError.uploadFailed
        }
        let backupKey = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: gridSize)

        onProgress(.readingVault)
        try Task.checkCancellation()
        let state = try await stageBackupToDisk(with: key, backupKey: backupKey, onProgress: { stage in
            onProgress(stage)
        })

        onProgress(.uploading)
        try await uploadStagedBackup(backupKey: backupKey, onUploadProgress: onUploadProgress)
        onProgress(.complete)
        Self.logger.info("[backup] Complete (\(state.dataChunkCount) data + \(state.decoyCount) decoy chunks)")
    }

    // MARK: - Phase 1: Stage Backup to Disk

    @discardableResult
    func stageBackupToDisk(
        with key: Data,
        backupKey: Data,
        onProgress: ((BackupStage) -> Void)? = nil
    ) async throws -> PendingBackupState {
        onProgress?(.readingVault)
        try Task.checkCancellation()
        let index = try await VaultStorage.shared.loadIndex(with: VaultKey(key))

        if index.files.isEmpty {
            Self.logger.info("[staging] Skipping — vault is empty")
            throw iCloudError.backupSkipped
        }
        if index.isSharedVault == true {
            Self.logger.info("[staging] Skipping — shared vault")
            throw iCloudError.backupSkipped
        }

        let fingerprint = Self.vaultFingerprint(from: backupKey)
        let payload = try await packBackupPayloadOffMain(index: index, vaultFingerprint: fingerprint)
        Self.logger.info("[staging] Payload packed: \(payload.count) bytes")

        onProgress?(.encrypting)
        try Task.checkCancellation()

        let backupId = UUID().uuidString

        // Split payload into chunk-sized pieces and encrypt each with backup key
        let plainChunks = splitPayload(payload)
        let dataChunkCount = plainChunks.count

        // Determine decoy count
        let decoyRatio = Double.random(in: Self.minDecoyRatio...Self.maxDecoyRatio)
        let decoyCount = max(1, Int(Double(dataChunkCount) * decoyRatio))

        clearStagingDirectory(fingerprint: fingerprint)
        let stagingDir = Self.stagingDir(fingerprint: fingerprint)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // Encrypt and write VDAT chunks
        for (chunkIndex, plaintext) in plainChunks.enumerated() {
            try Task.checkCancellation()
            // Build VDAT plaintext: [magic][chunkIndex][data]
            var chunkPlaintext = Data(capacity: plaintext.count + 8)
            var magic = Self.vdatMagic
            chunkPlaintext.append(Data(bytes: &magic, count: 4))
            var idx = UInt32(chunkIndex)
            chunkPlaintext.append(Data(bytes: &idx, count: 4))
            chunkPlaintext.append(plaintext)

            let blob = try Self.encryptBlob(chunkPlaintext, key: backupKey)
            let tag = try Self.encryptTag(Self.buildVDATTagPlaintext(backupId: backupId, chunkIndex: chunkIndex), key: backupKey)

            try writeChunkFile(blob, tag: tag, name: "vdat_\(chunkIndex)", dir: stagingDir)
        }

        // Build and encrypt VDIR chunk
        var versionIndex = loadLocalVersionIndex(fingerprint: fingerprint)
        let versionEntry = BackupVersionEntry(
            backupId: backupId,
            timestamp: Date(),
            size: payload.count,
            chunkCount: dataChunkCount,
            fileCount: index.files.count,
            vaultTotalSize: index.totalSize
        )
        let evicted = versionIndex.addVersion(versionEntry)
        saveLocalVersionIndex(versionIndex, fingerprint: fingerprint)

        let vdirJSON = try JSONEncoder().encode(versionIndex)
        var vdirPlaintext = Data(capacity: vdirJSON.count + 4)
        var vdirMagicVal = Self.vdirMagic
        vdirPlaintext.append(Data(bytes: &vdirMagicVal, count: 4))
        vdirPlaintext.append(vdirJSON)

        let vdirBlob = try Self.encryptBlob(vdirPlaintext, key: backupKey)
        let vdirTag = try Self.encryptTag(Self.buildVDIRTagPlaintext(backupId: backupId), key: backupKey)
        try writeChunkFile(vdirBlob, tag: vdirTag, name: "vdir", dir: stagingDir)

        // Generate decoy chunks — encrypt random data so blob structure matches real chunks
        for i in 0..<decoyCount {
            try Task.checkCancellation()
            let randomPayloadSize = Int.random(in: 1024...(Self.maxPayloadPerChunk))
            let randomPayload = CryptoEngine.generateRandomBytes(count: randomPayloadSize) ?? Data(count: randomPayloadSize)
            let decoyBlob = try Self.encryptBlob(randomPayload, key: backupKey)
            let decoyTag = try Self.encryptTag(Self.buildVDCYTagPlaintext(groupId: backupId), key: backupKey)
            try writeChunkFile(decoyBlob, tag: decoyTag, name: "decoy_\(i)", dir: stagingDir)
        }

        // Track evicted version for cleanup after upload
        var evictedBackupId: String?
        if let evictedVersion = evicted {
            evictedBackupId = evictedVersion.backupId
            Self.logger.info("[staging] Version evicted: \(evictedVersion.backupId.prefix(8))...")
        }

        let state = PendingBackupState(
            backupId: backupId,
            dataChunkCount: dataChunkCount,
            decoyCount: decoyCount,
            createdAt: Date(),
            uploadedFiles: [],
            retryCount: 0,
            fileCount: index.files.count,
            vaultTotalSize: index.totalSize,
            vaultFingerprint: fingerprint,
            evictedBackupId: evictedBackupId
        )
        savePendingBackupState(state)

        Self.logger.info("[staging] Staged \(dataChunkCount) data + 1 dir + \(decoyCount) decoy chunks to disk")
        return state
    }

    /// Splits payload into pieces that fit in VDAT chunks.
    private func splitPayload(_ payload: Data) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        while offset < payload.count {
            let end = min(offset + Self.maxPayloadPerChunk, payload.count)
            chunks.append(payload.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    /// Writes a 10MB .bin file and 64B .tag file to the staging directory.
    private func writeChunkFile(_ blob: Data, tag: Data, name: String, dir: URL) throws {
        let binURL = dir.appendingPathComponent("\(name).bin")
        let tagURL = dir.appendingPathComponent("\(name).tag")
        try blob.write(to: binURL, options: .atomic)
        try tag.write(to: tagURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: binURL.path
        )
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: tagURL.path
        )
    }

    // MARK: - Phase 2: Upload Staged Backup

    func uploadStagedBackup(
        backupKey: Data? = nil,
        onUploadProgress: ((Double) -> Void)? = nil
    ) async throws {
        let alreadyRunning = await MainActor.run {
            if isUploadRunning { return true }
            isUploadRunning = true
            return false
        }
        if alreadyRunning {
            Self.logger.info("[upload] Already in progress, skipping")
            return
        }
        defer { Task { @MainActor in self.isUploadRunning = false } }

        guard var state = loadPendingBackupState() else {
            Self.logger.info("[upload] No pending backup state")
            return
        }

        try await waitForAvailableAccount()
        try await ensureBackupZoneExists()

        let stagingDir = Self.stagingDir(fingerprint: state.vaultFingerprint)

        // Enumerate all chunk files to upload
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: stagingDir, includingPropertiesForKeys: nil
        ) else { return }

        let binFiles = files.filter { $0.pathExtension == "bin" && $0.lastPathComponent != "state.json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !state.uploadedFiles.contains($0) }

        let totalFiles = state.totalFiles
        let alreadyUploaded = state.uploadedFiles.count
        Self.logger.info("[upload] \(alreadyUploaded)/\(totalFiles) already uploaded, \(binFiles.count) remaining")
        onUploadProgress?(Double(alreadyUploaded) / Double(max(totalFiles, 1)))

        if !binFiles.isEmpty {
            try await withThrowingTaskGroup(of: String.self) { group in
                var completed = 0
                var inFlight = 0

                for name in binFiles {
                    try Task.checkCancellation()

                    if inFlight >= Self.maxConcurrent {
                        let done = try await group.next()!
                        completed += 1
                        inFlight -= 1
                        state.uploadedFiles.insert(done)
                        savePendingBackupState(state)
                        onUploadProgress?(Double(alreadyUploaded + completed) / Double(totalFiles))
                    }

                    group.addTask {
                        let binURL = stagingDir.appendingPathComponent("\(name).bin")
                        let tagURL = stagingDir.appendingPathComponent("\(name).tag")
                        let tagData = try Data(contentsOf: tagURL)

                        let recordName = UUID().uuidString
                        let recordID = CKRecord.ID(recordName: recordName, zoneID: self.backupZoneID)
                        let record = CKRecord(recordType: self.recordType, recordID: recordID)

                        // Write bin to temp file for CKAsset
                        let tempURL = self.fileManager.temporaryDirectory
                            .appendingPathComponent("\(recordName)_\(UUID().uuidString).bin")
                        try self.fileManager.copyItem(at: binURL, to: tempURL)
                        try FileManager.default.setAttributes(
                            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                            ofItemAtPath: tempURL.path
                        )
                        defer { try? self.fileManager.removeItem(at: tempURL) }

                        record["data"] = CKAsset(fileURL: tempURL)
                        record["tag"] = tagData as CKRecordValue

                        try await self.privateDatabase.saveWithRetry(record)
                        return name
                    }
                    inFlight += 1
                }

                for try await done in group {
                    completed += 1
                    state.uploadedFiles.insert(done)
                    savePendingBackupState(state)
                    onUploadProgress?(Double(alreadyUploaded + completed) / Double(totalFiles))
                }
            }
        }

        onUploadProgress?(0.95)

        // Delete old records if any
        if !state.recordsToDelete.isEmpty {
            await deleteRecords(named: state.recordsToDelete)
        }

        // Clean up evicted version records and stale VDIRs
        if let evictedId = state.evictedBackupId, let backupKey = backupKey {
            do {
                let scan = try await scanAllTags(backupKey: backupKey)
                var idsToDelete: [CKRecord.ID] = []

                // Delete VDAT chunks for evicted version
                for chunk in scan.dataChunks where chunk.backupId == evictedId {
                    idsToDelete.append(chunk.recordID)
                }
                // Delete decoys for evicted version
                for decoy in scan.decoyChunks where decoy.groupId == evictedId {
                    idsToDelete.append(decoy.recordID)
                }

                // Keep only the newest VDIR (sorted by creation date via scan order), delete the rest
                if scan.dirChunks.count > 1 {
                    for staleDir in scan.dirChunks.dropFirst() {
                        idsToDelete.append(staleDir.recordID)
                    }
                }

                if !idsToDelete.isEmpty {
                    Self.logger.info("[cleanup] Deleting \(idsToDelete.count) records for evicted version \(evictedId.prefix(8))... and stale VDIRs")
                    await deleteRecordIDs(idsToDelete)
                }
            } catch {
                Self.logger.warning("[cleanup] Failed to clean up evicted version: \(error)")
            }
        }

        // Update timestamps
        let timestampKey = state.vaultFingerprint.map { "lastBackupTimestamp_\($0)" } ?? "lastBackupTimestamp"
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
        UserDefaults.standard.removeObject(forKey: "lastLockedBackupAttempt")

        clearStagingDirectory(fingerprint: state.vaultFingerprint)
        onUploadProgress?(1.0)
        Self.logger.info("[upload] Complete")
    }

    // MARK: - Tag Scanning

    /// Scans all BackupBlob tags and decrypts with the backup key.
    /// Returns categorized results: data chunks, directory chunks, decoys.
    ///
    /// Uses zone-change fetching instead of CKQuery because the BackupBlob
    /// record type has no queryable indexes in CloudKit Dashboard. Zone changes
    /// enumerate all records without requiring any indexes.
    func scanAllTags(backupKey: Data) async throws -> ScanResult {
        try await waitForAvailableAccount()

        var result = ScanResult()
        try await ensureBackupZoneExists()
        var changeToken: CKServerChangeToken? = nil
        var moreComing = true

        while moreComing {
            let changes = try await privateDatabase.recordZoneChanges(
                inZoneWith: backupZoneID, since: changeToken
            )

            for modification in changes.modificationResultsByID {
                let (recordID, modResult) = modification
                guard case .success(let info) = modResult else { continue }
                let record = info.record
                guard record.recordType == recordType else { continue }

                result.totalScanned += 1
                guard let tagData = record["tag"] as? Data,
                      let plaintext = Self.decryptTag(tagData, key: backupKey),
                      let parsed = Self.parseTag(plaintext) else {
                    continue
                }

                switch parsed.magic {
                case Self.vdatMagic:
                    result.dataChunks.append(.init(recordID: recordID, backupId: parsed.backupId, chunkIndex: parsed.chunkIndex))
                case Self.vdirMagic:
                    result.dirChunks.append(.init(recordID: recordID, backupId: parsed.backupId))
                case Self.vdcyMagic:
                    result.decoyChunks.append(.init(recordID: recordID, groupId: parsed.backupId))
                default:
                    break
                }
            }

            changeToken = changes.changeToken
            moreComing = changes.moreComing
        }

        Self.logger.info("[scan] Scanned \(result.totalScanned) blobs: \(result.dataChunks.count) data, \(result.dirChunks.count) dir, \(result.decoyChunks.count) decoy")
        return result
    }

    /// Scans tags and returns the merged version index from all VDIR chunks.
    func scanForVersions(backupKey: Data) async throws -> BackupVersionIndex {
        let scan = try await scanAllTags(backupKey: backupKey)

        guard !scan.dirChunks.isEmpty else {
            return BackupVersionIndex()
        }

        // Download and decrypt each VDIR chunk, merge version indexes
        var merged = BackupVersionIndex()
        var seenBackupIds = Set<String>()

        for dirChunk in scan.dirChunks {
            do {
                let record = try await privateDatabase.record(for: dirChunk.recordID)
                guard let asset = record["data"] as? CKAsset,
                      let assetURL = asset.fileURL else { continue }

                let blobData = try Data(contentsOf: assetURL)
                let plaintext = try Self.decryptBlob(blobData, key: backupKey)

                guard plaintext.count > 4 else { continue }
                let magic = plaintext.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
                guard magic == Self.vdirMagic else { continue }

                let jsonData = plaintext.subdata(in: 4..<plaintext.count)
                let versionIndex = try JSONDecoder().decode(BackupVersionIndex.self, from: jsonData)

                for version in versionIndex.versions {
                    if !seenBackupIds.contains(version.backupId) {
                        seenBackupIds.insert(version.backupId)
                        merged.versions.append(version)
                    }
                }
            } catch {
                Self.logger.warning("[scan] Failed to read VDIR chunk: \(error)")
            }
        }

        // Sort by timestamp descending
        merged.versions.sort { $0.timestamp > $1.timestamp }
        return merged
    }

    // MARK: - Restore

    /// Restores a specific backup version by scanning tags, downloading matching VDAT chunks,
    /// decrypting each, reassembling the payload, and writing data to disk.
    func restoreBackupVersion(
        _ version: BackupVersionEntry,
        backupKey: Data,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        try await waitForAvailableAccount()

        Self.logger.info("[restore] Starting restore: \(version.chunkCount) chunks for backup \(version.backupId.prefix(8))...")

        // Scan tags to find all VDAT chunks for this backup
        let scan = try await scanAllTags(backupKey: backupKey)
        let matchingChunks = scan.dataChunks
            .filter { $0.backupId == version.backupId }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        guard matchingChunks.count == version.chunkCount else {
            Self.logger.error("[restore] Expected \(version.chunkCount) chunks, found \(matchingChunks.count)")
            // No matching chunks = wrong key (wrong pattern). Some but not all = actual download issue.
            throw matchingChunks.isEmpty ? iCloudError.checksumMismatch : iCloudError.downloadFailed
        }

        // Download and decrypt chunks in parallel
        let payloadData = try await downloadAndDecryptChunks(
            matchingChunks.map { ($0.recordID, $0.chunkIndex) },
            backupKey: backupKey,
            onProgress: onProgress
        )

        // Unpack VBK2 payload
        let (blobs, indexes) = try unpackBackupPayload(payloadData)

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let defaultBlobSize = 50 * 1024 * 1024

        // Restore blobs
        for (blobId, usedData) in blobs {
            let blobURL: URL
            if blobId == "primary" {
                blobURL = documents.appendingPathComponent("vault_data.bin")
            } else {
                blobURL = documents.appendingPathComponent("vd_\(blobId).bin")
            }

            fileManager.createFile(atPath: blobURL.path, contents: nil, attributes: [
                .protectionKey: FileProtectionType.complete
            ])
            if let handle = try? FileHandle(forWritingTo: blobURL) {
                let chunkSize = 1024 * 1024
                for _ in 0..<(defaultBlobSize / chunkSize) {
                    if let randomData = CryptoEngine.generateRandomBytes(count: chunkSize) {
                        handle.write(randomData)
                    }
                }
                if !usedData.isEmpty {
                    try handle.seek(toOffset: 0)
                    handle.write(usedData)
                }
                try? handle.close()
            }
        }

        // Restore index files
        for (fileName, data) in indexes {
            let indexURL = documents.appendingPathComponent(fileName)
            try data.write(to: indexURL, options: [.atomic, .completeFileProtection])
        }

        Self.logger.info("[restore] Complete: \(blobs.count) blob(s), \(indexes.count) index file(s)")
    }

    /// Downloads chunks in parallel and decrypts each, reassembling in order.
    private func downloadAndDecryptChunks(
        _ chunks: [(recordID: CKRecord.ID, chunkIndex: Int)],
        backupKey: Data,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Data {
        let total = chunks.count
        guard total > 0 else { return Data() }

        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var completed = 0
            var inFlight = 0
            var chunkMap = [Int: Data]()
            chunkMap.reserveCapacity(total)

            for (recordID, chunkIndex) in chunks {
                if inFlight >= Self.maxConcurrent {
                    let (idx, data) = try await group.next()!
                    chunkMap[idx] = data
                    completed += 1
                    inFlight -= 1
                    onProgress?(completed, total)
                }

                let capturedIndex = chunkIndex
                group.addTask {
                    let record = try await self.privateDatabase.record(for: recordID)
                    guard let asset = record["data"] as? CKAsset,
                          let assetURL = asset.fileURL else {
                        throw iCloudError.downloadFailed
                    }
                    let blobData = try Data(contentsOf: assetURL)
                    let plaintext = try Self.decryptBlob(blobData, key: backupKey)

                    // Strip VDAT header: [4B magic][4B chunkIndex][payload...]
                    guard plaintext.count > 8 else { throw iCloudError.downloadFailed }
                    let magic = plaintext.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
                    guard magic == Self.vdatMagic else { throw iCloudError.downloadFailed }
                    let payloadData = plaintext.subdata(in: 8..<plaintext.count)
                    return (capturedIndex, payloadData)
                }
                inFlight += 1
            }

            for try await (idx, data) in group {
                chunkMap[idx] = data
                completed += 1
                onProgress?(completed, total)
            }

            // Reassemble in order
            var result = Data()
            for i in 0..<total {
                guard let chunk = chunkMap[i] else { throw iCloudError.downloadFailed }
                result.append(chunk)
            }
            return result
        }
    }

    // MARK: - Delete

    /// Deletes a specific backup version's chunks (VDAT + associated decoys).
    func deleteBackupVersion(_ version: BackupVersionEntry, backupKey: Data) async throws {
        try await waitForAvailableAccount()
        let scan = try await scanAllTags(backupKey: backupKey)

        var idsToDelete: [CKRecord.ID] = []
        // Delete VDAT chunks for this version
        for chunk in scan.dataChunks where chunk.backupId == version.backupId {
            idsToDelete.append(chunk.recordID)
        }
        // Delete decoys associated with this backup's group only
        for decoy in scan.decoyChunks where decoy.groupId == version.backupId {
            idsToDelete.append(decoy.recordID)
        }

        if !idsToDelete.isEmpty {
            Self.logger.info("[delete] Deleting \(idsToDelete.count) records for version \(version.backupId.prefix(8))...")
            await deleteRecordIDs(idsToDelete)
        }

        // Update local version index
        if let fp = Self.deriveFingerprint(backupKey: backupKey) {
            var localIndex = loadLocalVersionIndex(fingerprint: fp)
            localIndex.versions.removeAll { $0.backupId == version.backupId }
            saveLocalVersionIndex(localIndex, fingerprint: fp)

            // Upload updated VDIR
            if !localIndex.versions.isEmpty {
                try await uploadUpdatedVDIR(localIndex, backupKey: backupKey)
            }
        }
    }

    /// Deletes ALL backup data for this vault (all versions, all decoys, all VDIRs).
    func deleteAllBackups(backupKey: Data) async throws {
        try await waitForAvailableAccount()
        let scan = try await scanAllTags(backupKey: backupKey)

        var idsToDelete: [CKRecord.ID] = []
        for chunk in scan.dataChunks { idsToDelete.append(chunk.recordID) }
        for dir in scan.dirChunks { idsToDelete.append(dir.recordID) }
        for decoy in scan.decoyChunks { idsToDelete.append(decoy.recordID) }

        if !idsToDelete.isEmpty {
            Self.logger.info("[delete] Deleting all \(idsToDelete.count) backup records")
            await deleteRecordIDs(idsToDelete)
        }

        if let fp = Self.deriveFingerprint(backupKey: backupKey) {
            saveLocalVersionIndex(BackupVersionIndex(), fingerprint: fp)
        }
    }

    /// Uploads a new VDIR chunk with the given version index.
    private func uploadUpdatedVDIR(_ index: BackupVersionIndex, backupKey: Data) async throws {
        let latestBackupId = index.versions.last?.backupId ?? UUID().uuidString

        let vdirJSON = try JSONEncoder().encode(index)
        var vdirPlaintext = Data(capacity: vdirJSON.count + 4)
        var magic = Self.vdirMagic
        vdirPlaintext.append(Data(bytes: &magic, count: 4))
        vdirPlaintext.append(vdirJSON)

        let blob = try Self.encryptBlob(vdirPlaintext, key: backupKey)
        let tag = try Self.encryptTag(Self.buildVDIRTagPlaintext(backupId: latestBackupId), key: backupKey)

        let recordName = UUID().uuidString
        let recordID = CKRecord.ID(recordName: recordName, zoneID: backupZoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("\(recordName).bin")
        try blob.write(to: tempURL)
        defer { try? fileManager.removeItem(at: tempURL) }

        record["data"] = CKAsset(fileURL: tempURL)
        record["tag"] = tag as CKRecordValue

        try await privateDatabase.saveWithRetry(record)
    }

    private static func deriveFingerprint(backupKey: Data) -> String? {
        guard backupKey.count == 32 else { return nil }
        return vaultFingerprint(from: backupKey)
    }

    // MARK: - Batch Delete Helpers

    private func deleteRecords(named recordNames: [String]) async {
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: backupZoneID) }
        await deleteRecordIDs(ids)
    }

    private func deleteRecordIDs(_ ids: [CKRecord.ID]) async {
        guard !ids.isEmpty else { return }
        let batchSize = 400
        for batchStart in stride(from: 0, to: ids.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, ids.count)
            let batch = Array(ids[batchStart..<batchEnd])
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility

            _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    if case .failure(let error) = result {
                        Self.logger.warning("[delete] Batch delete failed: \(error)")
                    }
                    continuation.resume()
                }
                self.privateDatabase.add(operation)
            }
        }
    }

    // MARK: - Resume Support

    @MainActor
    func resumeBackupUploadIfNeeded(trigger: String) {
        guard UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") else { return }
        guard CloudKitSharingManager.canProceedWithNetwork() else { return }
        guard let state = loadPendingBackupState() else { return }
        guard autoBackupTask == nil, !isUploadRunning else { return }

        Self.logger.info("[resume] Found staged backup (trigger=\(trigger, privacy: .public), terminated=\(state.wasTerminated))")

        var detachedTask: Task<Void, Never>?
        nonisolated(unsafe) var bgTaskId: UIBackgroundTaskIdentifier = .invalid

        bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            detachedTask?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if var state = self.loadPendingBackupState() {
                    state.wasTerminated = true
                    self.savePendingBackupState(state)
                }
                self.activeBgTaskIds.remove(bgTaskId)
                self.finishAutoBackupRun(bgTaskId: bgTaskId)
            }
        }
        currentAutoBackupBgTaskId = bgTaskId
        activeBgTaskIds.insert(bgTaskId)

        detachedTask = Task.detached(priority: .utility) { [weak self] in
            let bgTaskId = bgTaskId
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeBgTaskIds.remove(bgTaskId)
                    self.finishAutoBackupRun(bgTaskId: bgTaskId)
                }
            }
            do {
                if var state = self.loadPendingBackupState(), state.wasTerminated {
                    state.wasTerminated = false
                    self.savePendingBackupState(state)
                }
                try await self.uploadStagedBackup()
                self.sendBackupCompleteNotification(success: true)
            } catch {
                if Task.isCancelled {
                    self.scheduleBackgroundResumeTask(earliestIn: 60)
                    return
                }
                self.handleUploadFailure(error)
            }
        }
        autoBackupTask = detachedTask
    }

    // MARK: - Auto Background Backup

    @MainActor
    func performBackupIfNeeded(with key: Data, pattern: [Int]? = nil, gridSize: Int = 5, vaultFingerprint: String? = nil) {
        let defaults = UserDefaults.standard
        let enabledKey = vaultFingerprint.map { "iCloudBackupEnabled_\($0)" }
        let isEnabled = enabledKey.map { defaults.bool(forKey: $0) } ?? defaults.bool(forKey: "iCloudBackupEnabled")
        guard isEnabled else { return }
        guard CloudKitSharingManager.canProceedWithNetwork() else { return }
        guard autoBackupTask == nil, !isUploadRunning else { return }

        if loadPendingBackupState() != nil {
            resumeBackupUploadIfNeeded(trigger: "auto_backup_pending")
            scheduleBackgroundResumeTask(earliestIn: 300)
            return
        }

        let timestampKey = vaultFingerprint.map { "lastBackupTimestamp_\($0)" } ?? "lastBackupTimestamp"
        let lastTimestamp = defaults.double(forKey: timestampKey)
        if lastTimestamp > 0 {
            let nextDue = Date(timeIntervalSince1970: lastTimestamp).addingTimeInterval(Self.autoBackupInterval)
            guard Date() >= nextDue else { return }
        }

        guard let pattern = pattern else { return }

        let capturedKey = key
        let capturedPattern = pattern
        let capturedGridSize = gridSize
        let capturedTimestampKey = timestampKey
        var detachedTask: Task<Void, Never>?
        nonisolated(unsafe) var bgTaskId: UIBackgroundTaskIdentifier = .invalid

        bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            detachedTask?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeBgTaskIds.remove(bgTaskId)
                self.finishAutoBackupRun(bgTaskId: bgTaskId)
            }
        }
        currentAutoBackupBgTaskId = bgTaskId
        activeBgTaskIds.insert(bgTaskId)

        detachedTask = Task.detached(priority: .utility) { [weak self] in
            let bgTaskId = bgTaskId
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeBgTaskIds.remove(bgTaskId)
                    self.finishAutoBackupRun(bgTaskId: bgTaskId)
                }
            }
            do {
                let backupKey = try KeyDerivation.deriveBackupKey(from: capturedPattern, gridSize: capturedGridSize)
                try await self.stageBackupToDisk(with: capturedKey, backupKey: backupKey)
                try await self.uploadStagedBackup()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: capturedTimestampKey)
                self.sendBackupCompleteNotification(success: true)
            } catch let error as iCloudError where error == .backupSkipped {
                return
            } catch {
                if Task.isCancelled {
                    self.scheduleBackgroundResumeTask(earliestIn: 60)
                    return
                }
                EmbraceManager.shared.captureError(error, context: ["feature": "icloud_auto_backup"])
                self.handleUploadFailure(error)
            }
        }
        autoBackupTask = detachedTask
    }

    @MainActor
    private func finishAutoBackupRun(bgTaskId: UIBackgroundTaskIdentifier) {
        autoBackupTask = nil
        activeBgTaskIds.remove(bgTaskId)
        guard bgTaskId != .invalid, currentAutoBackupBgTaskId == bgTaskId else { return }
        currentAutoBackupBgTaskId = .invalid
        UIApplication.shared.endBackgroundTask(bgTaskId)
    }

    /// Shared retry logic for upload failures.
    private func handleUploadFailure(_ error: Error) {
        if var state = loadPendingBackupState() {
            state.retryCount += 1
            savePendingBackupState(state)

            if state.retryCount >= Self.maxRetryCount {
                Self.logger.error("[retry] Max retries reached. Scheduling 24h retry.")
                sendBackupCompleteNotification(success: false, errorMessage: "Backup failed after multiple attempts. Will retry in 24 hours.")
                scheduleBackgroundResumeTask(earliestIn: 24 * 60 * 60)
            } else {
                let delay = min(Self.retryBaseDelay * pow(2.0, Double(state.retryCount - 1)), 3600)
                Self.logger.info("[retry] Attempt \(state.retryCount)/\(Self.maxRetryCount) in \(Int(delay))s")
                scheduleBackgroundResumeTask(earliestIn: delay)
            }
        } else {
            scheduleBackgroundResumeTask(earliestIn: 300)
        }
    }

    // MARK: - Backup Payload Packing

    /// Packs all blob data (used portions only) + index files into a VBK2 binary payload.
    /// Format:
    /// ```
    /// Header:  magic 0x56424B32 (4B) | version 2 (1B) | blobCount (2B) | indexCount (2B)
    /// Blobs:   [idLen(2B) | blobId(var) | dataLen(8B) | data(var)] × blobCount
    /// Indexes: [nameLen(2B) | fileName(var) | dataLen(4B) | data(var)] × indexCount
    /// ```
    private func packBackupPayload(index: VaultStorage.VaultIndex, vaultFingerprint: String?) throws -> Data {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var payload = Data()

        var magic: UInt32 = 0x56424B32
        payload.append(Data(bytes: &magic, count: 4))
        var version: UInt8 = 2
        payload.append(Data(bytes: &version, count: 1))

        let blobs = index.blobs ?? [VaultStorage.BlobDescriptor(
            blobId: "primary",
            fileName: "vault_data.bin",
            capacity: index.totalSize,
            cursor: index.nextOffset
        )]

        var blobCount = UInt16(blobs.count)
        payload.append(Data(bytes: &blobCount, count: 2))

        let indexFiles: [URL]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            if let fp = vaultFingerprint {
                let targetName = "vault_index_\(fp).bin"
                indexFiles = files.filter { $0.lastPathComponent == targetName }
            } else {
                indexFiles = files.filter { $0.lastPathComponent.hasPrefix("vault_index_") && $0.pathExtension == "bin" }
            }
        } else {
            indexFiles = []
        }

        var indexCount = UInt16(indexFiles.count)
        payload.append(Data(bytes: &indexCount, count: 2))

        for blob in blobs {
            let blobIdData = Data(blob.blobId.utf8)
            var idLen = UInt16(blobIdData.count)
            payload.append(Data(bytes: &idLen, count: 2))
            payload.append(blobIdData)

            let blobURL: URL
            if blob.blobId == "primary" {
                blobURL = documents.appendingPathComponent("vault_data.bin")
            } else {
                blobURL = documents.appendingPathComponent(blob.fileName)
            }

            let usedSize = blob.cursor
            if usedSize > 0, let handle = try? FileHandle(forReadingFrom: blobURL) {
                let blobData = try handle.read(upToCount: usedSize) ?? Data()
                try? handle.close()
                var dataLen = UInt64(blobData.count)
                payload.append(Data(bytes: &dataLen, count: 8))
                payload.append(blobData)
            } else {
                var dataLen: UInt64 = 0
                payload.append(Data(bytes: &dataLen, count: 8))
            }
        }

        for indexURL in indexFiles {
            let fileName = indexURL.lastPathComponent
            let nameData = Data(fileName.utf8)
            var nameLen = UInt16(nameData.count)
            payload.append(Data(bytes: &nameLen, count: 2))
            payload.append(nameData)

            let fileData = try Data(contentsOf: indexURL)
            var dataLen = UInt32(fileData.count)
            payload.append(Data(bytes: &dataLen, count: 4))
            payload.append(fileData)
        }

        return payload
    }

    private func packBackupPayloadOffMain(index: VaultStorage.VaultIndex, vaultFingerprint: String?) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let payload = try self.packBackupPayload(index: index, vaultFingerprint: vaultFingerprint)
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Unpacks a VBK2 backup payload into blob data + index files.
    private func unpackBackupPayload(_ payload: Data) throws -> (blobs: [(blobId: String, data: Data)], indexes: [(fileName: String, data: Data)]) {
        var offset = 0
        let payloadCount = payload.count

        func requireBytes(_ count: Int) throws {
            guard offset + count <= payloadCount else { throw iCloudError.downloadFailed }
        }

        try requireBytes(9)
        let magic = payload.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
        offset += 4
        guard magic == 0x56424B32 else { throw iCloudError.downloadFailed }

        let version = payload[offset]
        offset += 1
        guard version == 2 else { throw iCloudError.downloadFailed }

        let blobCount = payload.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
        offset += 2
        let indexCount = payload.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
        offset += 2

        var blobs: [(blobId: String, data: Data)] = []
        for _ in 0..<blobCount {
            try requireBytes(2)
            let idLen = payload.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 2
            try requireBytes(Int(idLen))
            let blobId = String(data: payload.subdata(in: offset..<offset+Int(idLen)), encoding: .utf8) ?? "primary"
            offset += Int(idLen)

            try requireBytes(8)
            let dataLen = payload.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            guard dataLen <= UInt64(payloadCount - offset) else { throw iCloudError.downloadFailed }
            let data = payload.subdata(in: offset..<offset+Int(dataLen))
            offset += Int(dataLen)

            blobs.append((blobId, data))
        }

        var indexes: [(fileName: String, data: Data)] = []
        for _ in 0..<indexCount {
            try requireBytes(2)
            let nameLen = payload.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 2
            try requireBytes(Int(nameLen))
            let fileName = String(data: payload.subdata(in: offset..<offset+Int(nameLen)), encoding: .utf8) ?? ""
            offset += Int(nameLen)

            try requireBytes(4)
            let dataLen = payload.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard dataLen <= UInt32(payloadCount - offset) else { throw iCloudError.downloadFailed }
            let data = payload.subdata(in: offset..<offset+Int(dataLen))
            offset += Int(dataLen)

            indexes.append((fileName, data))
        }

        return (blobs, indexes)
    }

    // MARK: - Background Processing Task

    func registerBackgroundProcessingTask() {
        BackgroundTaskCoordinator.register(
            identifier: Self.backgroundBackupTaskIdentifier
        ) { task in
            Self.shared.handleBackgroundProcessingTask(task)
        }
    }

    func scheduleBackgroundResumeTask(earliestIn seconds: TimeInterval = 15) {
        BackgroundTaskCoordinator.schedule(
            identifier: Self.backgroundBackupTaskIdentifier,
            earliestIn: seconds
        )
    }

    @MainActor
    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        Self.logger.info("[bg-task] Backup processing task started")
        currentBGProcessingTask = task
        scheduleBackgroundResumeTask(earliestIn: 60)

        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                if var state = self?.loadPendingBackupState() {
                    state.wasTerminated = true
                    self?.savePendingBackupState(state)
                }
                self?.autoBackupTask?.cancel()
                self?.completeBackgroundProcessingTask(success: false)
            }
        }

        guard UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") else {
            completeBackgroundProcessingTask(success: true)
            return
        }
        guard CloudKitSharingManager.canProceedWithNetwork() else {
            completeBackgroundProcessingTask(success: true)
            return
        }

        // Case 1: Staged backup → upload
        if loadPendingBackupState() != nil {
            guard autoBackupTask == nil else {
                completeBackgroundProcessingTask(success: true)
                return
            }

            let bgTask = Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                var succeeded = false
                defer {
                    let taskSucceeded = succeeded
                    Task { @MainActor [weak self] in
                        self?.autoBackupTask = nil
                        self?.completeBackgroundProcessingTask(success: taskSucceeded)
                    }
                }
                do {
                    if var state = self.loadPendingBackupState(), state.wasTerminated {
                        state.wasTerminated = false
                        self.savePendingBackupState(state)
                    }
                    try await self.uploadStagedBackup()
                    succeeded = true
                    self.sendBackupCompleteNotification(success: true)
                } catch {
                    Self.logger.error("[bg-task] Upload failed: \(error)")
                    self.handleUploadFailure(error)
                }
            }
            autoBackupTask = bgTask
            return
        }

        // Case 2: No staged backup — check if overdue + key available
        let lastTimestamp = UserDefaults.standard.double(forKey: "lastBackupTimestamp")
        let isOverdue = lastTimestamp == 0 || Date().timeIntervalSince1970 - lastTimestamp >= Self.autoBackupInterval

        guard isOverdue else {
            completeBackgroundProcessingTask(success: true)
            return
        }

        if let key = vaultKeyProvider?() {
            guard autoBackupTask == nil else {
                completeBackgroundProcessingTask(success: true)
                return
            }

            let capturedKey = key
            let bgTask = Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                var succeeded = false
                defer {
                    let taskSucceeded = succeeded
                    Task { @MainActor [weak self] in
                        self?.autoBackupTask = nil
                        self?.completeBackgroundProcessingTask(success: taskSucceeded)
                    }
                }
                // Background task needs pattern — not available without vault unlock
                // Only upload staged backups in background; full backup requires foreground
                Self.logger.info("[bg-task] Vault key available but no pattern for staging")
                succeeded = true
                _ = capturedKey // suppress unused warning
            }
            autoBackupTask = bgTask
        } else {
            // Case 3: Overdue but no key — cascading retries
            let lastAttempt = UserDefaults.standard.double(forKey: "lastLockedBackupAttempt")
            let timeSinceLastAttempt = Date().timeIntervalSince1970 - lastAttempt
            let cascadeDelays: [TimeInterval] = [15 * 60, 60 * 60, 4 * 60 * 60, 12 * 60 * 60, 24 * 60 * 60]
            var nextDelay = cascadeDelays[0]
            for delay in cascadeDelays {
                if timeSinceLastAttempt < delay {
                    nextDelay = delay
                    break
                }
                nextDelay = delay
            }
            scheduleBackgroundResumeTask(earliestIn: nextDelay)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastLockedBackupAttempt")
            completeBackgroundProcessingTask(success: false)
        }
    }

    @MainActor
    private func completeBackgroundProcessingTask(success: Bool) {
        currentBGProcessingTask?.setTaskCompleted(success: success)
        currentBGProcessingTask = nil
    }

    // MARK: - Notifications

    func sendBackupCompleteNotification(success: Bool, errorMessage: String? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            if success {
                content.title = "iCloud Backup Complete"
                content.body = "Your vault has been backed up to iCloud."
            } else {
                content.title = "iCloud Backup Interrupted"
                content.body = errorMessage ?? "The backup was interrupted. Open Vaultaire to resume."
            }
            content.sound = .default
            content.categoryIdentifier = "backup_complete"

            let request = UNNotificationRequest(
                identifier: "icloud-backup-complete-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Self.logger.error("[notification] Failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
