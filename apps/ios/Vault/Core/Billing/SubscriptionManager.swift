import Foundation
import StoreKit
import os.log

enum StoreKitError: Error {
    case unknown
}

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "Subscription")

    private(set) var isPremium = false
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []

    static let productIDs = [
        "monthly_pro",
        "yearly_pro",
        "lifetime",
    ]

    static let subscriptionGroupID = "vaultaire_pro"

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
            UserDefaults(suiteName: VaultCoreConstants.appGroupIdentifier)?
                .set(newValue, forKey: VaultCoreConstants.isPremiumKey)
        }
    }

    private var transactionListener: Task<Void, Never>?

    private init() {
        // Start listening for transactions immediately
        transactionListener = listenForTransactions()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MAESTRO_PREMIUM_OVERRIDE")
            || ProcessInfo.processInfo.arguments.contains("MAESTRO_PREMIUM_OVERRIDE") {
            UserDefaults.standard.set(true, forKey: Self.premiumOverrideKey)
        }
        #endif

        // Apply testing override on launch
        if UserDefaults.standard.bool(forKey: Self.premiumOverrideKey) {
            isPremium = true
        }

        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    nonisolated deinit {
        // Task is automatically cancelled when reference is dropped
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { a, b in
                Self.productIDs.firstIndex(of: a.id) ?? 0 < Self.productIDs.firstIndex(of: b.id) ?? 0
            }
        } catch {
            Self.logger.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    var hasProducts: Bool { !products.isEmpty }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: - Transactions

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handleVerified(result)
            }
        }
    }

    private func handleVerified(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? result.payloadValue else {
            Self.logger.error("Transaction verification failed")
            return
        }

        if transaction.revocationDate != nil {
            purchasedProductIDs.remove(transaction.productID)
        } else {
            purchasedProductIDs.insert(transaction.productID)
        }

        await transaction.finish()
        refreshPremiumStatus()
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        let span = EmbraceManager.shared.startTransaction(name: "subscription.purchase", operation: "subscription.purchase")
        span.setTag(value: product.id, key: "product_id")
        span.setTag(value: Self.isSandbox ? "sandbox" : "production", key: "environment")

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            guard let transaction = try? verification.payloadValue else {
                EmbraceManager.shared.captureError(StoreKitError.unknown, context: [
                    "action": "purchase_verification_failed",
                    "product_id": product.id
                ])
                span.finish(status: .invalidArgument)
                return false
            }
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
            refreshPremiumStatus()
            EmbraceManager.shared.addBreadcrumb(category: "subscription.purchased", data: [
                "product_id": transaction.productID,
                "transaction_id": String(transaction.id)
            ])
            span.finish(status: .ok)
            return true

        case .userCancelled:
            EmbraceManager.shared.addBreadcrumb(category: "subscription.cancelled", data: ["product_id": product.id])
            span.finish(status: .aborted)
            return false

        case .pending:
            EmbraceManager.shared.addBreadcrumb(category: "subscription.pending", data: ["product_id": product.id])
            span.finish(status: .ok)
            return false

        @unknown default:
            EmbraceManager.shared.captureError(StoreKitError.unknown, context: [
                "action": "purchase_unknown_result",
                "product_id": product.id
            ])
            span.finish(status: .internalError)
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Entitlements

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
        refreshPremiumStatus()
    }

    private func refreshPremiumStatus() {
        let hasPurchase = !purchasedProductIDs.isEmpty
        let hasOverride = UserDefaults.standard.bool(forKey: Self.premiumOverrideKey)
        isPremium = hasPurchase || hasOverride
        UserDefaults(suiteName: VaultCoreConstants.appGroupIdentifier)?
            .set(isPremium, forKey: VaultCoreConstants.isPremiumKey)

        Self.logger.debug("isPremium=\(self.isPremium), products=\(self.purchasedProductIDs.joined(separator: ", "), privacy: .public)")
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

}
