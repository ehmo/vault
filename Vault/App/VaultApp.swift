import SwiftUI

@main
struct VaultApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    setupSecurityMeasures()
                }
        }
    }

    private func setupSecurityMeasures() {
        // Prevent screenshots and screen recording
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if UIScreen.main.isCaptured {
                Task { @MainActor in
                    appState.lockVault()
                }
            }
        }

        // Lock on background
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                appState.lockVault()
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isUnlocked = false
    @Published var currentVaultKey: Data?
    @Published var showOnboarding = false
    @Published var isLoading = false

    private let secureEnclave = SecureEnclaveManager.shared
    private let storage = VaultStorage.shared

    init() {
        checkFirstLaunch()
    }

    private func checkFirstLaunch() {
        showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false
    }

    func unlockWithPattern(_ pattern: [Int], gridSize: Int = 4) async -> Bool {
        isLoading = true

        // Always delay 1-2 seconds for consistent timing
        let delay = Double.random(in: 1.0...2.0)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        do {
            let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: gridSize)

            // Check if this is a duress pattern
            if await DuressHandler.shared.isDuressKey(key) {
                await DuressHandler.shared.triggerDuress(preservingKey: key)
            }

            currentVaultKey = key
            isUnlocked = true
            isLoading = false
            return true
        } catch {
            isLoading = false
            // Still show as "unlocked" with empty vault - no error indication
            currentVaultKey = nil
            isUnlocked = true
            return true
        }
    }

    func lockVault() {
        // Securely clear the key from memory
        if var key = currentVaultKey {
            key.resetBytes(in: 0..<key.count)
        }
        currentVaultKey = nil
        isUnlocked = false
    }
    
    #if DEBUG
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        showOnboarding = true
        lockVault()
    }
    #endif
}
