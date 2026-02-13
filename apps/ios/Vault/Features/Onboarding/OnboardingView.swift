import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep = 0

    var body: some View {
        VStack {
            switch currentStep {
            case 0:
                WelcomeView(
                    onContinue: { currentStep = 1 }
                )
            case 1:
                PatternSetupView(onComplete: { currentStep = 2 })
            case 2:
                PermissionsView(
                    onContinue: { currentStep = 3 }
                )
            case 3:
                AnalyticsConsentView(
                    onContinue: { completeOnboarding() }
                )
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
