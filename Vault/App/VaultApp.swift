import SwiftUI
import UserNotifications

@main
struct VaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(SubscriptionManager.shared)
        }
    }
}

@MainActor
@Observable
final class AppState {
    var isUnlocked = false
    var currentVaultKey: Data?
    var currentPattern: [Int]?
    var showOnboarding = false
    var isLoading = false
    var isSharedVault = false
    var screenshotDetected = false
    private(set) var vaultName: String = "Vault"

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

    func unlockWithPattern(_ pattern: [Int], gridSize: Int = 5, precomputedKey: Data? = nil) async -> Bool {
        #if DEBUG
        print("🔓 [AppState] unlockWithPattern called with pattern length: \(pattern.count), gridSize: \(gridSize)")
        #endif

        let transaction = SentryManager.shared.startTransaction(name: "vault.unlock", operation: "vault.unlock")
        transaction.setTag(value: "\(gridSize)", key: "gridSize")

        isLoading = true

        do {
            let key: Data

            if let precomputed = precomputedKey {
                // Reuse key already derived by the caller (avoids double PBKDF2)
                key = precomputed
                // Still add a small UX delay so the unlock feels intentional
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.5...1.0) * 1_000_000_000))
            } else {
                // Run delay and key derivation concurrently: total time = max(delay, derivation)
                let delay = Double.random(in: 0.5...1.0)
                async let delayTask: Void = Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                let keySpan = SentryManager.shared.startSpan(parent: transaction, operation: "crypto.key_derivation", description: "PBKDF2 key derivation")
                async let keyTask = KeyDerivation.deriveKey(from: pattern, gridSize: gridSize)

                key = try await keyTask
                keySpan.finish()
                try? await delayTask
            }

            #if DEBUG
            print("🔑 [AppState] Key derived. Hash: \(key.hashValue)")
            #endif

            // Check if this is a duress pattern
            let duressSpan = SentryManager.shared.startSpan(parent: transaction, operation: "security.duress_check", description: "Check duress key")
            if await DuressHandler.shared.isDuressKey(key) {
                #if DEBUG
                print("⚠️ [AppState] Duress key detected!")
                #endif
                await DuressHandler.shared.triggerDuress(preservingKey: key)
            }
            duressSpan.finish()

            currentVaultKey = key
            currentPattern = pattern
            let letters = GridLetterManager.shared.vaultName(for: pattern)
            vaultName = letters.isEmpty ? "Vault" : "Vault \(letters)"
            isUnlocked = true
            isLoading = false

            // Check if this is a shared vault
            let indexSpan = SentryManager.shared.startSpan(parent: transaction, operation: "storage.index_load", description: "Load vault index")
            if let index = try? VaultStorage.shared.loadIndex(with: key) {
                isSharedVault = index.isSharedVault ?? false
                let fileCount = index.files.filter { !$0.isDeleted }.count
                transaction.setTag(value: "\(fileCount)", key: "fileCount")
            }
            indexSpan.finish()

            transaction.finish(status: .ok)

            #if DEBUG
            print("✅ [AppState] Vault unlocked successfully")
            print("✅ [AppState] Vault name: \(vaultName)")
            print("✅ [AppState] currentVaultKey set: \(currentVaultKey != nil)")
            print("✅ [AppState] isUnlocked: \(isUnlocked)")
            print("✅ [AppState] isSharedVault: \(isSharedVault)")
            #endif

            return true
        } catch {
            #if DEBUG
            print("❌ [AppState] Error unlocking: \(error)")
            #endif
            transaction.finish(status: .internalError)
            isLoading = false
            // Still show as "unlocked" with empty vault - no error indication
            currentVaultKey = nil
            currentPattern = nil
            isUnlocked = true
            return true
        }
    }

    func updateVaultName(_ name: String) {
        vaultName = name
    }

    func lockVault() {
        #if DEBUG
        print("🔒 [AppState] lockVault() called")
        print("🔒 [AppState] Before lock - currentVaultKey exists: \(currentVaultKey != nil)")
        #endif

        SentryManager.shared.addBreadcrumb(category: "vault.locked")

        // Clear the key reference (Data is a value type; resetBytes on a copy is a no-op)
        currentVaultKey = nil
        currentPattern = nil
        vaultName = "Vault"
        isUnlocked = false
        isSharedVault = false
        screenshotDetected = false

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

// MARK: - AppDelegate for Foreground Notifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize analytics (Sentry + TelemetryDeck) if user opted in
        AnalyticsManager.shared.startIfEnabled()

        // Initialize RevenueCat
        SubscriptionManager.shared.configure(apiKey: "test_GqDBKuyzTuNOClYgpyIUbvSEtTu")

        UNUserNotificationCenter.current().delegate = self

        // Eagerly init VaultStorage so blob existence check (and potential background
        // blob creation on first launch) overlaps with the user drawing their pattern.
        _ = VaultStorage.shared

        return true
    }

    /// Show notification banners even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

