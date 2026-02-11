import SwiftUI
import CloudKit
import RevenueCatUI

// MARK: - App Settings Destination

enum AppSettingsDestination: Hashable {
    case duressPattern
    case iCloudBackup
    case restoreBackup
}

// MARK: - App Settings View

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @AppStorage("showPatternFeedback") private var showFeedback = true
    @AppStorage("analyticsEnabled") private var analyticsEnabled = false

    @State private var showingNuclearConfirmation = false
    @State private var showingPaywall = false
    @State private var showingCustomerCenter = false
    @State private var isRestoringPurchases = false
    @State private var showingClearStagedConfirmation = false
    @State private var pendingStagedSize: Int64 = 0

    #if DEBUG
    @State private var showingDebugResetConfirmation = false
    #endif

    var body: some View {
        List {
            // Premium
            if subscriptionManager.isPremium {
                Section("Premium") {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text("Vaultaire Pro")
                        Spacer()
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Button("Manage Subscription") {
                        showingCustomerCenter = true
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                            Text("Unlock Vaultaire Pro")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Unlimited vaults & files", systemImage: "infinity")
                            Label("Share encrypted vaults", systemImage: "person.2.fill")
                            Label("iCloud backup & sync", systemImage: "icloud.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)

                        Button(action: { showingPaywall = true }) {
                            Text("Upgrade")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .vaultProminentButtonStyle()
                        .accessibilityIdentifier("app_upgrade")
                    }
                    .padding(.vertical, 4)

                    Button(action: {
                        isRestoringPurchases = true
                        Task {
                            try? await subscriptionManager.restorePurchases()
                            isRestoringPurchases = false
                        }
                    }) {
                        if isRestoringPurchases {
                            HStack {
                                ProgressView()
                                Text("Restoring...")
                            }
                        } else {
                            Text("Restore Purchases")
                        }
                    }
                    .disabled(isRestoringPurchases)
                    .accessibilityIdentifier("app_restore_purchases")
                }
            }

            // Security & Privacy (merged)
            Section {
                Toggle("Show pattern feedback", isOn: $showFeedback)
                    .accessibilityIdentifier("app_pattern_feedback")

                Toggle("Help improve Vault", isOn: $analyticsEnabled)
                    .accessibilityIdentifier("app_analytics_toggle")

                NavigationLink("Duress pattern") {
                    DuressPatternSettingsView()
                }
                .accessibilityIdentifier("app_duress_pattern")

                if subscriptionManager.canSyncWithICloud() {
                    NavigationLink("iCloud Backup") {
                        iCloudBackupSettingsView()
                    }
                    .accessibilityIdentifier("app_icloud_backup")
                } else {
                    Button(action: { showingPaywall = true }) {
                        HStack {
                            Text("iCloud Backup")
                            Spacer()
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.vaultHighlight)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Security & Privacy")
            } footer: {
                Text("Anonymous crash reports help improve the app. No personal data is collected.")
            }
            .onChange(of: analyticsEnabled) { _, newValue in
                AnalyticsManager.shared.setEnabled(newValue)
            }

            // Storage Management
            if pendingStagedSize > 0 {
                Section {
                    HStack {
                        Text("Pending share imports")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: pendingStagedSize, countStyle: .file))
                            .foregroundStyle(.vaultSecondaryText)
                    }

                    Button("Clear Pending Imports", role: .destructive) {
                        showingClearStagedConfirmation = true
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Files shared via a pattern you no longer use. These are automatically cleared after 24 hours.")
                }
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.vaultSecondaryText)
                }
                
                #if DEBUG
                HStack {
                    Text("Build Configuration")
                    Spacer()
                    Text("Debug")
                        .foregroundStyle(.vaultHighlight)
                }
                #else
                HStack {
                    Text("Build Configuration")
                    Spacer()
                    Text("Release")
                        .foregroundStyle(.vaultSecondaryText)
                }
                #endif
            }
            
            #if DEBUG
            // Debug Tools
            Section {
                Button(action: {
                    appState.resetOnboarding()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.vaultHighlight)
                        Text("Reset Onboarding")
                    }
                }
                .accessibilityIdentifier("debug_reset_onboarding")

                Button(action: { showingDebugResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text("Full Reset / Wipe Everything")
                            .foregroundStyle(.vaultHighlight)
                    }
                }
                .accessibilityIdentifier("debug_full_reset")
            } header: {
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(.vaultHighlight)
                    Text("Debug Tools")
                }
            } footer: {
                Text("Development only: Reset onboarding or completely wipe all data including vault files, recovery phrases, settings, and Keychain entries.")
            }
            #endif

            // Testing Tools (visible in TestFlight / sandbox builds only)
            if SubscriptionManager.isSandbox {
                Section {
                    Toggle(isOn: Bindable(subscriptionManager).hasPremiumOverride) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                            Text("Premium Override")
                        }
                    }
                    .accessibilityIdentifier("testing_premium_override")
                } header: {
                    HStack {
                        Image(systemName: "testtube.2")
                        Text("Testing")
                    }
                } footer: {
                    Text("Grants premium access for testing. Only visible in TestFlight builds.")
                }
            }

            // Danger Zone
            Section {
                Button(role: .destructive, action: { showingNuclearConfirmation = true }) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Nuclear Option - Destroy All Data")
                    }
                }
                .accessibilityIdentifier("app_nuclear_option")
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Permanently destroys all vaults and data. This cannot be undone.")
            }
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Destroy All Data?", isPresented: $showingNuclearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Destroy Everything", role: .destructive) {
                performNuclearWipe()
            }
        } message: {
            Text("This will permanently destroy ALL vaults and ALL data. This action cannot be undone. The app will reset to its initial state.")
        }
        #if DEBUG
        .alert("Debug: Full Reset", isPresented: $showingDebugResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Wipe Everything", role: .destructive) {
                performDebugFullReset()
            }
        } message: {
            Text("This will completely wipe:\n• All vault files and indexes\n• Recovery phrase mappings\n• User preferences\n• Keychain entries\n• Onboarding state\n\nThe app will restart as if freshly installed.")
        }
        #endif
        .onAppear {
            pendingStagedSize = StagedImportManager.totalPendingSize()
        }
        .alert("Clear Pending Imports?", isPresented: $showingClearStagedConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                StagedImportManager.deleteAllBatches()
                pendingStagedSize = 0
            }
        } message: {
            Text("This will delete all files shared via the share extension that haven't been imported yet.")
        }
        .premiumPaywall(isPresented: $showingPaywall)
        .sheet(isPresented: $showingCustomerCenter) {
            CustomerCenterView()
        }
    }

    private func performNuclearWipe() {
        Task {
            await DuressHandler.shared.performNuclearWipe()
            await MainActor.run {
                // Reset app state to trigger onboarding
                appState.resetToOnboarding()
                dismiss()
            }
        }
    }
    
    #if DEBUG
    private func performDebugFullReset() {
        Task {
            await debugFullReset()
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    /// Performs a complete reset of all app data - DEBUG ONLY
    private func debugFullReset() async {
        #if DEBUG
        print("🧹 [Debug] Starting full reset...")
        #endif
        
        // 1. Clear vault files and storage
        await clearVaultStorage()
        
        // 2. Clear recovery phrase mappings
        clearRecoveryMappings()
        
        // 3. Clear all UserDefaults
        clearUserDefaults()
        
        // 4. Clear Keychain entries
        clearKeychain()
        
        // 5. Clear temporary files
        clearTemporaryFiles()
        
        // 6. Reset app state
        await MainActor.run {
            appState.lockVault()
            appState.resetToOnboarding()
        }
        
        #if DEBUG
        print("✅ [Debug] Full reset complete!")
        #endif
    }
    
    private func clearVaultStorage() async {
        // Delete vault storage directory
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vaultURL = documentsURL.appendingPathComponent("vault_storage")
        
        try? fileManager.removeItem(at: vaultURL)
        
        #if DEBUG
        print("🧹 [Debug] Vault storage cleared")
        #endif
    }
    
    private func clearRecoveryMappings() {
        UserDefaults.standard.removeObject(forKey: "recovery_mapping")
        
        #if DEBUG
        print("🧹 [Debug] Recovery mappings cleared")
        #endif
    }
    
    private func clearUserDefaults() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        #if DEBUG
        print("🧹 [Debug] UserDefaults cleared")
        #endif
    }
    
    private func clearKeychain() {
        // Clear all keychain items for the app
        let secItemClasses = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        
        for itemClass in secItemClasses {
            let spec: [String: Any] = [kSecClass as String: itemClass]
            SecItemDelete(spec as CFDictionary)
        }
        
        #if DEBUG
        print("🧹 [Debug] Keychain cleared")
        #endif
    }
    
    private func clearTemporaryFiles() {
        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory
        
        // Remove all temporary files
        if let contents = try? fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        #if DEBUG
        print("🧹 [Debug] Temporary files cleared")
        #endif
    }
    #endif
}

