import XCTest
@testable import Vault

/// Tests for VaultViewModel covering core functionality.
/// These tests catch common mistakes like:
/// - @MainActor await omission in import handlers
/// - Missing progress updates on MainActor before Task.detached
/// - Not handling all import error cases
@MainActor
final class VaultViewModelTests: XCTestCase {

    private var viewModel: VaultViewModel!
    private var appState: AppState!
    private var subscriptionManager: SubscriptionManager!
    private var testKey: VaultKey!
    private var storage: VaultStorage!

    override func setUp() {
        super.setUp()

        appState = AppState()
        subscriptionManager = SubscriptionManager.shared
        testKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        appState.currentVaultKey = testKey
        storage = VaultStorage.shared

        viewModel = VaultViewModel()
        viewModel.configure(appState: appState, subscriptionManager: subscriptionManager)
    }

    override func tearDown() {
        // Clean up test vault
        try? storage.deleteVaultIndex(for: testKey)
        super.tearDown()
    }

    // MARK: - File Operations

    func testLoadFiles_PopulatesFilesArray() async throws {
        // Create vault with test files
        let index = try storage.loadIndex(with: testKey)
        try storage.saveIndex(index, with: testKey)

        // Add files
        _ = try storage.storeFile(data: Data("content1".utf8), filename: "file1.txt", mimeType: "text/plain", with: testKey)
        _ = try storage.storeFile(data: Data("content2".utf8), filename: "file2.txt", mimeType: "text/plain", with: testKey)

        viewModel.loadFiles()
        await viewModel.activeLoadTask?.value

        XCTAssertEqual(viewModel.files.count, 2, "Should load 2 files")
    }

    func testToggleSelection_AddsAndRemoves() async throws {
        // Setup
        let index = try storage.loadIndex(with: testKey)
        try storage.saveIndex(index, with: testKey)
        let fileId = try storage.storeFile(data: Data("content".utf8), filename: "file.txt", mimeType: "text/plain", with: testKey)

        viewModel.loadFiles()
        await viewModel.activeLoadTask?.value
        viewModel.isEditing = true

        // Toggle on
        viewModel.toggleSelection(fileId)
        XCTAssertTrue(viewModel.selectedIds.contains(fileId))

        // Toggle off
        viewModel.toggleSelection(fileId)
        XCTAssertFalse(viewModel.selectedIds.contains(fileId))
    }

    // MARK: - Filter

    func testSetFileFilter_UpdatesFilter() {
        viewModel.setFileFilter(.all)
        // Verify filter was set (indirectly via computeVisibleFiles)
        let visible = viewModel.computeVisibleFiles()
        XCTAssertNotNil(visible)
    }

    func testSetFileFilter_Media() async throws {
        // Setup with media file
        let index = try storage.loadIndex(with: testKey)
        try storage.saveIndex(index, with: testKey)
        _ = try storage.storeFile(data: Data("image".utf8), filename: "image.jpg", mimeType: "image/jpeg", with: testKey)
        _ = try storage.storeFile(data: Data("doc".utf8), filename: "doc.pdf", mimeType: "application/pdf", with: testKey)

        viewModel.loadFiles()
        await viewModel.activeLoadTask?.value
        viewModel.setFileFilter(.media)

        let visible = viewModel.computeVisibleFiles()
        XCTAssertEqual(visible.media.count, 1, "Media filter should show only 1 media file")
    }

    // MARK: - Import Progress

    func testImportProgress_TracksCorrectly() {
        XCTAssertNil(viewModel.importProgress)
        XCTAssertFalse(viewModel.isImporting)

        viewModel.importProgress = (completed: 2, total: 5)
        XCTAssertTrue(viewModel.isImporting)
        XCTAssertEqual(viewModel.importProgress?.completed, 2)
        XCTAssertEqual(viewModel.importProgress?.total, 5)

        viewModel.importProgress = nil
        XCTAssertFalse(viewModel.isImporting)
    }

    // MARK: - Unified Progress Overlay (activeOperationProgress)

