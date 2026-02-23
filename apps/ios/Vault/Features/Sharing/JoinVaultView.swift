import SwiftUI
import CloudKit
import UIKit
import CryptoKit

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
    @State private var patternStep: PatternStep = .create
    @State private var validationResult: PatternValidationResult?
    @State private var errorMessage: String?
    @State private var showingOverwriteConfirmation = false
    @State private var pendingOverwriteKey: VaultKey?
    @State private var existingVaultNameForOverwrite = "Vault"
    @State private var existingFileCountForOverwrite = 0
    @State private var isSettingUpVault = false
    
    // Pending shared vault import state
    @State private var pendingImportState: ShareImportManager.PendingImportState?
    @State private var isResumingImport = false

    enum ViewMode: Equatable {
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
                    .accessibilityIdentifier("join_cancel")
                Spacer()
                Text("Join Shared Vault")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.vaultBackground.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .task {
            let status = await CloudKitSharingManager.shared.checkiCloudStatus()
            iCloudStatus = status
        }
        .onAppear {
            checkForPendingImport()
        }
        .task(id: mode) {
            #if DEBUG
            if mode == .patternSetup,
               appState.isMaestroTestMode,
               ProcessInfo.processInfo.arguments.contains("-MAESTRO_FORCE_JOIN_OVERWRITE_ALERT"),
               !showingOverwriteConfirmation {
                existingVaultNameForOverwrite = "Vault TEST"
                existingFileCountForOverwrite = 2
                let seed = Data("MAESTRO_JOIN_OVERWRITE_TEST_KEY".utf8)
                pendingOverwriteKey = VaultKey(Data(SHA256.hash(data: seed)))
                showingOverwriteConfirmation = true
            }
            #endif
        }
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
        .premiumPaywall(isPresented: $showingPaywall)
    }

    // MARK: - Views

    private var inputView: some View {
        VStack(spacing: 24) {
            // Show pending import banner if there's an interrupted download
            if let pending = pendingImportState {
                PendingSharedVaultImportBanner(
                    importedCount: pending.importedFileIds.count,
                    totalCount: pending.totalFiles,
                    onResume: resumePendingImport,
                    isResuming: $isResumingImport
                )
            }

            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Enter Share Phrase")
                .font(.title2).fontWeight(.semibold)

            Text("Enter the one-time share phrase you received.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            TextEditor(text: $phrase)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(8)
                .background(Color.vaultSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.vaultSecondaryText.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("join_phrase_input")

            Button(action: {
                if subscriptionManager.isPremium {
                    joinVault()
                } else {
                    showingPaywall = true
                }
            }) {
                Text("Join Vault")
            }
            .accessibilityIdentifier("join_vault_button")
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
                    ? "Connect at least 6 dots on the 5×5 grid with 2+ direction changes"
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
            .accessibilityIdentifier("join_pattern_grid")

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
                    .accessibilityIdentifier("join_pattern_error")
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
                .accessibilityIdentifier("join_pattern_start_over")
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
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Try Again") { mode = .input }
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
        Task {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Check phrase availability before proceeding to pattern setup
            let result = await CloudKitSharingManager.shared.checkPhraseAvailability(phrase: trimmed)
            if case .failure(let error) = result {
                mode = .error(error.localizedDescription)
                return
            }

            // Phrase is valid, proceed to pattern setup
            mode = .patternSetup
        }
    }

    private func handlePatternComplete(_ pattern: [Int]) {
        switch patternStep {
        case .create:
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
            validationResult = result

            if result.isValid {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                errorMessage = nil
                patternState.reset()
                Task { await setupSharedVault() }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
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

        do {
            let patternKey = try await resolvePatternKey(precomputedPatternKey: precomputedPatternKey)

            if VaultStorage.shared.vaultHasFiles(for: patternKey), !forceOverwrite {
                isSettingUpVault = false  // Reset so overwrite confirmation can proceed
                prepareOverwriteConfirmation(for: patternKey)
                return
            }

            if forceOverwrite {
                try await overwriteExistingVaultIfNeeded(patternKey: patternKey)
            }

            // Set app state so user can navigate the app
            appState.currentVaultKey = patternKey
            appState.currentPattern = newPattern
            let letters = GridLetterManager.shared.vaultName(for: newPattern)
            appState.updateVaultName(letters.isEmpty ? "Vault" : "Vault \(letters)")

            // Create an empty vault index so the vault can open immediately.
            // loadIndex auto-creates a proper v3 index with master key + blob when none exists.
            let emptyIndex = try VaultStorage.shared.loadIndex(with: patternKey)
            try VaultStorage.shared.saveIndex(emptyIndex, with: patternKey)

            // Navigate to the vault immediately
            appState.isUnlocked = true
            dismiss()

            // Download and import in background
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

    private func prepareOverwriteConfirmation(for patternKey: VaultKey) {
        let letters = GridLetterManager.shared.vaultName(for: newPattern)
        existingVaultNameForOverwrite = letters.isEmpty ? "Vault" : "Vault \(letters)"

        if let index = try? VaultStorage.shared.loadIndex(with: patternKey) {
            existingFileCountForOverwrite = index.files.filter { !$0.isDeleted }.count
        } else {
            existingFileCountForOverwrite = 0
        }

        pendingOverwriteKey = patternKey
        showingOverwriteConfirmation = true
    }

    private func overwriteExistingVaultIfNeeded(patternKey: VaultKey) async throws {
        if VaultStorage.shared.vaultExists(for: patternKey) {
            if await DuressHandler.shared.isDuressKey(patternKey.rawBytes) {
                await DuressHandler.shared.clearDuressVault()
            }
            try VaultStorage.shared.deleteVaultIndex(for: patternKey)
            try? await RecoveryPhraseManager.shared.deleteRecoveryData(for: patternKey.rawBytes)
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
    
    // MARK: - Pending Import Handling
    
    private func checkForPendingImport() {
        if let pending = ShareImportManager.shared.getPendingImportState() {
            pendingImportState = pending
        }
    }
    
    private func resumePendingImport() {
        guard let pending = pendingImportState else { return }
        
        isResumingImport = true
        
        // Need the vault key to resume - use the current key if available
        if let key = appState.currentVaultKey {
            ShareImportManager.shared.startBackgroundDownloadAndImport(
                phrase: pending.phrase,
                patternKey: key
            )
            // Dismiss after starting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } else {
            // No key available, can't resume
            isResumingImport = false
            errorMessage = "Cannot resume download - vault is locked. Please unlock your vault first."
        }
    }
}

#Preview {
    JoinVaultView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
