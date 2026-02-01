import Foundation
import RevenueCat
import RevenueCatUI

@MainActor
@Observable
final class SubscriptionManager: NSObject {
    static let shared = SubscriptionManager()

    private(set) var isPremium = false
    private(set) var customerInfo: CustomerInfo?

    static let entitlementID = "lifetime"
    static let maxFreeVaults = 5
    static let maxFreeSharedVaults = 10
    static let maxFreeFilesPerVault = 100

    private override init() {
        super.init()
    }

    func configure(apiKey: String) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self

        Task {
            await checkSubscriptionStatus()
        }
    }

    func checkSubscriptionStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateFromCustomerInfo(info)
        } catch {
            #if DEBUG
            print("❌ [SubscriptionManager] Failed to fetch customer info: \(error)")
            #endif
        }
    }

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        updateFromCustomerInfo(info)
    }

    // MARK: - Limit Checks

    func canCreateVault(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.maxFreeVaults
    }

    func canJoinSharedVault(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.maxFreeSharedVaults
    }

    func canAddFile(currentFileCount: Int) -> Bool {
        isPremium || currentFileCount < Self.maxFreeFilesPerVault
    }

    func canCreateSharedVault() -> Bool {
        isPremium
    }

    func canCreateDuressVault() -> Bool {
        isPremium
    }

    func canSyncWithICloud() -> Bool {
        isPremium
    }

    // MARK: - Update

    func updateFromCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        // Check for the specific "lifetime" entitlement, or fall back to any active entitlement
        // (covers sandbox/test mode where entitlement-product mapping may not be configured)
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
            || !info.entitlements.active.isEmpty

        #if DEBUG
        print("💰 [SubscriptionManager] isPremium: \(isPremium)")
        print("💰 [SubscriptionManager] Active entitlements: \(info.entitlements.active.keys.joined(separator: ", "))")
        print("💰 [SubscriptionManager] All entitlements: \(info.entitlements.all.keys.joined(separator: ", "))")
        print("💰 [SubscriptionManager] Non-subscription transactions: \(info.nonSubscriptions.count)")
        #endif
    }
}

// MARK: - PurchasesDelegate

extension SubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            updateFromCustomerInfo(customerInfo)
        }
    }
}
