import XCTest
import CloudKit
@testable import Vault

final class ShareVaultViewModeTests: XCTestCase {

    // MARK: - resolveMode: Loading transitions

    func testResolveModeChangesLoadingToManageWhenDataExists() {
        let mode = ShareVaultView.resolveMode(currentMode: .loading, hasShareData: true)
        assert(mode, matches: .manageShares)
    }

    func testResolveModeChangesLoadingToNewShareWhenNoData() {
        let mode = ShareVaultView.resolveMode(currentMode: .loading, hasShareData: false)
        assert(mode, matches: .newShare)
    }

    // MARK: - resolveMode: newShare is sticky

    func testResolveModeKeepsManualNewShareWhenShareDataExists() {
        let mode = ShareVaultView.resolveMode(currentMode: .newShare, hasShareData: true)
        assert(mode, matches: .newShare)
    }

    func testResolveModeKeepsManualNewShareWhenShareDataDisappears() {
        let mode = ShareVaultView.resolveMode(currentMode: .newShare, hasShareData: false)
        assert(mode, matches: .newShare)
    }

    // MARK: - resolveMode: manageShares transitions

    func testResolveModeChangesManageToNewWhenDataDisappears() {
        let mode = ShareVaultView.resolveMode(currentMode: .manageShares, hasShareData: false)
        assert(mode, matches: .newShare)
    }

    func testResolveModeKeepsManageWhenDataExists() {
        let mode = ShareVaultView.resolveMode(currentMode: .manageShares, hasShareData: true)
        assert(mode, matches: .manageShares)
    }

    // MARK: - resolveMode: Terminal states preserved

    func testResolveModePreservesErrorState() {
        let mode = ShareVaultView.resolveMode(currentMode: .error("boom"), hasShareData: true)
        if case .error(let message) = mode {
            XCTAssertEqual(message, "boom")
        } else {
            XCTFail("Expected .error mode")
        }
    }

    func testResolveModePreservesErrorStateWhenNoData() {
        let mode = ShareVaultView.resolveMode(currentMode: .error("err"), hasShareData: false)
        if case .error(let message) = mode {
            XCTAssertEqual(message, "err")
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

    func testResolveModePreservesICloudUnavailableWhenNoData() {
        let mode = ShareVaultView.resolveMode(currentMode: .iCloudUnavailable(.restricted), hasShareData: false)
        if case .iCloudUnavailable(let status) = mode {
            XCTAssertEqual(status, .restricted)
        } else {
            XCTFail("Expected .iCloudUnavailable mode")
        }
    }

    // MARK: - resolveMode: Uploading is preserved (explicit transitions only)

    func testResolveModePreservesUploadingWithData() {
        let mode = ShareVaultView.resolveMode(
            currentMode: .uploading(jobId: "j1", phrase: "alpha bravo", shareVaultId: "sv-1"),
            hasShareData: true
        )
        if case .uploading(let jobId, let phrase, let svId) = mode {
            XCTAssertEqual(jobId, "j1")
            XCTAssertEqual(phrase, "alpha bravo")
            XCTAssertEqual(svId, "sv-1")
        } else {
            XCTFail("Expected .uploading mode, got \(mode)")
        }
    }

    func testResolveModePreservesUploadingWithoutData() {
        // Even if share data disappears (e.g. revoke during upload), uploading stays
        let mode = ShareVaultView.resolveMode(
            currentMode: .uploading(jobId: "j2", phrase: "charlie delta", shareVaultId: "sv-2"),
            hasShareData: false
        )
        if case .uploading(let jobId, _, _) = mode {
            XCTAssertEqual(jobId, "j2")
        } else {
            XCTFail("Expected .uploading mode, got \(mode)")
        }
    }

    // MARK: - resolveMode: PhraseReveal is preserved (explicit transitions only)

    func testResolveModePreservesPhraseRevealWithData() {
        let mode = ShareVaultView.resolveMode(
            currentMode: .phraseReveal(phrase: "echo foxtrot", shareVaultId: "sv-3"),
            hasShareData: true
        )
        if case .phraseReveal(let phrase, let svId) = mode {
            XCTAssertEqual(phrase, "echo foxtrot")
            XCTAssertEqual(svId, "sv-3")
        } else {
            XCTFail("Expected .phraseReveal mode, got \(mode)")
        }
    }

    func testResolveModePreservesPhraseRevealWithoutData() {
        let mode = ShareVaultView.resolveMode(
            currentMode: .phraseReveal(phrase: "golf hotel", shareVaultId: "sv-4"),
            hasShareData: false
        )
        if case .phraseReveal(let phrase, _) = mode {
            XCTAssertEqual(phrase, "golf hotel")
        } else {
            XCTFail("Expected .phraseReveal mode, got \(mode)")
        }
    }

    // MARK: - policyDescriptionItems

    func testPolicyDescriptionNoExports() {
        let policy = VaultStorage.SharePolicy(allowDownloads: false)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items, ["No exports"])
    }

    func testPolicyDescriptionMaxOpens() {
        let policy = VaultStorage.SharePolicy(maxOpens: 10)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items, ["10 opens max"])
    }

