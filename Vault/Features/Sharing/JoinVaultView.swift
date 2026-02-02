import SwiftUI
import CloudKit

struct JoinVaultView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var phrase = ""
    @State private var mode: ViewMode = .input
    @State private var showingPaywall = false
    @State private var iCloudStatus: CKAccountStatus?

    // Pattern setup for shared vault
    @State private var patternState = PatternState()
    @State private var newPattern: [Int] = []
    @State private var confirmPattern: [Int] = []
    @State private var patternStep: PatternStep = .create

    enum ViewMode {
        case input
        case patternSetup
        case error(String)
    }

    enum PatternStep {
        case create
        case confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Join Shared Vault")
                    .font(.headline)
                Spacer()
                Button("Cancel") { }.opacity(0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    if let status = iCloudStatus, status != .available && status != .temporarilyUnavailable {
                        iCloudUnavailableView(status)
                    } else {
                        switch mode {
                        case .input:
                            inputView
                        case .patternSetup:
                            patternSetupView
                        case .error(let message):
                            errorView(message)
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            let status = await CloudKitSharingManager.shared.checkiCloudStatus()
            iCloudStatus = status
        }
        .premiumPaywall(isPresented: $showingPaywall)
    }

    // MARK: - Views

    private var inputView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Enter Share Phrase")
                .font(.title2).fontWeight(.semibold)

            Text("Enter the one-time share phrase you received.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            TextEditor(text: $phrase)
                .frame(height: 100)
                .padding(8)
                .background(Color.vaultSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: {
                if subscriptionManager.isPremium {
                    joinVault()
                } else {
                    showingPaywall = true
                }
            }) {
                Text("Join Vault")
            }
            .vaultProminentButtonStyle()
            .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Label("How it works", systemImage: "info.circle")
                    .font(.headline)
                Text("The share phrase downloads and decrypts the shared vault. Each phrase can only be used once.")
                    .font(.subheadline).foregroundStyle(.vaultSecondaryText)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .vaultGlassBackground(cornerRadius: 12)
        }
    }

    private var patternSetupView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)

                Text(patternStep == .create ? "Set a Pattern" : "Confirm Pattern")
                    .font(.title2).fontWeight(.semibold)

                Text(patternStep == .create
                    ? "Draw a pattern to unlock this shared vault"
                    : "Draw the same pattern to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            }

            PatternGridView(
                state: patternState,
                showFeedback: .constant(true),
                onPatternComplete: handlePatternComplete
            )
            .frame(width: 280, height: 280)
            .vaultPatternGridBackground()

            if patternStep == .confirm {
                Button("Start Over") {
                    patternStep = .create
                    newPattern = []
                    confirmPattern = []
                    patternState.reset()
                }
                .font(.subheadline)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.vaultHighlight)
            Text("Could Not Join")
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.vaultSecondaryText).multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Try Again") { mode = .input }
                    .buttonStyle(.bordered)
                Button("Edit Phrase") { mode = .input }
                    .vaultProminentButtonStyle()
            }
            .padding(.top)
        }
        .padding(.top, 60)
    }

    private func iCloudUnavailableView(_ status: CKAccountStatus) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48)).foregroundStyle(.vaultSecondaryText)
            Text("iCloud Required")
                .font(.title2).fontWeight(.semibold)
            Text(iCloudStatusMessage(status))
                .foregroundStyle(.vaultSecondaryText).multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func joinVault() {
        // Go straight to pattern setup; download happens after pattern is confirmed
        mode = .patternSetup
    }

    private func handlePatternComplete(_ pattern: [Int]) {
        guard pattern.count >= 6 else {
            patternState.reset()
            return
        }

        switch patternStep {
        case .create:
            newPattern = pattern
            patternStep = .confirm
            patternState.reset()

        case .confirm:
            if pattern == newPattern {
                confirmPattern = pattern
                patternState.reset()
                Task { await setupSharedVault() }
            } else {
                // Patterns don't match
                patternState.reset()
                patternStep = .create
                newPattern = []
            }
        }
    }

    private func setupSharedVault() async {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            // Derive key from the pattern
            let patternKey = try await KeyDerivation.deriveKey(from: newPattern, gridSize: 5)

            // Set app state so user can navigate the app
            appState.currentVaultKey = patternKey
            appState.currentPattern = newPattern

            // Create an empty vault index so the vault can open immediately
            let emptyIndex = VaultStorage.VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: 500 * 1024 * 1024
            )
            try VaultStorage.shared.saveIndex(emptyIndex, with: patternKey)

            // Navigate to the vault immediately
            appState.isUnlocked = true
            dismiss()

            // Download and import in background
            BackgroundShareTransferManager.shared.startBackgroundDownloadAndImport(
                phrase: trimmedPhrase,
                patternKey: patternKey,
                pattern: newPattern
            )
        } catch {
            mode = .error("Failed to set up vault: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func iCloudStatusMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "iCloud is available"
        case .noAccount: return "Please sign in to iCloud in Settings"
        case .restricted: return "iCloud access is restricted"
        case .couldNotDetermine: return "Could not determine iCloud status"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        @unknown default: return "iCloud is not available"
        }
    }
}

#Preview {
    JoinVaultView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
