import Foundation
import UIKit

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

final class iCloudBackupManager {
    static let shared = iCloudBackupManager()

    private let fileManager = FileManager.default
    private let backupFileName = "vault_backup.bin"

    private init() {}

    // MARK: - iCloud Availability

    var isICloudAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    var iCloudContainerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    // MARK: - Backup

    func performBackup(with key: Data) async throws {
        guard isICloudAvailable else {
            throw iCloudError.notAvailable
        }

        guard let containerURL = iCloudContainerURL else {
            throw iCloudError.containerNotFound
        }

        // Create container if needed
        if !fileManager.fileExists(atPath: containerURL.path) {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }

        // Get the vault blob
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let blobURL = documents.appendingPathComponent("vault_data.bin")

        guard fileManager.fileExists(atPath: blobURL.path) else {
            throw iCloudError.fileNotFound
        }

        // Read and encrypt the blob with additional layer
        let blobData = try Data(contentsOf: blobURL)
        let encryptedBackup = try CryptoEngine.encrypt(blobData, with: key)

        // Create backup metadata
        let metadata = BackupMetadata(
            timestamp: Date(),
            size: encryptedBackup.count,
            checksum: CryptoEngine.computeHMAC(for: encryptedBackup, with: key)
        )

        // Write metadata + encrypted blob
        let backupURL = containerURL.appendingPathComponent(backupFileName)

        var backupData = Data()
        let metadataJson = try JSONEncoder().encode(metadata)
        var metadataSize = UInt32(metadataJson.count)
        backupData.append(Data(bytes: &metadataSize, count: 4))
        backupData.append(metadataJson)
        backupData.append(encryptedBackup)

        try backupData.write(to: backupURL, options: [.atomic])
    }

    // MARK: - Restore

    func checkForBackup() async -> BackupMetadata? {
        guard let containerURL = iCloudContainerURL else { return nil }

        let backupURL = containerURL.appendingPathComponent(backupFileName)
        guard fileManager.fileExists(atPath: backupURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: backupURL)
            guard data.count > 4 else { return nil }

            let sizeData = data.prefix(4)
            let metadataSize = Int(sizeData.withUnsafeBytes { $0.load(as: UInt32.self) })

            guard data.count > 4 + metadataSize else { return nil }

            let metadataJson = data.subdata(in: 4..<(4 + metadataSize))
            return try JSONDecoder().decode(BackupMetadata.self, from: metadataJson)
        } catch {
            return nil
        }
    }

    func restoreBackup(with key: Data) async throws {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudError.containerNotFound
        }

        let backupURL = containerURL.appendingPathComponent(backupFileName)
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw iCloudError.fileNotFound
        }

        // Read backup
        let data = try Data(contentsOf: backupURL)
        guard data.count > 4 else {
            throw iCloudError.downloadFailed
        }

        // Parse metadata
        let sizeData = data.prefix(4)
        let metadataSize = Int(sizeData.withUnsafeBytes { $0.load(as: UInt32.self) })

        guard data.count > 4 + metadataSize else {
            throw iCloudError.downloadFailed
        }

        let metadataJson = data.subdata(in: 4..<(4 + metadataSize))
        let metadata = try JSONDecoder().decode(BackupMetadata.self, from: metadataJson)

        // Extract encrypted blob
        let encryptedBlob = data.subdata(in: (4 + metadataSize)..<data.count)

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
