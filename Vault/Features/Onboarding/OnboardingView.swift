import SwiftUI
import RevenueCatUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0

    var body: some View {
        VStack {
            switch currentStep {
            case 0:
                WelcomeView(onContinue: { currentStep = 1 })
            case 1:
                HowItWorksView(onContinue: { currentStep = 2 })
            case 2:
                AnalyticsConsentView(onContinue: { currentStep = 3 })
            case 3:
                OnboardingPaywallStep(onContinue: { currentStep = 4 })
            case 4:
                PatternSetupView(onComplete: completeOnboarding)
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut, value: currentStep)
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

// MARK: - Onboarding Paywall Step

struct OnboardingPaywallStep: View {
    let onContinue: () -> Void
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        VStack(spacing: 0) {
            PaywallView()
                .onPurchaseCompleted { info in
                    subscriptionManager.updateFromCustomerInfo(info)
                    onContinue()
                }
                .onRestoreCompleted { info in
                    subscriptionManager.updateFromCustomerInfo(info)
                    onContinue()
                }

            Button(action: onContinue) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - How It Works

struct HowItWorksView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("How Vaultaire Works")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(
                    icon: "hand.draw",
                    title: "Pattern-Based Encryption",
                    description: "Each pattern creates a unique encrypted vault. Different patterns = different vaults."
                )

                FeatureRow(
                    icon: "eye.slash",
                    title: "True Plausible Deniability",
                    description: "Nobody can tell how many vaults you have. Every pattern shows a vault."
                )

                FeatureRow(
                    icon: "lock.shield",
                    title: "Hardware Security",
                    description: "Your encryption keys are protected by your device's Secure Enclave."
                )

                FeatureRow(
                    icon: "icloud",
                    title: "Encrypted Backup",
                    description: "Back up to your iCloud. Only you can decrypt it with your pattern."
                )
            }
            .padding(.horizontal)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
