import XCTest
import CloudKit
@testable import Vault

final class ShareVaultViewModeTests: XCTestCase {

    func testResolveModeKeepsManualNewShareWhenShareDataExists() {
        let mode = ShareVaultView.resolveMode(currentMode: .newShare, hasShareData: true)
        assert(mode, matches: .newShare)
    }

    func testResolveModeKeepsManualNewShareWhenShareDataDisappears() {
        let mode = ShareVaultView.resolveMode(currentMode: .newShare, hasShareData: false)
        assert(mode, matches: .newShare)
    }

    func testResolveModeChangesManageToNewWhenDataDisappears() {
        let mode = ShareVaultView.resolveMode(currentMode: .manageShares, hasShareData: false)
        assert(mode, matches: .newShare)
    }

    func testResolveModeChangesLoadingToManageWhenDataExists() {
        let mode = ShareVaultView.resolveMode(currentMode: .loading, hasShareData: true)
        assert(mode, matches: .manageShares)
    }

    func testResolveModePreservesErrorState() {
        let mode = ShareVaultView.resolveMode(currentMode: .error("boom"), hasShareData: true)
        if case .error(let message) = mode {
            XCTAssertEqual(message, "boom")
        } else {
            XCTFail("Expected .error mode")
        }
    }

    func testResolveModePreservesICloudUnavailableState() {
        let mode = ShareVaultView.resolveMode(currentMode: .iCloudUnavailable(.noAccount), hasShareData: true)
        if case .iCloudUnavailable(let status) = mode {
            XCTAssertEqual(status, .noAccount)
        } else {
            XCTFail("Expected .iCloudUnavailable mode")
        }
    }

    func testResolveModePreservesUploadingState() {
        let mode = ShareVaultView.resolveMode(currentMode: .uploading(jobId: "test-job"), hasShareData: true)
        if case .uploading(let jobId) = mode {
            XCTAssertEqual(jobId, "test-job")
        } else {
            XCTFail("Expected .uploading mode")
        }
    }

    func testResolveModePreservesPhraseRevealState() {
        let mode = ShareVaultView.resolveMode(currentMode: .phraseReveal(phrase: "test phrase", shareVaultId: "sv-1"), hasShareData: true)
        if case .phraseReveal(let phrase, let svId) = mode {
            XCTAssertEqual(phrase, "test phrase")
            XCTAssertEqual(svId, "sv-1")
        } else {
            XCTFail("Expected .phraseReveal mode")
        }
    }

    func testPolicyDescriptionNoExports() {
        let policy = VaultStorage.SharePolicy(allowDownloads: false)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertTrue(items.contains("No exports"))
    }

    func testPolicyDescriptionMaxOpens() {
        let policy = VaultStorage.SharePolicy(maxOpens: 10)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertTrue(items.contains("10 opens max"))
    }

    func testPolicyDescriptionEmpty() {
        let policy = VaultStorage.SharePolicy()
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertTrue(items.isEmpty)
    }

    func testShouldDisplayUploadJobHidesCompleteAndCancelled() {
        XCTAssertFalse(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .complete)))
        XCTAssertFalse(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .cancelled)))
    }

    func testShouldDisplayUploadJobKeepsFailedAndRunning() {
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .failed)))
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .uploading)))
    }

    func testDuressDisabledForReceivedSharedVault() {
        XCTAssertTrue(
            VaultSettingsView.shouldDisableDuressForSharing(
                isSharedVault: true,
                activeShareCount: 0,
                activeUploadCount: 0
            )
        )
    }

    func testDuressDisabledForActiveShares() {
        XCTAssertTrue(
            VaultSettingsView.shouldDisableDuressForSharing(
                isSharedVault: false,
                activeShareCount: 1,
                activeUploadCount: 0
            )
        )
    }

    func testDuressDisabledForActiveUploads() {
        XCTAssertTrue(
            VaultSettingsView.shouldDisableDuressForSharing(
                isSharedVault: false,
                activeShareCount: 0,
                activeUploadCount: 1
            )
        )
    }

    func testIdleTimerDisabledOnlyWhenShareScreenVisibleAndUploadRunning() {
        XCTAssertTrue(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [makeUploadJob(status: .uploading)]
            )
        )
    }

    func testIdleTimerNotDisabledWhenShareScreenNotVisible() {
        XCTAssertFalse(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: false,
                uploadJobs: [makeUploadJob(status: .uploading)]
            )
        )
    }

    func testHasPendingUploadDoesNotDeleteJobDirectoryWithoutStateFile() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pendingRoot = documents.appendingPathComponent("pending_uploads", isDirectory: true)
        let jobId = "test-no-state-\(UUID().uuidString.lowercased())"
        let jobDir = pendingRoot.appendingPathComponent(jobId, isDirectory: true)
        let svdfURL = jobDir.appendingPathComponent("svdf_data.bin")

        try FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)
        try Data([0x01, 0x02, 0x03]).write(to: svdfURL, options: .atomic)

        defer { try? FileManager.default.removeItem(at: jobDir) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: jobDir.path))
        _ = await MainActor.run { ShareUploadManager.shared.hasPendingUpload }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: jobDir.path),
            "Scanning pending uploads should not delete in-progress directories without state.json"
        )
    }

    private func assert(_ mode: ShareVaultView.ViewMode, matches expected: ShareVaultView.ViewMode) {
        switch (mode, expected) {
        case (.loading, .loading),
             (.newShare, .newShare),
             (.manageShares, .manageShares):
            return
        default:
            XCTFail("Mode mismatch: got \(String(describing: mode)), expected \(String(describing: expected))")
        }
    }

    private func makeUploadJob(status: ShareUploadManager.UploadJobStatus) -> ShareUploadManager.UploadJob {
        ShareUploadManager.UploadJob(
            id: UUID().uuidString,
            ownerFingerprint: "owner",
            createdAt: Date(),
            shareVaultId: "share",
            phrase: nil,
            status: status,
            progress: 0,
            total: 100,
            message: "",
            errorMessage: nil
        )
    }
}
