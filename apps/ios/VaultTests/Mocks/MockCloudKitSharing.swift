import CloudKit
import Foundation
@testable import Vault

/// Configurable mock CloudKitSharingClient for testing.
/// Combines features used across ShareUploadManager, ShareSyncManager, and ShareUploadDebounce tests.
final class MockCloudKitSharing: CloudKitSharingClient {
    // MARK: - Configurable behavior

    var phraseAvailable = true
    var uploadCalls: [String] = []
    var deleteCalls: [String] = []
    var consumedStatus: [String: Bool] = [:]
    var syncFromFileCalls: [(shareVaultId: String, svdfFileURL: URL, newChunkHashes: [String], previousChunkHashes: [String])] = []
    var syncFromFileError: Error?

    // MARK: - Protocol implementation

    func checkPhraseAvailability(phrase _: String) async -> Result<Void, CloudKitSharingError> {
        phraseAvailable ? .success(()) : .failure(.notAvailable)
    }

    func consumedStatusByShareVaultIds(_ shareVaultIds: [String]) async throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in shareVaultIds {
            result[id] = consumedStatus[id] ?? false
        }
        return result
    }

    func claimedStatusByShareVaultIds(_ shareVaultIds: [String]) async throws -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: shareVaultIds.map { ($0, false) })
    }

    func markShareClaimed(shareVaultId _: String) async throws { /* No-op */ }
    func markShareConsumed(shareVaultId _: String) async throws { /* No-op */ }
    func isShareConsumed(shareVaultId _: String) async throws -> Bool { false }

    func uploadSharedVault(shareVaultId: String, phrase _: String, vaultData _: Data, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, onProgress _: ((Int, Int) -> Void)?) async throws {
        uploadCalls.append(shareVaultId)
    }

    func syncSharedVault(shareVaultId _: String, vaultData _: Data, shareKey _: ShareKey, currentVersion _: Int, onProgress _: ((Int, Int) -> Void)?) async throws { /* No-op */ }

    func syncSharedVaultIncremental(shareVaultId _: String, svdfData _: Data, newChunkHashes _: [String], previousChunkHashes _: [String], onProgress _: ((Int, Int) -> Void)?) async throws { /* No-op */ }

    func syncSharedVaultIncrementalFromFile(shareVaultId: String, svdfFileURL: URL, newChunkHashes: [String], previousChunkHashes: [String], onProgress _: ((Int, Int) -> Void)?) async throws {
        syncFromFileCalls.append((shareVaultId, svdfFileURL, newChunkHashes, previousChunkHashes))
        if let error = syncFromFileError { throw error }
    }

    func uploadChunksParallel(shareVaultId _: String, chunks _: [(Int, Data)], onProgress _: ((Int, Int) -> Void)?) async throws { /* No-op */ }

    func uploadChunksFromFile(shareVaultId: String, fileURL _: URL, chunkIndices _: [Int], onProgress _: ((Int, Int) -> Void)?) async throws {
        uploadCalls.append(shareVaultId)
    }

    func saveManifest(shareVaultId _: String, phraseVaultId _: String, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, totalChunks _: Int) async throws { /* No-op */ }

    func downloadSharedVault(phrase _: String, markClaimedOnDownload _: Bool, onProgress _: ((Int, Int) -> Void)?) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        (Data(), "mock-id", VaultStorage.SharePolicy(), 1)
    }

    func checkForUpdates(shareVaultId _: String, currentVersion _: Int) async throws -> Int? { nil }

    func downloadUpdatedVault(shareVaultId _: String, shareKey _: ShareKey, onProgress _: ((Int, Int) -> Void)?) async throws -> Data { Data() }

    func downloadSharedVaultToFile(phrase _: String, outputURL: URL, markClaimedOnDownload _: Bool, onProgress _: ((Int, Int) -> Void)?) async throws -> (fileURL: URL, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) { (outputURL, "", VaultStorage.SharePolicy(), 1) }

    func downloadUpdatedVaultToFile(shareVaultId _: String, shareKey _: ShareKey, outputURL _: URL, onProgress _: ((Int, Int) -> Void)?) async throws { /* No-op */ }

    func revokeShare(shareVaultId _: String) async throws { /* No-op */ }

    func deleteSharedVault(shareVaultId: String) async throws {
        deleteCalls.append(shareVaultId)
    }

    func deleteSharedVault(phrase _: String) async throws { /* No-op */ }

    func existingChunkIndices(for _: String) async throws -> Set<Int> { [] }

    func checkiCloudStatus() async -> CKAccountStatus { .available }
}
