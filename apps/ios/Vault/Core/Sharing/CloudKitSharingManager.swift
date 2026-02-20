import Foundation
import CloudKit
import CryptoKit
import os.log
import Network

private let networkMonitor = NWPathMonitor()
private var currentNetworkType: String = "unknown"

enum CloudKitSharingError: Error, LocalizedError {
    case notAvailable
    case uploadFailed(Error)
    case downloadFailed(Error)
    case vaultNotFound
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case alreadyClaimed
    case revoked
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "CloudKit is not available"
        case .uploadFailed(let e): return "Upload failed: \(e.localizedDescription)"
        case .downloadFailed(let e): return "Download failed: \(e.localizedDescription)"
        case .vaultNotFound: return "No vault found with this phrase"
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Could not decrypt the vault. The phrase may be incorrect."
        case .invalidData: return "Invalid vault data"
        case .alreadyClaimed: return "This share phrase has already been used"
        case .revoked: return "Access to this vault has been revoked"
        case .networkError: return "Can't verify phrase — check your connection and try again"
        }
    }
}

/// Manages shared vault storage in CloudKit's public database.
/// Supports chunked uploads, one-time claim phrases, and multi-recipient sync.
final class CloudKitSharingManager {
    static let shared = CloudKitSharingManager()

    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let manifestRecordType = "SharedVault"
    private let chunkRecordType = "SharedVaultChunk"

    /// Target chunk size for uploads (~2 MB for granular progress feedback).
    /// CloudKit supports up to 50 MB per asset, but smaller chunks give smoother
    /// progress updates since CKDatabase.save() has no byte-level callback.
    private let chunkSize = 2 * 1024 * 1024

