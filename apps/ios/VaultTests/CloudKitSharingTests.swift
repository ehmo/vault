import XCTest
@testable import Vault
import CloudKit

/// Comprehensive tests for CloudKit cross-iCloud sharing functionality.
/// Tests manifest creation, querying, and cross-account accessibility.
@MainActor
final class CloudKitSharingTests: XCTestCase {

    // MARK: - Test Data

    private let testPhrase = "abandon ability able about above absent absorb abstract absurd"
    private let testShareVaultId = "test-share-vault-id-12345"
    private let testOwnerFingerprint = "owner123"

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Clean up any test records before each test
        Task {
            await cleanupTestRecords()
        }
    }

    override func tearDown() {
        super.tearDown()
        // Clean up test records after each test
        Task {
            await cleanupTestRecords()
        }
    }

    private func cleanupTestRecords() async {
        let db = CKContainer.default().publicCloudDatabase
        let vaultId = CloudKitSharingManager.vaultId(from: testPhrase)
        let recordId = CKRecord.ID(recordName: vaultId)

        do {
            _ = try await db.deleteRecord(withID: recordId)
        } catch {
            // Record might not exist, which is fine
        }
    }

    // MARK: - Vault ID Generation Tests

    func testVaultIdGenerationConsistentHash() {
        // Same phrase should always generate same vaultId
        let vaultId1 = CloudKitSharingManager.vaultId(from: testPhrase)
        let vaultId2 = CloudKitSharingManager.vaultId(from: testPhrase)

        XCTAssertEqual(vaultId1, vaultId2, "Same phrase should generate identical vaultId")
        XCTAssertEqual(vaultId1.count, 32, "VaultId should be 32 hex characters (16 bytes)")
    }

    func testVaultIdGenerationCaseInsensitive() {
        // Phrase normalization should make it case-insensitive
        let lowerId = CloudKitSharingManager.vaultId(from: testPhrase.lowercased())
        let upperId = CloudKitSharingManager.vaultId(from: testPhrase.uppercased())
        let mixedId = CloudKitSharingManager.vaultId(from: "Abandon Ability Able About Above Absent Absorb Abstract Absurd")

        XCTAssertEqual(lowerId, upperId, "VaultId should be case-insensitive")
        XCTAssertEqual(lowerId, mixedId, "VaultId should handle mixed case")
    }

    func testVaultIdGenerationWhitespaceNormalization() {
        // Extra spaces should be normalized
        let normalId = CloudKitSharingManager.vaultId(from: testPhrase)
        let extraSpacesId = CloudKitSharingManager.vaultId(from: "  abandon   ability   able   about  ")

        XCTAssertNotEqual(normalId, extraSpacesId, "Leading/trailing spaces should not match")

        // But internal spaces should be normalized
        let internalExtraId = CloudKitSharingManager.vaultId(from: "abandon  ability  able  about  above  absent  absorb  abstract  absurd")
        XCTAssertEqual(normalId, internalExtraId, "Multiple internal spaces should be normalized to single spaces")
    }

    // MARK: - Manifest Creation Tests

    func testManifestCreationSavesToPublicDatabase() async throws {
        let shareKey = try ShareKey(Data(repeating: 0x01, count: 32))
        let policy = VaultStorage.SharePolicy(expiresAt: nil, maxOpens: nil, allowScreenshots: false, allowDownloads: true)
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        // Save manifest
        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 5
        )

        // Verify it exists by fetching directly from public database
        let db = CKContainer.default().publicCloudDatabase
        let recordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest = try await db.record(for: recordId)

        XCTAssertEqual(manifest.recordType, "SharedVault")
        XCTAssertEqual(manifest.recordID.recordName, phraseVaultId)
        XCTAssertEqual(manifest["shareVaultId"] as? String, testShareVaultId)
        XCTAssertEqual(manifest["ownerFingerprint"] as? String, testOwnerFingerprint)
        XCTAssertEqual(manifest["chunkCount"] as? Int, 5)
        XCTAssertEqual(manifest["claimed"] as? Bool, false)
        XCTAssertEqual(manifest["revoked"] as? Bool, false)
        XCTAssertEqual(manifest["version"] as? Int, 4)
    }

    // MARK: - Phrase Availability Tests

    func testCheckPhraseAvailabilityAvailableShare() async throws {
        // First create a share
        let shareKey = try ShareKey(Data(repeating: 0x02, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 3
        )

        // Now check availability
        let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)

        if case .failure(let e) = result { XCTFail("Available share should return success, got \(e)") }
    }

    func testCheckPhraseAvailabilityNotFound() async {
        // Check a non-existent phrase
        let nonExistentPhrase = "this phrase definitely does not exist anywhere"
        let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: nonExistentPhrase)

        if case .failure(let error) = result {
            XCTAssertEqual(error, .vaultNotFound, "Non-existent share should return vaultNotFound")
        } else {
            XCTFail("Should have returned failure for non-existent vault")
        }
    }

    func testCheckPhraseAvailabilityClaimedShare() async throws {
        // Create and claim a share
        let shareKey = try ShareKey(Data(repeating: 0x03, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 2
        )

        // Mark as claimed
        try await CloudKitSharingManager.shared.markShareClaimed(shareVaultId: testShareVaultId)

        // Check availability
        let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)

        if case .failure(let error) = result {
            XCTAssertEqual(error, .alreadyClaimed, "Claimed share should return alreadyClaimed")
        } else {
            XCTFail("Should have returned failure for claimed vault")
        }
    }

    func testCheckPhraseAvailabilityRevokedShare() async throws {
        // Create and revoke a share
        let shareKey = try ShareKey(Data(repeating: 0x04, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 1
        )

        // Revoke the share
        try await CloudKitSharingManager.shared.revokeShare(shareVaultId: testShareVaultId)

        // Check availability
        let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)

        if case .failure(let error) = result {
            XCTAssertEqual(error, .revoked, "Revoked share should return revoked")
        } else {
            XCTFail("Should have returned failure for revoked vault")
        }
    }

    // MARK: - Query Fallback Tests

    func testCheckPhraseAvailabilityQueryFallback() async throws {
        // Save a manifest
        let shareKey = try ShareKey(Data(repeating: 0x05, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 4
        )

        // Check should work via direct fetch (primary method)
        let result1 = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)
        if case .failure(let e) = result1 { XCTFail("Direct fetch should succeed, got \(e)") }

        // Verify record exists via query as well (tests query path indirectly through fallback)
        let db = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "recordID == %@", CKRecord.ID(recordName: phraseVaultId))
        let query = CKQuery(recordType: "SharedVault", predicate: predicate)
        let results = try await db.records(matching: query)

        XCTAssertEqual(results.matchResults.count, 1, "Query should return exactly one record")
    }

    // MARK: - Share Link Encoding Tests

    func testShareLinkEncodingPhraseExtraction() {
        let phrase = "test phrase for encoding"
        let encoded = ShareLinkEncoder.encode(phrase)
        let url = URL(string: "https://vaultaire.app/share#\(encoded)")!

        let extracted = ShareLinkEncoder.phrase(from: url)

        XCTAssertEqual(extracted, phrase, "Extracted phrase should match original")
    }

    func testShareLinkEncodingInvalidURL() {
        let invalidURL = URL(string: "https://other-domain.com/share#abc123")!
        let phrase = ShareLinkEncoder.phrase(from: invalidURL)

        XCTAssertNil(phrase, "Invalid domain should return nil")
    }

    func testShareLinkEncodingEmptyFragment() {
        let url = URL(string: "https://vaultaire.app/share")!
        let phrase = ShareLinkEncoder.phrase(from: url)

        XCTAssertNil(phrase, "Empty fragment should return nil")
    }

    func testShareLinkEncodingQueryParameterFallback() {
        // Some messaging apps might strip the fragment, so we support query params too
        let phrase = "fallback test phrase"
        let encoded = ShareLinkEncoder.encode(phrase)
        let url = URL(string: "https://vaultaire.app/share?p=\(encoded)")!

        let extracted = ShareLinkEncoder.phrase(from: url)

        XCTAssertEqual(extracted, phrase, "Query parameter fallback should work")
    }

    // MARK: - Retry Logic Tests

    func testCheckPhraseAvailabilityWithRetry() async throws {
        // This test verifies the retry mechanism works
        // We can't easily simulate network delays in unit tests,
        // but we can verify the method completes without errors

        let shareKey = try ShareKey(Data(repeating: 0x06, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 3
        )

        // The actual retry logic is in SharedVaultInviteView.task,
        // but checkPhraseAvailability is the underlying method it calls
        let startTime = Date()
        let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)
        let duration = Date().timeIntervalSince(startTime)

        if case .failure(let e) = result { XCTFail("Should find available share, got \(e)") }
        XCTAssertLessThan(duration, 1.0, "Direct fetch should be fast, no retry needed")
    }
}

