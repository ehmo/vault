import SwiftUI

struct LoadingView: View {
    var body: some View {
        VaultSyncIndicator(style: .loading, message: "Unlocking...")
    }
}

#Preview {
    LoadingView()
}
