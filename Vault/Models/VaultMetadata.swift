import Foundation

/// Metadata about a vault (stored per-key)
struct VaultMetadata: Codable {
    var createdAt: Date
    var lastAccessedAt: Date
    var fileCount: Int
    var totalSize: Int
    var isDuressVault: Bool
    var hasRecoveryPhrase: Bool

    init() {
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.fileCount = 0
        self.totalSize = 0
        self.isDuressVault = false
        self.hasRecoveryPhrase = false
    }

    mutating func updateAccess() {
        lastAccessedAt = Date()
    }

    mutating func addFile(size: Int) {
        fileCount += 1
        totalSize += size
        lastAccessedAt = Date()
    }

    mutating func removeFile(size: Int) {
        fileCount = max(0, fileCount - 1)
        totalSize = max(0, totalSize - size)
        lastAccessedAt = Date()
    }
}

/// Settings that apply globally (not per-vault)
struct GlobalSettings: Codable {
    var gridSize: Int
    var showPatternFeedback: Bool
    var iCloudBackupEnabled: Bool

    static var `default`: GlobalSettings {
        GlobalSettings(
            gridSize: 4,
            showPatternFeedback: false,
            iCloudBackupEnabled: false
        )
    }
}
