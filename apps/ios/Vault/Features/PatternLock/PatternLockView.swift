import SwiftUI
import UIKit
import os.log

private let patternLockLogger = Logger(subsystem: "app.vaultaire.ios", category: "PatternLock")

struct PatternLockView: View {
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var patternState = PatternState()

    @AppStorage("showPatternFeedback") private var showFeedback = true

    @State private var isProcessing = false
    @State private var showRecoveryOption = false
    @State private var showJoinSharedVault = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingPaywall = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVoiceOverActive: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.vaultSecondaryText)
                    .accessibilityHidden(true)

                Text(isVoiceOverActive ? "Unlock Your Vault" : "Draw your pattern")
                    .font(.title2)
                    .fontWeight(.medium)
            }

            // VoiceOver: promote recovery phrase above grid
            if isVoiceOverActive {
                VStack(spacing: 12) {
                    Text("VoiceOver is active. Use your recovery phrase to unlock.")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: { showRecoveryOption = true }) {
                        Text("Use Recovery Phrase")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .vaultProminentButtonStyle()
                    .padding(.horizontal, 40)
                    .accessibilityHint("Unlock vault using your recovery phrase instead of drawing a pattern")
                }
            }

            Spacer()

            // Pattern Grid
            PatternGridView(
                state: patternState,
                showFeedback: $showFeedback,
                onPatternComplete: handlePatternComplete
            )
            .frame(width: 280, height: 280)
            .disabled(isProcessing)
            .opacity(isVoiceOverActive ? 0.3 : (isProcessing ? 0.5 : 1))
            .accessibilityIdentifier("unlock_pattern_grid")

            // Error message — overlay so it never shifts the grid
            Color.clear
                .frame(height: 0)
                .overlay(alignment: .top) {
                    if showError, let message = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(message)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.vaultHighlight.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.scale.combined(with: .opacity))
                    }
                }

            Spacer()

            // Options (hidden when VoiceOver promotes recovery above)
            if !isVoiceOverActive {
                VStack(spacing: 12) {
                    Button(action: { showRecoveryOption = true }) {
                        Text("Use recovery phrase")
                            .font(.subheadline)
                            .foregroundStyle(.vaultSecondaryText)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("unlock_recovery_link")
                    .accessibilityHint("Unlock vault using your recovery phrase instead of drawing a pattern")

                    Button(action: { showJoinSharedVault = true }) {
                        Text("Join shared vault")
                            .font(.subheadline)
                            .foregroundStyle(.vaultSecondaryText)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("unlock_join_link")
                    .accessibilityHint("Enter a share phrase to access a vault shared with you")
                }
            } else {
                Button(action: { showJoinSharedVault = true }) {
                    Text("Join shared vault")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("unlock_join_link")
                .accessibilityHint("Enter a share phrase to access a vault shared with you")
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vaultBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: showError)
        .fullScreenCover(isPresented: $showRecoveryOption) {
            RecoveryPhraseInputView()
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showJoinSharedVault) {
            JoinVaultView()
        }
        .ignoresSafeArea(.keyboard)
        .premiumPaywall(isPresented: $showingPaywall)
    }

    private func handlePatternComplete(_ pattern: [Int]) {
        patternLockLogger.debug("Pattern completed, count=\(pattern.count)")
        
        guard !isProcessing else {
            patternLockLogger.debug("Already processing, ignoring pattern")
            return
        }
        
        // Require minimum pattern length to prevent accidental taps
        guard pattern.count >= 6 else {
            patternLockLogger.debug("Pattern too short: \(pattern.count) nodes, minimum 6 required")
            
            // Show error message to user
            errorMessage = "Pattern must connect at least 6 dots"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation {
                showError = true
            }
            
            // Hide error after 2 seconds and reset pattern
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation {
                        showError = false
                    }
                }
            }
            
            patternState.reset()
            return
        }

        // Clear any previous error
        showError = false
        
        patternLockLogger.debug("Pattern accepted, processing unlock")
        
        isProcessing = true

        Task {
            // Derive key once — reused for both the free-tier gate check and unlock
            let derivedKey: Data?
            do {
                derivedKey = try await KeyDerivation.deriveKey(from: pattern, gridSize: 5)
            } catch {
                derivedKey = nil
            }

            // Check if this pattern creates a new vault and if the user is at the free limit
            if !subscriptionManager.isPremium, let key = derivedKey {
                if !VaultStorage.shared.vaultExists(for: key) {
                    let vaultCount = VaultStorage.shared.existingVaultCount()
                    if !subscriptionManager.canCreateVault(currentCount: vaultCount) {
                        await MainActor.run {
                            isProcessing = false
                            patternState.reset()
                            showingPaywall = true
                        }
                        return
                    }
                }
            }

            // Attempt to unlock, passing pre-derived key to avoid double PBKDF2
            let unlocked = await appState.unlockWithPattern(pattern, gridSize: 5, precomputedKey: derivedKey)

            await MainActor.run {
                if unlocked {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                isProcessing = false
                patternState.reset()
            }
        }
    }
}

// MARK: - Recovery Phrase Input

struct RecoveryPhraseInputView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter your recovery phrase")
                    .font(.headline)

                Text("This is the memorable sentence you created when setting up your vault.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)

                TextEditor(text: $phrase)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color.vaultSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("unlock_recovery_phrase_input")

                Button(action: attemptRecovery) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Recover Vault")
                    }
                }
                .vaultProminentButtonStyle()
                .disabled(phrase.isEmpty || isProcessing)

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.vaultHighlight)
                    }
                    .padding()
                    .vaultGlassTintedBackground(tint: Color.vaultHighlight, cornerRadius: 8)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("unlock_recovery_cancel")
                }
            }
        }
        .background(Color.vaultBackground.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }

    private func attemptRecovery() {
        isProcessing = true

        Task {
            do {
                // Use the recovery manager to recover the vault
                let patternKey = try await RecoveryPhraseManager.shared.recoverVault(using: phrase)
                
                patternLockLogger.info("Vault recovered successfully")
                
                // Use the recovered pattern key to unlock the vault
                await MainActor.run {
                    appState.currentVaultKey = patternKey
                    appState.isUnlocked = true
                    dismiss()
                    
                    patternLockLogger.debug("Vault unlocked with recovery phrase")
                }
            } catch RecoveryError.invalidPhrase {
                patternLockLogger.info("Invalid recovery phrase")
                await MainActor.run {
                    showRecoveryError("Incorrect recovery phrase. Please check and try again.")
                }
            } catch {
                patternLockLogger.error("Recovery failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    showRecoveryError("Recovery failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    private func showRecoveryError(_ message: String) {
        errorMessage = message
        isProcessing = false
    }
    
}


#Preview {
    PatternLockView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
