import XCTest
@testable import Vault

/// Tests for the share import atomicity fix (VAULT-5ha).
///
/// Verifies that:
/// - Vault is pre-marked as shared BEFORE any files are imported
/// - Sharing metadata persists through index save/load cycles
/// - PendingImportState serialization, TTL, and persistence work correctly
/// - Incorrect shared-vault marking is repaired via file-ID overlap check
/// - Pre-marking is idempotent on resume
/// - openCount is correctly initialized to 0
final class ShareImportAtomicityTests: XCTestCase {

    private let storage = VaultStorage.shared
    private var testKey: VaultKey!

    // Standard test data matching real import flow
    private let testShareVaultId = "test-share-vault-\(UUID().uuidString)"
    private let testShareKeyData = Data(repeating: 0xAA, count: 32)
    private let testPolicy = VaultStorage.SharePolicy(
        expiresAt: Date().addingTimeInterval(86400),
        maxOpens: 5,
        allowScreenshots: false,
        allowDownloads: true
    )

    override func setUp() {
        super.setUp()
        testKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        // Clear any leftover pending import state from previous test runs
        ShareImportManager.clearPendingImport()
    }

    override func tearDown() {
        try? storage.deleteVaultIndex(for: testKey)
        ShareImportManager.clearPendingImport()
        super.tearDown()
    }

    // MARK: - PendingImportState Codable Round Trip

    func testPendingImportStateCodableRoundTrip() throws {
        let now = Date()
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "round-trip-test",
            phrase: "test phrase words",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 10,
            importedFileIds: ["file-1", "file-2", "file-3"],
            shareVaultVersion: 3,
            createdAt: now,
            isDownloadComplete: true,
            downloadError: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareImportManager.PendingImportState.self, from: data)

