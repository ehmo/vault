import SwiftUI
import os.log

private let logger = Logger(subsystem: "app.vaultaire.ios", category: "ContentView")

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkHandler.self) private var deepLinkHandler
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showUnlockTransition = false

    var body: some View {
        ZStack {
            Group {
                if appState.showOnboarding {
                    OnboardingView()
                } else if appState.isLoading {
                    LoadingView()
                } else if appState.isUnlocked {
                    VaultView()
                        .opacity(showUnlockTransition ? 0 : 1)
                        .offset(y: showUnlockTransition ? 20 : 0)
                } else {
                    PatternLockView()
                }
            }
            #if DEBUG
            .onAppear {
                if appState.isMaestroTestMode && !appState.isUnlocked && !appState.showOnboarding {
                    appState.maestroTestUnlock()
                }
            }
            #endif
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.isUnlocked)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.showOnboarding)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.isLoading)

            // Vault door unlock overlay
            if showUnlockTransition {
                Color.vaultBackground
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor)
                            .scaleEffect(showUnlockTransition ? 1.2 : 1.0)
                            .opacity(showUnlockTransition ? 1 : 0)
                    }
                    .transition(.opacity)
            }

            // Screenshot detected: full-screen overlay (covers UI before lock)
            if appState.screenshotDetected {
                Color.vaultBackground
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { deepLinkHandler.pendingSharePhrase != nil },
            set: { if !$0 { deepLinkHandler.clearPending() } }
        )) {
            SharedVaultInviteView()
                .environment(appState)
                .environment(deepLinkHandler)
                .environment(SubscriptionManager.shared)
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: appState.isUnlocked) { _, isUnlocked in
            guard isUnlocked else { return }

            // Trigger silent background backup if enabled and overdue
            if let key = appState.currentVaultKey {
                iCloudBackupManager.shared.performBackupIfNeeded(with: key)
            }

            guard !reduceMotion else { return }
            showUnlockTransition = true
            withAnimation(.easeOut(duration: 0.9)) {
                showUnlockTransition = false
            }
        }
        // Screenshot detection — locks vault when user takes a screenshot
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            #if DEBUG
            if appState.isMaestroTestMode { return }
            #endif
            logger.info("Screenshot detected, locking vault")
            EmbraceManager.shared.addBreadcrumb(category: "app.locked", data: ["trigger": "screenshot"])
            appState.screenshotDetected = true
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                appState.lockVault()
            }
        }
        // Screen recording detection
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { notification in
            #if DEBUG
            if appState.isMaestroTestMode { return }
            #endif
            guard let screen = notification.object as? UIScreen else { return }
            if screen.isCaptured {
                logger.info("Screen recording detected, locking vault")
                EmbraceManager.shared.addBreadcrumb(category: "app.locked", data: ["trigger": "recording"])
                appState.lockVault()
            }
        }
        // Lock only when the app actually enters background.
        // `willResignActive` also fires for transient system UI (e.g. import pickers),
        // which can interrupt in-app file import flows.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            #if DEBUG
            if appState.isMaestroTestMode { return }
            #endif
            if appState.suppressLockForShareSheet { return }
            logger.debug("App entered background, locking vault")
            EmbraceManager.shared.addBreadcrumb(category: "app.locked", data: ["trigger": "background"])
            appState.lockVault()
        }
        #if DEBUG
        // Simulator: Cmd+S doesn't post userDidTakeScreenshotNotification.
        // Shake device (Ctrl+Cmd+Z in simulator) to simulate a screenshot for testing.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            logger.debug("Simulated screenshot via shake")
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