// MARK: - Legacy SettingsView (Kept for compatibility)

struct SettingsView: View {
    var body: some View {
        AppSettingsView()
    }
}

// MARK: - Duress Pattern Settings

struct DuressPatternSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasDuressVault = false
    @State private var showingSetupSheet = false

    var body: some View {
        List {
            Section {
                if hasDuressVault {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Duress vault configured")
                    }

                    Button("Change duress vault") {
                        showingSetupSheet = true
                    }

                    Button("Remove duress vault", role: .destructive) {
                        Task {
                            await DuressHandler.shared.clearDuressVault()
                            await MainActor.run {
                                hasDuressVault = false
                            }
                        }
                    }
                } else {
                    Text("No duress vault configured")
                        .foregroundStyle(.vaultSecondaryText)

                    Button("Set up duress vault") {
                        showingSetupSheet = true
                    }
                }
            } header: {
                Text("Duress Vault")
            } footer: {
                Text("When you enter the duress pattern, all other vaults are silently destroyed while showing this vault's content.")
            }

            Section("How It Works") {
                Label("Enter duress pattern under coercion", systemImage: "1.circle")
                Label("All other vaults are permanently destroyed", systemImage: "2.circle")
                Label("Duress vault content is shown normally", systemImage: "3.circle")
                Label("No visible indication that anything happened", systemImage: "4.circle")
            }
            .font(.subheadline)
        }
        .navigationTitle("Duress Pattern")
        .task {
            hasDuressVault = await DuressHandler.shared.hasDuressVault
        }
        .sheet(isPresented: $showingSetupSheet) {
            DuressSetupSheet()
        }
    }
}

