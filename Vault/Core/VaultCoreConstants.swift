import Foundation

/// Shared constants used by both the main app and extensions.
enum VaultCoreConstants {
    static let appGroupIdentifier = "group.app.vaultaire.ios"
    static let keychainAccessGroup = "group.app.vaultaire.ios"
    static let saltKeychainTag = "app.vaultaire.ios.device.salt"

    // Pattern grid
    static let gridSize = 5
    static let minimumPatternNodes = 6

    // Streaming encryption
    static let streamingMagic: UInt32 = 0x56435345 // "VCSE"
    static let streamingVersion: UInt8 = 1
    static let streamingChunkSize = 262_144 // 256 KB
    static let streamingThreshold = 1_048_576 // 1 MB — files larger than this use streaming

    // Staged imports
    static let pendingImportsDirectory = "pending_imports"
    static let manifestFilename = "manifest.json"

    // Premium status
    static let isPremiumKey = "isPremium"

    // Free-tier limits (enforced in extension)
    static let freeMaxImages = 100
    static let freeMaxVideos = 10
    static let freeMaxFiles = 100

    /// Returns the app group container URL, or nil if unavailable.
    static var appGroupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Returns the pending imports directory URL within the app group container.
    static var pendingImportsURL: URL? {
        appGroupContainerURL?.appendingPathComponent(pendingImportsDirectory)
    }
}
