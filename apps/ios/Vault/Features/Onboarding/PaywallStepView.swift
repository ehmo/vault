import SwiftUI

struct PaywallStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VaultairePaywallView(onDismiss: onContinue)

            Button(action: onContinue) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
            }
            .accessibilityIdentifier("paywall_skip")
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    PaywallStepView(onContinue: {})
        .environment(SubscriptionManager.shared)
}
