import SwiftUI
import CloudKit
import StoreKit
import os.log

private let settingsLogger = Logger(subsystem: "app.vaultaire.ios", category: "Settings")

// MARK: - App Settings View

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @AppStorage("showPatternFeedback") private var showFeedback = true
    @AppStorage("analyticsEnabled") private var analyticsEnabled = false
    @AppStorage("fileOptimization") private var fileOptimization = "optimized"
    @AppStorage("networkPreference") private var networkPreference = "wifi"
    @AppStorage("iCloudBackupDefault") private var iCloudBackupDefault = true

    @State private var showingNuclearConfirmation = false
    @State private var showingPaywall = false
    @State private var showingCustomerCenter = false
    @State private var isRestoringPurchases = false
    @State private var showingClearStagedConfirmation = false
    @State private var pendingStagedSize: Int64 = 0
    @State private var showingOnboardingReplay = false

    #if DEBUG
    @State private var showingDebugResetConfirmation = false
    @State private var isNukingICloud = false
    @State private var iCloudNukeResult: String?
    #endif

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

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

            // Appearance
            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    HStack {
                        Text("Appearance")
                        Spacer()
                        Text(appState.appearanceMode.title)
                            .foregroundStyle(.vaultSecondaryText)
                    }
                }
                .accessibilityIdentifier("app_appearance_setting")

                Toggle("Show pattern feedback", isOn: $showFeedback)
                    .accessibilityIdentifier("app_pattern_feedback")
            } header: {
                Text("Appearance")
            }

            // Storage & Backup
            Section {
                Picker("Import Quality", selection: $fileOptimization) {
                    Text("Optimized").tag("optimized")
                    Text("Original").tag("original")
                }
                .accessibilityIdentifier("app_file_optimization")

                if subscriptionManager.isPremium {
                    Toggle("Auto-enable backup for new vaults", isOn: $iCloudBackupDefault)
                        .accessibilityIdentifier("app_icloud_backup_default")
                }
            } header: {
                Text("Storage & Backup")
            } footer: {
                if subscriptionManager.isPremium {
                    if fileOptimization == "optimized" {
                        Text("Reduces file sizes by up to 85%. New vaults will \(iCloudBackupDefault ? "automatically" : "not") have iCloud backup enabled.")
                    } else {
                        Text("Keeps files at original size and format. New vaults will \(iCloudBackupDefault ? "automatically" : "not") have iCloud backup enabled.")
                    }
                } else {
                    if fileOptimization == "optimized" {
                        Text("Reduces file sizes by up to 85%.")
                    } else {
                        Text("Keeps files at original size and format.")
                    }
                }
            }

            // Network
            Section {
                Picker("Sync & Backup over", selection: $networkPreference) {
                    Text("Wi-Fi Only").tag("wifi")
                    Text("Wi-Fi & Cellular").tag("any")
                }
                .accessibilityIdentifier("app_network_preference")
            } header: {
                Text("Network")
            } footer: {
                Text("Controls when share syncs and iCloud backups run. Wi-Fi Only saves cellular data.")
            }

            // Privacy & Analytics
            Section {
                Toggle("Help improve Vault", isOn: $analyticsEnabled)
                    .accessibilityIdentifier("app_analytics_toggle")
            } header: {
                Text("Privacy")
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
                    Text(appVersion)
                        .foregroundStyle(.vaultSecondaryText)
                }

                Button {
                    showingOnboardingReplay = true
                } label: {
                    Text("Review Onboarding")
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("app_review_onboarding")

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

                Button(action: { nukeAllICloudData() }) {
                    HStack {
                        if isNukingICloud {
                            ProgressView()
                                .controlSize(.small)
                            Text("Nuking iCloud...")
                        } else {
                            Image(systemName: "icloud.slash.fill")
                                .foregroundStyle(.red)
                            Text("Nuke All iCloud Data")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(isNukingICloud)
                .accessibilityIdentifier("debug_nuke_icloud")

                if let iCloudNukeResult {
                    Text(iCloudNukeResult)
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                }
            } header: {
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(.vaultHighlight)
                    Text("Debug Tools")
                }
            } footer: {
                Text("Development only: Reset onboarding or completely wipe all data including vault files, recovery phrases, settings, and Keychain entries. Nuke iCloud deletes ALL CloudKit records (shared vaults + backups).")
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Destroy All Data?", isPresented: $showingNuclearConfirmation) {
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
            Button("Destroy Everything", role: .destructive) {
                performNuclearWipe()
            }
        } message: {
            Text("This will permanently destroy ALL vaults and ALL data. This action cannot be undone. The app will reset to its initial state.")
        }
        #if DEBUG
        .alert("Debug: Full Reset", isPresented: $showingDebugResetConfirmation) {
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
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
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
            Button("Clear All", role: .destructive) {
                StagedImportManager.deleteAllBatches()
                pendingStagedSize = 0
            }
        } message: {
            Text("This will delete all files shared via the share extension that haven't been imported yet.")
        }
        .premiumPaywall(isPresented: $showingPaywall)
        .manageSubscriptionsSheet(isPresented: $showingCustomerCenter)
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showingOnboardingReplay) {
            OnboardingView(onReplayDismiss: { showingOnboardingReplay = false })
                .environment(appState)
                .environment(SubscriptionManager.shared)
        }
    }

    private func performNuclearWipe() {
        Task {
            await DuressHandler.shared.performNuclearWipe()
            await SubscriptionManager.shared.resetAfterWipe()
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
        settingsLogger.info("Starting full debug reset")
        
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
        
        // 6. Reset subscription state
        await SubscriptionManager.shared.resetAfterWipe()

        // 7. Reset app state
        await MainActor.run {
            appState.lockVault()
            appState.resetToOnboarding()
        }

        settingsLogger.info("Full debug reset complete")
    }
    
    private func clearVaultStorage() async {
        // Delete vault storage directory
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vaultURL = documentsURL.appendingPathComponent("vault_storage")
        
        try? fileManager.removeItem(at: vaultURL)
        
        settingsLogger.debug("Vault storage cleared")
    }
    
    private func clearRecoveryMappings() {
        UserDefaults.standard.removeObject(forKey: "recovery_mapping")
        
        settingsLogger.debug("Recovery mappings cleared")
    }
    
    private func clearUserDefaults() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        settingsLogger.debug("UserDefaults cleared")
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
        
        settingsLogger.debug("Keychain cleared")
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

        settingsLogger.debug("Temporary files cleared")
    }

    private func nukeAllICloudData() {
        isNukingICloud = true
        iCloudNukeResult = nil
        Task {
            var deleted = 0
            var errors = 0
            let container = CKContainer(identifier: "iCloud.app.vaultaire.shared")
            let publicDB = container.publicCloudDatabase
            let privateDB = container.privateCloudDatabase

            // Helper: delete all records of a given type from a database using a queryable field
            func deleteAll(recordType: String, queryableField: String, database: CKDatabase) async {
                let predicate = NSPredicate(format: "%K BEGINSWITH %@", queryableField, "")
                let query = CKQuery(recordType: recordType, predicate: predicate)

                // Collect all record IDs first
                var allIds: [CKRecord.ID] = []
                do {
                    let result = try await database.records(matching: query, desiredKeys: [], resultsLimit: 200)
                    allIds.append(contentsOf: result.matchResults.map { $0.0 })
                    var cursor = result.queryCursor
                    while let activeCursor = cursor {
                        let page = try await database.records(continuingMatchFrom: activeCursor, desiredKeys: [], resultsLimit: 200)
                        allIds.append(contentsOf: page.matchResults.map { $0.0 })
                        cursor = page.queryCursor
                    }
                } catch {
                    settingsLogger.error("Query failed for \(recordType) (\(queryableField)): \(error)")
                    errors += 1
                    return
                }

                let totalCount = allIds.count
                settingsLogger.info("[nuke] [\(recordType)] Found \(totalCount) records to delete")
                await MainActor.run { iCloudNukeResult = "Deleting \(totalCount) \(recordType) records..." }

                // Delete in non-atomic batches of 100 using CKModifyRecordsOperation
                for batch in stride(from: 0, to: allIds.count, by: 100) {
                    let end = min(batch + 100, allIds.count)
                    let batchIds = Array(allIds[batch..<end])

                    var batchDeleted = 0
                    var batchErrors = 0

                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batchIds)
                        op.isAtomic = false
                        op.perRecordDeleteBlock = { recordId, result in
                            switch result {
                            case .success:
                                batchDeleted += 1
                            case .failure(let err):
                                batchErrors += 1
                                settingsLogger.error("[nuke] \(recordType, privacy: .public) \(recordId.recordName, privacy: .public): \(String(describing: err), privacy: .public)")
                            }
                        }
                        op.modifyRecordsResultBlock = { _ in
                            continuation.resume()
                        }
                        database.add(op)
                    }

                    deleted += batchDeleted
                    errors += batchErrors
                    settingsLogger.info("[nuke] \(recordType) batch: \(batchDeleted) deleted, \(batchErrors) errors")
                }
            }

            // Public DB: SharedVault + SharedVaultChunk
            await deleteAll(recordType: "SharedVault", queryableField: "shareVaultId", database: publicDB)
            await deleteAll(recordType: "SharedVaultChunk", queryableField: "vaultId", database: publicDB)

            // Private DB: VaultBackupChunk (query by backupId)
            await deleteAll(recordType: "VaultBackupChunk", queryableField: "backupId", database: privateDB)

            // Private DB: VaultBackup manifest uses fixed recordName "current_backup"
            do {
                let backupRecordId = CKRecord.ID(recordName: "current_backup")
                try await privateDB.deleteRecord(withID: backupRecordId)
                deleted += 1
            } catch {
                // May not exist — that's fine
                settingsLogger.info("No VaultBackup manifest to delete: \(error.localizedDescription)")
            }

            await MainActor.run {
                isNukingICloud = false
                iCloudNukeResult = "Deleted \(deleted) records. \(errors > 0 ? "\(errors) errors." : "No errors.")"
                settingsLogger.info("iCloud nuke complete: \(deleted) deleted, \(errors) errors")
            }
        }
    }
    #endif
}

