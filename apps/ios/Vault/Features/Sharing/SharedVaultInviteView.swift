import SwiftUI
import CloudKit

struct SharedVaultInviteView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkHandler.self) private var deepLinkHandler
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ViewMode = .loading
    @State private var showingPaywall = false
    @State private var iCloudStatus: CKAccountStatus?

    // Pattern setup
    @State private var patternState = PatternState()
    @State private var newPattern: [Int] = []
    @State private var patternStep: PatternStep = .create
    @State private var validationResult: PatternValidationResult?
    @State private var errorMessage: String?
    @State private var showingOverwriteConfirmation = false
    @State private var pendingOverwriteKey: VaultKey?
    @State private var existingVaultNameForOverwrite = "Vault"
    @State private var existingFileCountForOverwrite = 0
    @State private var isSettingUpVault = false

    private var phrase: String {
        deepLinkHandler.pendingSharePhrase ?? ""
    }

    enum ViewMode {
        case loading
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
                Button("Cancel") {
                    // No-op: invisible spacer for symmetric layout
                }.opacity(0)
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
                        case .loading:
                            loadingView
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
        .background(Color.vaultBackground.ignoresSafeArea())
        .task {
            let status = await CloudKitSharingManager.shared.checkiCloudStatus()
            iCloudStatus = status
            
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                mode = .error("Invalid invitation link - no phrase found. Please try copying the link again.")
                return
            }
            
            // Retry phrase availability check up to 6 times (CloudKit public DB has eventual consistency)
            // Delays: 1s, 2s, 3s, 5s, 8s, 13s (Fibonacci) = 32 seconds total
            let retryDelays = [1, 2, 3, 5, 8, 13]
            var lastError: CloudKitSharingError?
            for (index, delay) in retryDelays.enumerated() {
                let attempt = index + 1
                let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: trimmed)
                switch result {
                case .success:
                    mode = .invite
                    return
                case .failure(let error):
                    lastError = error
                    // Check if we should retry (network errors or vault not found could be temporary)
                    let shouldRetry: Bool
                    switch error {
                    case .networkError, .vaultNotFound:
                        shouldRetry = attempt < retryDelays.count
                    default:
                        shouldRetry = false
                    }
                    
                    if shouldRetry {
                        try? await Task.sleep(for: .seconds(Double(delay)))
                        continue
                    } else {
                        mode = .error(error.localizedDescription)
                        return
                    }
                }
            }
            
            // If we get here, all retries failed
            if let error = lastError {
                mode = .error(error.localizedDescription)
            } else {
                mode = .error("Could not verify share availability. Please check your connection and try again.")
            }
        }
        .premiumPaywall(isPresented: $showingPaywall)
        .interactiveDismissDisabled()
        .alert("Replace Existing Vault?", isPresented: $showingOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingOverwriteKey = nil
            }
            Button("Replace Vault", role: .destructive) {
                guard let key = pendingOverwriteKey else { return }
                pendingOverwriteKey = nil
                Task { await setupSharedVault(forceOverwrite: true, precomputedPatternKey: key) }
            }
        } message: {
            Text(
                "\(existingVaultNameForOverwrite) already exists with \(existingFileCountForOverwrite) file\(existingFileCountForOverwrite == 1 ? "" : "s"). "
                + "Joining this shared vault will replace it. Files are not merged."
            )
        }
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
                Task {
                    // Re-verify the share is still available before accepting
                    let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                    let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: trimmed)
                    
                    switch result {
                    case .success:
                        let vaultCount = VaultStorage.shared.existingVaultCount()
                        if subscriptionManager.canJoinSharedVault(currentCount: vaultCount) {
                            mode = .patternSetup
                        } else {
                            showingPaywall = true
                        }
                    case .failure(let error):
                        mode = .error(error.localizedDescription)
                    }
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
            // Title and subtitle — fixed height prevents grid from shifting between steps
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .top)
            }

            Spacer()

            PatternGridView(
                state: patternState,
                showFeedback: .constant(true),
                onPatternComplete: handlePatternComplete
            )
            .frame(width: 280, height: 280)
            .tint(.purple)

            Spacer()

            // Validation feedback — fixed height to prevent layout shift
            Group {
                if let result = validationResult, patternStep == .create {
                    PatternValidationFeedbackView(result: result)
                } else if let error = errorMessage {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(error)
                            .font(.caption)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vaultGlassBackground(cornerRadius: 12)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Color.clear
                }
            }
            .frame(minHeight: 80)

            if patternStep == .confirm {
                Button("Start Over") {
                    patternStep = .create
                    newPattern = []
                    patternState.reset()
                    validationResult = nil
                    errorMessage = nil
                }
                .font(.subheadline)
            }
        }
    }


    private var loadingView: some View {
        VStack(spacing: 20) {
            PixelLoader.compact(size: 48)
            Text("Checking invitation...")
                .font(.headline)
                .foregroundStyle(.vaultSecondaryText)
        }
        .padding(.top, 100)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.vaultHighlight)
            Text("Could Not Join")
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.vaultSecondaryText).multilineTextAlignment(.center)

            Button("Close") {
                deepLinkHandler.clearPending()
                dismiss()
            }
            .vaultProminentButtonStyle()
            .padding(.top)
        }
        .padding(.top, 60)
    }

    private func iCloudUnavailableView(_ _: CKAccountStatus) -> some View {
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
        switch patternStep {
        case .create:
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
            validationResult = result

            if result.isValid {
                errorMessage = nil
                newPattern = pattern
                patternStep = .confirm
                patternState.reset()
            } else {
                patternState.reset()
            }

        case .confirm:
            if pattern == newPattern {
                guard !isSettingUpVault else { return }
                isSettingUpVault = true
                patternState.reset()
                Task { await setupSharedVault() }
            } else {
                errorMessage = "Patterns don't match. Try again."
                patternState.reset()
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run { errorMessage = nil }
                }
            }
        }
    }

    private func setupSharedVault(forceOverwrite: Bool = false, precomputedPatternKey: VaultKey? = nil) async {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else {
            mode = .error("Invalid share link — no phrase found.")
            return
        }

        do {
            let patternKey = try await resolvePatternKey(precomputedPatternKey: precomputedPatternKey)

            if await VaultStorage.shared.vaultHasFiles(for: patternKey), !forceOverwrite {
                isSettingUpVault = false  // Reset so overwrite confirmation can proceed
                await prepareOverwriteConfirmation(for: patternKey)
                return
            }

            if forceOverwrite {
                try await overwriteExistingVaultIfNeeded(patternKey: patternKey)
            }

            appState.currentVaultKey = patternKey
            appState.currentPattern = newPattern
            let letters = GridLetterManager.shared.vaultName(for: newPattern)
            appState.updateVaultName(letters.isEmpty ? "Vault" : "Vault \(letters)")

            // Ensure a proper v3 vault index with encrypted master key + blob metadata.
            // Using loadIndex here keeps shared-invite setup aligned with JoinVaultView.
            let emptyIndex = try await VaultStorage.shared.loadIndex(with: patternKey)
            try await VaultStorage.shared.saveIndex(emptyIndex, with: patternKey)

            appState.isUnlocked = true
            deepLinkHandler.clearPending()
            dismiss()

            ShareImportManager.shared.startBackgroundDownloadAndImport(
                phrase: trimmedPhrase,
                patternKey: patternKey
            )
        } catch {
            mode = .error("Failed to set up vault: \(error.localizedDescription)")
        }
    }

    private func resolvePatternKey(precomputedPatternKey: VaultKey?) async throws -> VaultKey {
        if let precomputedPatternKey {
            return precomputedPatternKey
        }
        let keyData = try await KeyDerivation.deriveKey(from: newPattern, gridSize: 5)
        return VaultKey(keyData)
    }

    private func prepareOverwriteConfirmation(for patternKey: VaultKey) async {
        let letters = GridLetterManager.shared.vaultName(for: newPattern)
        existingVaultNameForOverwrite = letters.isEmpty ? "Vault" : "Vault \(letters)"

        if let index = try? await VaultStorage.shared.loadIndex(with: patternKey) {
            existingFileCountForOverwrite = index.files.filter { !$0.isDeleted }.count
        } else {
            existingFileCountForOverwrite = 0
        }

        pendingOverwriteKey = patternKey
        showingOverwriteConfirmation = true
    }

    private func overwriteExistingVaultIfNeeded(patternKey: VaultKey) async throws {
        if VaultStorage.shared.vaultExists(for: patternKey) {
            if await DuressHandler.shared.isDuressKey(patternKey) {
                await DuressHandler.shared.clearDuressVault()
            }
            try VaultStorage.shared.deleteVaultIndex(for: patternKey)
            try? await RecoveryPhraseManager.shared.deleteRecoveryData(for: patternKey.rawBytes)
        }
    }
}

#Preview {
    SharedVaultInviteView()
        .environment(AppState())
        .environment(DeepLinkHandler())
        .environment(SubscriptionManager.shared)
}
