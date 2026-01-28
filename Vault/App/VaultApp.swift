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
        #if DEBUG
        print("🔓 [AppState] unlockWithPattern called with pattern length: \(pattern.count), gridSize: \(gridSize)")
        #endif
        
        isLoading = true

        // Always delay 1-2 seconds for consistent timing
        let delay = Double.random(in: 1.0...2.0)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        do {
            let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: gridSize)
            
            #if DEBUG
            print("🔑 [AppState] Key derived. Hash: \(key.hashValue)")
            #endif

            // Check if this is a duress pattern
            if await DuressHandler.shared.isDuressKey(key) {
                #if DEBUG
                print("⚠️ [AppState] Duress key detected!")
                #endif
                await DuressHandler.shared.triggerDuress(preservingKey: key)
            }

            currentVaultKey = key
            isUnlocked = true
            isLoading = false
            
            #if DEBUG
            print("✅ [AppState] Vault unlocked successfully")
            print("✅ [AppState] currentVaultKey set: \(currentVaultKey != nil)")
            print("✅ [AppState] isUnlocked: \(isUnlocked)")
            #endif
            
            return true
        } catch {
            #if DEBUG
            print("❌ [AppState] Error unlocking: \(error)")
            #endif
            isLoading = false
            // Still show as "unlocked" with empty vault - no error indication
            currentVaultKey = nil
            isUnlocked = true
            return true
        }
    }

    func lockVault() {
        #if DEBUG
        print("🔒 [AppState] lockVault() called")
        print("🔒 [AppState] Before lock - currentVaultKey exists: \(currentVaultKey != nil)")
        #endif
        
        // Securely clear the key from memory
        if var key = currentVaultKey {
            key.resetBytes(in: 0..<key.count)
        }
        currentVaultKey = nil
        isUnlocked = false
        
        #if DEBUG
        print("🔒 [AppState] After lock - currentVaultKey: nil, isUnlocked: false")
        #endif
    }
    
    func resetToOnboarding() {
        lockVault()
        showOnboarding = true
        
        #if DEBUG
        print("🔄 [AppState] Reset to onboarding state")
        #endif
    }
    
    #if DEBUG
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        resetToOnboarding()
    }
    #endif
}
