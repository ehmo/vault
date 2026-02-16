import SwiftUI
import UserNotifications
import CryptoKit
import os.log

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

@main
struct VaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var deepLinkHandler = DeepLinkHandler()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(deepLinkHandler)
                .environment(SubscriptionManager.shared)
                .onAppear {
                    appState.applyAppearanceToAllWindows()
                    ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "app_on_appear")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Re-apply when app becomes active — catches system appearance changes
                    appState.applyAppearanceToAllWindows()
                    ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "did_become_active")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in
                    // Re-apply when any new window becomes key — catches fullScreenCovers,
                    // sheets, and alerts which create new UIWindows
                    appState.applyAppearanceToAllWindows()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        if ShareUploadManager.shared.hasPendingUpload {
                            ShareUploadManager.shared.scheduleBackgroundResumeTask(earliestIn: 15)
                        }
                    case .active:
                        ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "scene_active")
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    deepLinkHandler.handle(url)
                }
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
    var pendingImportCount = 0
    var hasPendingImports = false
    var suppressLockForShareSheet = false
    private(set) var appearanceMode: AppAppearanceMode

    /// The UIKit interface style for the current appearance mode.
    /// Used exclusively via `window.overrideUserInterfaceStyle` — we do NOT use
    /// SwiftUI's `.preferredColorScheme()` because it conflicts with UIKit overrides
    /// and fails to revert from explicit (light/dark) back to system (.unspecified).
    var effectiveInterfaceStyle: UIUserInterfaceStyle {
        switch appearanceMode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "AppState")
    private static let appearanceModeKey = "appAppearanceMode"
    private static let unlockCeremonyDelayNanoseconds: UInt64 = 1_500_000_000

    #if DEBUG
    /// When true, Maestro E2E tests are running — disables lock triggers and enables test bypass
    let isMaestroTestMode = ProcessInfo.processInfo.arguments.contains("-MAESTRO_TEST")
    #endif

    init() {
        appearanceMode = Self.loadAppearanceMode()
        checkFirstLaunch()
        BackgroundShareTransferManager.shared.setVaultKeyProvider { [weak self] in
            self?.currentVaultKey
        }
        ShareUploadManager.shared.setVaultKeyProvider { [weak self] in
            self?.currentVaultKey
        }
    }

    private static func loadAppearanceMode() -> AppAppearanceMode {
        let stored = UserDefaults.standard.string(forKey: appearanceModeKey)
        return AppAppearanceMode(rawValue: stored ?? "") ?? .system
    }

    private func checkFirstLaunch() {
        #if DEBUG
        if isMaestroTestMode {
            // Auto-complete onboarding in test mode
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            showOnboarding = false
            return
        }
        #endif
        showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    func completeOnboarding() async {
        guard showOnboarding else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false
        isLoading = true
        try? await Task.sleep(nanoseconds: Self.unlockCeremonyDelayNanoseconds)
        isUnlocked = true
        isLoading = false
        ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "onboarding_completed")
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceModeKey)
        applyAppearanceToAllWindows()
    }

    /// Applies the user's appearance mode to all UIKit windows, ensuring sheets,
    /// fullScreenCovers, and alerts all respect the setting immediately.
    /// This is the SOLE mechanism for appearance control — SwiftUI's
    /// `.preferredColorScheme()` is intentionally not used.
    func applyAppearanceToAllWindows() {
        let style = effectiveInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }


    func unlockWithPattern(_ pattern: [Int], gridSize: Int = 5, precomputedKey: Data? = nil) async -> Bool {
        Self.logger.debug("unlockWithPattern called, pattern length: \(pattern.count), gridSize: \(gridSize)")

        let transaction = EmbraceManager.shared.startTransaction(name: "vault.unlock", operation: "vault.unlock")
        transaction.setTag(value: "\(gridSize)", key: "gridSize")

        isLoading = true

        do {
            let key: Data

            if let precomputed = precomputedKey {
                // Reuse key already derived by the caller (avoids double PBKDF2)
                key = precomputed
                // Consistent unlock ceremony: loader shown for 1.5s
                try? await Task.sleep(nanoseconds: Self.unlockCeremonyDelayNanoseconds)
            } else {
                // Run delay and key derivation concurrently: total time = max(1.5s, derivation)
                async let delayTask: Void = Task.sleep(nanoseconds: Self.unlockCeremonyDelayNanoseconds)

                let keySpan = EmbraceManager.shared.startSpan(parent: transaction, operation: "crypto.key_derivation", description: "PBKDF2 key derivation")
                async let keyTask = KeyDerivation.deriveKey(from: pattern, gridSize: gridSize)

                key = try await keyTask
                keySpan.finish()
                try? await delayTask
            }

            Self.logger.trace("Key derived successfully")

            // Check if this is a duress pattern
            let duressSpan = EmbraceManager.shared.startSpan(parent: transaction, operation: "security.duress_check", description: "Check duress key")
            if await DuressHandler.shared.isDuressKey(key) {
                Self.logger.info("Duress key detected")
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
            let indexSpan = EmbraceManager.shared.startSpan(parent: transaction, operation: "storage.index_load", description: "Load vault index")
            if let index = try? VaultStorage.shared.loadIndex(with: key) {
                isSharedVault = index.isSharedVault ?? false
                let fileCount = index.files.filter { !$0.isDeleted }.count
                transaction.setTag(value: "\(fileCount)", key: "fileCount")
            }
            indexSpan.finish()

            // Clean up expired staged imports (older than 24h)
            StagedImportManager.cleanupExpiredBatches()
            StagedImportManager.cleanupOrphans()

            // Check for pending imports from share extension
            let fingerprint = KeyDerivation.keyFingerprint(from: key)
            let pending = StagedImportManager.pendingBatches(for: fingerprint)
            if !pending.isEmpty {
                pendingImportCount = pending.reduce(0) { $0 + $1.files.count }
                hasPendingImports = true
            }

            ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "vault_unlocked")

            transaction.finish(status: .ok)

            Self.logger.info("Vault unlocked: name=\(self.vaultName, privacy: .public), shared=\(self.isSharedVault)")

            return true
        } catch {
            Self.logger.error("Error unlocking: \(error.localizedDescription, privacy: .public)")
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
        Self.logger.debug("lockVault() called")

        EmbraceManager.shared.addBreadcrumb(category: "vault.locked")

        // Clear the key reference (Data is a value type; resetBytes on a copy is a no-op)
        currentVaultKey = nil
        currentPattern = nil
        vaultName = "Vault"
        isUnlocked = false
        isSharedVault = false
        screenshotDetected = false
        pendingImportCount = 0
        hasPendingImports = false
        suppressLockForShareSheet = false

        Self.logger.debug("Vault locked")
    }
    
    func resetToOnboarding() {
        lockVault()
        showOnboarding = true
        
        Self.logger.debug("Reset to onboarding state")
    }
    
    #if DEBUG
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        resetToOnboarding()
    }

    /// Auto-unlock with a deterministic test key for Maestro E2E tests.
    /// Uses a fixed pattern [0,1,2,3,4,5] and derives a test key via SHA-256 hash
    /// so crypto operations (encrypt/decrypt) work consistently in tests.
    func maestroTestUnlock() {
        let testPattern = [0, 1, 2, 3, 4, 5]
        let testSeed = "MAESTRO_TEST_KEY_SEED_2026".data(using: .utf8)!
        // Deterministic 32-byte key via SHA-256 (no Secure Enclave needed)
        let testKey = Data(CryptoKit.SHA256.hash(data: testSeed))

        // Initialize empty vault if needed
        if !VaultStorage.shared.vaultExists(for: testKey) {
            let emptyIndex = VaultStorage.VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: 500 * 1024 * 1024
            )
            try? VaultStorage.shared.saveIndex(emptyIndex, with: testKey)
        }

        currentVaultKey = testKey
        currentPattern = testPattern
        vaultName = "Test Vault"
        isUnlocked = true
        isLoading = false
        ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "maestro_unlock")

        // Seed test files if requested
        if ProcessInfo.processInfo.arguments.contains("-MAESTRO_SEED_FILES") {
            seedTestFiles(key: testKey)
        }
    }

    /// Seeds the vault with dummy test files for Maestro flows that need files present.
    private func seedTestFiles(key: Data) {
        // Check if files already exist to avoid duplicates on re-launch
        guard let index = try? VaultStorage.shared.loadIndex(with: key),
              index.files.filter({ !$0.isDeleted }).isEmpty else {
            return
        }

        // Create a small 2x2 red JPEG (minimal valid image data)
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let jpegData = renderer.jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let pngData = renderer.pngData { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        // Store test files in the vault
        let _ = try? VaultStorage.shared.storeFile(
            data: jpegData,
            filename: "test_photo_1.jpg",
            mimeType: "image/jpeg",
            with: key,
            thumbnailData: jpegData
        )
        let _ = try? VaultStorage.shared.storeFile(
            data: pngData,
            filename: "test_photo_2.png",
            mimeType: "image/png",
            with: key,
            thumbnailData: pngData
        )

        Self.logger.debug("Seeded 2 test files into vault")
    }
    #endif
}