    func testPolicyDescriptionMaxOpensOne() {
        let policy = VaultStorage.SharePolicy(maxOpens: 1)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items, ["1 opens max"])
    }

    func testPolicyDescriptionExpiration() {
        let date = DateComponents(calendar: .current, year: 2026, month: 3, day: 15).date!
        let policy = VaultStorage.SharePolicy(expiresAt: date)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].hasPrefix("Expires "))
        XCTAssertTrue(items[0].contains("Mar"))
        XCTAssertTrue(items[0].contains("15"))
    }

    func testPolicyDescriptionAllRestrictions() {
        let date = DateComponents(calendar: .current, year: 2026, month: 6, day: 1).date!
        let policy = VaultStorage.SharePolicy(
            expiresAt: date,
            maxOpens: 5,
            allowDownloads: false
        )
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], "No exports")
        XCTAssertEqual(items[1], "5 opens max")
        XCTAssertTrue(items[2].hasPrefix("Expires "))
    }

    func testPolicyDescriptionDefaultPolicyIsEmpty() {
        let policy = VaultStorage.SharePolicy()
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertTrue(items.isEmpty, "Default policy (allowDownloads=true, no limits) should produce no items")
    }

    func testPolicyDescriptionAllowDownloadsProducesNoItem() {
        let policy = VaultStorage.SharePolicy(allowDownloads: true)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertFalse(items.contains("No exports"))
    }

    // MARK: - shouldDisplayUploadJob

    func testShouldDisplayUploadJobHidesCompleteAndCancelled() {
        XCTAssertFalse(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .complete)))
        XCTAssertFalse(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .cancelled)))
    }

    func testShouldDisplayUploadJobShowsRunningStates() {
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .preparing)))
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .uploading)))
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .finalizing)))
    }

    func testShouldDisplayUploadJobShowsFailedAndPaused() {
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .failed)))
        XCTAssertTrue(ShareVaultView.shouldDisplayUploadJob(makeUploadJob(status: .paused)))
    }

    // MARK: - Idle Timer Policy

    func testIdleTimerDisabledOnlyWhenShareScreenVisibleAndUploadRunning() {
        XCTAssertTrue(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [makeUploadJob(status: .uploading)]
            )
        )
    }

    func testIdleTimerDisabledForPreparingJobs() {
        XCTAssertTrue(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [makeUploadJob(status: .preparing)]
            )
        )
    }

    func testIdleTimerDisabledForFinalizingJobs() {
        XCTAssertTrue(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [makeUploadJob(status: .finalizing)]
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

    func testIdleTimerNotDisabledWhenNoRunningJobs() {
        XCTAssertFalse(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [makeUploadJob(status: .paused)]
            )
        )
    }

    func testIdleTimerNotDisabledForFailedJobs() {
        XCTAssertFalse(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [makeUploadJob(status: .failed)]
            )
        )
    }

    func testIdleTimerNotDisabledWithEmptyJobs() {
        XCTAssertFalse(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: []
            )
        )
    }

    func testIdleTimerDisabledIfAnyJobRunningAmongMixed() {
        XCTAssertTrue(
            ShareVaultView.shouldDisableIdleTimer(
                isShareScreenVisible: true,
                uploadJobs: [
                    makeUploadJob(status: .failed),
                    makeUploadJob(status: .uploading),
                    makeUploadJob(status: .paused),
                ]
            )
        )
    }

    // MARK: - Duress Sharing Interaction

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

    // MARK: - ShareRecord Codable backward compatibility

    func testShareRecordDecodesWithoutPhraseAndIsClaimed() throws {
        // Simulates decoding an existing index that doesn't have the new fields
        let json = """
        {
            "id": "sv-test-123",
            "createdAt": 0,
            "policy": {
                "allowScreenshots": false,
                "allowDownloads": true
            },
            "syncSequence": 1
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(VaultStorage.ShareRecord.self, from: json)

        XCTAssertEqual(record.id, "sv-test-123")
        XCTAssertNil(record.phrase, "phrase should be nil for old records")
        XCTAssertNil(record.isClaimed, "isClaimed should be nil for old records")
        XCTAssertNil(record.lastSyncedAt)
        XCTAssertNil(record.shareKeyData)
    }

    func testShareRecordEncodesAndDecodesNewFields() throws {
        var record = VaultStorage.ShareRecord(
            id: "sv-round-trip",
            createdAt: Date(timeIntervalSince1970: 1000),
            policy: VaultStorage.SharePolicy(maxOpens: 5, allowDownloads: false),
            lastSyncedAt: nil,
            shareKeyData: Data([0xAA, 0xBB]),
            syncSequence: 2
        )
        record.phrase = "alpha bravo charlie"
        record.isClaimed = false

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(VaultStorage.ShareRecord.self, from: data)

        XCTAssertEqual(decoded.id, "sv-round-trip")
        XCTAssertEqual(decoded.phrase, "alpha bravo charlie")
        XCTAssertEqual(decoded.isClaimed, false)
        XCTAssertEqual(decoded.policy.maxOpens, 5)
        XCTAssertEqual(decoded.policy.allowDownloads, false)
        XCTAssertEqual(decoded.shareKeyData, Data([0xAA, 0xBB]))
        XCTAssertEqual(decoded.syncSequence, 2)
    }

    func testShareRecordClaimedTrueRoundTrip() throws {
        var record = VaultStorage.ShareRecord(
            id: "sv-claimed",
            createdAt: Date(timeIntervalSince1970: 2000),
            policy: VaultStorage.SharePolicy(),
            lastSyncedAt: nil,
            shareKeyData: nil,
            syncSequence: nil
        )
        record.isClaimed = true
        record.phrase = nil // phrase cleared after claim

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(VaultStorage.ShareRecord.self, from: data)

        XCTAssertEqual(decoded.isClaimed, true)
        XCTAssertNil(decoded.phrase)
    }

    // MARK: - resolveMode exhaustive: every mode × hasShareData

    func testResolveModeExhaustiveMatrix() {
        // (currentMode, hasShareData) -> expectedMode
        // This ensures no mode+data combination produces an unexpected result
        let uploading: ShareVaultView.ViewMode = .uploading(jobId: "j", phrase: "p", shareVaultId: "s")
        let phraseReveal: ShareVaultView.ViewMode = .phraseReveal(phrase: "p", shareVaultId: "s")

        // loading
        assert(ShareVaultView.resolveMode(currentMode: .loading, hasShareData: true), matches: .manageShares)
        assert(ShareVaultView.resolveMode(currentMode: .loading, hasShareData: false), matches: .newShare)

        // newShare (sticky)
        assert(ShareVaultView.resolveMode(currentMode: .newShare, hasShareData: true), matches: .newShare)
        assert(ShareVaultView.resolveMode(currentMode: .newShare, hasShareData: false), matches: .newShare)

        // manageShares
        assert(ShareVaultView.resolveMode(currentMode: .manageShares, hasShareData: true), matches: .manageShares)
        assert(ShareVaultView.resolveMode(currentMode: .manageShares, hasShareData: false), matches: .newShare)

        // uploading (preserved regardless)
        assertUploading(ShareVaultView.resolveMode(currentMode: uploading, hasShareData: true))
        assertUploading(ShareVaultView.resolveMode(currentMode: uploading, hasShareData: false))

        // phraseReveal (preserved regardless)
        assertPhraseReveal(ShareVaultView.resolveMode(currentMode: phraseReveal, hasShareData: true))
        assertPhraseReveal(ShareVaultView.resolveMode(currentMode: phraseReveal, hasShareData: false))

        // error (preserved regardless)
        assertError(ShareVaultView.resolveMode(currentMode: .error("x"), hasShareData: true))
        assertError(ShareVaultView.resolveMode(currentMode: .error("x"), hasShareData: false))

        // iCloudUnavailable (preserved regardless)
        assertICloudUnavailable(ShareVaultView.resolveMode(currentMode: .iCloudUnavailable(.noAccount), hasShareData: true))
        assertICloudUnavailable(ShareVaultView.resolveMode(currentMode: .iCloudUnavailable(.noAccount), hasShareData: false))
    }

    // MARK: - UploadJob status helpers

    func testUploadJobIsRunning() {
        XCTAssertTrue(ShareUploadManager.UploadJobStatus.preparing.isRunning)
        XCTAssertTrue(ShareUploadManager.UploadJobStatus.uploading.isRunning)
        XCTAssertTrue(ShareUploadManager.UploadJobStatus.finalizing.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.paused.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.failed.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.complete.isRunning)
        XCTAssertFalse(ShareUploadManager.UploadJobStatus.cancelled.isRunning)
    }

    func testUploadJobCanResume() {
        let failed = makeUploadJob(status: .failed)
        let paused = makeUploadJob(status: .paused)
        let uploading = makeUploadJob(status: .uploading)
        let complete = makeUploadJob(status: .complete)

        XCTAssertTrue(failed.canResume)
        XCTAssertTrue(paused.canResume)
        XCTAssertFalse(uploading.canResume)
        XCTAssertFalse(complete.canResume)
    }

    func testUploadJobCanTerminate() {
        let uploading = makeUploadJob(status: .uploading)
        let paused = makeUploadJob(status: .paused)
        let failed = makeUploadJob(status: .failed)
        let complete = makeUploadJob(status: .complete)
        let cancelled = makeUploadJob(status: .cancelled)

        XCTAssertTrue(uploading.canTerminate)
        XCTAssertTrue(paused.canTerminate)
        XCTAssertTrue(failed.canTerminate)
        XCTAssertFalse(complete.canTerminate)
        XCTAssertFalse(cancelled.canTerminate)
    }

    // MARK: - Pending upload directory safety

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

    // MARK: - SharePolicy Codable

    func testSharePolicyDefaultValues() {
        let policy = VaultStorage.SharePolicy()
        XCTAssertNil(policy.expiresAt)
        XCTAssertNil(policy.maxOpens)
        XCTAssertFalse(policy.allowScreenshots)
        XCTAssertTrue(policy.allowDownloads)
    }

    func testSharePolicyEquatable() {
        let a = VaultStorage.SharePolicy(expiresAt: nil, maxOpens: 10, allowScreenshots: false, allowDownloads: true)
        let b = VaultStorage.SharePolicy(expiresAt: nil, maxOpens: 10, allowScreenshots: false, allowDownloads: true)
        let c = VaultStorage.SharePolicy(expiresAt: nil, maxOpens: 5, allowScreenshots: false, allowDownloads: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Helpers

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

    private func assertUploading(_ mode: ShareVaultView.ViewMode, file: StaticString = #filePath, line: UInt = #line) {
        if case .uploading = mode { return }
        XCTFail("Expected .uploading, got \(mode)", file: file, line: line)
    }

    private func assertPhraseReveal(_ mode: ShareVaultView.ViewMode, file: StaticString = #filePath, line: UInt = #line) {
        if case .phraseReveal = mode { return }
        XCTFail("Expected .phraseReveal, got \(mode)", file: file, line: line)
    }

    private func assertError(_ mode: ShareVaultView.ViewMode, file: StaticString = #filePath, line: UInt = #line) {
        if case .error = mode { return }
        XCTFail("Expected .error, got \(mode)", file: file, line: line)
    }

    private func assertICloudUnavailable(_ mode: ShareVaultView.ViewMode, file: StaticString = #filePath, line: UInt = #line) {
        if case .iCloudUnavailable = mode { return }
        XCTFail("Expected .iCloudUnavailable, got \(mode)", file: file, line: line)
    }

    private func makeUploadJob(
        status: ShareUploadManager.UploadJobStatus,
        shareVaultId: String = "share",
        phrase: String? = nil
    ) -> ShareUploadManager.UploadJob {
        ShareUploadManager.UploadJob(
            id: UUID().uuidString,
            ownerFingerprint: "owner",
            createdAt: Date(),
            shareVaultId: shareVaultId,
            phrase: phrase,
            status: status,
            progress: 0,
            total: 100,
            message: "",
            errorMessage: nil
        )
    }
}
