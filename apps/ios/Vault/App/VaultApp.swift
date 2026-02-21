import SwiftUI
import UserNotifications
import CryptoKit
import os.log
import QuartzCore
import AVFoundation

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
                    iCloudBackupManager.shared.resumeBackupUploadIfNeeded(trigger: "app_on_appear")
                    ShareSyncManager.shared.resumePendingSyncsIfNeeded(trigger: "app_on_appear")
                    Task { await CloudKitSharingManager.shared.cleanupOrphanChunks() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "did_become_active")
                    iCloudBackupManager.shared.resumeBackupUploadIfNeeded(trigger: "did_become_active")
                    ShareSyncManager.shared.resumePendingSyncsIfNeeded(trigger: "did_become_active")
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        if ShareUploadManager.shared.hasPendingUpload {
                            ShareUploadManager.shared.scheduleBackgroundResumeTask(earliestIn: 15)
                        }
                        if iCloudBackupManager.shared.hasPendingBackup {
                            iCloudBackupManager.shared.scheduleBackgroundResumeTask(earliestIn: 15)
                        }
                        if ShareSyncManager.shared.hasPendingSyncs {
                            ShareSyncManager.shared.scheduleBackgroundResumeTask(earliestIn: 15)
                        }
                    case .active:
                        ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "scene_active")
                        iCloudBackupManager.shared.resumeBackupUploadIfNeeded(trigger: "scene_active")
                        ShareSyncManager.shared.resumePendingSyncsIfNeeded(trigger: "scene_active")
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
    var currentVaultKey: VaultKey?
    var currentPattern: [Int]?
    var showOnboarding = false
    var isLoading = false
    var isSharedVault = false
    var screenshotDetected = false
    /// Monotonically increasing counter; bumped on every `lockVault()`.
    /// Unlock tasks check this to abort if the vault was locked mid-ceremony.
    private(set) var lockGeneration: UInt64 = 0
    private(set) var vaultName: String = "Vault"
    var pendingImportCount = 0
    var hasPendingImports = false
    var suppressLockForShareSheet = false
    private(set) var appearanceMode: AppAppearanceMode

    /// The UIKit interface style for the current appearance mode.
    var effectiveInterfaceStyle: UIUserInterfaceStyle {
        switch appearanceMode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }


    /// Background color resolved statically from the stored appearance mode at init.
    /// Does NOT depend on the current trait collection, so it renders correctly on
    /// the very first frame — before `overrideUserInterfaceStyle` is applied.
    let launchBackgroundColor: Color

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "AppState")
    private static let appearanceModeKey = "appAppearanceMode"
    private static let unlockCeremonyDelayNanoseconds: UInt64 = 1_500_000_000

    #if DEBUG
    /// When true, Maestro E2E tests are running — disables lock triggers and enables test bypass
    let isMaestroTestMode = ProcessInfo.processInfo.arguments.contains("-MAESTRO_TEST")
    /// When true, XCUITests are running — disables animations for faster test execution
    let isXCUITestMode = ProcessInfo.processInfo.arguments.contains("-XCUITEST_MODE")
    #endif

    init() {
        let mode = Self.loadAppearanceMode()
        appearanceMode = mode

        // Resolve VaultBackground for the stored mode at init time, before any
        // window or trait collection exists. For .system, use the dynamic color.
        let baseColor = UIColor(named: "VaultBackground") ?? .systemBackground
        switch mode {
        case .light:
            launchBackgroundColor = Color(
                baseColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            )
        case .dark:
            launchBackgroundColor = Color(
                baseColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            )
        case .system:
            launchBackgroundColor = Color.vaultBackground
        }

        checkFirstLaunch()
        ShareUploadManager.shared.setVaultKeyProvider { [weak self] in
            self?.currentVaultKey
        }
        ShareSyncManager.shared.setVaultKeyProvider { [weak self] in
            self?.currentVaultKey
        }
        iCloudBackupManager.shared.setVaultKeyProvider { [weak self] in
            self?.currentVaultKey?.rawBytes
        }
    }

    private static func loadAppearanceMode() -> AppAppearanceMode {
        let stored = UserDefaults.standard.string(forKey: appearanceModeKey)
        return AppAppearanceMode(rawValue: stored ?? "") ?? .system
    }

    private func checkFirstLaunch() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-RESET_ONBOARDING") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
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
        let startGeneration = lockGeneration
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false
        isLoading = true
        try? await Task.sleep(nanoseconds: Self.unlockCeremonyDelayNanoseconds)
        guard lockGeneration == startGeneration else { return }
        isUnlocked = true
        isLoading = false
        ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "onboarding_completed")
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        guard appearanceMode != mode else { return }
        withAnimation(.none) {
            appearanceMode = mode
        }
        UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceModeKey)
        applyAppearanceToAllWindows()
    }

    /// Applies the user's appearance mode to all UIKit windows.
    /// Only sets `overrideUserInterfaceStyle` — SwiftUI's
    /// `Color.vaultBackground.ignoresSafeArea()` handles the background color.
    /// Setting `window.backgroundColor` at runtime causes a blank-screen flash
    /// because SwiftUI views go transparent during trait-change re-layout.
    func applyAppearanceToAllWindows() {
        let style = effectiveInterfaceStyle

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
        CATransaction.commit()
    }


    func unlockWithPattern(_ pattern: [Int], gridSize: Int = 5, precomputedKey: Data? = nil) async -> Bool {
        Self.logger.debug("unlockWithPattern called, pattern length: \(pattern.count), gridSize: \(gridSize)")

        let transaction = EmbraceManager.shared.startTransaction(name: "vault.unlock", operation: "vault.unlock")
        transaction.setTag(value: "\(gridSize)", key: "gridSize")

        // Capture the lock generation before we start; if it changes during
        // the ceremony, the vault was locked and we must abort.
        let startGeneration = lockGeneration

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

            // Abort if the vault was locked during the ceremony (e.g. app backgrounded)
            guard lockGeneration == startGeneration else {
                Self.logger.info("Vault locked during unlock ceremony, aborting")
                transaction.finish(status: .aborted)
                return false
            }

            Self.logger.trace("Key derived successfully")

            // Check if this is a duress pattern
            let duressSpan = EmbraceManager.shared.startSpan(parent: transaction, operation: "security.duress_check", description: "Check duress key")
            if await DuressHandler.shared.isDuressKey(key) {
                Self.logger.info("Duress key detected")
                await DuressHandler.shared.triggerDuress(preservingKey: key)
            }
            duressSpan.finish()

            // Final generation check after duress (which can be async)
            guard lockGeneration == startGeneration else {
                Self.logger.info("Vault locked during unlock ceremony, aborting")
                transaction.finish(status: .aborted)
                return false
            }

            currentVaultKey = VaultKey(key)
            currentPattern = pattern
            let letters = GridLetterManager.shared.vaultName(for: pattern)
            vaultName = letters.isEmpty ? "Vault" : "Vault \(letters)"
            isUnlocked = true
            isLoading = false

            // Check if this is a shared vault
            let indexSpan = EmbraceManager.shared.startSpan(parent: transaction, operation: "storage.index_load", description: "Load vault index")
            if let index = try? VaultStorage.shared.loadIndex(with: VaultKey(key)) {
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
            // Abort if vault was locked during the ceremony
            guard lockGeneration == startGeneration else {
                Self.logger.info("Vault locked during unlock ceremony (error path), aborting")
                return false
            }
            isLoading = false
            // Still show as "unlocked" with empty vault - no error indication
            currentVaultKey = nil
            currentPattern = nil
            isUnlocked = true
            return true
        }
    }

    /// Unlocks vault with a pre-derived key, showing the same loading ceremony as pattern unlock.
    /// Used for recovery phrase flow to ensure consistent user experience.
    func unlockWithKey(_ key: Data, isRecovery: Bool = false) async {
        let transaction = EmbraceManager.shared.startTransaction(name: "vault.unlock", operation: "vault.unlock")
        transaction.setTag(value: "recovery", key: "unlockType")
        
        let startGeneration = lockGeneration
        isLoading = true
        
        // Consistent unlock ceremony: loader shown for 1.5s
        try? await Task.sleep(nanoseconds: Self.unlockCeremonyDelayNanoseconds)
        
        // Abort if the vault was locked during the ceremony
        guard lockGeneration == startGeneration else {
            Self.logger.info("Vault locked during recovery unlock ceremony, aborting")
            transaction.finish(status: .aborted)
            return
        }
        
        currentVaultKey = VaultKey(key)
        currentPattern = nil
        vaultName = "Vault"
        isUnlocked = true
        isLoading = false
        
        // Check if this is a shared vault
        let indexSpan = EmbraceManager.shared.startSpan(parent: transaction, operation: "storage.index_load", description: "Load vault index")
        if let index = try? VaultStorage.shared.loadIndex(with: VaultKey(key)) {
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
        
        Self.logger.info("Vault unlocked via recovery: shared=\(self.isSharedVault)")
    }

    func updateVaultName(_ name: String) {
        vaultName = name
    }

    func lockVault() {
        Self.logger.debug("lockVault() called")

        EmbraceManager.shared.addBreadcrumb(category: "vault.locked")

        // Bump generation so any in-flight unlock ceremony aborts
        lockGeneration &+= 1

        // Clear the key reference (Data is a value type; resetBytes on a copy is a no-op)
        currentVaultKey = nil
        currentPattern = nil
        vaultName = "Vault"
        isUnlocked = false
        isLoading = false
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

        let testVaultKey = VaultKey(testKey)

        // Clear vault if requested (for tests that need empty state)
        if ProcessInfo.processInfo.arguments.contains("-MAESTRO_CLEAR_VAULT") {
            // loadIndex auto-creates a proper v3 index with master key when none exists
            let emptyIndex = try? VaultStorage.shared.loadIndex(with: testVaultKey)
            if let emptyIndex {
                try? VaultStorage.shared.saveIndex(emptyIndex, with: testVaultKey)
            }
        }

        // Initialize empty vault if needed
        if !VaultStorage.shared.vaultExists(for: testVaultKey) {
            // loadIndex auto-creates a proper v3 index with master key when none exists
            let emptyIndex = try? VaultStorage.shared.loadIndex(with: testVaultKey)
            if let emptyIndex {
                try? VaultStorage.shared.saveIndex(emptyIndex, with: testVaultKey)
            }
        }

        currentVaultKey = testVaultKey
        currentPattern = testPattern
        vaultName = "Test Vault"
        isUnlocked = true
        isLoading = false
        ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "maestro_unlock")

        // Seed test files if requested
        if ProcessInfo.processInfo.arguments.contains("-MAESTRO_SEED_FILES") {
            seedTestFiles(key: testVaultKey)
        }
    }

    /// Seeds the vault with dummy test files for Maestro flows that need files present.
    private func seedTestFiles(key: VaultKey) {
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
    private var earlyAppearanceObserver: NSObjectProtocol?

    func application(
        _ _: UIApplication,
        willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Start telemetry as early as possible for startup instrumentation.
        AnalyticsManager.shared.startIfEnabled()

        // Force the app-wide tint to our AccentColor asset. On iOS 26+,
        // the Liquid Glass system can override Color.accentColor with its
        // own automatic tinting; setting the UIKit tint ensures consistency.
        if let accent = UIColor(named: "AccentColor") {
            UIView.appearance().tintColor = accent
        }

        // Make every UINavigationBar transparent by default. SwiftUI's
        // `.toolbarBackground(.hidden)` does the same thing, but it only takes
        // effect after the first layout pass — leaving a 1-2 frame flash of the
        // default opaque bar background when a NavigationStack is first created
        // (e.g. VaultView appearing during the unlock transition).
        let transparentAppearance = UINavigationBarAppearance()
        transparentAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = transparentAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = transparentAppearance
        UINavigationBar.appearance().compactAppearance = transparentAppearance

        // Apply the user's stored appearance override to every window as soon as
        // it becomes key — BEFORE SwiftUI's .onAppear fires. This prevents the
        // first-frame flash when the stored mode differs from the system default.
        let mode = AppAppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appAppearanceMode") ?? ""
        ) ?? .system
        if mode != .system {
            let style: UIUserInterfaceStyle = mode == .light ? .light : .dark
            let baseColor = UIColor(named: "VaultBackground") ?? .systemBackground
            let resolved = baseColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: style)
            )
            // Apply to each window once as it becomes key during launch.
            // The observer removes itself after the first fire to avoid
            // conflicting with runtime appearance changes from settings.
            earlyAppearanceObserver = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? UIWindow else { return }
                window.overrideUserInterfaceStyle = style
                window.backgroundColor = resolved
                // Remove after first window — SwiftUI's .onAppear handles the rest
                if let observer = self?.earlyAppearanceObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self?.earlyAppearanceObserver = nil
                }
            }
        }

        return true
    }

    func application(
        _ _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Configure audio session to allow video playback with sound
        // This enables audio even when the device is in silent mode
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }

        #if DEBUG
        // Disable animations for faster XCUITest execution
        if ProcessInfo.processInfo.arguments.contains("-XCUITEST_MODE") {
            UIView.setAnimationsEnabled(false)
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.layer.speed = 100
                }
            }
        }
        #endif

        // Eagerly init VaultStorage so blob existence check (and potential background
        // blob creation on first launch) overlaps with the user drawing their pattern.
        _ = VaultStorage.shared

        // Write notification icon to app group so the share extension can use it
        LocalNotificationManager.shared.warmNotificationIcon()

        // Register once at launch so iOS can wake the app to continue pending uploads/backups.
        ShareUploadManager.shared.registerBackgroundProcessingTask()
        ShareSyncManager.shared.registerBackgroundProcessingTask()
        iCloudBackupManager.shared.registerBackgroundProcessingTask()

        // If iOS terminated the previous upload process (jetsam/watchdog),
        // emit a breadcrumb on next launch with the last known phase.
        if let marker = ShareUploadManager.consumeStaleUploadLifecycleMarker() {
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

        // Register for memory warnings to track resource pressure events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        return true
    }

    @objc private func handleMemoryWarning() {
        EmbraceManager.shared.logMemoryWarning()
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
