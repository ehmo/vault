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
}

/// Backs up encrypted vault data to CloudKit private database.
/// Uses the user's own iCloud storage (not the app's public DB quota).
/// Private database requires CKAccountStatus.available — when status is
/// .temporarilyUnavailable, the backup waits briefly for it to resolve.
final class iCloudBackupManager {
    static let shared = iCloudBackupManager()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let recordType = "VaultBackup"
    private let backupRecordName = "current_backup"
    private let fileManager = FileManager.default

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "iCloudBackup")

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
                // Wait progressively: 1, 2, 3, 5, 8, 13s
                let delays: [UInt64] = [1, 2, 3, 5, 8, 13]
                let delay = delays[min(attempt, delays.count - 1)]
                Self.logger.info("[backup] Waiting \(delay)s for iCloud to become available...")
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                continue
            }

            // .noAccount or .restricted — not going to resolve
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

    func performBackup(with key: Data, onProgress: @escaping (BackupStage) -> Void) async throws {
        // Get the vault blob
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let blobURL = documents.appendingPathComponent("vault_data.bin")

        guard fileManager.fileExists(atPath: blobURL.path) else {
            throw iCloudError.fileNotFound
        }

        Self.logger.info("[backup] Starting backup...")

        // Wait for iCloud to be fully available (private DB requires it)
        onProgress(.waitingForICloud)
        try Task.checkCancellation()
        try await waitForAvailableAccount()

        // Read and encrypt the blob with additional layer
        onProgress(.readingVault)
        try Task.checkCancellation()
        let blobData = try Data(contentsOf: blobURL)

        onProgress(.encrypting)
        try Task.checkCancellation()
        let encryptedBackup = try CryptoEngine.encrypt(blobData, with: key)

        // Create backup metadata
        let metadata = BackupMetadata(
            timestamp: Date(),
            size: encryptedBackup.count,
            checksum: CryptoEngine.computeHMAC(for: encryptedBackup, with: key)
        )
        let metadataJson = try JSONEncoder().encode(metadata)

        // Write encrypted data to temp file for CKAsset
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("vault_backup_\(UUID().uuidString).bin")
        try encryptedBackup.write(to: tempURL)
        defer { try? fileManager.removeItem(at: tempURL) }

        // Save to CloudKit private database
        onProgress(.uploading)
        try Task.checkCancellation()
        let recordID = CKRecord.ID(recordName: backupRecordName)
        let record: CKRecord

        // Try to fetch existing record to update it, or create new
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record["metadata"] = metadataJson as CKRecordValue
        record["backupData"] = CKAsset(fileURL: tempURL)
        record["timestamp"] = metadata.timestamp as CKRecordValue

        try Task.checkCancellation()
        try await privateDatabase.save(record)
        onProgress(.complete)
        Self.logger.info("[backup] Backup complete (\(encryptedBackup.count / 1024)KB)")
    }

    // MARK: - Restore

    func checkForBackup() async -> BackupMetadata? {
        let recordID = CKRecord.ID(recordName: backupRecordName)
        do {
            let record = try await privateDatabase.record(for: recordID)
            guard let metadataData = record["metadata"] as? Data else { return nil }
            return try JSONDecoder().decode(BackupMetadata.self, from: metadataData)
        } catch {
            return nil
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

        guard let metadataData = record["metadata"] as? Data,
              let asset = record["backupData"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw iCloudError.downloadFailed
        }

        let metadata = try JSONDecoder().decode(BackupMetadata.self, from: metadataData)
        let encryptedBlob = try Data(contentsOf: assetURL)

        // Verify checksum
        let computedChecksum = CryptoEngine.computeHMAC(for: encryptedBlob, with: key)
        guard computedChecksum == metadata.checksum else {
            throw iCloudError.downloadFailed
        }

        // Decrypt
        let decryptedBlob = try CryptoEngine.decrypt(encryptedBlob, with: key)

        // Write to local storage
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let blobURL = documents.appendingPathComponent("vault_data.bin")

        try decryptedBlob.write(to: blobURL, options: [.atomic, .completeFileProtection])
        Self.logger.info("[backup] Restore complete")
    }

    // MARK: - Backup Metadata

    struct BackupMetadata: Codable {
        let timestamp: Date
        let size: Int
        let checksum: Data

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
