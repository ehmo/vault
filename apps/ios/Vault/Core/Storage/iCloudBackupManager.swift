import Foundation
import UIKit
import CloudKit
import os.log
import BackgroundTasks

/// Single source of truth for opening iCloud settings.
/// Used by ShareVaultView and iCloudBackupSettingsView — keep in sync.
enum SettingsURLHelper {
    static func openICloudSettings() {
        // iOS 17+: APPLE_ACCOUNT opens the Apple ID page (which contains iCloud).
        // Fallback to app settings if the private URL scheme is rejected.
        let iCloudURL = URL(string: "App-Prefs:root=APPLE_ACCOUNT")
        let fallbackURL = URL(string: UIApplication.openSettingsURLString)

        if let url = iCloudURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = fallbackURL {
            UIApplication.shared.open(url)
        }
    }
}

enum iCloudError: Error {
    case notAvailable
    case containerNotFound
    case uploadFailed
    case downloadFailed
    case fileNotFound
    case checksumMismatch
}

/// Backs up encrypted vault data to CloudKit private database.
/// Uses the user's own iCloud storage (not the app's public DB quota).
/// Private database requires CKAccountStatus.available — when status is
/// .temporarilyUnavailable, the backup waits briefly for it to resolve.
///
/// v1: Single CKAsset with entire blob — fails for blobs >250MB.
/// v2: Multi-blob payload packed into 2MB chunks, includes all index files.
///     Only backs up used portions of each blob (0→cursor), dramatically
///     reducing backup size. Backward-compatible restore handles both formats.
final class iCloudBackupManager: @unchecked Sendable {
    static let shared = iCloudBackupManager()
    nonisolated static let backgroundBackupTaskIdentifier = "app.vaultaire.ios.backup.resume"

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let recordType = "VaultBackup"
    private let chunkRecordType = "VaultBackupChunk"
    private let backupRecordName = "current_backup"
    private let fileManager = FileManager.default

