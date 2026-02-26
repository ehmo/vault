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

    // MARK: - PendingUploadState Codable backward compatibility

    func testPendingUploadStateDecodesWithoutPhraseField() throws {
        // Simulates decoding a legacy pending state that predates the phrase field
        let json = """
        {
            "jobId": "legacy-job-1",
            "shareVaultId": "sv-legacy",
            "phraseVaultId": "pv-legacy",
            "shareKeyData": "AQID",
            "policy": { "allowScreenshots": false, "allowDownloads": true },
            "ownerFingerprint": "fp123",
            "totalChunks": 10,
            "sharedFileIds": ["f1", "f2"],
            "svdfManifest": [],
            "createdAt": 1000,
            "uploadFinished": false,
            "lastProgress": 50,
            "lastMessage": "Uploading..."
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(ShareUploadManager.PendingUploadState.self, from: json)

        XCTAssertEqual(state.jobId, "legacy-job-1")
        XCTAssertEqual(state.shareVaultId, "sv-legacy")
        XCTAssertNil(state.phrase, "Legacy state without phrase field should decode as nil")
        XCTAssertEqual(state.totalChunks, 10)
        XCTAssertEqual(state.lastProgress, 50)
    }

    func testPendingUploadStateRoundTripWithPhrase() throws {
        let state = ShareUploadManager.PendingUploadState(
            jobId: "job-with-phrase",
            shareVaultId: "sv-phrase",
            phraseVaultId: "pv-phrase",
            shareKeyData: Data([0x01, 0x02, 0x03]),
            policy: VaultStorage.SharePolicy(maxOpens: 5),
            ownerFingerprint: "fp-test",
            totalChunks: 20,
            sharedFileIds: ["a", "b", "c"],
            svdfManifest: [],
            createdAt: Date(timeIntervalSince1970: 5000),
            uploadFinished: false,
            lastProgress: 75,
            lastMessage: "Almost there...",
            phrase: "alpha bravo charlie"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(ShareUploadManager.PendingUploadState.self, from: data)

        XCTAssertEqual(decoded.phrase, "alpha bravo charlie")
        XCTAssertEqual(decoded.jobId, "job-with-phrase")
        XCTAssertEqual(decoded.shareVaultId, "sv-phrase")
        XCTAssertEqual(decoded.lastProgress, 75)
    }

    func testPendingUploadStateDecodesWithNilPhrase() throws {
        let state = ShareUploadManager.PendingUploadState(
            jobId: "job-nil-phrase",
            shareVaultId: "sv-nil",
            phraseVaultId: "pv-nil",
            shareKeyData: Data([0x04]),
            policy: VaultStorage.SharePolicy(),
            ownerFingerprint: "fp-nil",
            totalChunks: 1,
            sharedFileIds: [],
            svdfManifest: [],
            createdAt: Date(timeIntervalSince1970: 0),
            uploadFinished: true,
            lastProgress: 100,
            lastMessage: "Done",
            phrase: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(ShareUploadManager.PendingUploadState.self, from: data)

        XCTAssertNil(decoded.phrase)
        XCTAssertTrue(decoded.uploadFinished)
    }

    // MARK: - ShareRecord reconciliation patterns

    func testReconcileConsumedSharesRemovesConsumedEntries() {
        // Simulates the reconcile logic: consumed shares should be removed
        var shares = [
            makeShareRecord(id: "sv-1", phrase: "phrase-1"),
            makeShareRecord(id: "sv-2", phrase: "phrase-2"),
            makeShareRecord(id: "sv-3", phrase: "phrase-3"),
        ]
        let consumedIds: Set<String> = ["sv-2"]

        shares.removeAll { consumedIds.contains($0.id) }

        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(shares.map(\.id), ["sv-1", "sv-3"])
    }

    func testReconcileClaimedSharesClearsPhraseAndSetsFlag() {
        // Simulates the reconcile logic: claimed shares get isClaimed=true, phrase=nil
        var shares = [
            makeShareRecord(id: "sv-1", phrase: "phrase-1"),
            makeShareRecord(id: "sv-2", phrase: "phrase-2"),
        ]
        let claimedIds: Set<String> = ["sv-1"]

        for i in shares.indices {
            if claimedIds.contains(shares[i].id) {
                shares[i].isClaimed = true
                shares[i].phrase = nil
            }
        }

        XCTAssertTrue(shares[0].isClaimed == true)
        XCTAssertNil(shares[0].phrase, "Phrase should be cleared after claim")
        XCTAssertNil(shares[1].isClaimed, "Unclaimed share should not be modified")
        XCTAssertEqual(shares[1].phrase, "phrase-2")
    }

    func testReconcileHandlesBothConsumedAndClaimedSimultaneously() {
        // One share consumed, another claimed, third untouched
        var shares = [
            makeShareRecord(id: "sv-1", phrase: "p1"),
            makeShareRecord(id: "sv-2", phrase: "p2"),
            makeShareRecord(id: "sv-3", phrase: "p3"),
        ]
        let consumedIds: Set<String> = ["sv-1"]
        let claimedIds: Set<String> = ["sv-2"]

        shares.removeAll { consumedIds.contains($0.id) }
        for i in shares.indices {
            if claimedIds.contains(shares[i].id) {
                shares[i].isClaimed = true
                shares[i].phrase = nil
            }
        }

        XCTAssertEqual(shares.count, 2, "Consumed share should be removed")
        XCTAssertEqual(shares[0].id, "sv-2")
        XCTAssertTrue(shares[0].isClaimed == true, "sv-2 should be claimed")
        XCTAssertNil(shares[0].phrase, "sv-2 phrase should be cleared")
        XCTAssertEqual(shares[1].id, "sv-3")
        XCTAssertNil(shares[1].isClaimed, "sv-3 should be untouched")
        XCTAssertEqual(shares[1].phrase, "p3")
    }

    func testReconcileWithOverlappingConsumedAndClaimed() {
        // A share that is both consumed AND claimed — consumed takes precedence (removes it)
        var shares = [
            makeShareRecord(id: "sv-1", phrase: "p1"),
        ]
        let consumedIds: Set<String> = ["sv-1"]
        let claimedIds: Set<String> = ["sv-1"]

        shares.removeAll { consumedIds.contains($0.id) }
        for i in shares.indices {
            if claimedIds.contains(shares[i].id) {
                shares[i].isClaimed = true
                shares[i].phrase = nil
            }
        }

        XCTAssertTrue(shares.isEmpty, "Consumed-and-claimed share should be removed entirely")
    }

    // MARK: - Share phrase visibility conditions

    func testPhraseVisibleWhenNotClaimedAndPhrasePresent() {
        let share = makeShareRecord(id: "sv-1", phrase: "test phrase", isClaimed: false)
        let shouldShowPhrase = share.isClaimed != true && share.phrase != nil
        XCTAssertTrue(shouldShowPhrase)
    }

    func testPhraseHiddenWhenClaimed() {
        var share = makeShareRecord(id: "sv-1", phrase: nil)
        share.isClaimed = true
        let shouldShowPhrase = share.isClaimed != true && share.phrase != nil
        XCTAssertFalse(shouldShowPhrase)
    }

    func testPhraseHiddenWhenNilPhrase() {
        let share = makeShareRecord(id: "sv-1", phrase: nil, isClaimed: nil)
        let shouldShowPhrase = share.isClaimed != true && share.phrase != nil
        XCTAssertFalse(shouldShowPhrase)
    }

    func testPhraseVisibleForLegacyRecordWithPhraseButNoClaimedStatus() {
        // Legacy record: isClaimed is nil (not set), but phrase was added
        let share = makeShareRecord(id: "sv-1", phrase: "legacy phrase", isClaimed: nil)
        let shouldShowPhrase = share.isClaimed != true && share.phrase != nil
        XCTAssertTrue(shouldShowPhrase, "nil isClaimed should not hide the phrase")
    }

    // MARK: - UploadJob status raw value stability (Codable)

    func testUploadJobStatusRawValues() {
        // These raw values are persisted via Codable — changing them breaks backward compat
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.preparing.rawValue, "preparing")
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.uploading.rawValue, "uploading")
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.finalizing.rawValue, "finalizing")
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.paused.rawValue, "paused")
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.failed.rawValue, "failed")
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.complete.rawValue, "complete")
        XCTAssertEqual(ShareUploadManager.UploadJobStatus.cancelled.rawValue, "cancelled")
    }

    func testUploadJobStatusCodableRoundTrip() throws {
        let statuses: [ShareUploadManager.UploadJobStatus] = [
            .preparing, .uploading, .finalizing, .paused, .failed, .complete, .cancelled
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in statuses {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(ShareUploadManager.UploadJobStatus.self, from: data)
            XCTAssertEqual(decoded, status, "Round-trip failed for \(status.rawValue)")
        }
    }

    // MARK: - UploadJob phrase propagation

    func testUploadJobStoresPhrase() {
        let job = makeUploadJob(status: .preparing, phrase: "test phrase here")
        XCTAssertEqual(job.phrase, "test phrase here")
    }

    func testUploadJobPhraseCanBeNil() {
        let job = makeUploadJob(status: .paused, phrase: nil)
        XCTAssertNil(job.phrase)
    }

    // MARK: - Policy description ordering consistency

    func testPolicyDescriptionItemsAlwaysInSameOrder() {
        // Order should be: No exports → maxOpens → Expires
        let date = DateComponents(calendar: .current, year: 2027, month: 1, day: 1).date!
        let policy = VaultStorage.SharePolicy(
            expiresAt: date,
            maxOpens: 3,
            allowDownloads: false
        )
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], "No exports")
        XCTAssertEqual(items[1], "3 opens max")
        XCTAssertTrue(items[2].hasPrefix("Expires "))
    }

    func testPolicyDescriptionMaxOpensZero() {
        // Edge case: maxOpens = 0
        let policy = VaultStorage.SharePolicy(maxOpens: 0)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertEqual(items, ["0 opens max"])
    }

    func testPolicyDescriptionOnlyScreenshotsDoesNotProduceItem() {
        // allowScreenshots isn't displayed in policy description
        let policy = VaultStorage.SharePolicy(allowScreenshots: true)
        let items = ShareVaultView.policyDescriptionItems(policy)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - resolveMode: sequential transitions simulate real usage

    func testResolveModeSequentialTransitionSimulation() {
        // Simulate: loading → manageShares → (user taps new share) → newShare → uploading → phraseReveal → manageShares
        var mode: ShareVaultView.ViewMode = .loading

        // 1. Initialization finds existing shares
        mode = ShareVaultView.resolveMode(currentMode: mode, hasShareData: true)
        assert(mode, matches: .manageShares)

        // 2. User manually enters newShare (not driven by resolveMode)
        mode = .newShare
        mode = ShareVaultView.resolveMode(currentMode: mode, hasShareData: true)
        assert(mode, matches: .newShare) // sticky

        // 3. User starts upload (set explicitly)
        mode = .uploading(jobId: "j1", phrase: "test phrase", shareVaultId: "sv-1")
        mode = ShareVaultView.resolveMode(currentMode: mode, hasShareData: true)
        assertUploading(mode) // preserved

        // 4. Upload completes (set explicitly by polling)
        mode = .phraseReveal(phrase: "test phrase", shareVaultId: "sv-1")
        mode = ShareVaultView.resolveMode(currentMode: mode, hasShareData: true)
        assertPhraseReveal(mode) // preserved

        // 5. User taps Done (set explicitly)
        mode = .manageShares
        mode = ShareVaultView.resolveMode(currentMode: mode, hasShareData: true)
        assert(mode, matches: .manageShares)
    }

    // MARK: - resolveMode: uploading/phraseReveal carry data through

    func testResolveModePreservesUploadingAssociatedValues() {
        let mode = ShareVaultView.resolveMode(
            currentMode: .uploading(jobId: "job-42", phrase: "india juliet kilo", shareVaultId: "sv-42"),
            hasShareData: false
        )
        if case .uploading(let jid, let p, let sv) = mode {
            XCTAssertEqual(jid, "job-42")
            XCTAssertEqual(p, "india juliet kilo")
            XCTAssertEqual(sv, "sv-42")
        } else {
            XCTFail("Expected .uploading mode with associated values")
        }
    }

    func testResolveModePreservesPhraseRevealAssociatedValues() {
        let mode = ShareVaultView.resolveMode(
            currentMode: .phraseReveal(phrase: "lima mike november", shareVaultId: "sv-99"),
            hasShareData: false
        )
        if case .phraseReveal(let p, let sv) = mode {
            XCTAssertEqual(p, "lima mike november")
            XCTAssertEqual(sv, "sv-99")
        } else {
            XCTFail("Expected .phraseReveal mode with associated values")
        }
    }

    // MARK: - ShareRecord sorting (newest first)

    func testShareRecordsSortNewestFirst() {
        let now = Date()
        let shares = [
            makeShareRecord(id: "sv-old", createdAt: now.addingTimeInterval(-3600)),
            makeShareRecord(id: "sv-new", createdAt: now),
            makeShareRecord(id: "sv-mid", createdAt: now.addingTimeInterval(-1800)),
        ]
        let sorted = shares.sorted { $0.createdAt > $1.createdAt }
        XCTAssertEqual(sorted.map(\.id), ["sv-new", "sv-mid", "sv-old"])
    }

    // MARK: - ShareRecord minimal JSON (all optionals absent)

    func testShareRecordDecodesMinimalJSON() throws {
        let json = """
        {
            "id": "sv-minimal",
            "createdAt": 0,
            "policy": { "allowScreenshots": false, "allowDownloads": true }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(VaultStorage.ShareRecord.self, from: json)

        XCTAssertEqual(record.id, "sv-minimal")
        XCTAssertNil(record.phrase)
        XCTAssertNil(record.isClaimed)
        XCTAssertNil(record.lastSyncedAt)
        XCTAssertNil(record.shareKeyData)
        XCTAssertNil(record.syncSequence)
    }

    // MARK: - shouldDisplayUploadJob for all statuses exhaustively

    func testShouldDisplayUploadJobExhaustive() {
        let allStatuses: [ShareUploadManager.UploadJobStatus] = [
            .preparing, .uploading, .finalizing, .paused, .failed, .complete, .cancelled
        ]
        let expectedVisible: [ShareUploadManager.UploadJobStatus: Bool] = [
            .preparing: true,
            .uploading: true,
            .finalizing: true,
            .paused: true,
            .failed: true,
            .complete: false,
            .cancelled: false,
        ]
        for status in allStatuses {
            let job = makeUploadJob(status: status)
            let visible = ShareVaultView.shouldDisplayUploadJob(job)
            XCTAssertEqual(
                visible, expectedVisible[status],
                "shouldDisplayUploadJob mismatch for \(status.rawValue)"
            )
        }
    }

    // MARK: - UploadJob canResume exhaustive

    func testUploadJobCanResumeExhaustive() {
        let expected: [ShareUploadManager.UploadJobStatus: Bool] = [
            .preparing: false,
            .uploading: false,
            .finalizing: false,
            .paused: true,
            .failed: true,
            .complete: false,
            .cancelled: false,
        ]
        for (status, expectedResult) in expected {
            let job = makeUploadJob(status: status)
            XCTAssertEqual(job.canResume, expectedResult, "canResume mismatch for \(status.rawValue)")
        }
    }

    // MARK: - UploadJob canTerminate exhaustive

    func testUploadJobCanTerminateExhaustive() {
        let expected: [ShareUploadManager.UploadJobStatus: Bool] = [
            .preparing: true,
            .uploading: true,
            .finalizing: true,
            .paused: true,
            .failed: true,
            .complete: false,
            .cancelled: false,
        ]
        for (status, expectedResult) in expected {
            let job = makeUploadJob(status: status)
            XCTAssertEqual(job.canTerminate, expectedResult, "canTerminate mismatch for \(status.rawValue)")
        }
    }

    // MARK: - SharePolicy Codable round trip

    func testSharePolicyCodableRoundTrip() throws {
        let date = DateComponents(calendar: .current, year: 2026, month: 12, day: 25).date!
        let policy = VaultStorage.SharePolicy(
            expiresAt: date,
            maxOpens: 42,
            allowScreenshots: true,
            allowDownloads: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(policy)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(VaultStorage.SharePolicy.self, from: data)

        XCTAssertEqual(decoded, policy)
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

    private func makeShareRecord(
        id: String,
        phrase: String? = nil,
        isClaimed: Bool? = nil,
        createdAt: Date = Date()
    ) -> VaultStorage.ShareRecord {
        var record = VaultStorage.ShareRecord(
            id: id,
            createdAt: createdAt,
            policy: VaultStorage.SharePolicy(),
            lastSyncedAt: nil,
            shareKeyData: nil,
            syncSequence: nil
        )
        record.phrase = phrase
        record.isClaimed = isClaimed
        return record
    }
}