// MARK: - AppDelegate for Foreground Notifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize analytics (Embrace + TelemetryDeck) if user opted in
        AnalyticsManager.shared.startIfEnabled()

        UNUserNotificationCenter.current().delegate = self

        // Eagerly init VaultStorage so blob existence check (and potential background
        // blob creation on first launch) overlaps with the user drawing their pattern.
        _ = VaultStorage.shared

        // Write notification icon to app group so the share extension can use it
        LocalNotificationManager.shared.warmNotificationIcon()

        // Register once at launch so iOS can wake the app to continue pending uploads.
        ShareUploadManager.shared.registerBackgroundProcessingTask()

        // If iOS terminated the previous upload process (jetsam/watchdog),
        // emit a breadcrumb on next launch with the last known phase.
        if let marker = BackgroundShareTransferManager.consumeStaleUploadLifecycleMarker() {
            let ageSeconds = Int(Date().timeIntervalSince(marker.timestamp))
            EmbraceManager.shared.addBreadcrumb(
                category: "share.upload.previous_run_terminated",
                data: [
                    "phase": marker.phase,
                    "shareVaultId": marker.shareVaultId,
                    "ageSeconds": ageSeconds
                ]
            )
        }

        return true
    }

    /// Show notification banners even when app is in foreground.
    func userNotificationCenter(
        _ _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
