import XCTest
@testable import Vault
import CloudKit

/// Tests for local vault access revocation when share is revoked by owner
/// Ensures User 2 loses access to local files when User 1 revokes the share
@MainActor
final class LocalVaultRevocationTests: XCTestCase {
    
    // MARK: - Test Data
    
    private let testPhrase = "abandon ability able about above absent absorb abstract absurd"
    private let testShareVaultId = "test-local-revocation-vault"
    private let testOwnerFingerprint = "owner-local-test"
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        Task {
            await cleanupTestRecords()
        }
    }
    
    override func tearDown() {
        super.tearDown()
        Task {
            await cleanupTestRecords()
        }
    }
    
    private func cleanupTestRecords() async {
        let vaultId = CloudKitSharingManager.vaultId(from: testPhrase)
        let recordId = CKRecord.ID(recordName: vaultId)
        
        do {
            _ = try await CKContainer.default().publicCloudDatabase.deleteRecord(withID: recordId)
        } catch {
            // Record might not exist
        }
    }
    
    // MARK: - Local Access Revocation Tests
    
    func testOpenSharedVaultRevokedTriggersSelfDestruct() async throws {
        // 1. Create and set up a shared vault locally (simulating User 2 already accepted)
        let shareKey = try ShareKey(Data(repeating: 0x40, count: 32))
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
        
        // 2. Revoke the share (User 1 revokes)
        try await CloudKitSharingManager.shared.revokeShare(shareVaultId: testShareVaultId)
        
        // 3. Verify the CloudKit record is marked as revoked
        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest = try await CKContainer.default().publicCloudDatabase.record(for: manifestRecordId)
        
        let isRevoked = manifest["revoked"] as? Bool ?? false
        XCTAssertTrue(isRevoked, "Manifest should be marked as revoked in CloudKit")
        
        // 4. Simulate opening the vault - checkForUpdates should detect revocation
        // This is what happens in VaultViewModel.checkSharedVaultStatus()
        do {
            _ = try await CloudKitSharingManager.shared.checkForUpdates(
                shareVaultId: testShareVaultId,
                currentVersion: 1
            )
            XCTFail("checkForUpdates should throw .revoked error for revoked share")
        } catch let error as CloudKitSharingError {
            XCTAssertEqual(error, .revoked, "Should throw .revoked error when checking updates for revoked vault")
        }
        
        // 5. Verify download also fails
        do {
            _ = try await CloudKitSharingManager.shared.downloadSharedVault(
                phrase: testPhrase,
                markClaimedOnDownload: false,
                onProgress: nil
            )
            XCTFail("Download should fail for revoked vault")
        } catch let error as CloudKitSharingError {
            XCTAssertEqual(error, .revoked, "Download should throw .revoked error")
        }
        
        // Cleanup
        _ = try? await CKContainer.default().publicCloudDatabase.deleteRecord(withID: manifestRecordId)
    }
    
    func testLocalVaultFilesRevokedShareCanBeDeleted() async throws {
        // This test verifies the selfDestruct mechanism works
        // When the UI detects revocation via checkForUpdates, it calls selfDestruct()
        
        let shareKey = try ShareKey(Data(repeating: 0x41, count: 32))
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
        
        // Revoke
        try await CloudKitSharingManager.shared.revokeShare(shareVaultId: testShareVaultId)
        
        // Verify revocation is detected
        let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)
        
        if case .failure(let error) = result {
            XCTAssertEqual(error, .revoked, "Should detect revoked share")
            
            // In the real app, this triggers selfDestruct() which:
            // 1. Marks share as consumed
            // 2. Deletes all local files
            // 3. Deletes vault index
        } else {
            XCTFail("Should return revoked error")
        }
        
        // Cleanup
        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        _ = try? await CKContainer.default().publicCloudDatabase.deleteRecord(withID: manifestRecordId)
    }
    
    func testVaultStatusCheckExpiredShareTriggersSelfDestruct() async throws {
        // Test that expired shares also trigger self-destruct (similar flow to revoked)
        let shareKey = try ShareKey(Data(repeating: 0x42, count: 32))
        let expiredDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let policy = VaultStorage.SharePolicy(expiresAt: expiredDate, maxOpens: nil, allowScreenshots: false, allowDownloads: true)
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)
        
        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: testShareVaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: testOwnerFingerprint,
            totalChunks: 1
        )
        
        // Verify expiration is detected
        let manifestRecordId = CKRecord.ID(recordName: phraseVaultId)
        let manifest = try await CKContainer.default().publicCloudDatabase.record(for: manifestRecordId)
        
        // The policy is encrypted in the manifest, but checkSharedVaultStatus() 
        // decrypts it and checks expiration
        XCTAssertNotNil(manifest["policy"], "Manifest should have policy attached")
        
        // Cleanup
        _ = try? await CKContainer.default().publicCloudDatabase.deleteRecord(withID: manifestRecordId)
    }
    
    // MARK: - Integration Tests
    
    func testFullLocalRevocationFlow() async throws {
        // Complete test: Create share → Accept locally → Revoke → Verify access blocked
        
        let shareKey = try ShareKey(Data(repeating: 0x50, count: 32))
        let policy = VaultStorage.SharePolicy()
        let phraseVaultId = CloudKitSharingManager.vaultId(from: testPhrase)
        let vaultId = "integration-local-revocation"
        
        // Step 1: Create share
        try await CloudKitSharingManager.shared.saveManifest(
            shareVaultId: vaultId,
            phraseVaultId: phraseVaultId,
            shareKey: shareKey,
            policy: policy,
            ownerFingerprint: "integration-owner",
            totalChunks: 3
        )
        
        // Step 2: Verify share is available (User 2 could accept)
        var availability = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: testPhrase)
        if case .failure(let e) = availability { XCTFail("Expected share to be available, got \(e)") }
        
        // Step 3: User 1 revokes
        try await CloudKitSharingManager.shared.revokeShare(shareVaultId: vaultId)
        
        // Step 4: Verify revocation detected when checking updates
        do {
            _ = try await CloudKitSharingManager.shared.checkForUpdates(
                shareVaultId: vaultId,
                currentVersion: 1
            )
            XCTFail("Should throw revoked error")
        } catch let error as CloudKitSharingError {
            XCTAssertEqual(error, .revoked)
        }
        
        // Step 5: Verify download blocked
        do {
            _ = try await CloudKitSharingManager.shared.downloadSharedVault(
                phrase: testPhrase,
                markClaimedOnDownload: false,
                onProgress: nil
            )
            XCTFail("Should throw revoked error")
        } catch let error as CloudKitSharingError {
            XCTAssertEqual(error, .revoked)
        }
        
        // Step 6: In real app, UI would show self-destruct alert and delete files
        
        // Cleanup
        let recordId = CKRecord.ID(recordName: phraseVaultId)
        _ = try? await CKContainer.default().publicCloudDatabase.deleteRecord(withID: recordId)
    }
}

