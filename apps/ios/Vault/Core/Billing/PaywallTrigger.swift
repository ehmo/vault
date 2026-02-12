import SwiftUI
import RevenueCat
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
                if subscriptionManager.hasOfferings {
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
                    FallbackPaywallView(showPaywall: $showPaywall)
                }
            }
    }
}

// MARK: - Fallback Paywall

/// Shown when RevenueCat offerings aren't available (configuration error, network issues, etc.)
struct FallbackPaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Binding var showPaywall: Bool

    private let features: [(icon: String, title: String, description: String)] = [
        ("infinity", "Unlimited Files", "Store as many files as you need"),
        ("square.stack.3d.up", "Unlimited Vaults", "Create vaults for every purpose"),
        ("person.2", "Shared Vaults", "Share encrypted vaults with others"),
        ("lock.shield", "Duress Vault", "Decoy vault for emergencies"),
        ("icloud", "iCloud Sync", "Access your vaults across devices"),
        ("externaldrive", "Expanded Storage", "No storage limits"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 56))
                            .foregroundStyle(.accent)

                        Text("Vaultaire PRO")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)

                        Text("Unlock the full power of Vaultaire")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    // Features
                    VStack(spacing: 16) {
                        ForEach(features, id: \.title) { feature in
                            HStack(spacing: 16) {
                                Image(systemName: feature.icon)
                                    .font(.title3)
                                    .foregroundStyle(.accent)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(feature.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 24)
                        }
                    }

                    // Sandbox testing note
                    if SubscriptionManager.isSandbox {
                        VStack(spacing: 8) {
                            Text("Testing Mode")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)

                            Text("In-app purchases aren't configured yet. Use the Premium Override toggle in Settings to test premium features.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Enable Premium Override") {
                                subscriptionManager.hasPremiumOverride = true
                                showPaywall = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accent)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    } else {
                        Text("Unable to load subscription options. Please check your connection and try again.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showPaywall = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension View {
    func premiumPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(PremiumGateModifier(showPaywall: isPresented))
    }
}