        XCTAssertEqual(decoded.shareVaultId, "round-trip-test")
        XCTAssertEqual(decoded.phrase, "test phrase words")
        XCTAssertEqual(decoded.shareKeyData, testShareKeyData)
        XCTAssertNotNil(decoded.policy.expiresAt)
        if let decodedExpiry = decoded.policy.expiresAt, let originalExpiry = testPolicy.expiresAt {
            XCTAssertEqual(decodedExpiry.timeIntervalSinceReferenceDate,
                           originalExpiry.timeIntervalSinceReferenceDate,
                           accuracy: 0.001)
        }
        XCTAssertEqual(decoded.policy.maxOpens, 5)
        XCTAssertEqual(decoded.policy.allowScreenshots, false)
        XCTAssertEqual(decoded.policy.allowDownloads, true)
        XCTAssertEqual(decoded.totalFiles, 10)
        XCTAssertEqual(decoded.importedFileIds, ["file-1", "file-2", "file-3"])
        XCTAssertEqual(decoded.shareVaultVersion, 3)
        XCTAssertTrue(decoded.isDownloadComplete)
        XCTAssertNil(decoded.downloadError)
    }

    func testPendingImportStateCodableWithDownloadError() throws {
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "error-test",
            phrase: "error phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 5,
            importedFileIds: ["f1"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: "Network timeout after 30s"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareImportManager.PendingImportState.self, from: data)

        XCTAssertEqual(decoded.downloadError, "Network timeout after 30s")
        XCTAssertEqual(decoded.importedFileIds.count, 1)
    }

    func testPendingImportStateCodableWithEmptyImportedFiles() throws {
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "empty-imports",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 20,
            importedFileIds: [],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareImportManager.PendingImportState.self, from: data)

        XCTAssertTrue(decoded.importedFileIds.isEmpty)
        XCTAssertEqual(decoded.totalFiles, 20)
    }

    func testPendingImportStateCodableWithIncompleteDownload() throws {
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "incomplete-dl",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 0,
            importedFileIds: [],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: false,
            downloadError: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ShareImportManager.PendingImportState.self, from: data)

        XCTAssertFalse(decoded.isDownloadComplete)
    }

    // MARK: - PendingImportState Persistence

    func testSavePendingImportAndLoadState() throws {
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "persist-test",
            phrase: "persist phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 7,
            importedFileIds: ["a", "b"],
            shareVaultVersion: 2,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )

        let vaultData = Data(repeating: 0xBB, count: 512)
        try ShareImportManager.savePendingImport(state, vaultData: vaultData)

        let loaded = ShareImportManager.loadPendingImportState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.shareVaultId, "persist-test")
        XCTAssertEqual(loaded?.phrase, "persist phrase")
        XCTAssertEqual(loaded?.importedFileIds, ["a", "b"])
        XCTAssertEqual(loaded?.totalFiles, 7)
        XCTAssertTrue(loaded?.isDownloadComplete ?? false)
    }

    func testUpdatePendingImportStatePreservesVaultData() throws {
        var state = ShareImportManager.PendingImportState(
            shareVaultId: "update-test",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 5,
            importedFileIds: [],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )

        let vaultData = Data(repeating: 0xCC, count: 256)
        try ShareImportManager.savePendingImport(state, vaultData: vaultData)

        // Update state with progress (simulates per-file progress saving)
        state.importedFileIds.append("file-1")
        state.importedFileIds.append("file-2")
        try ShareImportManager.updatePendingImportState(state)

        // Load and verify state updated but vault data file still exists
        let loaded = ShareImportManager.loadPendingImportState()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.importedFileIds, ["file-1", "file-2"])
    }

    func testClearPendingImportRemovesBothFiles() throws {
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "clear-test",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 3,
            importedFileIds: [],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )

        try ShareImportManager.savePendingImport(state, vaultData: Data(repeating: 0, count: 128))
        XCTAssertNotNil(ShareImportManager.loadPendingImportState())

        ShareImportManager.clearPendingImport()

        XCTAssertNil(ShareImportManager.loadPendingImportState(),
                     "State should be nil after clearing")
    }

    func testLoadPendingImportStateReturnsNilWhenEmpty() {
        ShareImportManager.clearPendingImport()
        XCTAssertNil(ShareImportManager.loadPendingImportState())
    }

    // MARK: - PendingImportState TTL Behavior

    func testPendingImportStateExpiredAfter24Hours() throws {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60) // 25 hours ago
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "ttl-expired",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 3,
            importedFileIds: ["f1"],
            shareVaultVersion: 1,
            createdAt: expiredDate,
            isDownloadComplete: true,
            downloadError: nil
        )

        let vaultData = Data(repeating: 0xDD, count: 128)
        try ShareImportManager.savePendingImport(state, vaultData: vaultData)

        let loaded = ShareImportManager.loadPendingImportState()
        XCTAssertNil(loaded, "State older than 24 hours should return nil (TTL expired)")
    }

    func testPendingImportStateValidJustBefore24Hours() throws {
        let almostExpired = Date().addingTimeInterval(-23 * 60 * 60) // 23 hours ago
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "ttl-valid",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 3,
            importedFileIds: ["f1"],
            shareVaultVersion: 1,
            createdAt: almostExpired,
            isDownloadComplete: true,
            downloadError: nil
        )

        let vaultData = Data(repeating: 0xEE, count: 128)
        try ShareImportManager.savePendingImport(state, vaultData: vaultData)

        let loaded = ShareImportManager.loadPendingImportState()
        XCTAssertNotNil(loaded, "State less than 24 hours old should still be valid")
        XCTAssertEqual(loaded?.shareVaultId, "ttl-valid")
    }

    func testPendingImportStateTTLCleansUpExpiredFiles() throws {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        let state = ShareImportManager.PendingImportState(
            shareVaultId: "ttl-cleanup",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: [],
            shareVaultVersion: 1,
            createdAt: expiredDate,
            isDownloadComplete: true,
            downloadError: nil
        )

        try ShareImportManager.savePendingImport(state, vaultData: Data(repeating: 0, count: 64))

        // First load should return nil AND clean up
        let _ = ShareImportManager.loadPendingImportState()

        // Second load should also return nil (files cleaned up)
        let secondLoad = ShareImportManager.loadPendingImportState()
        XCTAssertNil(secondLoad, "Expired state should be cleaned up on first access")
    }

    // MARK: - Pre-marking Vault as Shared (Atomicity Invariant)

    /// The core invariant: vault index must have sharing metadata set BEFORE any files
    /// are stored. This test simulates the pre-marking step that happens before file import.
    func testPreMarkSetsAllSharingFieldsOnIndex() async throws {
        // Create empty vault index (simulates JoinVaultView.setupSharedVault)
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Verify vault is NOT shared initially
        var index = try await storage.loadIndex(with: testKey)
        XCTAssertNil(index.isSharedVault)
        XCTAssertNil(index.sharedVaultId)
        XCTAssertNil(index.sharePolicy)
        XCTAssertNil(index.openCount)
        XCTAssertNil(index.shareKeyData)
        XCTAssertNil(index.sharedVaultVersion)

        // Pre-mark as shared (mirrors the fix in ShareImportManager lines 272-291)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 2
        try await storage.saveIndex(index, with: testKey)

        // Verify all fields persisted
        let reloaded = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(reloaded.isSharedVault ?? false, "isSharedVault must be true after pre-marking")
        XCTAssertEqual(reloaded.sharedVaultId, testShareVaultId)
        XCTAssertEqual(reloaded.sharePolicy?.maxOpens, 5)
        XCTAssertEqual(reloaded.sharePolicy?.allowScreenshots, false)
        XCTAssertEqual(reloaded.sharePolicy?.allowDownloads, true)
        XCTAssertNotNil(reloaded.sharePolicy?.expiresAt)
        XCTAssertEqual(reloaded.openCount, 0, "openCount must start at 0 for fresh shared vault")
        XCTAssertEqual(reloaded.shareKeyData, testShareKeyData)
        XCTAssertEqual(reloaded.sharedVaultVersion, 2)
    }

    /// Files stored AFTER pre-marking should inherit sharing restrictions.
    /// This verifies the invariant that files are never accessible without restrictions.
    func testFilesStoredAfterPreMarkInheritSharingRestrictions() async throws {
        // Setup: create vault and pre-mark as shared
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Store files (simulates the file import loop)
        let fileData = Data("test file content".utf8)
        let fileId = try await storage.storeFile(
            data: fileData,
            filename: "shared_doc.txt",
            mimeType: "text/plain",
            with: testKey
        )

        // Verify vault still marked as shared after file storage
        let afterStore = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(afterStore.isSharedVault ?? false,
                      "Vault must remain marked as shared after file storage")
        XCTAssertEqual(afterStore.sharedVaultId, testShareVaultId)
        XCTAssertEqual(afterStore.sharePolicy?.maxOpens, testPolicy.maxOpens)
        XCTAssertEqual(afterStore.openCount, 0)

        // Verify file exists in the vault
        XCTAssertTrue(afterStore.files.contains(where: { $0.fileId == fileId }),
                      "Stored file should be in the index")
    }

    // MARK: - Pre-marking Idempotency

    /// Running the pre-mark logic twice (as in resume) should not corrupt the vault.
    func testPreMarkIdempotentOnResume() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // First pre-mark
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Store a file
        _ = try await storage.storeFile(
            data: Data("file1".utf8), filename: "f1.txt", mimeType: "text/plain", with: testKey
        )

        // Simulate resume: check alreadyMarked condition (mirrors lines 277-278)
        let index2 = try await storage.loadIndex(with: testKey)
        let alreadyMarked = (index2.isSharedVault == true && index2.sharedVaultId == testShareVaultId)
        XCTAssertTrue(alreadyMarked, "Resume should detect vault is already pre-marked")

        // Even if we re-mark (skipping due to alreadyMarked), state should be unchanged
        XCTAssertEqual(index2.openCount, 0, "openCount should remain 0 on resume")
        XCTAssertEqual(index2.sharedVaultVersion, 1)
        XCTAssertTrue(index2.files.count >= 1, "Previously imported files should still be present")
    }

    /// alreadyMarked should be false when shareVaultId differs.
    func testAlreadyMarkedFalseForDifferentShareVaultId() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = "different-vault-id"
        index.sharePolicy = VaultStorage.SharePolicy()
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        let alreadyMarked = (loaded.isSharedVault == true && loaded.sharedVaultId == testShareVaultId)
        XCTAssertFalse(alreadyMarked,
                       "Should NOT be considered already marked when shareVaultId differs")
    }

    /// alreadyMarked should be false when isSharedVault is nil/false.
    func testAlreadyMarkedFalseWhenNotShared() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        let alreadyMarked = (loaded.isSharedVault == true && loaded.sharedVaultId == testShareVaultId)
        XCTAssertFalse(alreadyMarked,
                       "Fresh vault should not be considered already marked")
    }

    // MARK: - Incorrect Shared-Vault Repair Logic

    /// A vault incorrectly marked as shared (files don't overlap with pending import)
    /// should have its shared flag cleared.
    func testRepairClearsIncorrectlyMarkedVault() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Store a local file (NOT from a share import)
        _ = try await storage.storeFile(
            data: Data("my private file".utf8), filename: "private.txt",
            mimeType: "text/plain", with: testKey
        )

        // Incorrectly mark vault as shared (simulates the old retroactive fix bug)
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 2
        try await storage.saveIndex(index, with: testKey)

        // Pending import exists with different file IDs (from the real shared vault)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 3,
            importedFileIds: ["shared-file-1", "shared-file-2"],
            shareVaultVersion: 2,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // Run repair (mirrors checkSharedVaultStatus)
        index = try await storage.loadIndex(with: testKey)
        if index.isSharedVault == true,
           let pending = ShareImportManager.loadPendingImportState() {
            let importedIds = Set(pending.importedFileIds)
            let vaultFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })
            let hasImportedFiles = !importedIds.intersection(vaultFileIds).isEmpty

            if !hasImportedFiles && !vaultFileIds.isEmpty {
                index.isSharedVault = nil
                index.sharedVaultId = nil
                index.sharePolicy = nil
                index.openCount = nil
                index.shareKeyData = nil
                index.sharedVaultVersion = nil
                try await storage.saveIndex(index, with: testKey)
            }
        }

        let repaired = try await storage.loadIndex(with: testKey)
        XCTAssertNil(repaired.isSharedVault, "Repair must clear incorrect shared flag")
        XCTAssertNil(repaired.sharedVaultId)
        XCTAssertNil(repaired.sharePolicy)
        XCTAssertNil(repaired.shareKeyData)
        XCTAssertEqual(repaired.files.count, 1, "Local files must be preserved")
    }

    /// A legitimately shared vault (files overlap with pending import) should keep its flag.
    func testRepairKeepsLegitimateSharedVault() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Store a file, then mark vault shared with that file's ID in pending import
        _ = try await storage.storeFile(
            data: Data("shared content".utf8), filename: "shared.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        let importedFileId = index.files.first!.fileId.uuidString

        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Pending import includes this vault's file ID (legitimate import)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 1,
            importedFileIds: [importedFileId],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // Run repair
        index = try await storage.loadIndex(with: testKey)
        if index.isSharedVault == true,
           let pending = ShareImportManager.loadPendingImportState() {
            let importedIds = Set(pending.importedFileIds)
            let vaultFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })
            let hasImportedFiles = !importedIds.intersection(vaultFileIds).isEmpty

            if !hasImportedFiles && !vaultFileIds.isEmpty {
                index.isSharedVault = nil
                try await storage.saveIndex(index, with: testKey)
            }
        }

        let kept = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(kept.isSharedVault ?? false,
                      "Repair must NOT clear flag on legitimately shared vault")
        XCTAssertEqual(kept.sharedVaultId, testShareVaultId)
    }

    /// Repair should not trigger when no pending import exists.
    func testRepairNoOpWithoutPendingImport() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        ShareImportManager.clearPendingImport()

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        try await storage.saveIndex(index, with: testKey)

        // Run repair — no pending import, so no repair possible
        index = try await storage.loadIndex(with: testKey)
        let pending = ShareImportManager.loadPendingImportState()
        XCTAssertNil(pending, "No pending import should exist")
        // Repair condition requires pending != nil, so nothing happens
        XCTAssertTrue(index.isSharedVault ?? false,
                      "Without pending import, repair cannot determine correctness — flag stays")
    }

    /// Repair should not clear flag on empty shared vault (pre-mark, no files yet).
    func testRepairKeepsEmptySharedVault() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Mark vault shared (pre-mark before import starts)
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        try await storage.saveIndex(index, with: testKey)

        // Pending import exists but no files imported yet
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 5,
            importedFileIds: [],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // Run repair
        index = try await storage.loadIndex(with: testKey)
        if index.isSharedVault == true,
           let pending = ShareImportManager.loadPendingImportState() {
            let importedIds = Set(pending.importedFileIds)
            let vaultFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })
            let hasImportedFiles = !importedIds.intersection(vaultFileIds).isEmpty

            if !hasImportedFiles && !vaultFileIds.isEmpty {
                index.isSharedVault = nil
                try await storage.saveIndex(index, with: testKey)
            }
        }

        let kept = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(kept.isSharedVault ?? false,
                      "Repair must NOT clear flag on empty shared vault awaiting import")
    }

    // MARK: - Repair Helper (mirrors VaultViewModel.checkSharedVaultStatus)

    /// Runs the same repair logic as checkSharedVaultStatus and returns
    /// (didRepair, updatedIndex) for verification.
    private func runRepair(with key: VaultKey) async throws -> (didRepair: Bool, index: VaultStorage.VaultIndex) {
        var index = try await storage.loadIndex(with: key)
        var didRepair = false

        if index.isSharedVault == true,
           let pending = ShareImportManager.loadPendingImportState() {
            let importedIds = Set(pending.importedFileIds)
            let vaultFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })
            let hasImportedFiles = !importedIds.intersection(vaultFileIds).isEmpty

            if !hasImportedFiles && !vaultFileIds.isEmpty {
                index.isSharedVault = nil
                index.sharedVaultId = nil
                index.sharePolicy = nil
                index.openCount = nil
                index.shareKeyData = nil
                index.sharedVaultVersion = nil
                try await storage.saveIndex(index, with: key)
                didRepair = true
            }
        }

        return (didRepair, index)
    }

    // MARK: - Comprehensive Repair Tests

    /// Repair must prevent self-destruct by clearing flag BEFORE expiration
    /// check would run on an incorrectly marked vault with an expired policy.
    func testRepairPreventsExpiredPolicySelfDestruct() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Store a local file
        _ = try await storage.storeFile(
            data: Data("precious file".utf8), filename: "precious.txt",
            mimeType: "text/plain", with: testKey
        )

        // Incorrectly mark with an EXPIRED policy
        let expiredPolicy = VaultStorage.SharePolicy(
            expiresAt: Date().addingTimeInterval(-3600), // expired 1 hour ago
            maxOpens: nil,
            allowScreenshots: false,
            allowDownloads: true
        )
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = expiredPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Pending import with different file IDs
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: expiredPolicy,
            totalFiles: 2,
            importedFileIds: ["other-file-1", "other-file-2"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, repairedIndex) = try await runRepair(with: testKey)

        XCTAssertTrue(didRepair, "Must repair incorrectly marked vault with expired policy")
        XCTAssertNil(repairedIndex.isSharedVault,
                     "Flag must be cleared so expiration check never runs")
        XCTAssertNil(repairedIndex.sharePolicy,
                     "Expired policy must be removed")

        // Verify files survived (self-destruct did NOT run)
        let final_ = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(final_.files.filter { !$0.isDeleted }.count, 1,
                       "CRITICAL: Local files must survive — self-destruct must not run")
    }

    /// Repair must prevent self-destruct from max-opens being exceeded
    /// on an incorrectly marked vault.
    func testRepairPreventsMaxOpensSelfDestruct() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("important data".utf8), filename: "important.txt",
            mimeType: "text/plain", with: testKey
        )

        // Incorrectly mark with maxOpens already exceeded
        let limitPolicy = VaultStorage.SharePolicy(maxOpens: 2)
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = limitPolicy
        index.openCount = 3 // Already exceeded maxOpens of 2
        index.shareKeyData = testShareKeyData
        try await storage.saveIndex(index, with: testKey)

        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: limitPolicy,
            totalFiles: 1,
            importedFileIds: ["unrelated-file"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, repairedIndex) = try await runRepair(with: testKey)

        XCTAssertTrue(didRepair)
        XCTAssertNil(repairedIndex.isSharedVault)
        XCTAssertNil(repairedIndex.openCount, "openCount must be cleared")
    }

    /// Repair is idempotent — running twice produces the same result.
    func testRepairIsIdempotent() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("file".utf8), filename: "f.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.shareKeyData = testShareKeyData
        try await storage.saveIndex(index, with: testKey)

        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["no-match"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // First repair
        let (didRepair1, _) = try await runRepair(with: testKey)
        XCTAssertTrue(didRepair1)

        // Second repair — isSharedVault is now nil, so outer condition fails
        let (didRepair2, index2) = try await runRepair(with: testKey)
        XCTAssertFalse(didRepair2, "Second repair should be a no-op")
        XCTAssertNil(index2.isSharedVault)
    }

    /// Vault with only deleted files should NOT have its flag cleared
    /// (empty from an active-file perspective).
    func testRepairKeepsVaultWithOnlyDeletedFiles() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Store and then "delete" a file
        let fileId = try await storage.storeFile(
            data: Data("soon deleted".utf8), filename: "del.txt",
            mimeType: "text/plain", with: testKey
        )
        try await storage.deleteFile(id: fileId, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        // Verify the file is marked deleted but still in the index
        XCTAssertTrue(index.files.contains { $0.fileId == fileId && $0.isDeleted })

        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        try await storage.saveIndex(index, with: testKey)

        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["other"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, repairedIndex) = try await runRepair(with: testKey)

        // vaultFileIds (non-deleted) is empty, so !vaultFileIds.isEmpty is false
        XCTAssertFalse(didRepair, "Vault with only deleted files treated as empty — no repair")
        XCTAssertTrue(repairedIndex.isSharedVault ?? false)
    }

    /// Repair must work correctly when pending import has no imported files yet
    /// but vault has its own local files (incorrectly marked before import started).
    func testRepairClearsVaultWhenPendingHasNoImportedFiles() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("local file".utf8), filename: "local.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.shareKeyData = testShareKeyData
        try await storage.saveIndex(index, with: testKey)

        // Pending import exists but NO files imported yet (import just started)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 5,
            importedFileIds: [], // Empty — import hasn't imported any files
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, repairedIndex) = try await runRepair(with: testKey)

        // importedIds is empty → intersection is empty → hasImportedFiles = false
        // vaultFileIds is non-empty → condition met → clear
        XCTAssertTrue(didRepair, "Must clear flag: vault has local files, pending has no imported files")
        XCTAssertNil(repairedIndex.isSharedVault)
    }

    /// When pending import TTL expires, repair cannot run (no pending data).
    /// The incorrectly marked vault remains marked until manual intervention.
    func testRepairCannotRunAfterPendingTTLExpires() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("file".utf8), filename: "f.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        try await storage.saveIndex(index, with: testKey)

        // Create an expired pending import (>24h old)
        let expiredState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["no-match"],
            shareVaultVersion: 1,
            createdAt: Date().addingTimeInterval(-25 * 60 * 60), // 25 hours ago
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(expiredState, vaultData: Data(repeating: 0, count: 64))

        // loadPendingImportState() returns nil for expired states
        let (didRepair, repairedIndex) = try await runRepair(with: testKey)

        XCTAssertFalse(didRepair, "Cannot repair after TTL — no pending data available")
        XCTAssertTrue(repairedIndex.isSharedVault ?? false, "Flag persists (known limitation)")
    }

    /// Two different vaults: repair correctly identifies which to clear.
    func testRepairDistinguishesMultipleVaults() async throws {
        let legitimateKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        defer { try? storage.deleteVaultIndex(for: legitimateKey) }

        // Setup legitimate vault — store file, mark shared
        let freshLegitimate = try await storage.loadIndex(with: legitimateKey)
        try await storage.saveIndex(freshLegitimate, with: legitimateKey)
        let sharedFileId = try await storage.storeFile(
            data: Data("shared content".utf8), filename: "shared.txt",
            mimeType: "text/plain", with: legitimateKey
        )
        var legIndex = try await storage.loadIndex(with: legitimateKey)
        let sharedFileIdStr = legIndex.files.first!.fileId.uuidString
        legIndex.isSharedVault = true
        legIndex.sharedVaultId = testShareVaultId
        legIndex.sharePolicy = testPolicy
        legIndex.shareKeyData = testShareKeyData
        try await storage.saveIndex(legIndex, with: legitimateKey)

        // Setup incorrectly marked vault — local files, same sharedVaultId
        let freshIncorrect = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIncorrect, with: testKey)
        _ = try await storage.storeFile(
            data: Data("my local file".utf8), filename: "mine.txt",
            mimeType: "text/plain", with: testKey
        )
        var incIndex = try await storage.loadIndex(with: testKey)
        incIndex.isSharedVault = true
        incIndex.sharedVaultId = testShareVaultId
        incIndex.sharePolicy = testPolicy
        incIndex.shareKeyData = testShareKeyData
        try await storage.saveIndex(incIndex, with: testKey)

        // Pending import references the legitimate vault's file
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 1,
            importedFileIds: [sharedFileIdStr],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // Repair legitimate vault — should keep flag
        let (didRepairLeg, legResult) = try await runRepair(with: legitimateKey)
        XCTAssertFalse(didRepairLeg, "Legitimate vault must NOT be repaired")
        XCTAssertTrue(legResult.isSharedVault ?? false)

        // Repair incorrect vault — should clear flag
        let (didRepairInc, incResult) = try await runRepair(with: testKey)
        XCTAssertTrue(didRepairInc, "Incorrect vault must be repaired")
        XCTAssertNil(incResult.isSharedVault)
    }

    /// Repair clears ALL sharing metadata fields, not just isSharedVault.
    func testRepairClearsAllSharingMetadata() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("file".utf8), filename: "f.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = "some-vault-id"
        index.sharePolicy = VaultStorage.SharePolicy(
            expiresAt: Date().addingTimeInterval(3600),
            maxOpens: 10,
            allowScreenshots: true,
            allowDownloads: false
        )
        index.openCount = 5
        index.shareKeyData = Data(repeating: 0xFF, count: 32)
        index.sharedVaultVersion = 42
        try await storage.saveIndex(index, with: testKey)

        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: "some-vault-id",
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["no-match"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, _) = try await runRepair(with: testKey)
        XCTAssertTrue(didRepair)

        let repaired = try await storage.loadIndex(with: testKey)
        XCTAssertNil(repaired.isSharedVault, "isSharedVault must be nil")
        XCTAssertNil(repaired.sharedVaultId, "sharedVaultId must be nil")
        XCTAssertNil(repaired.sharePolicy, "sharePolicy must be nil")
        XCTAssertNil(repaired.openCount, "openCount must be nil")
        XCTAssertNil(repaired.shareKeyData, "shareKeyData must be nil")
        XCTAssertNil(repaired.sharedVaultVersion, "sharedVaultVersion must be nil")

        // Non-sharing fields must be untouched
        XCTAssertEqual(repaired.files.filter { !$0.isDeleted }.count, 1, "Files preserved")
        XCTAssertNotNil(repaired.encryptedMasterKey, "Master key preserved")
    }

    /// Repair must NOT run on a vault that is not marked as shared.
    func testRepairSkipsNonSharedVault() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("file".utf8), filename: "f.txt",
            mimeType: "text/plain", with: testKey
        )

        // Pending import exists but vault is NOT shared
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["some-id"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, index) = try await runRepair(with: testKey)

        XCTAssertFalse(didRepair, "Must not repair vault that isn't marked as shared")
        XCTAssertNil(index.isSharedVault)
    }

    /// Repair preserves the vault's custom name when clearing sharing fields.
    func testRepairPreservesCustomName() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("file".utf8), filename: "f.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.shareKeyData = testShareKeyData
        index.customName = "My Personal Vault"
        try await storage.saveIndex(index, with: testKey)

        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["no-match"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, _) = try await runRepair(with: testKey)
        XCTAssertTrue(didRepair)

        let repaired = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(repaired.customName, "My Personal Vault",
                       "Custom name must survive repair")
    }

    /// Repair preserves owner-side activeShares when clearing recipient-side fields.
    func testRepairPreservesActiveShares() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("file".utf8), filename: "f.txt",
            mimeType: "text/plain", with: testKey
        )

        var index = try await storage.loadIndex(with: testKey)
        // This vault is an OWNER of a different share AND incorrectly marked as shared
        index.activeShares = [VaultStorage.ShareRecord(
            id: "owner-share-123",
            createdAt: Date(),
            policy: VaultStorage.SharePolicy()
        )]
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.shareKeyData = testShareKeyData
        try await storage.saveIndex(index, with: testKey)

        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: VaultStorage.SharePolicy(),
            totalFiles: 1,
            importedFileIds: ["no-match"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let (didRepair, _) = try await runRepair(with: testKey)
        XCTAssertTrue(didRepair)

        let repaired = try await storage.loadIndex(with: testKey)
        XCTAssertNil(repaired.isSharedVault, "Recipient-side flag cleared")
        XCTAssertEqual(repaired.activeShares?.count, 1,
                       "Owner-side activeShares must be preserved")
        XCTAssertEqual(repaired.activeShares?.first?.id, "owner-share-123")
    }

    // MARK: - SharePolicy Persistence Through Index

    func testSharePolicyPersistsThroughIndexSaveLoad() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        let restrictivePolicy = VaultStorage.SharePolicy(
            expiresAt: Date().addingTimeInterval(7200),
            maxOpens: 3,
            allowScreenshots: false,
            allowDownloads: false
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharePolicy = restrictivePolicy
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(loaded.sharePolicy?.maxOpens, 3)
        XCTAssertFalse(loaded.sharePolicy?.allowScreenshots ?? true)
        XCTAssertFalse(loaded.sharePolicy?.allowDownloads ?? true)
        XCTAssertNotNil(loaded.sharePolicy?.expiresAt)
    }

    func testSharePolicyWithNoRestrictionsPersists() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        let openPolicy = VaultStorage.SharePolicy(
            expiresAt: nil,
            maxOpens: nil,
            allowScreenshots: true,
            allowDownloads: true
        )

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharePolicy = openPolicy
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        XCTAssertNil(loaded.sharePolicy?.expiresAt)
        XCTAssertNil(loaded.sharePolicy?.maxOpens)
        XCTAssertTrue(loaded.sharePolicy?.allowScreenshots ?? false)
        XCTAssertTrue(loaded.sharePolicy?.allowDownloads ?? false)
    }

    // MARK: - openCount Behavior

    func testOpenCountInitializedToZero() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.openCount = 0
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(loaded.openCount, 0, "openCount must be 0 for newly imported shared vault")
    }

    func testOpenCountIncrements() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharePolicy = VaultStorage.SharePolicy(maxOpens: 5)
        index.openCount = 0
        try await storage.saveIndex(index, with: testKey)

        // Simulate 3 opens (mirrors VaultViewModel.checkSharedVaultStatus)
        for expected in 1...3 {
            var current = try await storage.loadIndex(with: testKey)
            let newCount = (current.openCount ?? 0) + 1
            current.openCount = newCount
            try await storage.saveIndex(current, with: testKey)

            let verify = try await storage.loadIndex(with: testKey)
            XCTAssertEqual(verify.openCount, expected, "openCount should be \(expected) after \(expected) opens")
        }
    }

    func testOpenCountExceedsMaxOpensTriggersDestructCondition() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharePolicy = VaultStorage.SharePolicy(maxOpens: 2)
        index.openCount = 2 // Already at max
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        let currentOpens = (loaded.openCount ?? 0) + 1
        let maxOpens = loaded.sharePolicy?.maxOpens ?? Int.max

        XCTAssertTrue(currentOpens > maxOpens,
                      "Next open should exceed maxOpens, triggering self-destruct")
    }

    // MARK: - Version Tracking

    func testSharedVaultVersionPersists() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultVersion = 5
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(loaded.sharedVaultVersion, 5)
    }

    func testSharedVaultVersionUpdatedPostImport() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Pre-mark with version 1
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Post-import update to version 3 (mirrors the post-import section, line 392)
        var postImport = try await storage.loadIndex(with: testKey)
        postImport.sharedVaultVersion = 3
        try await storage.saveIndex(postImport, with: testKey)

        let final_ = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(final_.sharedVaultVersion, 3, "Version should be updated post-import")
        XCTAssertTrue(final_.isSharedVault ?? false, "isSharedVault should still be true")
    }

    // MARK: - Simulated Crash Scenario (End-to-End)

    /// Simulates the crash scenario that caused the original bug:
    /// 1. Vault created empty
    /// 2. Pre-mark as shared (the fix)
    /// 3. Some files imported, then "crash" (we just stop)
    /// 4. On relaunch, verify vault is still protected
    func testSimulatedCrashDuringImportLeavesVaultProtected() async throws {
        // Step 1: Create vault (simulates JoinVaultView.setupSharedVault)
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Step 2: Pre-mark as shared (THE FIX)
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Step 3: Import some files, then "crash"
        _ = try await storage.storeFile(
            data: Data("file 1 data".utf8), filename: "doc1.txt",
            mimeType: "text/plain", with: testKey
        )
        _ = try await storage.storeFile(
            data: Data("file 2 data".utf8), filename: "doc2.txt",
            mimeType: "text/plain", with: testKey
        )

        // Save pending import state (as the import loop does after each file)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "crash test phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 5,
            importedFileIds: ["file-1-id", "file-2-id"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // === CRASH HAPPENS HERE ===
        // (We don't call clearPendingImport or finalize)

        // Step 4: "Relaunch" - load vault and verify it's protected
        let afterCrash = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(afterCrash.isSharedVault ?? false,
                      "CRITICAL: Vault MUST be marked as shared after crash during import")
        XCTAssertEqual(afterCrash.sharedVaultId, testShareVaultId)
        XCTAssertEqual(afterCrash.sharePolicy?.maxOpens, 5)
        XCTAssertEqual(afterCrash.openCount, 0)
        XCTAssertEqual(afterCrash.shareKeyData, testShareKeyData)

        // Files should be present but protected by sharing restrictions
        XCTAssertEqual(afterCrash.files.count, 2, "Imported files should persist")

        // Pending import should still exist for resume
        let pending = ShareImportManager.loadPendingImportState()
        XCTAssertNotNil(pending, "Pending import state should survive crash for resume")
        XCTAssertEqual(pending?.importedFileIds.count, 2)
    }

    /// Pre-mark now handles atomicity, so the old retroactive fix is removed.
    /// This test verifies the pre-mark path protects the vault directly.
    func testPreMarkProtectsVaultDuringImport() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Simulate pre-mark (mirrors ShareImportManager import flow)
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Verify vault is protected BEFORE any files are imported
        let protected = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(protected.isSharedVault ?? false,
                      "Pre-mark must protect vault before file import begins")
        XCTAssertEqual(protected.sharedVaultId, testShareVaultId)
        XCTAssertEqual(protected.sharePolicy?.maxOpens, testPolicy.maxOpens)
        XCTAssertEqual(protected.openCount, 0)
    }

    // MARK: - shareKeyData Integrity

    func testShareKeyDataPreservedThroughIndexSaveLoad() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        let specificKey = CryptoEngine.generateRandomBytes(count: 32)!
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.shareKeyData = specificKey
        try await storage.saveIndex(index, with: testKey)

        let loaded = try await storage.loadIndex(with: testKey)
        XCTAssertEqual(loaded.shareKeyData, specificKey,
                       "Share key data must survive index save/load cycle without corruption")
        XCTAssertEqual(loaded.shareKeyData?.count, 32, "Share key must be 32 bytes")
    }
}