// MARK: - Legacy SettingsView (Kept for compatibility)

struct SettingsView: View {
    var body: some View {
        AppSettingsView()
    }
}

struct iCloudBackupSettingsView: View {
    @Environment(AppState.self) private var appState

    let vaultFingerprint: String

    @State private var isBackupEnabled = false
    @State private var lastBackupTimestamp: Double = 0
    @State private var isBackingUp = false
    @State private var backupStage: iCloudBackupManager.BackupStage?
    @State private var uploadProgress: Double = 0
    @State private var backupTask: Task<Void, Never>?
    @State private var showingRestore = false
    @State private var iCloudAvailable = true
    @State private var errorMessage: String?
    @State private var totalBackupStorage: Int64 = 0
    @State private var versionCount = 0
    @State private var showingDeleteAllConfirmation = false
    @State private var suppressToggleHandler = false

    /// Backups run automatically every 24 hours when enabled.
    private static let backupInterval: TimeInterval = 24 * 60 * 60

    private let backupManager = iCloudBackupManager.shared

    private var enabledKey: String { "iCloudBackupEnabled_\(vaultFingerprint)" }
    private var timestampKey: String { "lastBackupTimestamp_\(vaultFingerprint)" }

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
        ZStack {
            Color.vaultBackground.ignoresSafeArea()

            Group {
                if !iCloudAvailable {
                    iCloudUnavailableView
                } else {
                    List {
                        toggleSection

                        if isBackupEnabled {
                            statusSection
                            storageSection
                            restoreSection
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("iCloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { onAppear() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { @MainActor in
                iCloudAvailable = await checkiCloudAvailable()
            }
        }
        .onChange(of: isBackupEnabled) { _, enabled in
            handleToggleChange(enabled)
        }
        .fullScreenCover(isPresented: $showingRestore) {
            RestoreFromBackupView()
        }
        .alert("Delete All Backups?", isPresented: $showingDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {
                // Revert toggle without triggering handleToggleChange
                suppressToggleHandler = true
                isBackupEnabled = true
            }
            Button("Delete All", role: .destructive) {
                confirmDisableBackup()
                deleteAllVersions()
            }
        } message: {
            Text("Disabling backup will delete all \(versionCount) backup version\(versionCount == 1 ? "" : "s") from iCloud. This cannot be undone.")
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
                .lineLimit(nil)
                .padding(.horizontal)

            Button { SettingsURLHelper.openICloudSettings() } label: {
                Label("Open iCloud Settings", systemImage: "gear")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Button("Retry") {
                Task { @MainActor in
                    iCloudAvailable = await checkiCloudAvailable()
                }
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if backupStage != .uploading {
                            ProgressView()
                        }
                        Text(backupStage?.rawValue ?? "Preparing...")
                            .foregroundStyle(.vaultSecondaryText)
                    }
                    if backupStage == .uploading {
                        HStack(spacing: 8) {
                            ProgressView(value: uploadProgress)
                                .tint(Color.accentColor)
                            Text("\(Int(uploadProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.vaultSecondaryText)
                                .monospacedDigit()
                        }
                    }
                }

                Button("Cancel Backup", role: .destructive) {
                    backupTask?.cancel()
                    backupTask = nil
                    isBackingUp = false
                    backupStage = nil
                    // Clear staged files so auto-resume doesn't restart the cancelled backup
                    backupManager.clearStagingDirectory(fingerprint: vaultFingerprint)
                    IdleTimerManager.shared.enable()
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

    private var storageSection: some View {
        Section {
            HStack {
                Text("Backup versions")
                Spacer()
                Text("\(versionCount)")
                    .foregroundStyle(.vaultSecondaryText)
            }

            HStack {
                Text("Total backup storage")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: totalBackupStorage, countStyle: .file))
                    .foregroundStyle(.vaultSecondaryText)
            }
        } header: {
            Text("Storage")
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
        // Load per-vault settings from UserDefaults
        isBackupEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        lastBackupTimestamp = UserDefaults.standard.double(forKey: timestampKey)
        loadVersionInfo()

        Task { @MainActor in
            let available = await checkiCloudAvailable()
            iCloudAvailable = available
            if !available && isBackupEnabled {
                isBackupEnabled = false
                UserDefaults.standard.set(false, forKey: enabledKey)
            }

            // Settings view is read-only — auto-backup runs from ContentView on vault unlock
            // and resumeBackupUploadIfNeeded on app resume. Only "Backup Now" triggers here.
        }
    }

    private func handleToggleChange(_ enabled: Bool) {
        if suppressToggleHandler {
            suppressToggleHandler = false
            return
        }
        guard enabled else {
            // Show confirmation to delete all backup versions
            if versionCount > 0 {
                showingDeleteAllConfirmation = true
            } else {
                confirmDisableBackup()
            }
            return
        }

        UserDefaults.standard.set(true, forKey: enabledKey)

        // Check iCloud via CloudKit account status before allowing enable
        Task { @MainActor in
            let available = await checkiCloudAvailable()
            guard available else {
                isBackupEnabled = false
                UserDefaults.standard.set(false, forKey: enabledKey)
                iCloudAvailable = false
                return
            }
            // First enable — run backup immediately
            performBackup()
        }
    }

    private func performBackup() {
        guard !isBackingUp else { return }
        
        // Check if there's a pending backup to resume
        if backupManager.hasPendingBackup {
            resumePendingBackup()
            return
        }
        
        guard let key = appState.currentVaultKey else {
            errorMessage = "No vault key available"
            return
        }

        isBackingUp = true
        backupStage = nil
        uploadProgress = 0
        errorMessage = nil
        IdleTimerManager.shared.disable()

        backupTask = Task {
            defer {
                Task { @MainActor in
                    IdleTimerManager.shared.enable()
                }
            }
            do {
                try await backupManager.performBackup(
                    with: key.rawBytes,
                    pattern: appState.currentPattern,
                    gridSize: 5,
                    onProgress: { @Sendable stage in
                        Task { @MainActor in
                            backupStage = stage
                        }
                    },
                    onUploadProgress: { @Sendable progress in
                        Task { @MainActor in
                            uploadProgress = progress
                        }
                    }
                )
                await MainActor.run {
                    let now = Date().timeIntervalSince1970
                    lastBackupTimestamp = now
                    UserDefaults.standard.set(now, forKey: timestampKey)
                    uploadProgress = 1.0 // Show 100% briefly before hiding
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
            } catch iCloudError.wifiRequired {
                await MainActor.run {
                    errorMessage = "Wi-Fi required. Change in Settings → Network to allow cellular."
                    isBackingUp = false
                    backupStage = nil
                }
            } catch iCloudError.backupSkipped {
                await MainActor.run {
                    errorMessage = "Nothing to back up. Add some files first."
                    isBackingUp = false
                    backupStage = nil
                }
            } catch {
                EmbraceManager.shared.captureError(
                    error,
                    context: ["feature": "icloud_backup_settings"]
                )
                await MainActor.run {
                    errorMessage = "\(error.localizedDescription)\n\nError type: \(type(of: error))\nDetails: \(error)"
                    isBackingUp = false
                    backupStage = nil
                }
            }
        }
    }
    
    /// Resumes an interrupted backup from staged data
    private func confirmDisableBackup() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        backupTask?.cancel()
        backupTask = nil
        isBackingUp = false
        backupStage = nil
        IdleTimerManager.shared.enable()
    }

    private func deleteAllVersions() {
        guard let pattern = appState.currentPattern else { return }
        Task {
            do {
                let backupKey = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
                try await backupManager.deleteAllBackups(backupKey: backupKey)
                await MainActor.run {
                    versionCount = 0
                    totalBackupStorage = 0
                }
            } catch {
                EmbraceManager.shared.captureError(error, context: ["action": "deleteAllBackupVersions"])
            }
        }
    }

    private func loadVersionInfo() {
        guard let pattern = appState.currentPattern else { return }
        Task {
            do {
                let backupKey = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)

                // Load from local cache first for instant display
                if let cached = backupManager.getCachedVersionIndex(backupKey: backupKey) {
                    let cachedSize = cached.versions.reduce(0) { $0 + Int64($1.size) }
                    await MainActor.run {
                        versionCount = cached.versions.count
                        totalBackupStorage = cachedSize
                    }
                }

                // Refresh from CloudKit in background
                let versionIndex = try await backupManager.scanForVersions(backupKey: backupKey)
                let totalSize = versionIndex.versions.reduce(0) { $0 + Int64($1.size) }
                await MainActor.run {
                    versionCount = versionIndex.versions.count
                    totalBackupStorage = totalSize
                }
            } catch {
                // Silently fail — storage display is informational
            }
        }
    }

    private func resumePendingBackup() {
        isBackingUp = true
        backupStage = .uploading
        // Don't set uploadProgress to 0 - the uploadStagedBackup function
        // will immediately report the correct initial progress based on
        // already-uploaded chunks. This prevents the "0% then jump" issue.
        uploadProgress = -1 // Use negative to indicate "calculating..."
        errorMessage = nil
        IdleTimerManager.shared.disable()

        backupTask = Task {
            defer {
                Task { @MainActor in
                    IdleTimerManager.shared.enable()
                }
            }
            do {
                // Resume upload from staged data (no vault key needed)
                try await backupManager.uploadStagedBackup(onUploadProgress: { @Sendable progress in
                    Task { @MainActor in
                        uploadProgress = progress
                    }
                })
                await MainActor.run {
                    let now = Date().timeIntervalSince1970
                    lastBackupTimestamp = now
                    UserDefaults.standard.set(now, forKey: timestampKey)
                    uploadProgress = 1.0 // Show 100% briefly before hiding
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
            } catch {
                EmbraceManager.shared.captureError(
                    error,
                    context: ["feature": "icloud_backup_resume"]
                )
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
    @State private var versions: [iCloudBackupManager.BackupVersionEntry] = []
    @State private var selectedVersion: iCloudBackupManager.BackupVersionEntry?
    @State private var isLoading = true
    @State private var noBackupFound = false
    @State private var isRestoring = false
    @State private var restoreStage: String?
    @State private var downloadProgress: (downloaded: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var restoreSuccess = false

    private let backupManager = iCloudBackupManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaultBackground.ignoresSafeArea()

                Group {
                    if isLoading {
                        ProgressView("Checking for backups...")
                    } else if restoreSuccess {
                        successView
                    } else if selectedVersion != nil {
                        restorePatternView
                    } else if noBackupFound {
                        noBackupView
                    } else {
                        versionListView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(selectedVersion != nil ? "Enter Pattern" : "Restore from Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.vaultBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedVersion != nil && !isRestoring {
                        Button("Back") {
                            selectedVersion = nil
                            errorMessage = nil
                            patternState.reset()
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRestoring)
        .task { await loadVersions() }
    }

    // MARK: - Version List

    private var versionListView: some View {
        List {
            Section {
                ForEach(versions, id: \.backupId) { version in
                    Button {
                        selectedVersion = version
                        errorMessage = nil
                        patternState.reset()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.timestamp, style: .date)
                                    .font(.subheadline.weight(.medium))
                                HStack(spacing: 8) {
                                    Text(version.timestamp, style: .time)
                                    Text("·")
                                    Text(formatSize(version.size))
                                    Text("·")
                                    Text("\(version.chunkCount) chunks")
                                }
                                .font(.caption)
                                .foregroundStyle(.vaultSecondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.vaultSecondaryText)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: deleteVersions)
            } header: {
                Text("Available Backups")
            } footer: {
                Text("Select a backup version to restore. Draw your pattern to decrypt and restore your vault data.")
            }

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - No Backup

    private var noBackupView: some View {
        VStack(spacing: 16) {
            Image(systemName: errorMessage != nil ? "exclamationmark.icloud.fill" : "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(errorMessage != nil ? .red : .vaultSecondaryText)

            if let errorMessage {
                Text("Backup Check Failed")
                    .font(.title2).fontWeight(.semibold)
                Text(errorMessage)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal)

                Button("Retry") {
                    self.errorMessage = nil
                    self.noBackupFound = false
                    self.isLoading = true
                    Task { await loadVersions() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            } else {
                Text("No Backup Found")
                    .font(.title2).fontWeight(.semibold)
                Text("No iCloud backup was found for this vault. Enable iCloud Backup and create a backup first.")
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Success

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
                .lineLimit(nil)
                .padding(.horizontal)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(.top, 60)
    }

    // MARK: - Pattern Entry for Selected Version

    private var restorePatternView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                if let version = selectedVersion {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.timestamp, style: .date)
                                .font(.subheadline.weight(.medium))
                            Text("\(formatSize(version.size))")
                                .font(.caption)
                                .foregroundStyle(.vaultSecondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text("Draw your pattern to decrypt the backup")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .top)
            }

            Spacer(minLength: 0)

            if isRestoring {
                VStack(spacing: 12) {
                    if let progress = downloadProgress {
                        ProgressView(value: Double(progress.downloaded), total: Double(progress.total))
                            .tint(Color.accentColor)
                            .frame(width: 200)
                        Text("Downloading \(progress.downloaded) of \(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.vaultSecondaryText)
                            .monospacedDigit()
                    } else {
                        ProgressView()
                    }
                    Text(restoreStage ?? "Restoring...")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 280, height: 280)
                .frame(maxWidth: .infinity)
            } else {
                PatternGridView(state: patternState, showFeedback: $showFeedback) { pattern in
                    performVersionRestore(with: pattern)
                }
                .frame(width: 280, height: 280)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("restore_pattern_grid")
            }

            Spacer(minLength: 0)

            Group {
                if let errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.vaultHighlight)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(errorMessage)
                                .font(.caption)
                                .lineLimit(nil)
                            Button("Try Again") {
                                self.errorMessage = nil
                                self.downloadProgress = nil
                                patternState.reset()
                            }
                            .font(.caption.weight(.medium))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vaultGlassBackground(cornerRadius: 12)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Color.clear
                }
            }
            .frame(height: 80)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Logic

    private func loadVersions() async {
        isLoading = true

        guard appState.currentVaultKey != nil, let pattern = appState.currentPattern else {
            await MainActor.run { isLoading = false; noBackupFound = true }
            return
        }

        do {
            let backupKey = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)

            // Load from local cache first for instant display
            if let cached = backupManager.getCachedVersionIndex(backupKey: backupKey) {
                let cachedVersions = cached.versions.sorted { $0.timestamp > $1.timestamp }
                await MainActor.run {
                    versions = cachedVersions
                    noBackupFound = cachedVersions.isEmpty
                    isLoading = !cachedVersions.isEmpty // Keep loading if cache was empty
                }
            }

            // Refresh from CloudKit
            let versionIndex = try await backupManager.scanForVersions(backupKey: backupKey)

            await MainActor.run {
                versions = versionIndex.versions.sorted { $0.timestamp > $1.timestamp }
                noBackupFound = versions.isEmpty
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                noBackupFound = true
                errorMessage = "Failed to check iCloud: \(error.localizedDescription)"
            }
        }
    }

    private func deleteVersions(at offsets: IndexSet) {
        let versionsToDelete = offsets.map { versions[$0] }
        versions.remove(atOffsets: offsets)

        Task {
            guard let backupKey = try? KeyDerivation.deriveBackupKey(from: appState.currentPattern ?? [], gridSize: 5) else { return }
            for version in versionsToDelete {
                do {
                    try await backupManager.deleteBackupVersion(version, backupKey: backupKey)
                } catch {
                    EmbraceManager.shared.captureError(error, context: ["action": "deleteBackupVersion"])
                }
            }
            await MainActor.run {
                if versions.isEmpty {
                    noBackupFound = true
                }
            }
        }
    }

    private func performVersionRestore(with pattern: [Int]) {
        guard pattern.count >= 6 else {
            patternState.reset()
            return
        }

        guard let version = selectedVersion else {
            patternState.reset()
            return
        }

        isRestoring = true
        errorMessage = nil
        downloadProgress = nil
        restoreStage = "Deriving encryption key..."

        Task {
            do {
                let backupKey = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: patternState.gridSize)

                await MainActor.run { restoreStage = "Downloading..." }
                try await backupManager.restoreBackupVersion(version, backupKey: backupKey) { @Sendable downloaded, total in
                    Task { @MainActor in
                        downloadProgress = (downloaded, total)
                    }
                }

                await MainActor.run {
                    downloadProgress = nil
                    isRestoring = false
                    restoreSuccess = true
                }
            } catch iCloudError.checksumMismatch {
                await MainActor.run {
                    errorMessage = "Wrong pattern. The pattern doesn't match the one used for this backup."
                    isRestoring = false
                    downloadProgress = nil
                    patternState.reset()
                }
            } catch iCloudError.notAvailable {
                await MainActor.run {
                    errorMessage = "iCloud is not available. Check your connection and try again."
                    isRestoring = false
                    downloadProgress = nil
                    patternState.reset()
                }
            } catch iCloudError.downloadFailed {
                await MainActor.run {
                    errorMessage = "Download failed. The backup data may be corrupted."
                    isRestoring = false
                    downloadProgress = nil
                    patternState.reset()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRestoring = false
                    downloadProgress = nil
                    patternState.reset()
                }
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppState())
    .environment(SubscriptionManager.shared)
}
