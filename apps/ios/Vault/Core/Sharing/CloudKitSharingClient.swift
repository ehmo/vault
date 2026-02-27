import CloudKit
import Foundation

/// Protocol abstracting CloudKitSharingManager for testability.
/// Covers the public API surface used by ShareSyncManager, ShareUploadManager, and other consumers.
protocol CloudKitSharingClient: Sendable {
    // MARK: - Phrase & Status

    func checkPhraseAvailability(phrase: String) async -> Result<Void, CloudKitSharingError>
    func consumedStatusByShareVaultIds(_ shareVaultIds: [String]) async throws -> [String: Bool]
    func claimedStatusByShareVaultIds(_ shareVaultIds: [String]) async throws -> [String: Bool]
    func markShareClaimed(shareVaultId: String) async throws
    func markShareConsumed(shareVaultId: String) async throws
    func isShareConsumed(shareVaultId: String) async throws -> Bool

    // MARK: - Upload

    func uploadSharedVault(
        shareVaultId: String,
        phrase: String,
        vaultData: Data,
        shareKey: ShareKey,
        policy: VaultStorage.SharePolicy,
        ownerFingerprint: String,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    func syncSharedVault(
        shareVaultId: String,
        vaultData: Data,
        shareKey: ShareKey,
        currentVersion: Int,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    func syncSharedVaultIncremental(
        shareVaultId: String,
        svdfData: Data,
        newChunkHashes: [String],
        previousChunkHashes: [String],
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    func syncSharedVaultIncrementalFromFile(
        shareVaultId: String,
        svdfFileURL: URL,
        newChunkHashes: [String],
        previousChunkHashes: [String],
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    func uploadChunksParallel(
        shareVaultId: String,
        chunks: [(Int, Data)],
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    func uploadChunksFromFile(
        shareVaultId: String,
        fileURL: URL,
        chunkIndices: [Int],
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    func saveManifest(
        shareVaultId: String,
        phraseVaultId: String,
        shareKey: ShareKey,
        policy: VaultStorage.SharePolicy,
        ownerFingerprint: String,
        totalChunks: Int
    ) async throws

    // MARK: - Download

    func downloadSharedVault(
        phrase: String,
        markClaimedOnDownload: Bool,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int)

    func checkForUpdates(shareVaultId: String, currentVersion: Int) async throws -> Int?

    func downloadUpdatedVault(
        shareVaultId: String,
        shareKey: ShareKey,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> Data

    // MARK: - Download to File (Streaming)

    func downloadSharedVaultToFile(
        phrase: String,
        outputURL: URL,
        markClaimedOnDownload: Bool,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> (fileURL: URL, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int)

    func downloadUpdatedVaultToFile(
        shareVaultId: String,
        shareKey: ShareKey,
        outputURL: URL,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws

    // MARK: - Revoke & Delete

    func revokeShare(shareVaultId: String) async throws
    func deleteSharedVault(shareVaultId: String) async throws
    func deleteSharedVault(phrase: String) async throws

    // MARK: - Chunk Queries

    func existingChunkIndices(for shareVaultId: String) async throws -> Set<Int>

    // MARK: - iCloud Status

    func checkiCloudStatus() async -> CKAccountStatus
}

// MARK: - Default Parameter Values

extension CloudKitSharingClient {
    func uploadSharedVault(
        shareVaultId: String, phrase: String, vaultData: Data, shareKey: ShareKey,
        policy: VaultStorage.SharePolicy, ownerFingerprint: String
    ) async throws {
        try await uploadSharedVault(
            shareVaultId: shareVaultId, phrase: phrase, vaultData: vaultData,
            shareKey: shareKey, policy: policy, ownerFingerprint: ownerFingerprint, onProgress: nil
        )
    }

    func syncSharedVault(
        shareVaultId: String, vaultData: Data, shareKey: ShareKey, currentVersion: Int
    ) async throws {
        try await syncSharedVault(
            shareVaultId: shareVaultId, vaultData: vaultData, shareKey: shareKey,
            currentVersion: currentVersion, onProgress: nil
        )
    }

    func syncSharedVaultIncremental(
        shareVaultId: String, svdfData: Data, newChunkHashes: [String], previousChunkHashes: [String]
    ) async throws {
        try await syncSharedVaultIncremental(
            shareVaultId: shareVaultId, svdfData: svdfData,
            newChunkHashes: newChunkHashes, previousChunkHashes: previousChunkHashes, onProgress: nil
        )
    }

    func syncSharedVaultIncrementalFromFile(
        shareVaultId: String, svdfFileURL: URL, newChunkHashes: [String], previousChunkHashes: [String]
    ) async throws {
        try await syncSharedVaultIncrementalFromFile(
            shareVaultId: shareVaultId, svdfFileURL: svdfFileURL,
            newChunkHashes: newChunkHashes, previousChunkHashes: previousChunkHashes, onProgress: nil
        )
    }

    func uploadChunksParallel(shareVaultId: String, chunks: [(Int, Data)]) async throws {
        try await uploadChunksParallel(shareVaultId: shareVaultId, chunks: chunks, onProgress: nil)
    }

    func uploadChunksFromFile(shareVaultId: String, fileURL: URL, chunkIndices: [Int]) async throws {
        try await uploadChunksFromFile(
            shareVaultId: shareVaultId, fileURL: fileURL, chunkIndices: chunkIndices, onProgress: nil
        )
    }

    func downloadSharedVault(phrase: String) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        try await downloadSharedVault(phrase: phrase, markClaimedOnDownload: true, onProgress: nil)
    }

    func downloadSharedVault(
        phrase: String, markClaimedOnDownload: Bool
    ) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        try await downloadSharedVault(phrase: phrase, markClaimedOnDownload: markClaimedOnDownload, onProgress: nil)
    }

    func downloadUpdatedVault(shareVaultId: String, shareKey: ShareKey) async throws -> Data {
        try await downloadUpdatedVault(shareVaultId: shareVaultId, shareKey: shareKey, onProgress: nil)
    }

    func downloadSharedVaultToFile(
        phrase: String, outputURL: URL
    ) async throws -> (fileURL: URL, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        try await downloadSharedVaultToFile(
            phrase: phrase, outputURL: outputURL, markClaimedOnDownload: true, onProgress: nil
        )
    }

    func downloadSharedVaultToFile(
        phrase: String, outputURL: URL, markClaimedOnDownload: Bool
    ) async throws -> (fileURL: URL, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        try await downloadSharedVaultToFile(
            phrase: phrase, outputURL: outputURL, markClaimedOnDownload: markClaimedOnDownload, onProgress: nil
        )
    }

    func downloadUpdatedVaultToFile(
        shareVaultId: String, shareKey: ShareKey, outputURL: URL
    ) async throws {
        try await downloadUpdatedVaultToFile(
            shareVaultId: shareVaultId, shareKey: shareKey, outputURL: outputURL, onProgress: nil
        )
    }
}

extension CloudKitSharingManager: CloudKitSharingClient {}
