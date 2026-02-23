import SwiftUI
import os.log

private let vaultSettingsLogger = Logger(subsystem: "app.vaultaire.ios", category: "VaultSettings")

struct VaultSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var showingChangePattern = false
    @State private var showingRegeneratedPhrase = false
    @State private var regenerateErrorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingShareVault = false
    @State private var showingRegenerateConfirmation = false
    @State private var isSharedVault = false
    @State private var activeShareCount = 0
    @State private var showingCustomPhraseInput = false
    @State private var showingDuressConfirmation = false
    @State private var isDuressVault = false
    @State private var pendingDuressValue = false
    @State private var hasLoadedDuressState = false
    @State private var duressAlreadyEnabled = false
    @State private var activeUploadCount = 0
    @State private var fileCount = 0
    @State private var storageUsed: Int64 = 0
    @State private var showingPaywall = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""

    var body: some View {
        List {
            // Vault Info
            Section("This Vault") {
                Button {
                    renameText = appState.vaultName
                    showingRenameAlert = true
                } label: {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(appState.vaultName)
                            .foregroundStyle(.vaultSecondaryText)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("settings_vault_name")

                HStack {
                    Text("Files")
                    Spacer()
                    Text("\(fileCount)")
                        .foregroundStyle(.vaultSecondaryText)
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(formatBytes(storageUsed))
                        .foregroundStyle(.vaultSecondaryText)
                }
            }

            // Pattern Management
            Section("Pattern") {
                Button("Change pattern for this vault") {
                    showingChangePattern = true
                }
                .accessibilityIdentifier("settings_change_pattern")
            }

            // Recovery
            Section("Recovery") {
                Button("Regenerate recovery phrase") {
                    showingRegenerateConfirmation = true
                }
                .accessibilityIdentifier("settings_regen_phrase")

                Button("Set custom recovery phrase") {
                    showingCustomPhraseInput = true
                }
                .accessibilityIdentifier("settings_custom_phrase")
            }

            // Sharing
            Section {
                if isSharedVault {
                    HStack {
                        Text("This is a shared vault")
                        Spacer()
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.vaultSecondaryText)
                    }
                } else {
                    if subscriptionManager.canCreateSharedVault() {
                        Button("Share This Vault") {
                            showingShareVault = true
                        }
                        .accessibilityIdentifier("settings_share_vault")
                    } else {
                        Button(action: { showingPaywall = true }) {
                            HStack {
                                Text("Share This Vault")
                                Spacer()
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(.vaultHighlight)
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("settings_share_vault")
                    }
                    if activeShareCount > 0 {
                        HStack {
                            Text("Shared with")
                            Spacer()
                            Text("\(activeShareCount) \(activeShareCount == 1 ? "person" : "people")")
                                .foregroundStyle(.vaultSecondaryText)
                        }
                    }
                }
            } header: {
                Text("Sharing")
            } footer: {
                if isSharedVault {
                    Text("This vault was shared with you. You cannot reshare it.")
                } else {
                    Text("Share this vault with others via a one-time phrase. You can revoke access individually.")
                }
            }

            // Duress
            Section {
                if Self.shouldDisableDuressForSharing(
                    isSharedVault: isSharedVault,
                    activeShareCount: activeShareCount,
                    activeUploadCount: activeUploadCount
                ) {
                    Text("Vaults with active sharing cannot be set as duress vaults")
                        .foregroundStyle(.vaultSecondaryText)
                } else if !subscriptionManager.canCreateDuressVault() {
                    Button(action: { showingPaywall = true }) {
                        HStack {
                            Text("Use as duress vault")
                            Spacer()
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.vaultHighlight)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    Toggle("Use as duress vault", isOn: $isDuressVault)
                        .accessibilityIdentifier("settings_duress_toggle")
                }

                DisclosureGroup {
                    Text("When you enter this pattern while under duress, your real vaults are silently destroyed. The person watching sees normal-looking content and has no way to know your real data ever existed.")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                } label: {
                    Text("What is this?")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                }
            } header: {
                Text("Duress")
            }

            // App Settings
            Section("App") {
                NavigationLink("App Settings") {
                    AppSettingsView()
                }
                .accessibilityIdentifier("settings_app_settings")
            }

            // Danger
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete this vault")
                }
                .accessibilityIdentifier("settings_delete_vault")
            } footer: {
                Text("Permanently deletes all files in this vault. This cannot be undone.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationTitle("Vault Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("vault_settings_done")
            }
        }
        .fullScreenCover(isPresented: $showingChangePattern) {
            ChangePatternView()
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showingRegeneratedPhrase) {
            RecoveryPhraseView()
        }
        .fullScreenCover(isPresented: $showingShareVault) {
            ShareVaultView()
        }
        .fullScreenCover(isPresented: $showingCustomPhraseInput) {
            CustomRecoveryPhraseInputView()
                .interactiveDismissDisabled()
        }
        .ignoresSafeArea(.keyboard)
        .alert("Delete Vault?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
            Button("Delete", role: .destructive) {
                deleteVault()
            }
        } message: {
            Text("All files in this vault will be permanently deleted. This cannot be undone.")
        }
        .alert("Regenerate Recovery Phrase?", isPresented: $showingRegenerateConfirmation) {
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
            Button("Regenerate", role: .destructive) {
                regenerateRecoveryPhrase()
            }
        } message: {
            Text("Your current recovery phrase will no longer work. Write down the new phrase immediately.")
        }
        .alert("Error", isPresented: Binding(
            get: { regenerateErrorMessage != nil },
            set: { if !$0 { regenerateErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { regenerateErrorMessage = nil }
        } message: {
            Text(regenerateErrorMessage ?? "An unexpected error occurred.")
        }
        .alert("Rename Vault", isPresented: $showingRenameAlert) {
            TextField("Vault name", text: $renameText)
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
            Button("Save") { renameVault() }
        } message: {
            Text("Enter a custom name, or clear to reset to the default name.")
        }
        .alert("Enable Duress Vault?", isPresented: $showingDuressConfirmation) {
            Button("Cancel", role: .cancel) {
                isDuressVault = !pendingDuressValue
                duressAlreadyEnabled = false  // Reset so confirmation shows if they try again
            }
            Button("Enable", role: .destructive) {
                setAsDuressVault()
            }
        } message: {
            Text("⚠️ EXTREMELY DESTRUCTIVE ⚠️\n\nWhen this pattern is entered, ALL OTHER VAULTS will be PERMANENTLY DESTROYED with no warning or confirmation.\n\nThis includes:\n• All files in other vaults\n• All recovery phrases for other vaults\n• No way to undo this action\n\nOnly use this if you understand you may lose important data under duress.\n\nAre you absolutely sure?")
        }
        .onChange(of: isDuressVault) { oldValue, newValue in
            let duressDisabledBySharing = Self.shouldDisableDuressForSharing(
                isSharedVault: isSharedVault,
                activeShareCount: activeShareCount,
                activeUploadCount: activeUploadCount
            )
            guard !duressDisabledBySharing else {
                isDuressVault = oldValue
                return
            }
            // Only process changes after initial load - ignore the change when view initializes
            guard hasLoadedDuressState else { return }
            if newValue != oldValue {
                pendingDuressValue = newValue
                if newValue {
                    // Trying to enable - show confirmation only if duress wasn't already enabled
                    // (prevents showing confirmation when reopening settings on an already-enabled duress vault)
                    if !duressAlreadyEnabled {
                        showingDuressConfirmation = true
                    }
                } else {
                    // Trying to disable - allow without confirmation
                    duressAlreadyEnabled = false
                    removeDuressVault()
                }
            }
        }
        .task {
            loadVaultStatistics()
        }
        .onChange(of: showingShareVault) { _, isShowing in
            if !isShowing { loadVaultStatistics() }
        }
        .premiumPaywall(isPresented: $showingPaywall)
    }

    private func setAsDuressVault() {
        guard let key = appState.currentVaultKey else { return }
        EmbraceManager.shared.addBreadcrumb(category: "settings.duressToggled")
        Task {
            do {
                try await DuressHandler.shared.setAsDuressVault(key: key.rawBytes)
                await MainActor.run {
                    duressAlreadyEnabled = true
                }
            } catch {
                EmbraceManager.shared.captureError(error)
            }
        }
    }

    private func removeDuressVault() {
        EmbraceManager.shared.addBreadcrumb(category: "settings.duressToggled")
        Task {
            await DuressHandler.shared.clearDuressVault()
        }
    }

    private func renameVault() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = appState.currentVaultKey else { return }

        do {
            var index = try VaultStorage.shared.loadIndex(with: key)
            if trimmed.isEmpty {
                index.customName = nil
                if let pattern = appState.currentPattern {
                    let letters = GridLetterManager.shared.vaultName(for: pattern)
                    appState.updateVaultName(letters.isEmpty ? "Vault" : "Vault \(letters)")
                } else {
                    appState.updateVaultName("Vault")
                }
            } else {
                let name = String(trimmed.prefix(30))
                index.customName = name
                appState.updateVaultName(name)
            }
            try VaultStorage.shared.saveIndex(index, with: key)
        } catch {
            vaultSettingsLogger.error("Failed to rename vault: \(error.localizedDescription)")
        }
    }

    private func deleteVault() {
        guard let key = appState.currentVaultKey else {
            dismiss()
            return
        }

        // Delete all files and the vault index
        do {
            let index = try VaultStorage.shared.loadIndex(with: key)
            for file in index.files where !file.isDeleted {
                do {
                    try VaultStorage.shared.deleteFile(id: file.fileId, with: key)
                } catch {
                    vaultSettingsLogger.error("Failed to delete file \(file.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    EmbraceManager.shared.captureError(error, context: ["action": "deleteFile", "fileId": file.fileId])
                }
            }

            // Revoke any active CloudKit shares to invalidate all recipient copies
            if let shares = index.activeShares {
                for share in shares {
                    Task {
                        do {
                            // Revoke the share so recipients can no longer access it
                            try await CloudKitSharingManager.shared.revokeShare(shareVaultId: share.id)
                            vaultSettingsLogger.info("Revoked shared vault \(share.id, privacy: .public)")
                        } catch {
                            vaultSettingsLogger.error("Failed to revoke shared vault \(share.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            EmbraceManager.shared.captureError(error, context: ["action": "revokeShare", "shareId": share.id])
                        }
                    }
                }
            }

            // If this is a shared vault we joined, mark it as consumed
            if let isShared = index.isSharedVault, isShared, let vaultId = index.sharedVaultId {
                Task {
                    do {
                        try await CloudKitSharingManager.shared.markShareConsumed(shareVaultId: vaultId)
                        vaultSettingsLogger.info("Marked shared vault \(vaultId, privacy: .public) as consumed")
                    } catch {
                        vaultSettingsLogger.error("Failed to mark shared vault consumed \(vaultId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        EmbraceManager.shared.captureError(error, context: ["action": "markShareConsumed", "vaultId": vaultId])
                    }
                }
            }

            try VaultStorage.shared.deleteVaultIndex(for: key)
        } catch {
            vaultSettingsLogger.error("Delete vault error: \(error.localizedDescription, privacy: .public)")
            EmbraceManager.shared.captureError(error, context: ["action": "deleteVault"])
        }

        // Clean up recovery data and duress status
        Task {
            do {
                try await RecoveryPhraseManager.shared.deleteRecoveryData(for: key.rawBytes)
            } catch {
                vaultSettingsLogger.error("Failed to delete recovery data: \(error.localizedDescription, privacy: .public)")
                EmbraceManager.shared.captureError(error, context: ["action": "deleteRecoveryData"])
            }
            if await DuressHandler.shared.isDuressKey(key.rawBytes) {
                await DuressHandler.shared.clearDuressVault()
            }
        }

        appState.lockVault()
        dismiss()
    }
    
    private func regenerateRecoveryPhrase() {
        guard let key = appState.currentVaultKey else { return }
        EmbraceManager.shared.addBreadcrumb(category: "settings.phraseRegenerated")
        Task {
            do {
                do {
                    _ = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(for: key.rawBytes)
                } catch RecoveryError.vaultNotFound {
                    // No existing recovery data — create fresh entry
                    vaultSettingsLogger.info("No recovery data found, creating new recovery phrase")
                    let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                    try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                        phrase: newPhrase,
                        pattern: appState.currentPattern ?? [],
                        gridSize: 5,
                        patternKey: key.rawBytes
                    )
                }
                vaultSettingsLogger.debug("Recovery phrase regenerated")
                await MainActor.run {
                    showingRegeneratedPhrase = true
                }
            } catch {
                vaultSettingsLogger.error("Failed to regenerate phrase: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    regenerateErrorMessage = "Failed to regenerate recovery phrase. Please try again."
                }
            }
        }
    }
    
    private func loadVaultStatistics() {
        guard let key = appState.currentVaultKey else { return }
        
        Task {
            do {
                let result = try VaultStorage.shared.listFilesLightweight(with: key)
                let files = result.files
                let totalSize = files.reduce(0) { $0 + Int64($1.size) }
                
                // Check if this is the duress vault
                let ownerFingerprint = KeyDerivation.keyFingerprint(from: key.rawBytes)
                let duressInitiallyEnabled = await DuressHandler.shared.isDuressKey(key.rawBytes)

                // Load sharing info
                let index = try VaultStorage.shared.loadIndex(with: key)
                let shared = index.isSharedVault ?? false
                let shareCount = index.activeShares?.count ?? 0
                let activeUploadJobs = await MainActor.run {
                    ShareUploadManager.shared.jobs(forOwnerFingerprint: ownerFingerprint)
                        .filter { $0.canTerminate }
                }
                let uploadCount = activeUploadJobs.count
                let sharingDisablesDuress = Self.shouldDisableDuressForSharing(
                    isSharedVault: shared,
                    activeShareCount: shareCount,
                    activeUploadCount: uploadCount
                )
                if duressInitiallyEnabled && sharingDisablesDuress {
                    await DuressHandler.shared.clearDuressVault()
                    vaultSettingsLogger.info("Cleared duress because this vault has active sharing")
                }
                let isDuress = duressInitiallyEnabled && !sharingDisablesDuress

                await MainActor.run {
                    fileCount = files.count
                    storageUsed = totalSize
                    duressAlreadyEnabled = isDuress
                    isDuressVault = isDuress
                    isSharedVault = shared
                    activeShareCount = shareCount
                    activeUploadCount = uploadCount
                    hasLoadedDuressState = true
                }
            } catch {
                vaultSettingsLogger.error("Failed to load vault statistics: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    fileCount = 0
                    storageUsed = 0
                    activeUploadCount = 0
                }
            }
        }
    }

    static func shouldDisableDuressForSharing(
        isSharedVault: Bool,
        activeShareCount: Int,
        activeUploadCount: Int
    ) -> Bool {
        isSharedVault || activeShareCount > 0 || activeUploadCount > 0
    }
    
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        Self.byteCountFormatter.string(fromByteCount: bytes)
    }
}

#Preview {
    VaultSettingsView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
