import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.showOnboarding {
                OnboardingView()
            } else if appState.isLoading {
                LoadingView()
            } else if appState.isUnlocked {
                VaultView()
            } else {
                PatternLockView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isUnlocked)
        .animation(.easeInOut(duration: 0.3), value: appState.showOnboarding)
        .animation(.easeInOut(duration: 0.3), value: appState.isLoading)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