struct DuressSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.vaultHighlight)

                Text("Set Up Duress Vault")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose which vault to keep accessible when under duress. All other vaults will be destroyed when this pattern is entered.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Text("Enter the pattern for the vault you want to use as your duress vault.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)

                // Pattern input would go here
                // For now, placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vaultSurface)
                    .frame(height: 200)
                    .overlay {
                        Text("Pattern input")
                            .foregroundStyle(.vaultSecondaryText)
                    }

                Spacer()
            }
            .padding()
            .navigationTitle("Duress Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - iCloud Backup Settings

struct iCloudBackupSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("iCloudBackupEnabled") private var isBackupEnabled = false
    @AppStorage("lastBackupTimestamp") private var lastBackupTimestamp: Double = 0
    @State private var isBackingUp = false
    @State private var backupStage: iCloudBackupManager.BackupStage?
    @State private var backupTask: Task<Void, Never>?
    @State private var showingRestore = false
    @State private var iCloudAvailable = true
    @State private var errorMessage: String?

    /// Backups run automatically every 24 hours when enabled.
    private static let backupInterval: TimeInterval = 24 * 60 * 60

    private let backupManager = iCloudBackupManager.shared

    private var lastBackupDate: Date? {
        lastBackupTimestamp > 0 ? Date(timeIntervalSince1970: lastBackupTimestamp) : nil
    }

    private var nextBackupDate: Date? {
        guard let last = lastBackupDate else { return nil }
        return last.addingTimeInterval(Self.backupInterval)
    }

    private var isBackupOverdue: Bool {
        guard let next = nextBackupDate else { return true }
        return Date() >= next
    }

    var body: some View {
        Group {
            if !iCloudAvailable {
                iCloudUnavailableView
            } else {
                List {
                    toggleSection

                    if isBackupEnabled {
                        statusSection
                        restoreSection
                    }
                }
            }
        }
        .navigationTitle("iCloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { onAppear() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { iCloudAvailable = await checkiCloudAvailable() }
        }
        .onChange(of: isBackupEnabled) { _, enabled in
            handleToggleChange(enabled)
        }
        .sheet(isPresented: $showingRestore) {
            RestoreFromBackupView()
        }
    }

    // MARK: - Views

    private var iCloudUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(.vaultSecondaryText)
            Text("iCloud Required")
                .font(.title2).fontWeight(.semibold)
            Text("iCloud is not available. Sign in to iCloud in Settings to enable backups.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button { SettingsURLHelper.openICloudSettings() } label: {
                Label("Open iCloud Settings", systemImage: "gear")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Button("Retry") {
                Task { iCloudAvailable = await checkiCloudAvailable() }
            }
            .foregroundStyle(.vaultSecondaryText)
        }
        .padding(.top, 60)
    }

    private var toggleSection: some View {
        Section {
            Toggle("Enable iCloud Backup", isOn: $isBackupEnabled)
        } footer: {
            Text("Encrypted vault data is backed up to your iCloud Drive daily. Only you can decrypt it with your pattern.")
        }
    }

    private var statusSection: some View {
        Section("Backup Status") {
            if isBackingUp {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(backupStage?.rawValue ?? "Preparing...")
                        .foregroundStyle(.vaultSecondaryText)
                }

                Button("Cancel Backup", role: .destructive) {
                    backupTask?.cancel()
                    backupTask = nil
                    isBackingUp = false
                    backupStage = nil
                }
                .font(.subheadline)
            } else if let date = lastBackupDate {
                HStack {
                    Text("Last backup")
                    Spacer()
                    Text(date, style: .relative)
                        .foregroundStyle(.vaultSecondaryText)
                }

                if let next = nextBackupDate {
                    HStack {
                        Text("Next backup")
                        Spacer()
                        if Date() >= next {
                            Text("On next app open")
                                .foregroundStyle(.vaultSecondaryText)
                        } else {
                            Text(next, style: .relative)
                                .foregroundStyle(.vaultSecondaryText)
                        }
                    }
                }
            } else {
                Text("No backup yet")
                    .foregroundStyle(.vaultSecondaryText)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Backup Failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.medium))
                    Text(errorMessage)
                        .foregroundStyle(.vaultSecondaryText)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            if !isBackingUp {
                Button("Backup Now") { performBackup() }
            }
        }
    }

    private var restoreSection: some View {
        Section("Restore") {
            Button("Restore from Backup") {
                showingRestore = true
            }
        }
    }

    // MARK: - Logic

    private func checkiCloudAvailable() async -> Bool {
        let status = await CloudKitSharingManager.shared.checkiCloudStatus()
        // .temporarilyUnavailable means signed in but CloudKit still syncing — treat as available
        return status == .available || status == .temporarilyUnavailable
    }

    private func onAppear() {
        Task {
            let available = await checkiCloudAvailable()
            iCloudAvailable = available
            if !available && isBackupEnabled {
                isBackupEnabled = false
            }
            // Auto-backup if enabled and overdue
            if isBackupEnabled && available && isBackupOverdue {
                performBackup()
            }
        }
    }

    private func handleToggleChange(_ enabled: Bool) {
        guard enabled else { return }

        // Check iCloud via CloudKit account status before allowing enable
        Task {
            let available = await checkiCloudAvailable()
            guard available else {
                isBackupEnabled = false
                iCloudAvailable = false
                return
            }
            // First enable — run backup immediately
            performBackup()
        }
    }

    private func performBackup() {
        guard let key = appState.currentVaultKey else {
            errorMessage = "No vault key available"
            return
        }

        isBackingUp = true
        backupStage = nil
        errorMessage = nil

        backupTask = Task {
            do {
                try await backupManager.performBackup(with: key) { stage in
                    Task { @MainActor in
                        backupStage = stage
                    }
                }
                await MainActor.run {
                    lastBackupTimestamp = Date().timeIntervalSince1970
                    isBackingUp = false
                    backupStage = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    isBackingUp = false
                    backupStage = nil
                }
            } catch iCloudError.notAvailable {
                await MainActor.run {
                    errorMessage = "iCloud is not available. Check that you're signed in to iCloud in Settings."
                    isBackingUp = false
                    backupStage = nil
                }
            } catch iCloudError.fileNotFound {
                await MainActor.run {
                    errorMessage = "No vault data found to back up. Add some files first."
                    isBackingUp = false
                    backupStage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "\(error.localizedDescription)\n\nError type: \(type(of: error))\nDetails: \(error)"
                    isBackingUp = false
                    backupStage = nil
                }
            }
        }
    }
}

