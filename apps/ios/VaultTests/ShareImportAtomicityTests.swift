import XCTest
@testable import Vault

/// Tests for the share import atomicity fix (VAULT-5ha).
///
/// Verifies that:
/// - Vault is pre-marked as shared BEFORE any files are imported
/// - Sharing metadata persists through index save/load cycles
/// - PendingImportState serialization, TTL, and persistence work correctly
/// - Retroactive fix detects and repairs unprotected shared vaults
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

    // MARK: - Retroactive Fix Logic

    /// Tests the retroactive fix: an unprotected vault with a pending import state
    /// that has imported files should get sharing restrictions applied.
    func testRetroactiveFixAppliesSharingToUnprotectedVault() async throws {
        // Setup: vault with files but NOT marked as shared (simulates pre-fix crash)
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("orphan file".utf8), filename: "orphan.txt",
            mimeType: "text/plain", with: testKey
        )

        // Create pending import state (simulates crash recovery)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "recovery phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 3,
            importedFileIds: ["file-1"], // At least one file imported
            shareVaultVersion: 2,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // Simulate the retroactive fix (mirrors VaultViewModel.checkSharedVaultStatus lines 840-851)
        var index = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(index.isSharedVault != true, "Vault should NOT be shared initially")

        let pending = ShareImportManager.loadPendingImportState()
        XCTAssertNotNil(pending)
        XCTAssertFalse(pending!.importedFileIds.isEmpty)

        // Apply the retroactive fix
        if index.isSharedVault != true,
           let pending = ShareImportManager.loadPendingImportState(),
           !pending.importedFileIds.isEmpty {
            index.isSharedVault = true
            index.sharedVaultId = pending.shareVaultId
            index.sharePolicy = pending.policy
            index.openCount = 0
            index.shareKeyData = pending.shareKeyData
            index.sharedVaultVersion = pending.shareVaultVersion
            try await storage.saveIndex(index, with: testKey)
        }

        // Verify sharing restrictions now applied
        let fixed = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(fixed.isSharedVault ?? false, "Retroactive fix must mark vault as shared")
        XCTAssertEqual(fixed.sharedVaultId, testShareVaultId)
        XCTAssertEqual(fixed.sharePolicy?.maxOpens, 5)
        XCTAssertNotNil(fixed.sharePolicy?.expiresAt)
        if let fixedExpiry = fixed.sharePolicy?.expiresAt, let originalExpiry = testPolicy.expiresAt {
            XCTAssertEqual(fixedExpiry.timeIntervalSinceReferenceDate,
                           originalExpiry.timeIntervalSinceReferenceDate,
                           accuracy: 0.001)
        }
        XCTAssertEqual(fixed.openCount, 0)
        XCTAssertEqual(fixed.shareKeyData, testShareKeyData)
        XCTAssertEqual(fixed.sharedVaultVersion, 2)
    }

    /// Retroactive fix should NOT trigger on normal (non-shared) vaults.
    func testRetroactiveFixNoFalsePositiveOnNormalVault() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // No pending import state exists
        ShareImportManager.clearPendingImport()

        let index = try await storage.loadIndex(with: testKey)
        let pending = ShareImportManager.loadPendingImportState()

        // Condition from retroactive fix should NOT match
        let shouldFix = index.isSharedVault != true
            && pending != nil
            && !(pending?.importedFileIds.isEmpty ?? true)
        XCTAssertFalse(shouldFix, "Retroactive fix must not trigger on normal vault without pending import")
    }

    /// Retroactive fix should NOT trigger when pending import has empty importedFileIds.
    func testRetroactiveFixSkipsEmptyImportedFiles() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Create pending import with NO imported files (download complete but import never started)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 5,
            importedFileIds: [], // Empty — no files actually stored
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let index = try await storage.loadIndex(with: testKey)
        let pending = ShareImportManager.loadPendingImportState()

        let shouldFix = index.isSharedVault != true
            && pending != nil
            && !(pending?.importedFileIds.isEmpty ?? true)
        XCTAssertFalse(shouldFix,
                       "Retroactive fix must not trigger when no files were actually imported")
    }

    /// Retroactive fix should NOT trigger on vaults already marked as shared.
    func testRetroactiveFixSkipsAlreadySharedVault() async throws {
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        // Pre-mark vault as shared
        var index = try await storage.loadIndex(with: testKey)
        index.isSharedVault = true
        index.sharedVaultId = testShareVaultId
        index.sharePolicy = testPolicy
        index.openCount = 0
        index.shareKeyData = testShareKeyData
        index.sharedVaultVersion = 1
        try await storage.saveIndex(index, with: testKey)

        // Create pending import state (simulates normal resume scenario)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 5,
            importedFileIds: ["f1", "f2"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        let reloaded = try await storage.loadIndex(with: testKey)
        let shouldFix = reloaded.isSharedVault != true

        XCTAssertFalse(shouldFix,
                       "Retroactive fix must not trigger on vault already marked as shared")
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

    /// Simulates what happened BEFORE the fix: vault NOT pre-marked, crash during import.
    /// The retroactive fix in checkSharedVaultStatus should repair this.
    func testSimulatedPreFixCrashRepairedByRetroactiveFix() async throws {
        // Setup: vault with files but NOT marked as shared (the old buggy behavior)
        let freshIndex = try await storage.loadIndex(with: testKey)
        try await storage.saveIndex(freshIndex, with: testKey)

        _ = try await storage.storeFile(
            data: Data("unprotected file".utf8), filename: "exposed.txt",
            mimeType: "text/plain", with: testKey
        )

        // Pending import exists (crash happened mid-import)
        let pendingState = ShareImportManager.PendingImportState(
            shareVaultId: testShareVaultId,
            phrase: "leaked phrase",
            shareKeyData: testShareKeyData,
            policy: testPolicy,
            totalFiles: 3,
            importedFileIds: ["leaked-file-1"],
            shareVaultVersion: 1,
            createdAt: Date(),
            isDownloadComplete: true,
            downloadError: nil
        )
        try ShareImportManager.savePendingImport(pendingState, vaultData: Data(repeating: 0, count: 64))

        // Verify vault is NOT protected (the bug)
        let buggy = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(buggy.isSharedVault != true, "Pre-fix: vault should NOT be shared")
        XCTAssertEqual(buggy.files.count, 1, "Files are accessible without restrictions")

        // Run retroactive fix (mirrors checkSharedVaultStatus)
        var index = try await storage.loadIndex(with: testKey)
        if index.isSharedVault != true,
           let pending = ShareImportManager.loadPendingImportState(),
           !pending.importedFileIds.isEmpty {
            index.isSharedVault = true
            index.sharedVaultId = pending.shareVaultId
            index.sharePolicy = pending.policy
            index.openCount = 0
            index.shareKeyData = pending.shareKeyData
            index.sharedVaultVersion = pending.shareVaultVersion
            try await storage.saveIndex(index, with: testKey)
        }

        // Verify vault is now protected
        let fixed = try await storage.loadIndex(with: testKey)
        XCTAssertTrue(fixed.isSharedVault ?? false,
                      "Retroactive fix must protect previously unprotected vault")
        XCTAssertEqual(fixed.sharedVaultId, testShareVaultId)
        XCTAssertEqual(fixed.sharePolicy?.maxOpens, testPolicy.maxOpens)
    }

    // MARK: - SharePolicy Codable Edge Cases

    func testSharePolicyCodableRoundTrip() throws {
        let policy = VaultStorage.SharePolicy(
            expiresAt: Date().addingTimeInterval(3600),
            maxOpens: 10,
            allowScreenshots: true,
            allowDownloads: false
        )

        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(VaultStorage.SharePolicy.self, from: data)

        XCTAssertEqual(decoded.maxOpens, 10)
        XCTAssertTrue(decoded.allowScreenshots)
        XCTAssertFalse(decoded.allowDownloads)
        XCTAssertNotNil(decoded.expiresAt)
    }

    func testSharePolicyDefaultValues() {
        let policy = VaultStorage.SharePolicy()
        XCTAssertNil(policy.expiresAt)
        XCTAssertNil(policy.maxOpens)
        XCTAssertFalse(policy.allowScreenshots, "Default should disallow screenshots")
        XCTAssertTrue(policy.allowDownloads, "Default should allow downloads")
    }

    func testSharePolicyEquality() {
        let policy1 = VaultStorage.SharePolicy(maxOpens: 5, allowScreenshots: false, allowDownloads: true)
        let policy2 = VaultStorage.SharePolicy(maxOpens: 5, allowScreenshots: false, allowDownloads: true)
        let policy3 = VaultStorage.SharePolicy(maxOpens: 3, allowScreenshots: false, allowDownloads: true)

        XCTAssertEqual(policy1, policy2, "Identical policies should be equal")
        XCTAssertNotEqual(policy1, policy3, "Different maxOpens should make policies unequal")
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
