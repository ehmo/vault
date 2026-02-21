import XCTest
@testable import Vault

// MARK: - Mock

@MainActor
final class MockSubscriptionClient: SubscriptionClient {
    var isPremium: Bool

    init(isPremium: Bool = false) {
        self.isPremium = isPremium
    }

    func canCreateVault(currentCount: Int) -> Bool {
        isPremium || currentCount < SubscriptionManager.maxFreeVaults
    }

    func canJoinSharedVault(currentCount: Int) -> Bool {
        isPremium || currentCount < SubscriptionManager.maxFreeSharedVaults
    }

    func canAddFile(currentFileCount: Int) -> Bool {
        isPremium || currentFileCount < SubscriptionManager.maxFreeFilesPerVault
    }

    func canCreateSharedVault() -> Bool { isPremium }
    func canCreateDuressVault() -> Bool { isPremium }
    func canSyncWithICloud() -> Bool { isPremium }
    func canExpandStorage() -> Bool { isPremium }
}

// MARK: - Tests

@MainActor
final class SubscriptionManagerTests: XCTestCase {

    // MARK: - Constants

    func testFreeTierLimits() {
        XCTAssertEqual(SubscriptionManager.maxFreeVaults, 5)
        XCTAssertEqual(SubscriptionManager.maxFreeSharedVaults, 10)
        XCTAssertEqual(SubscriptionManager.maxFreeFilesPerVault, 100)
    }

