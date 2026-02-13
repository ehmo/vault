import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep = 0

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar + back arrow
            HStack(spacing: 4) {
                Button { currentStep -= 1 } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.vaultText)
                }
                .opacity(currentStep > 0 ? 1 : 0)
                .disabled(currentStep == 0)
                .accessibilityIdentifier("onboarding_back")

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.vaultSecondaryText.opacity(0.2))
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps))
                    }
                    .frame(height: 4)
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Step content
            switch currentStep {
            case 0:
                WelcomeView(onContinue: { currentStep = 1 })
            case 1:
                PermissionsView(onContinue: { currentStep = 2 })
            case 2:
                AnalyticsConsentView(onContinue: { currentStep = 3 })
            case 3:
                VStack(spacing: 0) {
                    VaultairePaywallView(onDismiss: { currentStep = 4 })

                    Button(action: { currentStep = 4 }) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundStyle(.vaultSecondaryText)
                    }
                    .accessibilityIdentifier("paywall_skip")
                    .padding(.bottom, 24)
                }
            case 4:
                PatternSetupView(onComplete: { completeOnboarding() })
            default:
                EmptyView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut, value: currentStep)
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let useVertical = dynamicTypeSize.isAccessibilitySize

        Group {
            if useVertical {
                VStack(alignment: .leading, spacing: 8) {
                    featureIcon
                    featureText
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    featureIcon
                    featureText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var featureIcon: some View {
        Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
            .accessibilityHidden(true)
    }

    private var featureText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