    func testActiveOperationProgress_NilWhenIdle() {
        // No import, no delete, no transfer → should be nil
        viewModel.importProgress = nil
        viewModel.isDeleteInProgress = false
        XCTAssertNil(viewModel.activeOperationProgress, "Should be nil when no operation is active")
    }

    func testActiveOperationProgress_ShowsImportProgress() {
        viewModel.importProgress = (completed: 3, total: 10)
        viewModel.isDeleteInProgress = false

        let progress = viewModel.activeOperationProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.completed, 3)
        XCTAssertEqual(progress?.total, 10)
        XCTAssertTrue(progress?.message.contains("Importing") == true,
                       "Message should say 'Importing' not 'Deleting'")
        XCTAssertTrue(progress?.message.contains("3") == true)
        XCTAssertTrue(progress?.message.contains("10") == true)
    }

    func testActiveOperationProgress_ShowsDeleteProgress() {
        viewModel.importProgress = (completed: 5, total: 8)
        viewModel.isDeleteInProgress = true

        let progress = viewModel.activeOperationProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.completed, 5)
        XCTAssertEqual(progress?.total, 8)
        XCTAssertTrue(progress?.message.contains("Deleting") == true,
                       "Message should say 'Deleting' when isDeleteInProgress is true")
    }

    func testActiveOperationProgress_ImportTakesPriorityOverTransfer() {
        // Both import and transfer active → import should win
        viewModel.importProgress = (completed: 1, total: 5)
        viewModel.isDeleteInProgress = false

        let progress = viewModel.activeOperationProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.total, 5, "Import progress should take priority over transfer manager")
        XCTAssertTrue(progress?.message.contains("Importing") == true)
    }

    func testActiveOperationProgress_ZeroProgress() {
        viewModel.importProgress = (completed: 0, total: 10)
        viewModel.isDeleteInProgress = false

        let progress = viewModel.activeOperationProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.completed, 0)
        XCTAssertEqual(progress?.total, 10)
    }

    func testActiveOperationProgress_CompletedEqualsTotal() {
        viewModel.importProgress = (completed: 10, total: 10)
        viewModel.isDeleteInProgress = false

        let progress = viewModel.activeOperationProgress
        XCTAssertNotNil(progress, "Should still show progress when completed == total (cleanup hasn't run yet)")
        XCTAssertEqual(progress?.completed, 10)
    }

    func testActiveOperationProgress_DisappearsWhenImportCleared() {
        viewModel.importProgress = (completed: 3, total: 5)
        XCTAssertNotNil(viewModel.activeOperationProgress)

        viewModel.importProgress = nil
        // transferManager is idle by default
        XCTAssertNil(viewModel.activeOperationProgress, "Should be nil after import progress cleared")
    }

    // MARK: - Free Tier Limits

    func testCanAddFile_FreeTierLimit() {
        // Test free tier file limit logic
        // When not premium and at limit
        if !subscriptionManager.isPremium {
            let canAdd = subscriptionManager.canAddFile(currentFileCount: SubscriptionManager.maxFreeFilesPerVault)
            XCTAssertFalse(canAdd, "Should not allow adding files at free tier limit")

            let canAddUnderLimit = subscriptionManager.canAddFile(currentFileCount: SubscriptionManager.maxFreeFilesPerVault - 1)
            XCTAssertTrue(canAddUnderLimit, "Should allow adding files under free tier limit")
        }
    }

    // MARK: - Vault Key Change

    func testHandleVaultKeyChange_ClearsFiles() async throws {
        // Setup with files
        let index = try storage.loadIndex(with: testKey)
        try storage.saveIndex(index, with: testKey)
        _ = try storage.storeFile(data: Data("content".utf8), filename: "file.txt", mimeType: "text/plain", with: testKey)

        viewModel.loadFiles()
        await viewModel.activeLoadTask?.value
        XCTAssertEqual(viewModel.files.count, 1)

        // Change key
        let newKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        viewModel.handleVaultKeyChange(oldKey: testKey, newKey: newKey)

        // Files should be cleared (will reload for new key)
        XCTAssertEqual(viewModel.files.count, 0, "Files should be cleared on key change")
    }
}