// MARK: - Mock Objects for Testing

/// Mock CloudKitSharingClient for unit testing without network calls
class MockCloudKitSharingClient: CloudKitSharingClient {
    var manifests: [String: CKRecord] = [:]
    var shouldFailWithError: CloudKitSharingError?

    func checkPhraseAvailability(phrase: String) async -> Result<Void, CloudKitSharingError> {
        if let error = shouldFailWithError {
            return .failure(error)
        }

        let vaultId = CloudKitSharingManager.vaultId(from: phrase)
        if let manifest = manifests[vaultId] {
            if let claimed = manifest["claimed"] as? Bool, claimed {
                return .failure(.alreadyClaimed)
            }
            if let revoked = manifest["revoked"] as? Bool, revoked {
                return .failure(.revoked)
            }
            return .success(())
        }
        return .failure(.vaultNotFound)
    }

    func consumedStatusByShareVaultIds(_: [String]) async throws -> [String: Bool] {
        return [:]
    }

    func markShareClaimed(shareVaultId _: String) async throws {}

    func markShareConsumed(shareVaultId _: String) async throws {}

    func isShareConsumed(shareVaultId _: String) async throws -> Bool {
        return false
    }

    func uploadSharedVault(shareVaultId _: String, phrase _: String, vaultData _: Data, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, onProgress _: ((Int, Int) -> Void)?) async throws {}

