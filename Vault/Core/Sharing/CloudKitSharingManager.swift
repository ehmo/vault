import Foundation
import CloudKit
import CryptoKit
import CommonCrypto
import os.log

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

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "CloudKitSharing")

    private init() {
        container = CKContainer(identifier: "iCloud.app.vaultaire.shared")
        publicDatabase = container.publicCloudDatabase
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

    /// Derives an encryption key from the share phrase.
    static func deriveShareKey(from phrase: String) throws -> Data {
        let normalized = normalizePhrase(phrase)
        let password = Data(normalized.utf8)
        let salt = "vault-share-v1-salt".data(using: .utf8)!

        var derivedKey = Data(count: 32)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            password.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        UInt32(800_000),
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw CloudKitSharingError.encryptionFailed
        }
        return derivedKey
    }

    private static func normalizePhrase(_ phrase: String) -> String {
        phrase.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        shareKey: Data,
        policy: VaultStorage.SharePolicy,
        ownerFingerprint: String,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let transaction = SentryManager.shared.startTransaction(name: "share.upload", operation: "share.upload")
        let ckStart = CFAbsoluteTimeGetCurrent()

        // Pre-flight: verify iCloud account is available
        let accountStatus = await checkiCloudStatus()
        Self.logger.info("[upload-telemetry] iCloud account status: \(accountStatus.rawValue)")
        guard accountStatus == .available else {
            let statusDesc: String
            switch accountStatus {
            case .noAccount: statusDesc = "No iCloud account. Sign in to iCloud in Settings to share vaults."
            case .restricted: statusDesc = "iCloud is restricted on this device."
            case .couldNotDetermine: statusDesc = "Could not determine iCloud status. Check your internet connection."
            case .temporarilyUnavailable: statusDesc = "iCloud is temporarily unavailable. Try again later."
            @unknown default: statusDesc = "iCloud is not available (status: \(accountStatus.rawValue))."
            }
            transaction.finish(status: .internalError)
            throw CloudKitSharingError.notAvailable
        }

        let phraseVaultId = Self.vaultId(from: phrase)

        // v2: skip outer encryption — individual files are already encrypted with shareKey
        let uploadData = vaultData

        // Split into chunks
        let chunks = stride(from: 0, to: uploadData.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, uploadData.count)
            return uploadData[start..<end]
        }

        let totalChunks = chunks.count
        Self.logger.info("[upload-telemetry] \(totalChunks) chunks (\(uploadData.count / 1024)KB total)")

        // Upload chunks
        for (index, chunkData) in chunks.enumerated() {
            let chunkStart = CFAbsoluteTimeGetCurrent()
            let chunkRecordId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(index)")
            let chunkRecord = CKRecord(recordType: chunkRecordType, recordID: chunkRecordId)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try Data(chunkData).write(to: tempURL)

            chunkRecord["chunkData"] = CKAsset(fileURL: tempURL)
            chunkRecord["chunkIndex"] = index
            chunkRecord["vaultId"] = shareVaultId

            do {
                try await saveWithRetry(chunkRecord)
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw CloudKitSharingError.uploadFailed(error)
            }

            Self.logger.info("[upload-telemetry] chunk[\(index)]/\(totalChunks) (\(chunkData.count / 1024)KB): \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - chunkStart))s")
            onProgress?(index + 1, totalChunks)
        }

        Self.logger.info("[upload-telemetry] all chunks uploaded: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - ckStart))s")
        let manifestStart = CFAbsoluteTimeGetCurrent()

        // Encrypt policy
        let policyData = try JSONEncoder().encode(policy)
        let encryptedPolicy = try CryptoEngine.encrypt(policyData, with: shareKey)

        // Create manifest record (keyed by phrase-derived ID for recipient lookup)
        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest = CKRecord(recordType: manifestRecordType, recordID: manifestRecordId)

        manifest["shareVaultId"] = shareVaultId
        manifest["updatedAt"] = Date()
        manifest["version"] = 3  // v3: binary plist encoding, no outer encryption
        manifest["ownerFingerprint"] = ownerFingerprint
        manifest["chunkCount"] = totalChunks
        manifest["claimed"] = false
        manifest["revoked"] = false

        // Store encrypted policy as asset
        let policyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try encryptedPolicy.write(to: policyURL)
        manifest["policy"] = CKAsset(fileURL: policyURL)

        do {
            try await saveWithRetry(manifest)
            try? FileManager.default.removeItem(at: policyURL)
        } catch {
            try? FileManager.default.removeItem(at: policyURL)
            SentryManager.shared.captureError(error)
            transaction.finish(status: .internalError)
            throw CloudKitSharingError.uploadFailed(error)
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
        shareKey: Data,
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

        for (index, chunkData) in chunks.enumerated() {
            let chunkRecordId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(index)")
            let chunkRecord = CKRecord(recordType: chunkRecordType, recordID: chunkRecordId)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try Data(chunkData).write(to: tempURL)

            chunkRecord["chunkData"] = CKAsset(fileURL: tempURL)
            chunkRecord["chunkIndex"] = index
            chunkRecord["vaultId"] = shareVaultId

            do {
                try await saveWithRetry(chunkRecord)
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw CloudKitSharingError.uploadFailed(error)
            }

            onProgress?(index + 1, totalChunks)
        }

        // Update manifest version & timestamp
        // Find the manifest that references this shareVaultId
        let predicate = NSPredicate(format: "shareVaultId == %@", shareVaultId)
        let query = CKQuery(recordType: manifestRecordType, predicate: predicate)
        let results = try await publicDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                record["version"] = currentVersion + 1
                record["updatedAt"] = Date()
                record["chunkCount"] = totalChunks
                try await publicDatabase.save(record)
            }
        }
    }

    // MARK: - Download (Chunked)

    /// Downloads and decrypts a shared vault using a share phrase.
    /// Checks claimed status and sets it after successful download.
    func downloadSharedVault(
        phrase: String,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        let transaction = SentryManager.shared.startTransaction(name: "share.download", operation: "share.download")
        let phraseVaultId = Self.vaultId(from: phrase)
        let shareKey = try Self.deriveShareKey(from: phrase)

        // Fetch manifest
        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest: CKRecord
        do {
            manifest = try await publicDatabase.record(for: manifestRecordId)
        } catch let error as CKError where error.code == .unknownItem {
            transaction.finish(status: .notFound)
            throw CloudKitSharingError.vaultNotFound
        } catch {
            SentryManager.shared.captureError(error)
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

        // Decrypt policy
        var policy = VaultStorage.SharePolicy()
        if let policyAsset = manifest["policy"] as? CKAsset,
           let policyURL = policyAsset.fileURL {
            let encryptedPolicy = try Data(contentsOf: policyURL)
            let decryptedPolicy = try CryptoEngine.decrypt(encryptedPolicy, with: shareKey)
            policy = try JSONDecoder().decode(VaultStorage.SharePolicy.self, from: decryptedPolicy)
        }

        // Download chunks in order
        var encryptedData = Data()
        for i in 0..<chunkCount {
            let chunkRecordId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(i)")
            let chunkRecord: CKRecord
            do {
                chunkRecord = try await publicDatabase.record(for: chunkRecordId)
            } catch {
                throw CloudKitSharingError.downloadFailed(error)
            }

            guard let chunkAsset = chunkRecord["chunkData"] as? CKAsset,
                  let chunkURL = chunkAsset.fileURL else {
                throw CloudKitSharingError.invalidData
            }

            let chunkBytes = try Data(contentsOf: chunkURL)
            encryptedData.append(chunkBytes)

            onProgress?(i + 1, chunkCount)
        }

        let remoteVersion = manifest["version"] as? Int ?? 1

        // v1: outer encryption layer present; v2+: no outer encryption
        let decryptedData: Data
        if remoteVersion < 2 {
            do {
                decryptedData = try CryptoEngine.decrypt(encryptedData, with: shareKey)
            } catch {
                throw CloudKitSharingError.decryptionFailed
            }
        } else {
            decryptedData = encryptedData
        }

        // Mark as claimed
        manifest["claimed"] = true
        try await publicDatabase.save(manifest)

        transaction.finish(status: .ok)
        return (decryptedData, shareVaultId, policy, remoteVersion)
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
        shareKey: Data,
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

        // Download chunks
        var rawData = Data()
        for i in 0..<chunkCount {
            let chunkRecordId = CKRecord.ID(recordName: "\(shareVaultId)_chunk_\(i)")
            let chunkRecord = try await publicDatabase.record(for: chunkRecordId)

            guard let chunkAsset = chunkRecord["chunkData"] as? CKAsset,
                  let chunkURL = chunkAsset.fileURL else {
                throw CloudKitSharingError.invalidData
            }

            rawData.append(try Data(contentsOf: chunkURL))
            onProgress?(i + 1, chunkCount)
        }

        // v1: outer encryption layer; v2+: no outer encryption
        if remoteVersion < 2 {
            do {
                return try CryptoEngine.decrypt(rawData, with: shareKey)
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

    // MARK: - Retry Logic

    /// Saves a CKRecord with automatic retry on transient CloudKit errors.
    private func saveWithRetry(_ record: CKRecord, maxRetries: Int = 3) async throws {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                try await publicDatabase.save(record)
                return
            } catch let error as CKError {
                Self.logger.error("[upload-telemetry] CKError code=\(error.code.rawValue) desc=\(error.localizedDescription, privacy: .public)")
                if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
                    Self.logger.error("[upload-telemetry] underlying: \(underlying.localizedDescription, privacy: .public)")
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
             .zoneBusy, .requestRateLimited:
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
            #if DEBUG
            print("⚠️ [CloudKit] Failed to delete chunks: \(error)")
            #endif
        }
    }

    // MARK: - iCloud Status

    func checkiCloudStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
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
