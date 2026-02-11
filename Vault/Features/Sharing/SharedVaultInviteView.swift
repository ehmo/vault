import SwiftUI
import CloudKit

struct SharedVaultInviteView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkHandler.self) private var deepLinkHandler
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ViewMode = .invite
    @State private var showingPaywall = false
    @State private var iCloudStatus: CKAccountStatus?

    // Pattern setup
    @State private var patternState = PatternState()
    @State private var newPattern: [Int] = []
    @State private var patternStep: PatternStep = .create

    private var phrase: String {
        deepLinkHandler.pendingSharePhrase ?? ""
    }

    enum ViewMode {
        case invite
        case patternSetup
        case error(String)
    }

    enum PatternStep {
        case create
        case confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    deepLinkHandler.clearPending()
                    dismiss()
                }
                .accessibilityIdentifier("invite_cancel")
                Spacer()
                Text("Shared Vault")
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
                        case .invite:
                            inviteView
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
        .interactiveDismissDisabled()
    }

    // MARK: - Views

    private var inviteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("You've been invited")
                .font(.title2).fontWeight(.semibold)

            Text("Someone shared a vault with you. Accept to create a secure copy on your device.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            Button {
                if subscriptionManager.isPremium {
                    mode = .patternSetup
                } else {
                    showingPaywall = true
                }
            } label: {
                Text("Accept Invite")
            }
            .accessibilityIdentifier("invite_accept")
            .vaultProminentButtonStyle()

            VStack(alignment: .leading, spacing: 8) {
                Label("End-to-end encrypted", systemImage: "lock.fill")
                Label("One-time use link", systemImage: "link")
                Label("You'll set a pattern to protect it", systemImage: "shield.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.vaultSecondaryText)
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

            Button("Try Again") { mode = .invite }
                .vaultProminentButtonStyle()
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
            Text("Sign in to iCloud in Settings to accept shared vaults.")
                .foregroundStyle(.vaultSecondaryText).multilineTextAlignment(.center)

            Button { SettingsURLHelper.openICloudSettings() } label: {
                Label("Open iCloud Settings", systemImage: "gear")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(.top, 60)
    }

    // MARK: - Actions

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
                patternState.reset()
                Task { await setupSharedVault() }
            } else {
                patternState.reset()
                patternStep = .create
                newPattern = []
            }
        }
    }

    private func setupSharedVault() async {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else {
            mode = .error("Invalid share link — no phrase found.")
            return
        }

        do {
            let patternKey = try await KeyDerivation.deriveKey(from: newPattern, gridSize: 5)

            appState.currentVaultKey = patternKey
            appState.currentPattern = newPattern
            let letters = GridLetterManager.shared.vaultName(for: newPattern)
            appState.updateVaultName(letters.isEmpty ? "Vault" : "Vault \(letters)")

            let emptyIndex = VaultStorage.VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: 500 * 1024 * 1024
            )
            try VaultStorage.shared.saveIndex(emptyIndex, with: patternKey)

            appState.isUnlocked = true
            deepLinkHandler.clearPending()
            dismiss()

            BackgroundShareTransferManager.shared.startBackgroundDownloadAndImport(
                phrase: trimmedPhrase,
                patternKey: patternKey
            )
        } catch {
            mode = .error("Failed to set up vault: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SharedVaultInviteView()
        .environment(AppState())
        .environment(DeepLinkHandler())
        .environment(SubscriptionManager.shared)
}
