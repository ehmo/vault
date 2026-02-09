import SwiftUI
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

    #if DEBUG
    @State private var showingDebugResetConfirmation = false
    #endif

    var body: some View {
        List {
            // Premium
            Section("Premium") {
                HStack {
                    Image(systemName: subscriptionManager.isPremium ? "crown.fill" : "crown")
                        .foregroundStyle(subscriptionManager.isPremium ? .yellow : .secondary)
                    Text(subscriptionManager.isPremium ? "Premium" : "Free Plan")
                    Spacer()
                    if subscriptionManager.isPremium {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if subscriptionManager.isPremium {
                    Button("Manage Subscription") {
                        showingCustomerCenter = true
                    }
                } else {
                    Button("Upgrade to Premium") {
                        showingPaywall = true
                    }
                }

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
            }

            // Security & Privacy (merged)
            Section {
                Toggle("Show pattern feedback", isOn: $showFeedback)

                Toggle("Help improve Vault", isOn: $analyticsEnabled)

                NavigationLink("Duress pattern") {
                    DuressPatternSettingsView()
                }

                if subscriptionManager.canSyncWithICloud() {
                    NavigationLink("iCloud Backup") {
                        iCloudBackupSettingsView()
                    }
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
                
                Button(action: { showingDebugResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text("Full Reset / Wipe Everything")
                            .foregroundStyle(.vaultHighlight)
                    }
                }
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

            // Danger Zone
            Section {
                Button(role: .destructive, action: { showingNuclearConfirmation = true }) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Nuclear Option - Destroy All Data")
                    }
                }
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
    @State private var isBackupEnabled = false
    @State private var lastBackupDate: Date?
    @State private var isBackingUp = false
    @State private var showingRestore = false

    var body: some View {
        List {
            Section {
                Toggle("Enable iCloud Backup", isOn: $isBackupEnabled)
            } footer: {
                Text("Encrypted vault data is backed up to your iCloud Drive. Only you can decrypt it with your pattern.")
            }

            if isBackupEnabled {
                Section("Backup Status") {
                    if let date = lastBackupDate {
                        HStack {
                            Text("Last backup")
                            Spacer()
                            Text(date, style: .relative)
                                .foregroundStyle(.vaultSecondaryText)
                        }
                    } else {
                        Text("No backup yet")
                            .foregroundStyle(.vaultSecondaryText)
                    }

                    Button(action: performBackup) {
                        if isBackingUp {
                            HStack {
                                ProgressView()
                                Text("Backing up...")
                            }
                        } else {
                            Text("Backup Now")
                        }
                    }
                    .disabled(isBackingUp)
                }

                Section("Restore") {
                    Button("Restore from Backup") {
                        showingRestore = true
                    }
                }
            }
        }
        .navigationTitle("iCloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRestore) {
            RestoreFromBackupView()
        }
    }

    private func performBackup() {
        isBackingUp = true

        Task {
            // Perform backup
            try? await Task.sleep(nanoseconds: 2_000_000_000) // Simulated delay

            await MainActor.run {
                lastBackupDate = Date()
                isBackingUp = false
            }
        }
    }
}

struct RestoreFromBackupView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.vaultSecondaryText)

            Text("Restore from iCloud")
                .font(.title2)
                .fontWeight(.medium)

            Text("Enter your pattern to restore a vault from your iCloud backup.")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .navigationTitle("Restore")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppState())
    .environment(SubscriptionManager.shared)
}