    /// Max chunk size for CloudKit uploads (2MB)
    private static let chunkSize = 2 * 1024 * 1024
    /// Max concurrent chunk upload/download operations
    private static let maxConcurrent = 4

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "iCloudBackup")
    @MainActor private var autoBackupTask: Task<Void, Never>?
    @MainActor private var currentAutoBackupBgTaskId: UIBackgroundTaskIdentifier = .invalid
    @MainActor private var activeBgTaskIds: Set<UIBackgroundTaskIdentifier> = []

    // MARK: - Background Task State
    @MainActor private var currentBGProcessingTask: BGProcessingTask?

    // MARK: - Vault Key Provider
    private var vaultKeyProvider: (() -> Data?)?

    /// Provide a closure that returns the current vault key (if unlocked).
    /// Called from background tasks to attempt full backup when vault is unlocked.
    func setVaultKeyProvider(_ provider: @escaping () -> Data?) {
        vaultKeyProvider = provider
    }

    // MARK: - Pending Backup State (Staging)

    struct PendingBackupState: Codable {
        let backupId: String
        let totalChunks: Int
        let checksum: Data
        let encryptedSize: Int
        let createdAt: Date
        var uploadFinished: Bool
        var manifestSaved: Bool
        /// Number of upload retry attempts (for exponential backoff)
        var retryCount: Int
    }

    /// 48-hour TTL for staged backups
    private nonisolated static let pendingTTL: TimeInterval = 48 * 60 * 60

    private nonisolated static var backupStagingDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated static func chunkFileURL(index: Int) -> URL {
        backupStagingDir.appendingPathComponent("chunk_\(index).bin")
    }

    private nonisolated static var stateURL: URL {
        backupStagingDir.appendingPathComponent("state.json")
    }

    nonisolated func loadPendingBackupState() -> PendingBackupState? {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder().decode(PendingBackupState.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(state.createdAt) < Self.pendingTTL else {
            clearStagingDirectory()
            return nil
        }
        return state
    }

    private nonisolated func savePendingBackupState(_ state: PendingBackupState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: Self.stateURL, options: .atomic)
            // Set file protection so it's readable after first unlock
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: Self.stateURL.path
            )
        } catch {
            Self.logger.error("[staging] Failed to save pending state: \(error.localizedDescription)")
        }
    }

    nonisolated func clearStagingDirectory() {
        try? FileManager.default.removeItem(at: Self.backupStagingDir)
    }

    var hasPendingBackup: Bool {
        loadPendingBackupState() != nil
    }

    private init() {
        container = CKContainer(identifier: "iCloud.app.vaultaire.shared")
        privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Account Status

    /// Waits for CKAccountStatus.available, retrying for up to ~30s.
    /// On real devices, .temporarilyUnavailable resolves quickly after sign-in.
    /// Throws iCloudError.notAvailable if it doesn't resolve in time.
    private func waitForAvailableAccount() async throws {
        for attempt in 0..<6 {
            let status = try await container.accountStatus()
            Self.logger.info("[backup] CKAccountStatus = \(status.rawValue) (attempt \(attempt))")

            if status == .available {
                return
            }

            if status == .temporarilyUnavailable || status == .couldNotDetermine {
                let delays: [UInt64] = [1, 2, 3, 5, 8, 13]
                let delay = delays[min(attempt, delays.count - 1)]
                Self.logger.info("[backup] Waiting \(delay)s for iCloud to become available...")
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
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

    /// Two-phase manual backup: stage encrypted chunks to disk, then upload.
    func performBackup(with key: Data, onProgress: @escaping (BackupStage) -> Void, onUploadProgress: @escaping (Double) -> Void = { _ in
        // No-op: default ignores progress
    }) async throws {
        Self.logger.info("[backup] Starting two-phase backup...")

        // Phase 1: Stage
        onProgress(.readingVault)
        try Task.checkCancellation()
        let state = try await stageBackupToDisk(with: key, onProgress: { stage in
            onProgress(stage)
        })

        // Phase 2: Upload
        onProgress(.uploading)
        try await uploadStagedBackup(onUploadProgress: onUploadProgress)
        onProgress(.complete)
        Self.logger.info("[backup] Two-phase backup complete (\(state.totalChunks) chunks, \(state.encryptedSize / 1024)KB)")
    }

    // MARK: - Phase 1: Stage Backup to Disk

    /// Packs, encrypts, and chunks the vault into staging files on disk.
    /// Requires the vault key (foreground only). Written with `.completeUntilFirstUserAuthentication`
    /// so the staged files can be read later even if the vault is locked.
    @discardableResult
    func stageBackupToDisk(
        with key: Data,
        onProgress: ((BackupStage) -> Void)? = nil
    ) async throws -> PendingBackupState {
        onProgress?(.readingVault)
        try Task.checkCancellation()
        let index = try VaultStorage.shared.loadIndex(with: VaultKey(key))

        let payload = try await packBackupPayloadOffMain(index: index, key: key)
        Self.logger.info("[staging] Payload packed: \(payload.count) bytes")

        onProgress?(.encrypting)
        try Task.checkCancellation()
        let (checksum, encryptedSize, chunks) = try await encryptAndPrepareChunksOffMain(payload, key: key)
        let backupId = UUID().uuidString

        // Clear any stale staging data before writing new chunks
        clearStagingDirectory()

        // Ensure staging dir exists
        try FileManager.default.createDirectory(
            at: Self.backupStagingDir,
            withIntermediateDirectories: true
        )

        // Write each chunk to disk with relaxed file protection
        for (index, data) in chunks {
            let chunkURL = Self.chunkFileURL(index: index)
            try data.write(to: chunkURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: chunkURL.path
            )
        }

        let state = PendingBackupState(
            backupId: backupId,
            totalChunks: chunks.count,
            checksum: checksum,
            encryptedSize: encryptedSize,
            createdAt: Date(),
            uploadFinished: false,
            manifestSaved: false,
            retryCount: 0
        )
        savePendingBackupState(state)

        Self.logger.info("[staging] Staged \(chunks.count) chunks (\(encryptedSize / 1024)KB) to disk")
        return state
    }

    // MARK: - Phase 2: Upload Staged Backup

    /// Uploads pre-encrypted chunks from the staging directory to CloudKit.
    /// Does NOT require the vault key — chunks are already encrypted.
    func uploadStagedBackup(
        onUploadProgress: ((Double) -> Void)? = nil
    ) async throws {
        guard var state = loadPendingBackupState() else {
            Self.logger.info("[upload] No pending backup state on disk")
            return
        }

        try await waitForAvailableAccount()

        // Query CloudKit for already-uploaded chunks
        let existingIndices = try await existingBackupChunkIndices(for: state.backupId)
        let missingIndices = (0..<state.totalChunks).filter { !existingIndices.contains($0) }

        Self.logger.info("[upload] \(existingIndices.count)/\(state.totalChunks) chunks already uploaded, \(missingIndices.count) remaining")

        // Upload missing chunks from disk files
        if !missingIndices.isEmpty {
            let totalToUpload = missingIndices.count
            try await withThrowingTaskGroup(of: Void.self) { group in
                var completed = 0
                var inFlight = 0

                for chunkIndex in missingIndices {
                    if inFlight >= Self.maxConcurrent {
                        try await group.next()
                        completed += 1
                        inFlight -= 1
                        let progress = Double(existingIndices.count + completed) / Double(state.totalChunks)
                        onUploadProgress?(progress)
                    }

                    group.addTask {
                        let chunkURL = Self.chunkFileURL(index: chunkIndex)
                        let chunkData = try Data(contentsOf: chunkURL)

                        let recordName = "\(state.backupId)_bchunk_\(chunkIndex)"
                        let recordID = CKRecord.ID(recordName: recordName)
                        let record = CKRecord(recordType: self.chunkRecordType, recordID: recordID)

                        // Write to temp file with relaxed protection for CKAsset
                        let tempURL = self.fileManager.temporaryDirectory
                            .appendingPathComponent("\(recordName).bin")
                        try chunkData.write(to: tempURL)
                        try FileManager.default.setAttributes(
                            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                            ofItemAtPath: tempURL.path
                        )
                        defer { try? self.fileManager.removeItem(at: tempURL) }

                        record["chunkData"] = CKAsset(fileURL: tempURL)
                        record["chunkIndex"] = chunkIndex as CKRecordValue
                        record["backupId"] = state.backupId as CKRecordValue

                        try await self.saveWithRetry(record)
                    }
                    inFlight += 1
                }

                for try await _ in group {
                    completed += 1
                    let progress = Double(existingIndices.count + completed) / Double(state.totalChunks)
                    onUploadProgress?(progress)
                }
            }
        }

        state.uploadFinished = true
        savePendingBackupState(state)

        // Save manifest record
        let metadata = BackupMetadata(
            timestamp: Date(),
            size: state.encryptedSize,
            checksum: state.checksum,
            formatVersion: 2,
            chunkCount: state.totalChunks,
            backupId: state.backupId
        )
        let metadataJson = try JSONEncoder().encode(metadata)

        let recordID = CKRecord.ID(recordName: backupRecordName)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record["metadata"] = metadataJson as CKRecordValue
        record["backupData"] = nil
        record["timestamp"] = metadata.timestamp as CKRecordValue
        record["formatVersion"] = 2 as CKRecordValue
        record["chunkCount"] = state.totalChunks as CKRecordValue
        record["backupId"] = state.backupId as CKRecordValue

        try await saveWithRetry(record)

        state.manifestSaved = true
        savePendingBackupState(state)

        // Delete old backup chunks
        try await deleteOldBackupChunks(excludingBackupId: state.backupId)

        // Update last backup timestamp
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastBackupTimestamp")
        
        // Reset retry count and locked attempt tracking on success
        UserDefaults.standard.removeObject(forKey: "lastLockedBackupAttempt")

        // Clear staging directory
        clearStagingDirectory()

        Self.logger.info("[upload] Backup upload complete")
    }

    /// Queries CloudKit for already-uploaded backup chunk indices.
    private func existingBackupChunkIndices(for backupId: String) async throws -> Set<Int> {
        let predicate = NSPredicate(format: "backupId == %@", backupId)
        let query = CKQuery(recordType: chunkRecordType, predicate: predicate)

        var indices = Set<Int>()
        var cursor: CKQueryOperation.Cursor?

        let (results, nextCursor) = try await privateDatabase.records(
            matching: query,
            desiredKeys: ["chunkIndex"],
            resultsLimit: 200
        )
        for (_, result) in results {
            if let record = try? result.get(),
               let chunkIndex = record["chunkIndex"] as? Int {
                indices.insert(chunkIndex)
            }
        }
        cursor = nextCursor

        while let currentCursor = cursor {
            let (moreResults, nextCursor) = try await privateDatabase.records(
                continuingMatchFrom: currentCursor,
                resultsLimit: 200
            )
            for (_, result) in moreResults {
                if let record = try? result.get(),
                   let chunkIndex = record["chunkIndex"] as? Int {
                    indices.insert(chunkIndex)
                }
            }
            cursor = nextCursor
        }

        return indices
    }

    // MARK: - Resume Support

    /// Checks for staged backup on disk and starts upload if found.
    /// Can be called from multiple resume triggers (app launch, scene active, etc).
    @MainActor
    func resumeBackupUploadIfNeeded(trigger: String) {
        guard UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") else { return }
        guard loadPendingBackupState() != nil else { return }
        guard autoBackupTask == nil else {
            Self.logger.info("[resume] Backup already running, skipping (trigger=\(trigger, privacy: .public))")
            return
        }

        Self.logger.info("[resume] Found staged backup, starting upload (trigger=\(trigger, privacy: .public))")

        var detachedTask: Task<Void, Never>?
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid

        bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            Self.logger.warning("[resume] Background time expired")
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
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeBgTaskIds.remove(bgTaskId)
                    self.finishAutoBackupRun(bgTaskId: bgTaskId)
                }
            }
            do {
                try await self.uploadStagedBackup()
                Self.logger.info("[resume] Staged backup upload completed successfully")
                await self.sendBackupCompleteNotification(success: true)
            } catch {
                if Task.isCancelled {
                    Self.logger.warning("[resume] Staged backup upload cancelled")
                    await self.scheduleBackgroundResumeTask(earliestIn: 60)
                    return
                }
                
                // Check retry count to prevent infinite loops
                if var state = self.loadPendingBackupState() {
                    state.retryCount += 1
                    self.savePendingBackupState(state)
                    
                    if state.retryCount >= Self.maxRetryCount {
                        Self.logger.error("[resume] Max retry count (\(Self.maxRetryCount)) reached. Scheduling next attempt in 24 hours.")
                        await self.sendBackupCompleteNotification(success: false, errorMessage: "Backup failed after multiple attempts. Will retry in 24 hours.")
                        // Don't clear staging - keep it for the next periodic retry
                        // Schedule a retry in 24 hours to try again
                        await self.scheduleBackgroundResumeTask(earliestIn: 24 * 60 * 60)
                        return
                    }
                    
                    // Exponential backoff
                    let delay = min(Self.retryBaseDelay * pow(2.0, Double(state.retryCount - 1)), 3600)
                    Self.logger.info("[resume] Scheduling retry \(state.retryCount)/\(Self.maxRetryCount) in \(Int(delay))s")
                    await self.scheduleBackgroundResumeTask(earliestIn: delay)
                } else {
                    await self.scheduleBackgroundResumeTask(earliestIn: 300)
                }
            }
        }
        autoBackupTask = detachedTask
    }

    private func packBackupPayloadOffMain(index: VaultStorage.VaultIndex, key: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let payload = try self.packBackupPayload(index: index, key: key)
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func encryptAndPrepareChunksOffMain(
        _ payload: Data,
        key: Data
    ) async throws -> (checksum: Data, encryptedSize: Int, chunks: [(Int, Data)]) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let encryptedPayload = try CryptoEngine.encrypt(payload, with: key)
                    let checksum = CryptoEngine.computeHMAC(for: encryptedPayload, with: key)
                    let encryptedSize = encryptedPayload.count
                    let chunks = self.chunkData(encryptedPayload)
                    // Release encryptedPayload before returning — chunks already hold copies
                    continuation.resume(returning: (checksum, encryptedSize, chunks))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Backup Payload Packing

    /// Packs all blob data (used portions only) + all index files into a binary payload.
    /// Format:
    /// ```
    /// Header:  magic 0x56424B32 (4B) | version 2 (1B) | blobCount (2B) | indexCount (2B)
    /// Blobs:   [idLen(2B) | blobId(var) | dataLen(8B) | data(var)] × blobCount
    /// Indexes: [nameLen(2B) | fileName(var) | dataLen(4B) | data(var)] × indexCount
    /// ```
    private func packBackupPayload(index: VaultStorage.VaultIndex, key _: Data) throws -> Data {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var payload = Data()

        // Header
        var magic: UInt32 = 0x56424B32 // "VBK2"
        payload.append(Data(bytes: &magic, count: 4))
        var version: UInt8 = 2
        payload.append(Data(bytes: &version, count: 1))

        // Collect blobs
        let blobs = index.blobs ?? [VaultStorage.BlobDescriptor(
            blobId: "primary",
            fileName: "vault_data.bin",
            capacity: index.totalSize,
            cursor: index.nextOffset
        )]

        var blobCount = UInt16(blobs.count)
        payload.append(Data(bytes: &blobCount, count: 2))

        // Collect index files
        let indexFiles: [URL]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            indexFiles = files.filter { $0.lastPathComponent.hasPrefix("vault_index_") && $0.pathExtension == "bin" }
        } else {
            indexFiles = []
        }

        var indexCount = UInt16(indexFiles.count)
        payload.append(Data(bytes: &indexCount, count: 2))

        // Write blobs (used portion only: 0→cursor)
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

        // Write index files
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

    /// Unpacks a v2 backup payload into blob data + index files.
    private func unpackBackupPayload(_ payload: Data) throws -> (blobs: [(blobId: String, data: Data)], indexes: [(fileName: String, data: Data)]) {
        var offset = 0
        let payloadCount = payload.count

        func requireBytes(_ count: Int) throws {
            guard offset + count <= payloadCount else { throw iCloudError.downloadFailed }
        }

        // Header
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

        // Read blobs
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

        // Read indexes
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

    // MARK: - Chunked Upload/Download

    /// Split data into chunks of `chunkSize` bytes.
    private func chunkData(_ data: Data) -> [(Int, Data)] {
        var chunks: [(Int, Data)] = []
        var offset = 0
        var index = 0
        while offset < data.count {
            let end = min(offset + Self.chunkSize, data.count)
            chunks.append((index, data.subdata(in: offset..<end)))
            offset = end
            index += 1
        }
        return chunks
    }

    /// Upload backup chunks in parallel with bounded concurrency.
    private func uploadBackupChunksParallel(
        backupId: String,
        chunks: [(Int, Data)],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let totalChunks = chunks.count
        guard totalChunks > 0 else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var completed = 0
            var inFlight = 0

            for (index, data) in chunks {
                if inFlight >= Self.maxConcurrent {
                    try await group.next()
                    completed += 1
                    inFlight -= 1
                    onProgress?(completed, totalChunks)
                }

                group.addTask {
                    let recordName = "\(backupId)_bchunk_\(index)"
                    let recordID = CKRecord.ID(recordName: recordName)
                    let record = CKRecord(recordType: self.chunkRecordType, recordID: recordID)

                    let tempURL = self.fileManager.temporaryDirectory
                        .appendingPathComponent("\(recordName).bin")
                    try data.write(to: tempURL)
                    defer { try? self.fileManager.removeItem(at: tempURL) }

                    record["chunkData"] = CKAsset(fileURL: tempURL)
                    record["chunkIndex"] = index as CKRecordValue
                    record["backupId"] = backupId as CKRecordValue

                    try await self.saveWithRetry(record)
                }
                inFlight += 1
            }

            // Drain remaining
            for try await _ in group {
                completed += 1
                onProgress?(completed, totalChunks)
            }
        }
    }

    /// Download backup chunks in parallel, reassemble in order.
    private func downloadBackupChunksParallel(
        backupId: String,
        chunkCount: Int,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Data {
        guard chunkCount > 0 else { return Data() }

        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var completed = 0
            var inFlight = 0
            var chunkMap = [Int: Data]()
            chunkMap.reserveCapacity(chunkCount)

            for i in 0..<chunkCount {
                if inFlight >= Self.maxConcurrent {
                    let (index, data) = try await group.next()!
                    chunkMap[index] = data
                    completed += 1
                    inFlight -= 1
                    onProgress?(completed, chunkCount)
                }

                group.addTask {
                    let recordName = "\(backupId)_bchunk_\(i)"
                    let recordID = CKRecord.ID(recordName: recordName)
                    let record = try await self.privateDatabase.record(for: recordID)

                    guard let asset = record["chunkData"] as? CKAsset,
                          let assetURL = asset.fileURL else {
                        throw iCloudError.downloadFailed
                    }

                    let data = try Data(contentsOf: assetURL)
                    return (i, data)
                }
                inFlight += 1
            }

            // Drain remaining
            for try await (index, data) in group {
                chunkMap[index] = data
                completed += 1
                onProgress?(completed, chunkCount)
            }

            // Reassemble in order
            var result = Data()
            for i in 0..<chunkCount {
                guard let chunk = chunkMap[i] else {
                    throw iCloudError.downloadFailed
                }
                result.append(chunk)
            }
            return result
        }
    }

    /// Delete old backup chunks that don't belong to the current backup.
    private func deleteOldBackupChunks(excludingBackupId: String) async throws {
        let predicate = NSPredicate(format: "backupId != %@", excludingBackupId)
        let query = CKQuery(recordType: chunkRecordType, predicate: predicate)

        var recordIDs: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?

        // Fetch all old chunk record IDs
        let (results, nextCursor) = try await privateDatabase.records(matching: query, resultsLimit: 200)
        for (id, _) in results {
            recordIDs.append(id)
        }
        cursor = nextCursor

        while let currentCursor = cursor {
            let (moreResults, nextCursor) = try await privateDatabase.records(continuingMatchFrom: currentCursor, resultsLimit: 200)
            for (id, _) in moreResults {
                recordIDs.append(id)
            }
            cursor = nextCursor
        }

        // Delete in batches of 400 (CloudKit batch limit)
        if !recordIDs.isEmpty {
            Self.logger.info("[backup] Deleting \(recordIDs.count) old backup chunks")
            let batchSize = 400
            for batchStart in stride(from: 0, to: recordIDs.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, recordIDs.count)
                let batch = Array(recordIDs[batchStart..<batchEnd])
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .utility

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    operation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            continuation.resume()
                        case .failure(let error):
                            // Non-fatal — old chunks will be overwritten next time
                            Self.logger.warning("[backup] Failed to delete old chunks batch: \(error)")
                            continuation.resume()
                        }
                    }
                    self.privateDatabase.add(operation)
                }
            }
        }
    }

    /// Saves a CKRecord with retry on transient CloudKit errors.
    private func saveWithRetry(_ record: CKRecord, maxRetries: Int = 3) async throws {
        var currentRecord = record
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try await privateDatabase.save(currentRecord)
                return
            } catch let error as CKError {
                if error.code == .serverRecordChanged, attempt < maxRetries,
                   let serverRecord = try? await privateDatabase.record(for: currentRecord.recordID) {
                    for key in currentRecord.allKeys() {
                        serverRecord[key] = currentRecord[key]
                    }
                    currentRecord = serverRecord
                    continue
                }

                if Self.isRetryable(error) && attempt < maxRetries {
                    lastError = error
                    let delay = error.retryAfterSeconds ?? Double(attempt + 1) * 2
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
        throw lastError ?? iCloudError.uploadFailed
    }

    private static func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .zoneBusy, .requestRateLimited, .accountTemporarilyUnavailable:
            return true
        default:
            return false
        }
    }

    /// Saves a record using CKModifyRecordsOperation to get per-record upload progress.
    private func saveWithProgress(record: CKRecord, onUploadProgress: @escaping (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            operation.perRecordProgressBlock = { _, progress in
                onUploadProgress(progress)
            }

            var perRecordError: Error?
            operation.perRecordSaveBlock = { _, result in
                if case .failure(let error) = result {
                    Self.logger.error("[backup] Per-record save failed: \(error)")
                    perRecordError = error
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let error = perRecordError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }
    }

    // MARK: - Auto Background Backup

    /// 24-hour interval between automatic backups.
    private static let autoBackupInterval: TimeInterval = 24 * 60 * 60
    /// Maximum number of retry attempts before giving up (prevents infinite retry loops)
    private static let maxRetryCount: Int = 10
    /// Base delay for exponential backoff (in seconds)
    private static let retryBaseDelay: TimeInterval = 60

    /// Silently performs a backup if enabled and overdue (24h since last).
    /// Two-phase: stage encrypted chunks to disk, then upload independently.
    /// If a staged backup already exists on disk, skips straight to upload.
    @MainActor
    func performBackupIfNeeded(with key: Data) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "iCloudBackupEnabled") else { return }
        guard autoBackupTask == nil else {
            Self.logger.info("[auto-backup] Backup already running, skipping")
            return
        }

        // If a staged backup exists, skip to Phase 2
        if loadPendingBackupState() != nil {
            Self.logger.info("[auto-backup] Found staged backup, resuming upload")
            resumeBackupUploadIfNeeded(trigger: "auto_backup_pending")
            // Always schedule a fallback BG task in case resume doesn't start or complete
            scheduleBackgroundResumeTask(earliestIn: 300)
            return
        }

        let lastTimestamp = defaults.double(forKey: "lastBackupTimestamp")
        if lastTimestamp > 0 {
            let nextDue = Date(timeIntervalSince1970: lastTimestamp)
                .addingTimeInterval(Self.autoBackupInterval)
            guard Date() >= nextDue else {
                Self.logger.info("[auto-backup] Not due yet, skipping")
                return
            }
        }

        Self.logger.info("[auto-backup] Starting two-phase background backup")

        let capturedKey = key
        var detachedTask: Task<Void, Never>?
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid

        bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            Self.logger.warning("[auto-backup] Background time expired")
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
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeBgTaskIds.remove(bgTaskId)
                    self.finishAutoBackupRun(bgTaskId: bgTaskId)
                }
            }
            do {
                // Phase 1: Stage to disk (requires key)
                try await self.stageBackupToDisk(with: capturedKey)
                // Phase 2: Upload (no key needed)
                try await self.uploadStagedBackup()
                Self.logger.info("[auto-backup] Two-phase backup completed successfully")
                await self.sendBackupCompleteNotification(success: true)
            } catch {
                if Task.isCancelled {
                    Self.logger.warning("[auto-backup] Backup cancelled")
                    await self.scheduleBackgroundResumeTask(earliestIn: 60)
                    return
                }
                EmbraceManager.shared.captureError(
                    error,
                    context: ["feature": "icloud_auto_backup"]
                )
                Self.logger.error("[auto-backup] Backup failed: \(error)")
                
                // Check retry count to prevent infinite loops
                if var state = self.loadPendingBackupState() {
                    state.retryCount += 1
                    self.savePendingBackupState(state)
                    
                    if state.retryCount >= Self.maxRetryCount {
                        Self.logger.error("[auto-backup] Max retry count (\(Self.maxRetryCount)) reached. Will retry in 24 hours.")
                        await self.sendBackupCompleteNotification(success: false, errorMessage: "Backup failed after multiple attempts. Will retry in 24 hours.")
                        // Don't clear staging - schedule retry in 24 hours instead
                        await self.scheduleBackgroundResumeTask(earliestIn: 24 * 60 * 60)
                        return
                    }
                    
                    // Exponential backoff: 60s, 120s, 240s, 480s, etc. (max 1 hour)
                    let delay = min(Self.retryBaseDelay * pow(2.0, Double(state.retryCount - 1)), 3600)
                    Self.logger.info("[auto-backup] Scheduling retry \(state.retryCount)/\(Self.maxRetryCount) in \(Int(delay))s")
                    await self.scheduleBackgroundResumeTask(earliestIn: delay)
                } else {
                    await self.sendBackupCompleteNotification(success: false, errorMessage: error.localizedDescription)
                    await self.scheduleBackgroundResumeTask(earliestIn: 300)
                }
            }
        }
        autoBackupTask = detachedTask
    }

    @MainActor
    private func finishAutoBackupRun(bgTaskId: UIBackgroundTaskIdentifier) {
        autoBackupTask = nil

        // Remove from active set first
        activeBgTaskIds.remove(bgTaskId)
        
        // Only end the background task if it's still the current one.
        // This prevents double-end when both the expiration handler and
        // the defer block call this method for the same bgTaskId.
        guard bgTaskId != .invalid, currentAutoBackupBgTaskId == bgTaskId else { return }
        currentAutoBackupBgTaskId = .invalid
        UIApplication.shared.endBackgroundTask(bgTaskId)
    }


    // MARK: - Restore

    enum BackupCheckResult {
        case found(BackupMetadata)
        case notFound
        case error(String)
    }

    func checkForBackup() async -> BackupCheckResult {
        do {
            try await waitForAvailableAccount()
        } catch {
            Self.logger.error("[backup] iCloud not available for backup check: \(error)")
            return .error("iCloud is not available. Check that you're signed in to iCloud in Settings.")
        }

        let recordID = CKRecord.ID(recordName: backupRecordName)
        do {
            let record = try await privateDatabase.record(for: recordID)
            guard let metadataData = record["metadata"] as? Data else {
                Self.logger.error("[backup] Record found but metadata field is nil or wrong type")
                return .error("Backup record exists but metadata is missing.")
            }
            let metadata = try JSONDecoder().decode(BackupMetadata.self, from: metadataData)
            return .found(metadata)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            Self.logger.info("[backup] No backup record exists in CloudKit")
            return .notFound
        } catch {
            Self.logger.error("[backup] checkForBackup failed: \(error)")
            return .error("Failed to check iCloud: \(error.localizedDescription)")
        }
    }

    func restoreBackup(with key: Data) async throws {
        try await waitForAvailableAccount()

        let recordID = CKRecord.ID(recordName: backupRecordName)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            throw iCloudError.fileNotFound
        }

        guard let metadataData = record["metadata"] as? Data else {
            throw iCloudError.downloadFailed
        }

        let metadata = try JSONDecoder().decode(BackupMetadata.self, from: metadataData)

        // Check format version for v1 vs v2 restore path
        if let formatVersion = metadata.formatVersion, formatVersion >= 2 {
            try await restoreV2(record: record, metadata: metadata, key: key)
        } else {
            try await restoreV1(record: record, metadata: metadata, key: key)
        }
    }

    // MARK: - v1 Legacy Restore

    /// Restores a v1 backup (single CKAsset containing the entire primary blob).
    private func restoreV1(record: CKRecord, metadata: BackupMetadata, key: Data) async throws {
        guard let asset = record["backupData"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw iCloudError.downloadFailed
        }

        let encryptedBlob = try Data(contentsOf: assetURL)

        // Verify checksum
        let computedChecksum = CryptoEngine.computeHMAC(for: encryptedBlob, with: key)
        guard computedChecksum == metadata.checksum else {
            throw iCloudError.checksumMismatch
        }

        // Decrypt (handles both single-shot and streaming VCSE format)
        let decryptedBlob = try CryptoEngine.decryptStaged(encryptedBlob, with: key)

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let blobURL = documents.appendingPathComponent("vault_data.bin")
        try decryptedBlob.write(to: blobURL, options: [.atomic, .completeFileProtection])
        Self.logger.info("[backup] v1 restore complete")
    }

    // MARK: - v2 Chunked Restore

    /// Restores a v2 backup (chunked payload with all blobs + index files).
    private func restoreV2(record _: CKRecord, metadata: BackupMetadata, key: Data) async throws {
        guard let backupId = metadata.backupId,
              let chunkCount = metadata.chunkCount, chunkCount > 0 else {
            throw iCloudError.downloadFailed
        }

        Self.logger.info("[backup] Starting v2 restore: \(chunkCount) chunks")

        // Download all chunks in parallel
        let encryptedPayload = try await downloadBackupChunksParallel(
            backupId: backupId,
            chunkCount: chunkCount
        )

        // Verify checksum
        let computedChecksum = CryptoEngine.computeHMAC(for: encryptedPayload, with: key)
        guard computedChecksum == metadata.checksum else {
            throw iCloudError.checksumMismatch
        }

        // Decrypt
        let payload = try CryptoEngine.decrypt(encryptedPayload, with: key)

        // Unpack
        let (blobs, indexes) = try unpackBackupPayload(payload)

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let defaultBlobSize = 50 * 1024 * 1024 // Match VaultStorage.defaultBlobSize

        // Restore blobs
        for (blobId, usedData) in blobs {
            let blobURL: URL
            if blobId == "primary" {
                blobURL = documents.appendingPathComponent("vault_data.bin")
            } else {
                blobURL = documents.appendingPathComponent("vd_\(blobId).bin")
            }

            // Create full-size blob filled with random data
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
                // Overwrite beginning with used data
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

        Self.logger.info("[backup] v2 restore complete: \(blobs.count) blob(s), \(indexes.count) index file(s)")
    }

    // MARK: - Backup Metadata

    struct BackupMetadata: Codable {
        let timestamp: Date
        let size: Int
        let checksum: Data
        let formatVersion: Int?   // nil=v1 single asset, 2=chunked
        let chunkCount: Int?
        let backupId: String?

        init(timestamp: Date, size: Int, checksum: Data,
             formatVersion: Int? = nil, chunkCount: Int? = nil, backupId: String? = nil) {
            self.timestamp = timestamp
            self.size = size
            self.checksum = checksum
            self.formatVersion = formatVersion
            self.chunkCount = chunkCount
            self.backupId = backupId
        }

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        }

        var formattedSize: String {
            let mb = Double(size) / (1024 * 1024)
            return String(format: "%.1f MB", mb)
        }
    }
    
    // MARK: - Background Processing Task Support
    
    /// Registers the background processing task for iCloud backup resume
    func registerBackgroundProcessingTask() {
        let identifier = Self.backgroundBackupTaskIdentifier
        let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                Self.shared.handleBackgroundProcessingTask(processingTask)
            }
        }
        
        if success {
            Self.logger.info("[bg-task] Registered \(identifier, privacy: .public)")
        } else {
            Self.logger.error("[bg-task] Failed to register \(identifier, privacy: .public)")
        }
    }
    
    /// Schedules a background task to resume interrupted backup
    func scheduleBackgroundResumeTask(earliestIn seconds: TimeInterval = 15) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundBackupTaskIdentifier)
        
        let request = BGProcessingTaskRequest(identifier: Self.backgroundBackupTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.info("[bg-task] Scheduled backup resume task in ~\(Int(seconds))s")
        } catch {
            Self.logger.error("[bg-task] Failed to schedule backup resume task: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Handles the background processing task execution.
    /// If a staged backup exists → upload it (no key needed).
    /// If backup overdue + vault unlocked → full stage+upload.
    /// Otherwise → schedule retry.
    @MainActor
    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        Self.logger.info("[bg-task] Backup processing task started")
        currentBGProcessingTask = task
        // Chain-schedule next attempt
        scheduleBackgroundResumeTask(earliestIn: 60)

        task.expirationHandler = { [weak self] in
            Self.logger.warning("[bg-task] Processing task expired")
            Task { @MainActor [weak self] in
                self?.autoBackupTask?.cancel()
                self?.completeBackgroundProcessingTask(success: false)
            }
        }

        guard UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") else {
            completeBackgroundProcessingTask(success: true)
            return
        }

        // Case 1: Staged backup exists → upload (no key needed)
        if loadPendingBackupState() != nil {
            Self.logger.info("[bg-task] Found staged backup, starting upload")
            guard autoBackupTask == nil else {
                Self.logger.info("[bg-task] Upload already running")
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
                    try await self.uploadStagedBackup()
                    succeeded = true
                    Self.logger.info("[bg-task] Staged backup upload completed")
                    await self.sendBackupCompleteNotification(success: true)
                } catch {
                    Self.logger.error("[bg-task] Staged backup upload failed: \(error)")
                    
                    // Check retry count
                    if var state = self.loadPendingBackupState() {
                        state.retryCount += 1
                        self.savePendingBackupState(state)
                        
                        if state.retryCount >= Self.maxRetryCount {
                            Self.logger.error("[bg-task] Max retry count reached. Will retry in 24 hours.")
                            await self.sendBackupCompleteNotification(success: false, errorMessage: "Backup failed after multiple attempts. Will retry in 24 hours.")
                            // Don't clear staging - schedule retry in 24 hours
                            await self.scheduleBackgroundResumeTask(earliestIn: 24 * 60 * 60)
                        } else {
                            let delay = min(Self.retryBaseDelay * pow(2.0, Double(state.retryCount - 1)), 3600)
                            await self.scheduleBackgroundResumeTask(earliestIn: delay)
                        }
                    } else {
                        await self.scheduleBackgroundResumeTask(earliestIn: 300)
                    }
                }
            }
            autoBackupTask = bgTask
            return
        }

        // Case 2: No staged backup — check if overdue + key available
        let lastTimestamp = UserDefaults.standard.double(forKey: "lastBackupTimestamp")
        let isOverdue = lastTimestamp == 0 || Date().timeIntervalSince1970 - lastTimestamp >= Self.autoBackupInterval

        guard isOverdue else {
            Self.logger.info("[bg-task] Backup not overdue")
            completeBackgroundProcessingTask(success: true)
            return
        }

        if let key = vaultKeyProvider?() {
            Self.logger.info("[bg-task] Vault unlocked, running full backup")
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
                do {
                    try await self.stageBackupToDisk(with: capturedKey)
                    try await self.uploadStagedBackup()
                    succeeded = true
                    Self.logger.info("[bg-task] Full backup completed")
                    await self.sendBackupCompleteNotification(success: true)
                } catch {
                    Self.logger.error("[bg-task] Full backup failed: \(error)")
                    await self.scheduleBackgroundResumeTask(earliestIn: 300)
                }
            }
            autoBackupTask = bgTask
        } else {
            // Case 3: Overdue but no key — schedule cascading retries
            // Calculate next retry based on last locked attempt time
            let lastAttempt = UserDefaults.standard.double(forKey: "lastLockedBackupAttempt")
            let timeSinceLastAttempt = Date().timeIntervalSince1970 - lastAttempt
            
            // Cascading delays: 15min, 1hr, 4hr, 12hr, 24hr
            let cascadeDelays: [TimeInterval] = [15 * 60, 60 * 60, 4 * 60 * 60, 12 * 60 * 60, 24 * 60 * 60]
            var nextDelay = cascadeDelays[0]
            
            // Find appropriate next delay based on time since last attempt
            for delay in cascadeDelays {
                if timeSinceLastAttempt < delay {
                    nextDelay = delay
                    break
                }
                nextDelay = delay
            }
            
            Self.logger.info("[bg-task] Backup overdue but vault locked, scheduling retry in \(Int(nextDelay/60))min")
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
    
    // MARK: - Backup Notifications
    
    /// Sends a local notification when backup completes
    func sendBackupCompleteNotification(success: Bool, errorMessage: String? = nil) {
        // Check notification authorization first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                Self.logger.info("[notification] Cannot send backup notification - not authorized (status: \(settings.authorizationStatus.rawValue))")
                return
            }
            
            let content = UNMutableNotificationContent()
            
            if success {
                content.title = "iCloud Backup Complete"
                content.body = "Your vault has been backed up to iCloud."
                content.sound = .default
            } else {
                content.title = "iCloud Backup Interrupted"
                content.body = errorMessage ?? "The backup was interrupted. Open Vaultaire to resume."
                content.sound = .default
            }
            
            content.categoryIdentifier = "backup_complete"
            
            let request = UNNotificationRequest(
                identifier: "icloud-backup-complete-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Self.logger.error("[notification] Failed to schedule: \(error.localizedDescription)")
                }
            }
        }
    }
}
