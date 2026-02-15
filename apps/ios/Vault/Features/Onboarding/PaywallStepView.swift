import SwiftUI

struct PaywallStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VaultairePaywallView(onDismiss: onContinue, showDismissButton: false)
    }
}

#Preview {
    PaywallStepView(onContinue: {})
        .environment(SubscriptionManager.shared)
}
