import SwiftUI

// MARK: - Navigation Destinations

enum VaultSettingsDestination: Hashable {
    case appSettings
    case duressPattern
    case iCloudBackup
    case restoreBackup
}

struct VaultSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingChangePattern = false
    @State private var showingRecoveryPhrase = false
    @State private var showingDeleteConfirmation = false
    @State private var isDuressVault = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        List {
            // Vault Info
            Section("This Vault") {
                HStack {
                    Text("Files")
                    Spacer()
                    Text("0") // Would be actual count
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text("0 MB") // Would be actual size
                        .foregroundStyle(.secondary)
                }
            }

            // Pattern Management
            Section("Pattern") {
                Button("Change pattern for this vault") {
                    showingChangePattern = true
                }
            }

            // Recovery
            Section("Recovery") {
                Button("View recovery phrase") {
                    showingRecoveryPhrase = true
                }

                Button("Regenerate recovery phrase") {
                    // Would show confirmation and regenerate
                }
            }

            // Duress
            Section {
                Toggle("Use as duress vault", isOn: $isDuressVault)
            } header: {
                Text("Duress")
            } footer: {
                Text("When this pattern is entered, all OTHER vaults are silently destroyed.")
            }

            // App Settings
            Section("App") {
                Button("App Settings") {
                    navigationPath.append(VaultSettingsDestination.appSettings)
                }
            }

            // Danger
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete this vault")
                }
            } footer: {
                Text("Permanently deletes all files in this vault. This cannot be undone.")
            }
        }
        .navigationTitle("Vault Settings")
        .navigationDestination(for: VaultSettingsDestination.self) { destination in
            switch destination {
            case .appSettings:
                AppSettingsView()
            case .duressPattern:
                DuressPatternSettingsView()
            case .iCloudBackup:
                iCloudBackupSettingsView()
            case .restoreBackup:
                RestoreFromBackupView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingChangePattern) {
            ChangePatternView()
        }
        .sheet(isPresented: $showingRecoveryPhrase) {
            RecoveryPhraseView()
        }
        .alert("Delete Vault?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteVault()
            }
        } message: {
            Text("All files in this vault will be permanently deleted. This cannot be undone.")
        }
        .onChange(of: isDuressVault) { _, newValue in
            if newValue {
                setAsDuressVault()
            } else {
                removeDuressVault()
            }
        }
    }

    private func setAsDuressVault() {
        guard let key = appState.currentVaultKey else { return }
        Task {
            try? await DuressHandler.shared.setAsDuressVault(key: key)
        }
    }

    private func removeDuressVault() {
        Task {
            await DuressHandler.shared.clearDuressVault()
        }
    }

    private func deleteVault() {
        // Would delete all vault data
        dismiss()
    }
}

// MARK: - Change Pattern

struct ChangePatternView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0 // 0: current, 1: new, 2: confirm

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Change Pattern")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            VStack {
                switch step {
                case 0:
                    Text("Enter your current pattern")
                case 1:
                    Text("Draw your new pattern")
                case 2:
                    Text("Confirm your new pattern")
                default:
                    Text("Pattern changed successfully")
                }

                Spacer()

                // Pattern grid would go here
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 280)

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    VaultSettingsView()
        .environmentObject(AppState())
}