    func testProductIDs() {
        let ids = SubscriptionManager.productIDs
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains("monthly_pro"))
        XCTAssertTrue(ids.contains("yearly_pro"))
        XCTAssertTrue(ids.contains("lifetime"))
    }

    func testSubscriptionGroupID() {
        XCTAssertEqual(SubscriptionManager.subscriptionGroupID, "vaultaire_pro")
    }

    // MARK: - Free Tier Vault Limits

    func testFreeUser_canCreateVault_underLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertTrue(client.canCreateVault(currentCount: 0))
        XCTAssertTrue(client.canCreateVault(currentCount: 4))
    }

    func testFreeUser_canCreateVault_atLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertFalse(client.canCreateVault(currentCount: 5))
    }

    func testFreeUser_canCreateVault_overLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertFalse(client.canCreateVault(currentCount: 10))
    }

    // MARK: - Free Tier File Limits

    func testFreeUser_canAddFile_underLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertTrue(client.canAddFile(currentFileCount: 0))
        XCTAssertTrue(client.canAddFile(currentFileCount: 99))
    }

    func testFreeUser_canAddFile_atLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertFalse(client.canAddFile(currentFileCount: 100))
    }

    func testFreeUser_canAddFile_overLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertFalse(client.canAddFile(currentFileCount: 500))
    }

    // MARK: - Free Tier Shared Vault Limits

    func testFreeUser_canJoinSharedVault_underLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertTrue(client.canJoinSharedVault(currentCount: 0))
        XCTAssertTrue(client.canJoinSharedVault(currentCount: 9))
    }

    func testFreeUser_canJoinSharedVault_atLimit() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertFalse(client.canJoinSharedVault(currentCount: 10))
    }

    // MARK: - Premium-Only Features (Free User)

    func testFreeUser_premiumOnlyFeatures_denied() {
        let client = MockSubscriptionClient(isPremium: false)
        XCTAssertFalse(client.canCreateSharedVault())
        XCTAssertFalse(client.canCreateDuressVault())
        XCTAssertFalse(client.canSyncWithICloud())
        XCTAssertFalse(client.canExpandStorage())
    }

    // MARK: - Premium Unlocks All

    func testPremiumUser_canCreateVault_noLimit() {
        let client = MockSubscriptionClient(isPremium: true)
        XCTAssertTrue(client.canCreateVault(currentCount: 0))
        XCTAssertTrue(client.canCreateVault(currentCount: 100))
        XCTAssertTrue(client.canCreateVault(currentCount: 999))
    }

    func testPremiumUser_canAddFile_noLimit() {
        let client = MockSubscriptionClient(isPremium: true)
        XCTAssertTrue(client.canAddFile(currentFileCount: 0))
        XCTAssertTrue(client.canAddFile(currentFileCount: 1000))
        XCTAssertTrue(client.canAddFile(currentFileCount: 99999))
    }

    func testPremiumUser_canJoinSharedVault_noLimit() {
        let client = MockSubscriptionClient(isPremium: true)
        XCTAssertTrue(client.canJoinSharedVault(currentCount: 0))
        XCTAssertTrue(client.canJoinSharedVault(currentCount: 100))
    }

    func testPremiumUser_premiumOnlyFeatures_granted() {
        let client = MockSubscriptionClient(isPremium: true)
        XCTAssertTrue(client.canCreateSharedVault())
        XCTAssertTrue(client.canCreateDuressVault())
        XCTAssertTrue(client.canSyncWithICloud())
        XCTAssertTrue(client.canExpandStorage())
    }

    // MARK: - State Transitions

    func testUpgradeToFreeToPremium_unlocksFeatures() {
        let client = MockSubscriptionClient(isPremium: false)

        // Free tier — limited
        XCTAssertFalse(client.canCreateVault(currentCount: 5))
        XCTAssertFalse(client.canCreateSharedVault())

        // Upgrade
        client.isPremium = true

        // Premium — unlimited
        XCTAssertTrue(client.canCreateVault(currentCount: 5))
        XCTAssertTrue(client.canCreateSharedVault())
    }

    func testDowngradePremiumToFree_reinstatesLimits() {
        let client = MockSubscriptionClient(isPremium: true)

        // Premium — unlimited
        XCTAssertTrue(client.canCreateVault(currentCount: 100))
        XCTAssertTrue(client.canCreateDuressVault())

        // Downgrade (subscription expired)
        client.isPremium = false

        // Free tier — limited again
        XCTAssertFalse(client.canCreateVault(currentCount: 100))
        XCTAssertFalse(client.canCreateDuressVault())
    }

    // MARK: - Boundary Conditions

    func testFreeUser_vaultLimit_boundaryExact() {
        let client = MockSubscriptionClient(isPremium: false)
        // maxFreeVaults = 5, so count < 5 is OK, count >= 5 is blocked
        XCTAssertTrue(client.canCreateVault(currentCount: 4))
        XCTAssertFalse(client.canCreateVault(currentCount: 5))
    }

    func testFreeUser_fileLimit_boundaryExact() {
        let client = MockSubscriptionClient(isPremium: false)
        // maxFreeFilesPerVault = 100, so count < 100 is OK, count >= 100 is blocked
        XCTAssertTrue(client.canAddFile(currentFileCount: 99))
        XCTAssertFalse(client.canAddFile(currentFileCount: 100))
    }

    func testFreeUser_sharedVaultLimit_boundaryExact() {
        let client = MockSubscriptionClient(isPremium: false)
        // maxFreeSharedVaults = 10, so count < 10 is OK, count >= 10 is blocked
        XCTAssertTrue(client.canJoinSharedVault(currentCount: 9))
        XCTAssertFalse(client.canJoinSharedVault(currentCount: 10))
    }

    // MARK: - Premium Override (Singleton)

    func testPremiumOverride_setsIsPremium() {
        let manager = SubscriptionManager.shared
        let originalValue = manager.hasPremiumOverride

        // Set override
        manager.hasPremiumOverride = true
        XCTAssertTrue(manager.isPremium)
        XCTAssertTrue(manager.canCreateDuressVault())
        XCTAssertTrue(manager.canCreateVault(currentCount: 999))

        // Clear override
        manager.hasPremiumOverride = false
        // Note: isPremium may still be true if there are real purchases.
        // But the override flag itself should be false.
        XCTAssertFalse(manager.hasPremiumOverride)

        // Restore
        manager.hasPremiumOverride = originalValue
    }

    // MARK: - Brute Force Delay (PatternLockView)

    func testBruteForceDelay_progressiveSchedule() {
        // 0-3 attempts: no delay
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 0), 0)
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 3), 0)

        // 4-5 attempts: 5s
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 4), 5)
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 5), 5)

        // 6-8 attempts: 30s
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 6), 30)
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 8), 30)

        // 9-10 attempts: 5 minutes
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 9), 300)
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 10), 300)

        // 11+ attempts: 15 minutes
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 11), 900)
        XCTAssertEqual(PatternLockView.bruteForceDelay(forAttempts: 100), 900)
    }
}