struct RestoreFromBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var patternState = PatternState()
    @State private var showFeedback = true
    @State private var backupInfo: iCloudBackupManager.BackupMetadata?
    @State private var isCheckingBackup = true
    @State private var noBackupFound = false
    @State private var isRestoring = false
    @State private var restoreStage: String?
    @State private var errorMessage: String?
    @State private var restoreSuccess = false

    private let backupManager = iCloudBackupManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if isCheckingBackup {
                    ProgressView("Checking for backup...")
                } else if noBackupFound {
                    noBackupView
                } else if restoreSuccess {
                    successView
                } else {
                    restoreContentView
                }
            }
            .navigationTitle("Restore from Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isRestoring)
        .task { await checkForBackup() }
    }

    private var noBackupView: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(.vaultSecondaryText)
            Text("No Backup Found")
                .font(.title2).fontWeight(.semibold)
            Text("No iCloud backup was found for this account. Enable iCloud Backup and create a backup first.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 60)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Restore Complete")
                .font(.title2).fontWeight(.semibold)
            Text("Your vault has been restored. Lock and re-enter your pattern to access it.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(.top, 60)
    }

    private var restoreContentView: some View {
        VStack(spacing: 16) {
            if let info = backupInfo {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup from \(info.formattedDate)")
                            .font(.subheadline.weight(.medium))
                        Text(info.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.vaultSecondaryText)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if isRestoring {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(restoreStage ?? "Restoring...")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                }
                .padding(.top, 40)
            } else {
                Text("Draw your pattern to decrypt the backup")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)

                PatternGridView(state: patternState, showFeedback: $showFeedback) { pattern in
                    performRestore(with: pattern)
                }
                .frame(maxWidth: 280, maxHeight: 280)
                .padding()
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Restore Failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.medium))
                    Text(errorMessage)
                        .foregroundStyle(.vaultSecondaryText)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)

                Button("Try Again") {
                    resetForRetry()
                }
                .font(.subheadline)
            }

            Spacer()
        }
    }

    private func resetForRetry() {
        errorMessage = nil
        patternState.reset()
    }

    private func checkForBackup() async {
        isCheckingBackup = true
        let info = await backupManager.checkForBackup()
        await MainActor.run {
            backupInfo = info
            noBackupFound = info == nil
            isCheckingBackup = false
        }
    }

    private func performRestore(with pattern: [Int]) {
        guard pattern.count >= 6 else {
            patternState.reset()
            return
        }

        isRestoring = true
        errorMessage = nil
        restoreStage = "Deriving encryption key..."

        Task {
            do {
                let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)

                await MainActor.run { restoreStage = "Downloading from iCloud..." }
                try await backupManager.restoreBackup(with: key)

                await MainActor.run {
                    isRestoring = false
                    restoreSuccess = true
                }
            } catch iCloudError.notAvailable {
                await MainActor.run {
                    errorMessage = "iCloud is not available. Check your connection and try again."
                    isRestoring = false
                    patternState.reset()
                }
            } catch iCloudError.downloadFailed {
                await MainActor.run {
                    errorMessage = "Decryption failed. This usually means the pattern doesn't match the one used to create the backup."
                    isRestoring = false
                    patternState.reset()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "\(error.localizedDescription)\n\nDetails: \(error)"
                    isRestoring = false
                    patternState.reset()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppState())
    .environment(SubscriptionManager.shared)
}

