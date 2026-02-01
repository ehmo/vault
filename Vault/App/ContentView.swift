import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.isUnlocked)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.showOnboarding)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.isLoading)

            // Screenshot detected: full-screen black overlay (covers UI before lock)
            if appState.screenshotDetected {
                Color.black
                    .ignoresSafeArea()
            }
        }
        // Screenshot detection — locks vault when user takes a screenshot
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            #if DEBUG
            print("📸 [ContentView] Screenshot notification received!")
            #endif
            SentryManager.shared.addBreadcrumb(category: "app.locked", data: ["trigger": "screenshot"])
            appState.screenshotDetected = true
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                appState.lockVault()
            }
        }
        // Screen recording detection
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { notification in
            let screen = notification.object as? UIScreen ?? UIScreen.main
            if screen.isCaptured {
                #if DEBUG
                print("🎥 [ContentView] Screen recording detected!")
                #endif
                SentryManager.shared.addBreadcrumb(category: "app.locked", data: ["trigger": "recording"])
                appState.lockVault()
            }
        }
        // Lock on background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            #if DEBUG
            print("⏸️ [ContentView] App resigning active — locking vault")
            #endif
            SentryManager.shared.addBreadcrumb(category: "app.locked", data: ["trigger": "background"])
            appState.lockVault()
        }
        #if DEBUG
        // Simulator: Cmd+S doesn't post userDidTakeScreenshotNotification.
        // Shake device (Ctrl+Cmd+Z in simulator) to simulate a screenshot for testing.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            print("📸 [ContentView] DEBUG: Simulated screenshot via shake!")
            appState.screenshotDetected = true
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                appState.lockVault()
            }
        }
        #endif
    }
}

#if DEBUG
// Extend UIDevice to detect shake gestures for debug screenshot simulation
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}
#endif

#Preview {
    ContentView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
