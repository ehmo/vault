import SwiftUI

// MARK: - App Settings Destination

enum AppSettingsDestination: Hashable {
    case duressPattern
    case iCloudBackup
    case restoreBackup
}

// MARK: - App Settings View

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @AppStorage("showPatternFeedback") private var showFeedback = true
    @AppStorage("randomizeGrid") private var randomizeGrid = false
    @AppStorage("analyticsEnabled") private var analyticsEnabled = false

    @State private var wipeThreshold: WipePolicyThreshold = .tenAttempts
    @State private var showingNuclearConfirmation = false
    
    #if DEBUG
    @State private var showingDebugResetConfirmation = false
    #endif

    var body: some View {
        List {
            // Pattern Settings
            Section("Pattern Lock") {
                Toggle("Show visual feedback", isOn: $showFeedback)

                Toggle("Randomize grid (smudge defense)", isOn: $randomizeGrid)
            }

            // Security Settings
            Section("Security") {
                Picker("Auto-wipe after failed attempts", selection: $wipeThreshold) {
                    ForEach(WipePolicyThreshold.allCases, id: \.self) { threshold in
                        Text(threshold.displayName).tag(threshold)
                    }
                }

                NavigationLink("Duress pattern") {
                    DuressPatternSettingsView()
                }
            }

            // Backup
            Section("Backup") {
                NavigationLink("iCloud Backup") {
                    iCloudBackupSettingsView()
                }
            }

            // Privacy
            Section {
                Toggle("Help improve Vault", isOn: $analyticsEnabled)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Share anonymous crash reports and usage statistics. No personal data is collected.")
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
                        .foregroundStyle(.secondary)
                }
                
                #if DEBUG
                HStack {
                    Text("Build Configuration")
                    Spacer()
                    Text("Debug")
                        .foregroundStyle(.orange)
                }
                #else
                HStack {
                    Text("Build Configuration")
                    Spacer()
                    Text("Release")
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.orange)
                        Text("Reset Onboarding")
                    }
                }
                
                Button(action: { showingDebugResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.red)
                        Text("Full Reset / Wipe Everything")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(.orange)
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
        .onAppear {
            wipeThreshold = WipePolicy.shared.threshold
        }
        .onChange(of: wipeThreshold) { _, newValue in
            WipePolicy.shared.threshold = newValue
        }
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
                        .foregroundStyle(.secondary)

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
        .onAppear {
            Task {
                hasDuressVault = await DuressHandler.shared.hasDuressVault
            }
        }
        .sheet(isPresented: $showingSetupSheet) {
            DuressSetupSheet()
        }
    }
}

struct DuressSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Duress Vault")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Set Up Duress Vault")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose which vault to keep accessible when under duress. All other vaults will be destroyed when this pattern is entered.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Text("Enter the pattern for the vault you want to use as your duress vault.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Pattern input would go here
                // For now, placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 200)
                    .overlay {
                        Text("Pattern input")
                            .foregroundStyle(.secondary)
                    }

                Spacer()
            }
            .padding()
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
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No backup yet")
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)

            Text("Restore from iCloud")
                .font(.title2)
                .fontWeight(.medium)

            Text("Enter your pattern to restore a vault from your iCloud backup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .navigationTitle("Restore")
    }
}

#Preview {
    SettingsView()
}

