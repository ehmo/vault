import Foundation
import UIKit
import CloudKit
import os.log

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
final class iCloudBackupManager {
    static let shared = iCloudBackupManager()

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

    func performBackup(with key: Data, onProgress: @escaping (BackupStage) -> Void, onUploadProgress: @escaping (Double) -> Void = { _ in
        // No-op: default ignores progress
    }) async throws {
        Self.logger.info("[backup] Starting v2 multi-blob backup...")

        // Wait for iCloud
        onProgress(.waitingForICloud)
        try Task.checkCancellation()
        try await waitForAvailableAccount()

        // Read vault index to get blob descriptors
        onProgress(.readingVault)
        try Task.checkCancellation()
        let index = try VaultStorage.shared.loadIndex(with: key)

        // Pack all blobs (used portions only) + all index files
        let payload = try packBackupPayload(index: index, key: key)
        Self.logger.info("[backup] Payload packed: \(payload.count) bytes")

        // Encrypt the payload
        onProgress(.encrypting)
        try Task.checkCancellation()
        let encryptedPayload = try CryptoEngine.encrypt(payload, with: key)

        // Compute checksum
        let checksum = CryptoEngine.computeHMAC(for: encryptedPayload, with: key)

        // Chunk into 2MB pieces
        let chunks = chunkData(encryptedPayload)
        let backupId = UUID().uuidString

        let metadata = BackupMetadata(
            timestamp: Date(),
            size: encryptedPayload.count,
            checksum: checksum,
            formatVersion: 2,
            chunkCount: chunks.count,
            backupId: backupId
        )
        let metadataJson = try JSONEncoder().encode(metadata)

        // Upload chunks
        onProgress(.uploading)
        try Task.checkCancellation()
        try await uploadBackupChunksParallel(backupId: backupId, chunks: chunks) { completed, total in
            onUploadProgress(Double(completed) / Double(total))
        }

        // Save manifest record (clear old backupData asset for v2)
        let recordID = CKRecord.ID(recordName: backupRecordName)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record["metadata"] = metadataJson as CKRecordValue
        record["backupData"] = nil // v2 uses chunks, not single asset
        record["timestamp"] = metadata.timestamp as CKRecordValue
        record["formatVersion"] = 2 as CKRecordValue
        record["chunkCount"] = chunks.count as CKRecordValue
        record["backupId"] = backupId as CKRecordValue

        try await saveWithRetry(record)

        // Delete old backup chunks (previous backupId)
        try await deleteOldBackupChunks(excludingBackupId: backupId)

        onProgress(.complete)
        Self.logger.info("[backup] v2 backup complete (\(chunks.count) chunks, \(encryptedPayload.count / 1024)KB)")
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

        // Header
        guard payload.count >= 9 else { throw iCloudError.downloadFailed }
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
            let idLen = payload.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 2
            let blobId = String(data: payload.subdata(in: offset..<offset+Int(idLen)), encoding: .utf8) ?? "primary"
            offset += Int(idLen)

            let dataLen = payload.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            let data = payload.subdata(in: offset..<offset+Int(dataLen))
            offset += Int(dataLen)

            blobs.append((blobId, data))
        }

        // Read indexes
        var indexes: [(fileName: String, data: Data)] = []
        for _ in 0..<indexCount {
            let nameLen = payload.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 2
            let fileName = String(data: payload.subdata(in: offset..<offset+Int(nameLen)), encoding: .utf8) ?? ""
            offset += Int(nameLen)

            let dataLen = payload.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
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

        // Delete in batches
        if !recordIDs.isEmpty {
            Self.logger.info("[backup] Deleting \(recordIDs.count) old backup chunks")
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        // Non-fatal — old chunks will be overwritten next time
                        Self.logger.warning("[backup] Failed to delete old chunks: \(error)")
                        continuation.resume()
                    }
                }
                self.privateDatabase.add(operation)
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

    /// Silently performs a backup if enabled and overdue (24h since last).
    /// Captures the vault key by value and wraps work in a background task
    /// so it survives the app being backgrounded. Fire-and-forget — no UI.
    @MainActor
    func performBackupIfNeeded(with key: Data) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "iCloudBackupEnabled") else { return }
        guard autoBackupTask == nil else {
            Self.logger.info("[auto-backup] Backup already running, skipping")
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

        Self.logger.info("[auto-backup] Starting background backup")

        let capturedKey = key
        var detachedTask: Task<Void, Never>?
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid

        bgTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            Self.logger.warning("[auto-backup] Background time expired")
            detachedTask?.cancel()
            MainActor.assumeIsolated {
                self?.finishAutoBackupRun(bgTaskId: bgTaskId)
            }
        }
        currentAutoBackupBgTaskId = bgTaskId

        detachedTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                Self.runMainSync {
                    self.finishAutoBackupRun(bgTaskId: bgTaskId)
                }
            }
            do {
                try await self.performBackup(
                    with: capturedKey,
                    onProgress: { _ in
                        // No-op: auto-backup ignores progress
                    },
                    onUploadProgress: { _ in
                        // No-op: auto-backup ignores upload progress
                    }
                )
                await MainActor.run {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastBackupTimestamp")
                }
                Self.logger.info("[auto-backup] Backup completed successfully")
            } catch {
                if Task.isCancelled {
                    Self.logger.warning("[auto-backup] Backup cancelled")
                    return
                }
                Self.logger.error("[auto-backup] Backup failed: \(error)")
            }
        }
        autoBackupTask = detachedTask
    }

    @MainActor
    private func finishAutoBackupRun(bgTaskId: UIBackgroundTaskIdentifier) {
        autoBackupTask = nil

        if currentAutoBackupBgTaskId == bgTaskId {
            currentAutoBackupBgTaskId = .invalid
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
            return
        }

        if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
        }
    }

    nonisolated private static func runMainSync(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    block()
                }
            }
        }
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
}
