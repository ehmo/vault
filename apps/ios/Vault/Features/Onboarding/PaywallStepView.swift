import SwiftUI

struct PaywallStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VaultairePaywallView(onDismiss: onContinue, showDismissButton: false)
    }
}

#Preview {
    PaywallStepView(onContinue: {
        // No-op: preview stub
    })
        .environment(SubscriptionManager.shared)
}
