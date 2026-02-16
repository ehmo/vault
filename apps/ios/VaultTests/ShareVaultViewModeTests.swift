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

    func testShouldDisplayUploadJobHidesCompleteAndCancelled() {
        XCTAssertFalse(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .complete)))
        XCTAssertFalse(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .cancelled)))
    }

    func testShouldDisplayUploadJobKeepsFailedAndRunning() {
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .failed)))
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .uploading)))
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
