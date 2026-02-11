import SwiftUI
import RevenueCatUI

enum PremiumFeature: String {
    case unlimitedVaults
    case unlimitedFiles
    case sharedVault
    case duressVault
    case icloudSync
    case expandedStorage

    var displayName: String {
        switch self {
        case .unlimitedVaults: return "Unlimited Vaults"
        case .unlimitedFiles: return "Unlimited Files"
        case .sharedVault: return "Shared Vaults"
        case .duressVault: return "Duress Vault"
        case .icloudSync: return "iCloud Sync"
        case .expandedStorage: return "Expanded Storage"
        }
    }
}

struct PremiumGateModifier: ViewModifier {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Binding var showPaywall: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPaywall) {
                if subscriptionManager.isConfigured {
                    PaywallView()
                        .onPurchaseCompleted { info in
                            subscriptionManager.updateFromCustomerInfo(info)
                            showPaywall = false
                        }
                        .onRestoreCompleted { info in
                            subscriptionManager.updateFromCustomerInfo(info)
                            showPaywall = false
                        }
                } else {
                    Text("Premium features coming soon")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

extension View {
    func premiumPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(PremiumGateModifier(showPaywall: isPresented))
    }
}
