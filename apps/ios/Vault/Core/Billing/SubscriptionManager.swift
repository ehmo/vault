import Foundation
import RevenueCat
import RevenueCatUI
import os.log

@MainActor
@Observable
final class SubscriptionManager: NSObject {
    static let shared = SubscriptionManager()

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "Subscription")

    private(set) var isPremium = false
    private(set) var isConfigured = false
    private(set) var hasOfferings = false
    private(set) var customerInfo: CustomerInfo?

    static let entitlementID = "lifetime"
    static let maxFreeVaults = 5
    static let maxFreeSharedVaults = 10
    static let maxFreeFilesPerVault = 100

    private static let premiumOverrideKey = "premiumTestingOverride"

    /// Whether the app is running in a sandbox environment (TestFlight or Xcode)
    static var isSandbox: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Testing override for premium status (persisted in UserDefaults)
    var hasPremiumOverride: Bool {
        get { UserDefaults.standard.bool(forKey: Self.premiumOverrideKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.premiumOverrideKey)
            isPremium = newValue
            Self.isPremiumSnapshot = newValue
            UserDefaults(suiteName: VaultCoreConstants.appGroupIdentifier)?
                .set(newValue, forKey: VaultCoreConstants.isPremiumKey)
        }
    }

    private override init() {
        super.init()
        // Apply testing override on launch
        if UserDefaults.standard.bool(forKey: Self.premiumOverrideKey) {
            isPremium = true
            Self.isPremiumSnapshot = true
        }
    }

    func configure(apiKey: String) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self
        isConfigured = true

        Task {
            await checkSubscriptionStatus()
            await checkOfferings()
        }
    }

    func checkSubscriptionStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateFromCustomerInfo(info)
        } catch {
            Self.logger.error("Failed to fetch customer info: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func checkOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            hasOfferings = offerings.current != nil
        } catch {
            hasOfferings = false
            Self.logger.error("Failed to fetch offerings: \(error.localizedDescription, privacy: .public)")
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

    func canExpandStorage() -> Bool {
        isPremium
    }

    /// Thread-safe snapshot of premium status for non-MainActor callers (e.g. VaultStorage).
    ///
    /// SAFETY: `nonisolated(unsafe)` is sound here because:
    /// - Bool load/store is atomic on ARM64 (aligned, single-word)
    /// - Single writer (`@MainActor` `updateFromCustomerInfo`), multiple readers
    /// - Stale read has no correctness impact (worst case: extra paywall shown once)
    nonisolated(unsafe) static var isPremiumSnapshot: Bool = false

    // MARK: - Update

    func updateFromCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        // Check for the specific "lifetime" entitlement, or fall back to any active entitlement
        // (covers sandbox/test mode where entitlement-product mapping may not be configured)
        let rcPremium = info.entitlements[Self.entitlementID]?.isActive == true
            || !info.entitlements.active.isEmpty
        // Don't downgrade if testing override is active
        isPremium = rcPremium || UserDefaults.standard.bool(forKey: Self.premiumOverrideKey)
        Self.isPremiumSnapshot = isPremium

        // Cache premium status in app group for share extension access
        UserDefaults(suiteName: VaultCoreConstants.appGroupIdentifier)?
            .set(isPremium, forKey: VaultCoreConstants.isPremiumKey)

        Self.logger.debug("isPremium=\(self.isPremium), active entitlements=\(info.entitlements.active.keys.joined(separator: ", "), privacy: .public)")
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
