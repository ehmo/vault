import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case analytics
    case paywall
    case thankYou
    case rating

    var progressFraction: CGFloat {
        CGFloat(rawValue + 1) / CGFloat(Self.allCases.count)
    }

    func next() -> OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    func previous() -> OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

struct OnboardingView: View {
    /// When set, the view is shown in replay mode: pattern setup is skipped and
    /// tapping "Continue" on the final step calls this closure instead.
    var onReplayDismiss: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep: OnboardingStep = .welcome
    @State private var showPatternSetup = false

    private var isReplay: Bool { onReplayDismiss != nil }

    var body: some View {
        if showPatternSetup {
            PatternSetupView(onComplete: { completeOnboarding() })
        } else {
            VStack(spacing: 0) {
                // Progress bar + back arrow (+ close button in replay mode)
                HStack(spacing: 8) {
                    Button {
                        if let prev = currentStep.previous() {
                            withAnimation(animation) { currentStep = prev }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.vaultText)
                    }
                    .opacity(currentStep != .welcome ? 1 : 0)
                    .disabled(currentStep == .welcome)
                    .accessibilityIdentifier("onboarding_back")

                    Capsule()
                        .fill(Color.vaultSecondaryText.opacity(0.2))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(
                                    width: nil,
                                    height: 4
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .scaleEffect(x: currentStep.progressFraction, y: 1, anchor: .leading)
                        }

                    if currentStep == .paywall {
                        Button("Skip") { advance() }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.vaultSecondaryText)
                            .accessibilityIdentifier("paywall_skip")
                    } else if isReplay {
                        Button {
                            onReplayDismiss?()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.vaultSecondaryText)
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("onboarding_replay_close")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Step content
                switch currentStep {
                case .welcome:
                    WelcomeView(onContinue: { advance() })
                case .permissions:
                    PermissionsView(onContinue: { advance() })
                case .analytics:
                    AnalyticsConsentView(onContinue: { advance() })
                case .paywall:
                    PaywallStepView(onContinue: { advance() })
                case .thankYou:
                    ThankYouView(onContinue: { advance() })
                case .rating:
                    RatingView(onContinue: {
                        if let dismiss = onReplayDismiss {
                            dismiss()
                        } else {
                            withAnimation(animation) { showPatternSetup = true }
                        }
                    })
                }
            }
            .background(Color.vaultBackground.ignoresSafeArea())
        }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut
    }

    private func advance() {
        if let next = currentStep.next() {
            withAnimation(animation) { currentStep = next }
        }
    }

    private func completeOnboarding() {
        Task {
            await appState.completeOnboarding()
        }
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
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
