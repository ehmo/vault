import SwiftUI

struct LoadingView: View {
    var body: some View {
        VaultSyncIndicator(style: .loading, message: "Unlocking...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.vaultBackground.ignoresSafeArea())
    }
}

#Preview {
    LoadingView()
}