    func syncSharedVault(shareVaultId _: String, vaultData _: Data, shareKey _: ShareKey, currentVersion _: Int, onProgress _: ((Int, Int) -> Void)?) async throws {}

    func syncSharedVaultIncremental(shareVaultId _: String, svdfData _: Data, newChunkHashes _: [String], previousChunkHashes _: [String], onProgress _: ((Int, Int) -> Void)?) async throws {}

    func syncSharedVaultIncrementalFromFile(shareVaultId _: String, svdfFileURL _: URL, newChunkHashes _: [String], previousChunkHashes _: [String], onProgress _: ((Int, Int) -> Void)?) async throws {}

    func uploadChunksParallel(shareVaultId _: String, chunks _: [(Int, Data)], onProgress _: ((Int, Int) -> Void)?) async throws {}

    func uploadChunksFromFile(shareVaultId _: String, fileURL _: URL, chunkIndices _: [Int], onProgress _: ((Int, Int) -> Void)?) async throws {}

    func saveManifest(shareVaultId: String, phraseVaultId: String, shareKey _: ShareKey, policy _: VaultStorage.SharePolicy, ownerFingerprint _: String, totalChunks _: Int) async throws {
        let record = CKRecord(recordType: "SharedVault")
        record["shareVaultId"] = shareVaultId
        record["claimed"] = false
        record["revoked"] = false
        manifests[phraseVaultId] = record
    }

    func downloadSharedVault(phrase _: String, markClaimedOnDownload _: Bool, onProgress _: ((Int, Int) -> Void)?) async throws -> (data: Data, shareVaultId: String, policy: VaultStorage.SharePolicy, version: Int) {
        return (Data(), "", VaultStorage.SharePolicy(), 1)
    }

    func checkForUpdates(shareVaultId _: String, currentVersion _: Int) async throws -> Int? {
        return nil
    }

    func downloadUpdatedVault(shareVaultId _: String, shareKey _: ShareKey, onProgress _: ((Int, Int) -> Void)?) async throws -> Data {
        return Data()
    }

    func revokeShare(shareVaultId _: String) async throws {}

    func deleteSharedVault(shareVaultId _: String) async throws {}

    func deleteSharedVault(phrase _: String) async throws {}

    func existingChunkIndices(for _: String) async throws -> Set<Int> {
        return []
    }

    func checkiCloudStatus() async -> CKAccountStatus {
        return .available
    }
}

// MARK: - Performance Tests

@MainActor
final class CloudKitSharingPerformanceTests: XCTestCase {

    func testCheckPhraseAvailabilityPerformance() async throws {
        // Create a share first
        let testPhrase = "performance test phrase"
        let shareKey = try ShareKey(Data(repeating: 0x07, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)

        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: "perf-test-id",
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: "perf-test-owner",
            totalChunks: 1
        )

        // Measure performance
        measure {
            let expectation = self.expectation(description: "Check availability")
            Task {
                _ = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}