    /// Maximum concurrent CloudKit chunk uploads/saves/downloads.
    private static let maxConcurrentChunkOps = 4

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "CloudKitSharing")

    private init() {
        container = CKContainer(identifier: "iCloud.app.vaultaire.shared")
        publicDatabase = container.publicCloudDatabase

        // Start network monitoring
        networkMonitor.pathUpdateHandler = { path in
            if path.usesInterfaceType(.wifi) {
                currentNetworkType = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                currentNetworkType = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                currentNetworkType = "ethernet"
            } else {
                currentNetworkType = path.status == .satisfied ? "other" : "offline"
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .background))
    }

    /// Returns current network type for telemetry.
    private func getNetworkType() -> String {
        currentNetworkType
    }

    // MARK: - Key & ID Derivation

    /// Generates a unique share vault ID (UUID-based, not phrase-derived).
    static func generateShareVaultId() -> String {
        UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Derives a vault ID from a share phrase (for lookup by recipient).
    static func vaultId(from phrase: String) -> String {
        let normalized = normalizePhrase(phrase)
        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizePhrase(_ phrase: String) -> String {
        phrase.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Lightweight check: is this share phrase still available (not claimed, revoked, or missing)?
    func checkPhraseAvailability(phrase: String) async -> Result<Void, CloudKitSharingError> {
        let phraseVaultId = Self.vaultId(from: phrase)
        let recordId = CKRecord.ID(recordName: phraseVaultId)
        do {
            let manifest = try await publicDatabase.record(for: recordId)
            if let claimed = manifest["claimed"] as? Bool, claimed {
                return .failure(.alreadyClaimed)
            }
            if let revoked = manifest["revoked"] as? Bool, revoked {
                return .failure(.revoked)
            }
            return .success(())
        } catch let error as CKError where error.code == .unknownItem {
            return .failure(.vaultNotFound)
        } catch {
            // Network error — surface it so user knows verification failed
            return .failure(.networkError)
        }
    }

    // MARK: - Manifest Update Helper

    /// Queries the manifest record for a shareVaultId, increments version, and saves.
    private func updateManifestRecord(shareVaultId: String, chunkCount: Int, currentVersion: Int? = nil) async throws {
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let version = currentVersion ?? (record["version"] as? Int) ?? 3
                record["version"] = version + 1
                record["updatedAt"] = Date()
                record["chunkCount"] = chunkCount
                try await saveWithRetry(record)
            }
        }
    }

    // MARK: - Upload (Chunked)

    /// Uploads vault data to CloudKit in chunks for a specific share vault ID.
    /// - Parameters:
    ///   - shareVaultId: The unique ID for this share recipient
    ///   - phrase: The one-time share phrase (used for lookup by recipient)
    ///   - vaultData: Serialized vault data to upload
    ///   - shareKey: Encryption key derived from phrase
    ///   - policy: Share policy (expiration, view limits, etc.)
    ///   - ownerFingerprint: Key fingerprint of the vault owner
    ///   - onProgress: Progress callback (current chunk, total chunks)
    func uploadSharedVault(
        shareVaultId: String,
        phrase: String,
        vaultData: Data,
        shareKey: ShareKey,
        policy: VaultStorage.SharePolicy,
        ownerFingerprint: String,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let transaction = EmbraceManager.shared.startTransaction(name: "share.upload", operation: "share.upload")
        transaction.setTag(value: getNetworkType(), key: "network_type")
        let ckStart = CFAbsoluteTimeGetCurrent()
        let startMemoryState = EmbraceManager.shared.getDeviceState()
        transaction.setTag(value: startMemoryState.thermalState, key: "thermal_state_start")

        // Pre-flight: verify iCloud account is available or temporarily unavailable (signed in, syncing)
        let accountStatus = await checkiCloudStatus()
        Self.logger.info("[upload-telemetry] iCloud account status: \(accountStatus.rawValue)")
        guard accountStatus == .available || accountStatus == .temporarilyUnavailable else {
            transaction.finish(status: .internalError)
            throw CloudKitSharingError.notAvailable
        }

        let phraseVaultId = Self.vaultId(from: phrase)
        // Use ERROR level for critical debugging info
        Self.logger.error("🔴 UPLOAD DEBUG phraseVaultId: \(phraseVaultId, privacy: .public)")
        Self.logger.error("🔴 UPLOAD DEBUG shareVaultId: \(shareVaultId, privacy: .public)")
        #if DEBUG
        print("🔴 UPLOAD DEBUG phraseVaultId: \(phraseVaultId)")
        print("🔴 UPLOAD DEBUG shareVaultId: \(shareVaultId)")
        #endif

        // v2: skip outer encryption — individual files are already encrypted with shareKey
        let uploadData = vaultData

        // Split into chunks
        let chunks = stride(from: 0, to: uploadData.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, uploadData.count)
            return uploadData[start..<end]
        }

        let totalChunks = chunks.count
        Self.logger.info("[upload-telemetry] \(totalChunks) chunks (\(uploadData.count / 1024)KB total)")

        // Upload chunks in parallel
        try await uploadChunksParallel(
            shareVaultId: shareVaultId,
            chunks: chunks.enumerated().map { ($0, Data($1)) },
            onProgress: onProgress
        )

        Self.logger.info("[upload-telemetry] all chunks uploaded: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - ckStart))s")
        let manifestStart = CFAbsoluteTimeGetCurrent()

        do {
            Self.logger.error("🔴 UPLOAD DEBUG Saving manifest with phraseVaultId: \(phraseVaultId, privacy: .public)")
            #if DEBUG
            print("🔴 UPLOAD DEBUG Saving manifest with phraseVaultId: \(phraseVaultId)")
            #endif
            try await saveManifest(
                shareVaultId: shareVaultId,
                phraseVaultId: phraseVaultId,
                shareKey: shareKey,
                policy: policy,
                ownerFingerprint: ownerFingerprint,
                totalChunks: totalChunks
            )
            Self.logger.error("🔴 UPLOAD DEBUG Manifest saved successfully")
            #if DEBUG
            print("🔴 UPLOAD DEBUG Manifest saved successfully")
            #endif
        } catch {
            Self.logger.error("🔴 UPLOAD DEBUG Manifest save FAILED: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("🔴 UPLOAD DEBUG Manifest save FAILED: \(error)")
            #endif
            EmbraceManager.shared.captureError(error)
            transaction.finish(status: .internalError)
            throw error
        }

        Self.logger.info("[upload-telemetry] manifest saved: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - manifestStart))s")
        Self.logger.info("[upload-telemetry] total CloudKit time: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - ckStart))s")

        transaction.setTag(value: "\(totalChunks)", key: "chunkCount")
        transaction.setTag(value: "\(vaultData.count / 1024)", key: "totalSizeKB")
        transaction.finish(status: .ok)
    }

    /// Re-uploads vault data to an existing share vault ID (for sync updates).
    /// Deletes old chunks and uploads new ones, then updates the manifest.
    func syncSharedVault(
        shareVaultId: String,
        vaultData: Data,
        shareKey _: ShareKey,
        currentVersion: Int,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        // Delete old chunks
        try await deleteChunks(for: shareVaultId)

        // v2: skip outer encryption — individual files already encrypted with shareKey
        let chunks = stride(from: 0, to: vaultData.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, vaultData.count)
            return vaultData[start..<end]
        }

        let totalChunks = chunks.count

        try await uploadChunksParallel(
            shareVaultId: shareVaultId,
            chunks: chunks.enumerated().map { ($0, Data($1)) },
            onProgress: onProgress
        )

        try await updateManifestRecord(shareVaultId: shareVaultId, chunkCount: totalChunks, currentVersion: currentVersion)
    }

    /// Incrementally syncs SVDF data by only uploading chunks whose content changed.
    /// Uses deterministic CKRecord IDs (`{shareVaultId}_chunk_{index}`) so saving to
    /// an existing ID updates in place without a separate delete.
    func syncSharedVaultIncremental(
        shareVaultId: String,
        svdfData: Data,
        newChunkHashes: [String],
        previousChunkHashes: [String],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let chunks = stride(from: 0, to: svdfData.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, svdfData.count)
            return svdfData[start..<end]
        }
        let totalChunks = chunks.count

        // Filter to only changed or new chunks, then upload in parallel
        let changedChunks = chunks.enumerated().compactMap { (index, chunkData) -> (Int, Data)? in
            let hashChanged = index >= previousChunkHashes.count
                || previousChunkHashes[index] != newChunkHashes[index]
            return hashChanged ? (index, Data(chunkData)) : nil
        }
        let uploadedCount = changedChunks.count

        try await uploadChunksParallel(
            shareVaultId: shareVaultId,
            chunks: changedChunks,
            onProgress: onProgress
        )

        // Delete orphaned chunks if the blob shrank
        if totalChunks < previousChunkHashes.count {
            for orphanIndex in totalChunks..<previousChunkHashes.count {
                let orphanId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(orphanIndex)")
                _ = try? await publicDatabase.deleteRecord(withID: orphanId)
            }
        }

        Self.logger.info("[sync-incremental] \(uploadedCount)/\(totalChunks) chunks uploaded for \(shareVaultId, privacy: .public)")

        try await updateManifestRecord(shareVaultId: shareVaultId, chunkCount: totalChunks)
    }

    /// Incrementally syncs SVDF data from a file on disk.
    /// Computes chunk hashes by streaming, uploads only changed chunks from file,
    /// and cleans up orphaned chunks. Peak memory is O(chunk_size) ≈ 2MB.
    func syncSharedVaultIncrementalFromFile(
        shareVaultId: String,
        svdfFileURL: URL,
        newChunkHashes: [String],
        previousChunkHashes: [String],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let totalChunks = newChunkHashes.count

        // Find changed or new chunk indices
        let changedIndices = (0..<totalChunks).filter { index in
            index >= previousChunkHashes.count
                || previousChunkHashes[index] != newChunkHashes[index]
        }

        // Upload changed chunks by reading from file
        try await uploadChunksFromFile(
            shareVaultId: shareVaultId,
            fileURL: svdfFileURL,
            chunkIndices: changedIndices,
            onProgress: onProgress
        )

        // Delete orphaned chunks if the blob shrank
        if totalChunks < previousChunkHashes.count {
            for orphanIndex in totalChunks..<previousChunkHashes.count {
                let orphanId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(orphanIndex)")
                _ = try? await publicDatabase.deleteRecord(withID: orphanId)
            }
        }

        Self.logger.info("[sync-incremental] \(changedIndices.count)/\(totalChunks) chunks uploaded for \(shareVaultId, privacy: .public)")

        try await updateManifestRecord(shareVaultId: shareVaultId, chunkCount: totalChunks)
    }

    // MARK: - Download (Chunked)

    /// Downloads and decrypts a shared vault using a share phrase.
    /// Checks claimed status and optionally marks as claimed after download.
    func downloadSharedVault(
        phrase: String,
        markClaimedOnDownload: Bool = true,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        let transaction = EmbraceManager.shared.startTransaction(name: "share.download", operation: "share.download")
        let phraseVaultId = Self.vaultId(from: phrase)
        // Use ERROR level for critical debugging info
        Self.logger.error("🔴 DOWNLOAD DEBUG Looking for manifest with phraseVaultId: \(phraseVaultId, privacy: .public)")
        Self.logger.error("🔴 DOWNLOAD DEBUG Phrase: \(phrase, privacy: .public)")
        #if DEBUG
        print("🔴 DOWNLOAD DEBUG Looking for manifest with phraseVaultId: \(phraseVaultId)")
        print("🔴 DOWNLOAD DEBUG Phrase: \(phrase)")
        #endif
        
        // Try v2 (per-phrase salt) key first, fall back to v1 (fixed salt) for existing shares
        let shareKeyV2 = ShareKey(try KeyDerivation.deriveShareKey(from: phrase))
        var shareKey = shareKeyV2
        let shareKeyV1: ShareKey? = (try? KeyDerivation.deriveShareKeyLegacy(from: phrase)).map { ShareKey($0) }

        // Fetch manifest
        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest: CKRecord
        do {
            manifest = try await publicDatabase.record(for: manifestRecordId)
            Self.logger.error("🔴 DOWNLOAD DEBUG Manifest found successfully")
            #if DEBUG
            print("🔴 DOWNLOAD DEBUG Manifest found successfully")
            #endif
        } catch let error as CKError where error.code == .unknownItem {
            Self.logger.error("🔴 DOWNLOAD DEBUG Manifest NOT FOUND for phraseVaultId: \(phraseVaultId, privacy: .public)")
            #if DEBUG
            print("🔴 DOWNLOAD DEBUG Manifest NOT FOUND for phraseVaultId: \(phraseVaultId)")
            #endif
            transaction.finish(status: .notFound)
            throw CloudKitSharingError.vaultNotFound
        } catch {
            EmbraceManager.shared.captureError(error)
            transaction.finish(status: .internalError)
            throw CloudKitSharingError.downloadFailed(error)
        }

        // Check if already claimed
        if let claimed = manifest["claimed"] as? Bool, claimed {
            throw CloudKitSharingError.alreadyClaimed
        }

        // Check if revoked
        if let revoked = manifest["revoked"] as? Bool, revoked {
            throw CloudKitSharingError.revoked
        }

        guard let shareVaultId = manifest["shareVaultId"] as? String,
              let chunkCount = manifest["chunkCount"] as? Int else {
            throw CloudKitSharingError.invalidData
        }

        // Decrypt policy — try v2 key first, fall back to v1 for legacy shares
        var policy = VaultStorage.SharePolicy()
        if let policyAsset = manifest["policy"] as? CKAsset,
           let policyURL = policyAsset.fileURL {
            let encryptedPolicy = try Data(contentsOf: policyURL)
            if let decryptedPolicy = try? CryptoEngine.decrypt(encryptedPolicy, with: shareKeyV2.rawBytes),
               let decoded = try? JSONDecoder().decode(VaultStorage.SharePolicy.self, from: decryptedPolicy) {
                policy = decoded
            } else if let v1Key = shareKeyV1,
                      let decryptedPolicy = try? CryptoEngine.decrypt(encryptedPolicy, with: v1Key.rawBytes),
                      let decoded = try? JSONDecoder().decode(VaultStorage.SharePolicy.self, from: decryptedPolicy) {
                shareKey = v1Key // This share was encrypted with the legacy key
                policy = decoded
            } else {
                throw CloudKitSharingError.decryptionFailed
            }
        }

        // Download chunks in parallel (max 4 concurrent)
        let encryptedData = try await downloadChunksParallel(
            shareVaultId: shareVaultId,
            chunkCount: chunkCount,
            onProgress: onProgress
        )

        let remoteVersion = manifest["version"] as? Int ?? 1

        // v1: outer encryption layer present; v2+: no outer encryption
        let decryptedData: Data
        if remoteVersion < 2 {
            do {
                decryptedData = try CryptoEngine.decrypt(encryptedData, with: shareKey.rawBytes)
            } catch {
                throw CloudKitSharingError.decryptionFailed
            }
        } else {
            decryptedData = encryptedData
        }

        // For compatibility, some callers still claim at download-time.
        if markClaimedOnDownload {
            manifest["claimed"] = true
            try await publicDatabase.save(manifest)
        }

        transaction.finish(status: .ok)
        return (decryptedData, shareVaultId, policy, remoteVersion)
    }

    /// Marks a share as claimed by its recipient after setup/import succeeds.
    /// Uses shareVaultId to locate and update the manifest record.
    func markShareClaimed(shareVaultId: String) async throws {
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                record["claimed"] = true
                try await publicDatabase.save(record)
                return
            }
        }

        throw CloudKitSharingError.vaultNotFound
    }

    // MARK: - Check for Updates (Recipient)

    /// Checks if a shared vault has been updated since last sync.
    /// Returns the new version number if updated, nil if up to date.
    func checkForUpdates(shareVaultId: String, currentVersion: Int) async throws -> Int? {
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                // Check revoked
                if let revoked = record["revoked"] as? Bool, revoked {
                    throw CloudKitSharingError.revoked
                }

                if let version = record["version"] as? Int, version > currentVersion {
                    return version
                }
            }
        }
        return nil
    }

    /// Downloads updated vault data for a recipient (no claim check needed - already claimed).
    func downloadUpdatedVault(
        shareVaultId: String,
        shareKey: ShareKey,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Data {
        // Find manifest
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        var chunkCount = 0
        var remoteVersion = 1
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let revoked = record["revoked"] as? Bool, revoked {
                    throw CloudKitSharingError.revoked
                }
                chunkCount = (record["chunkCount"] as? Int) ?? 0
                remoteVersion = (record["version"] as? Int) ?? 1
            }
        }

        guard chunkCount > 0 else {
            throw CloudKitSharingError.vaultNotFound
        }

        // Download chunks in parallel (max 4 concurrent)
        let rawData = try await downloadChunksParallel(
            shareVaultId: shareVaultId,
            chunkCount: chunkCount,
            onProgress: onProgress
        )

        // v1: outer encryption layer; v2+: no outer encryption
        if remoteVersion < 2 {
            do {
                return try CryptoEngine.decrypt(rawData, with: shareKey.rawBytes)
            } catch {
                throw CloudKitSharingError.decryptionFailed
            }
        } else {
            return rawData
        }
    }

    // MARK: - Revoke

    /// Revokes a specific share by setting revoked=true on the manifest.
    func revokeShare(shareVaultId: String) async throws {
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                record["revoked"] = true
                try await publicDatabase.save(record)
            }
        }
    }

    /// Deletes all CloudKit records for a share vault ID (manifest + chunks).
    func deleteSharedVault(shareVaultId: String) async throws {
        // Delete chunks
        try await deleteChunks(for: shareVaultId)

        // Delete manifest
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (recordId, _) in results.matchResults {
            _ = try? await publicDatabase.deleteRecord(withID: recordId)
        }
    }

    /// Deletes a manifest by phrase-derived vault ID.
    func deleteSharedVault(phrase: String) async throws {
        let vaultId = Self.vaultId(from: phrase)
        let recordID = CKRecord.ID(recordName: vaultId)
        do {
            let record = try await publicDatabase.record(for: recordID)
            // Also delete associated chunks
            if let shareVaultId = record["shareVaultId"] as? String {
                try await deleteChunks(for: shareVaultId)
            }
            try await publicDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Already deleted
        } catch {
            throw CloudKitSharingError.downloadFailed(error)
        }
    }

    // MARK: - Record Helpers

    /// Fetches an existing CKRecord by ID, or creates a new one if it doesn't exist.
    /// This prevents CKError 14 ("record to insert already exists") when saving.
    private func fetchOrCreateRecord(id: CKRecord.ID) async -> CKRecord {
        do {
            return try await publicDatabase.record(for: id)
        } catch {
            return CKRecord(recordType: chunkRecordType, recordID: id)
        }
    }

    /// Saves a chunk record to CloudKit with temp file lifecycle management.
    /// Uses fetch-or-create pattern for idempotent saves.
    private func saveChunkRecord(shareVaultId: String, index: Int, data: Data) async throws {
        let chunkRecordId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(index)")
        let chunkRecord = await fetchOrCreateRecord(id: chunkRecordId)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        chunkRecord["chunkData"] = CKAsset(fileURL: tempURL)
        chunkRecord["chunkIndex"] = index
        chunkRecord["vaultId"] = shareVaultId

        do {
            try await saveWithRetry(chunkRecord)
        } catch {
            throw CloudKitSharingError.uploadFailed(error)
        }
    }

    /// Uploads chunk records in parallel with bounded concurrency.
    /// Progress reports completed count (order-independent).
    func uploadChunksParallel(
        shareVaultId: String,
        chunks: [(Int, Data)],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let totalChunks = chunks.count
        guard totalChunks > 0 else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var completed = 0
            var inFlight = 0

            for (index, data) in chunks {
                if inFlight >= Self.maxConcurrentChunkOps {
                    try await group.next()
                    completed += 1
                    inFlight -= 1
                    onProgress?(completed, totalChunks)
                }

                group.addTask {
                    try await self.saveChunkRecord(
                        shareVaultId: shareVaultId, index: index, data: data
                    )
                }
                inFlight += 1
            }

            // Drain remaining in-flight uploads
            for try await _ in group {
                completed += 1
                onProgress?(completed, totalChunks)
            }
        }
    }

    /// Uploads specific chunk indices by streaming each chunk directly from a file.
    /// This avoids constructing a full in-memory `[Data]` chunk list for resume flows.
    func uploadChunksFromFile(
        shareVaultId: String,
        fileURL: URL,
        chunkIndices: [Int],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let uniqueSortedIndices = Array(Set(chunkIndices)).sorted()
        let totalChunks = uniqueSortedIndices.count
        guard totalChunks > 0 else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var completed = 0
            var inFlight = 0

            for chunkIndex in uniqueSortedIndices {
                if inFlight >= Self.maxConcurrentChunkOps {
                    try await group.next()
                    completed += 1
                    inFlight -= 1
                    onProgress?(completed, totalChunks)
                }

                group.addTask {
                    let chunkData = try self.readChunk(
                        from: fileURL,
                        index: chunkIndex,
                        chunkSize: self.chunkSize
                    )
                    try await self.saveChunkRecord(
                        shareVaultId: shareVaultId,
                        index: chunkIndex,
                        data: chunkData
                    )
                }
                inFlight += 1
            }

            for try await _ in group {
                completed += 1
                onProgress?(completed, totalChunks)
            }
        }
    }

    private func readChunk(from fileURL: URL, index: Int, chunkSize: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let offset = UInt64(index * chunkSize)
        try handle.seek(toOffset: offset)

        guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else {
            throw CloudKitSharingError.invalidData
        }
        return data
    }

    /// Downloads chunk records in parallel with bounded concurrency.
    /// Reassembles chunks in index order after all downloads complete.
    private func downloadChunksParallel(
        shareVaultId: String,
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
                if inFlight >= Self.maxConcurrentChunkOps {
                    let (index, data) = try await group.next()!
                    chunkMap[index] = data
                    completed += 1
                    inFlight -= 1
                    onProgress?(completed, chunkCount)
                }

                group.addTask {
                    let chunkRecordId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(i)")
                    let chunkRecord: CKRecord
                    do {
                        chunkRecord = try await self.publicDatabase.record(for: chunkRecordId)
                    } catch {
                        throw CloudKitSharingError.downloadFailed(error)
                    }

                    guard let chunkAsset = chunkRecord["chunkData"] as? CKAsset,
                          let chunkURL = chunkAsset.fileURL else {
                        throw CloudKitSharingError.invalidData
                    }

                    let chunkBytes = try Data(contentsOf: chunkURL)
                    return (i, chunkBytes)
                }
                inFlight += 1
            }

            // Drain remaining in-flight downloads
            for try await (index, data) in group {
                chunkMap[index] = data
                completed += 1
                onProgress?(completed, chunkCount)
            }

            // Reassemble in order
            var result = Data()
            for i in 0..<chunkCount {
                guard let chunk = chunkMap[i] else {
                    throw CloudKitSharingError.invalidData
                }
                result.append(chunk)
            }
            return result
        }
    }

    // MARK: - Manifest

    /// Saves (or updates) the SharedVault manifest record in CloudKit.
    /// Extracted for reuse by both initial upload and resume paths.
    func saveManifest(
        shareVaultId: String,
        phraseVaultId: String,
        shareKey: ShareKey,
        policy: VaultStorage.SharePolicy,
        ownerFingerprint: String,
        totalChunks: Int
    ) async throws {
        let policyData = try JSONEncoder().encode(policy)
        let encryptedPolicy = try CryptoEngine.encrypt(policyData, with: shareKey.rawBytes)

        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest = CKRecord(recordType: manifestRecordType, recordID: manifestRecordId)

        manifest["shareVaultId"] = shareVaultId
        manifest["updatedAt"] = Date()
        manifest["version"] = 4
        manifest["ownerFingerprint"] = ownerFingerprint
        manifest["chunkCount"] = totalChunks
        manifest["claimed"] = false
        manifest["revoked"] = false

        let policyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try encryptedPolicy.write(to: policyURL)
        manifest["policy"] = CKAsset(fileURL: policyURL)

        do {
            try await saveWithRetry(manifest)
            try? FileManager.default.removeItem(at: policyURL)
        } catch {
            try? FileManager.default.removeItem(at: policyURL)
            throw CloudKitSharingError.uploadFailed(error)
        }
    }

    // MARK: - Retry Logic

    /// Saves a CKRecord with automatic retry on transient CloudKit errors.
    /// Handles serverRecordChanged (code 14) by fetching the server record and retrying.
    private func saveWithRetry(_ record: CKRecord, maxRetries: Int = 3) async throws {
        var currentRecord = record
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                try await publicDatabase.save(currentRecord)
                return
            } catch let error as CKError {
                Self.logger.error("[upload-telemetry] CKError code=\(error.code.rawValue) desc=\(error.localizedDescription, privacy: .public)")
                if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
                    Self.logger.error("[upload-telemetry] underlying: \(underlying.localizedDescription, privacy: .public)")
                }

                // Handle "record already exists" by fetching server version and updating it
                if error.code == .serverRecordChanged, attempt < maxRetries {
                    Self.logger.info("[upload-telemetry] record exists, fetching server version to update")
                    if let serverRecord = try? await publicDatabase.record(for: currentRecord.recordID) {
                        // Copy all fields from our record to the server record
                        for key in currentRecord.allKeys() {
                            serverRecord[key] = currentRecord[key]
                        }
                        currentRecord = serverRecord
                        continue
                    }
                    // Fetch failed (transient network error) — retry with delay
                    // so we get another chance to fetch the server record
                    lastError = error
                    let delay = Self.retryDelay(for: error, attempt: attempt)
                    Self.logger.info("[upload-telemetry] server record fetch failed, retrying \(attempt + 1)/\(maxRetries) after \(String(format: "%.1f", delay))s")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                if Self.isRetryable(error) && attempt < maxRetries {
                    lastError = error
                    let delay = Self.retryDelay(for: error, attempt: attempt)
                    Self.logger.info("[upload-telemetry] retrying \(attempt + 1)/\(maxRetries) after \(String(format: "%.1f", delay))s")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            } catch {
                Self.logger.error("[upload-telemetry] non-CK error: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        throw lastError!
    }

    private static func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .zoneBusy, .requestRateLimited,
             .notAuthenticated, .accountTemporarilyUnavailable:
            return true
        default:
            return false
        }
    }

    private static func retryDelay(for error: CKError, attempt: Int) -> TimeInterval {
        if let retryAfter = error.retryAfterSeconds {
            return retryAfter
        }
        return pow(2.0, Double(attempt)) // 1, 2, 4 seconds
    }

    // MARK: - Consumed

    /// Batch-fetches consumed state for multiple share IDs in a single CloudKit query.
    func consumedStatusByShareVaultIds(_ shareVaultIds: [String]) async -> [String: Bool] {
        guard !shareVaultIds.isEmpty else { return [:] }
        let predicate = NSPredicate(format: "shareVaultId IN %@", shareVaultIds)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)

        do {
            let results = try await publicDatabase.records(matching: query)
            var statusById: [String: Bool] = [:]
            statusById.reserveCapacity(shareVaultIds.count)
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let shareVaultId = record["shareVaultId"] as? String {
                    statusById[shareVaultId] = (record["consumed"] as? Bool) ?? false
                }
            }
            return statusById
        } catch {
            Self.logger.warning("Failed to batch-check consumed status: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// Marks a share as consumed by the recipient (e.g. after policy-triggered self-destruct).
    /// Sets `consumed = true` on the CloudKit manifest, mirroring how `revokeShare` sets `revoked`.
    func markShareConsumed(shareVaultId: String) async throws {
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                record["consumed"] = true
                try await publicDatabase.save(record)
            }
        }
    }

    /// Checks whether a share has been consumed by its recipient.
    func isShareConsumed(shareVaultId: String) async -> Bool {
        let consumedMap = await consumedStatusByShareVaultIds([shareVaultId])
        return consumedMap[shareVaultId] ?? false
    }

    // MARK: - Helpers

    private func deleteChunks(for shareVaultId: String) async throws {
        let predicate = NSPredicate(format: "vaultId == %@", shareVaultId)
        let query = CKQuery(recordType: chunkRecordType, predicate: predicate)

        do {
            let results = try await publicDatabase.records(matching: query)
            for (recordId, _) in results.matchResults {
                _ = try? await publicDatabase.deleteRecord(withID: recordId)
            }
        } catch {
            // Non-fatal: chunks may not exist yet
            Self.logger.warning("Failed to delete chunks: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Queries CloudKit for chunk indices that already exist for a given share vault ID.
    /// Uses cursor pagination to handle vaults with >100 chunks.
    func existingChunkIndices(for shareVaultId: String) async throws -> Set<Int> {
        let predicate = NSPredicate(format: "vaultId == %@", shareVaultId)
        let query = CKQuery(recordType: chunkRecordType, predicate: predicate)

        var indices = Set<Int>()
        var cursor: CKQueryOperation.Cursor?

        // First page
        let firstResult = try await publicDatabase.records(
            matching: query,
            desiredKeys: ["chunkIndex"]
        )
        for (_, result) in firstResult.matchResults {
            if let record = try? result.get(),
               let index = record["chunkIndex"] as? Int {
                indices.insert(index)
            }
        }
        cursor = firstResult.queryCursor

        // Paginate through remaining results
        while let activeCursor = cursor {
            let page = try await publicDatabase.records(
                continuingMatchFrom: activeCursor,
                desiredKeys: ["chunkIndex"]
            )
            for (_, result) in page.matchResults {
                if let record = try? result.get(),
                   let index = record["chunkIndex"] as? Int {
                    indices.insert(index)
                }
            }
            cursor = page.queryCursor
        }

        return indices
    }

    // MARK: - iCloud Status

    func checkiCloudStatus() async -> CKAccountStatus {
        do {
            let status = try await container.accountStatus()
            Self.logger.info("[icloud-check] CKAccountStatus = \(status.rawValue) (\(Self.statusName(status), privacy: .public))")
            return status
        } catch {
            Self.logger.error("[icloud-check] accountStatus() threw: \(error.localizedDescription, privacy: .public)")
            return .couldNotDetermine
        }
    }

    private static func statusName(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
}

// MARK: - Shared Vault Data Structure (for serialization)

/// The data structure serialized and stored encrypted in CloudKit chunks.
struct SharedVaultData: Codable, Sendable {
    let files: [SharedFile]
    let metadata: SharedVaultMetadata
    let createdAt: Date
    let updatedAt: Date

    /// Decodes from either binary plist or JSON, auto-detecting the format.
    static func decode(from data: Data) throws -> SharedVaultData {
        if data.prefix(6) == Data("bplist".utf8) {
            return try PropertyListDecoder().decode(SharedVaultData.self, from: data)
        } else {
            return try JSONDecoder().decode(SharedVaultData.self, from: data)
        }
    }

    struct SharedFile: Codable, Identifiable, Sendable {
        let id: UUID
        let filename: String
        let mimeType: String
        let size: Int
        let encryptedContent: Data
        let createdAt: Date
        let encryptedThumbnail: Data?

        init(id: UUID, filename: String, mimeType: String, size: Int, encryptedContent: Data, createdAt: Date, encryptedThumbnail: Data? = nil) {
            self.id = id
            self.filename = filename
            self.mimeType = mimeType
            self.size = size
            self.encryptedContent = encryptedContent
            self.createdAt = createdAt
            self.encryptedThumbnail = encryptedThumbnail
        }
    }

    struct SharedVaultMetadata: Codable, Sendable {
        let ownerFingerprint: String
        let sharedAt: Date
    }
}
