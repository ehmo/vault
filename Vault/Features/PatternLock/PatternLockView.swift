import SwiftUI

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

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.vaultSecondaryText)

                Text("Draw your pattern")
                    .font(.title2)
                    .fontWeight(.medium)
            }

            Spacer()

            // Pattern Grid
            PatternGridView(
                state: patternState,
                showFeedback: $showFeedback,
                onPatternComplete: handlePatternComplete
            )
            .frame(maxWidth: 280, maxHeight: 280)
            .disabled(isProcessing)
            .opacity(isProcessing ? 0.5 : 1)
            
            // Error message — fixed height to prevent grid from shifting
            Group {
                if showError, let message = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.vaultHighlight)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.vaultHighlight.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 40)

            Spacer()

            // Options
            VStack(spacing: 12) {
                Button(action: { showRecoveryOption = true }) {
                    Text("Use recovery phrase")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                }

                Button(action: { showJoinSharedVault = true }) {
                    Text("Join shared vault")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                }
            }

            Spacer()
        }
        .padding()
        .animation(.spring(response: 0.3), value: showError)
        .sheet(isPresented: $showRecoveryOption) {
            RecoveryPhraseInputView()
        }
        .sheet(isPresented: $showJoinSharedVault) {
            JoinVaultView()
        }
        .premiumPaywall(isPresented: $showingPaywall)
    }

    private func handlePatternComplete(_ pattern: [Int]) {
        #if DEBUG
        print("🎯 [PatternLock] Pattern completed: \(pattern) (count: \(pattern.count))")
        print("🎯 [PatternLock] Grid size: 5x5")
        #endif
        
        guard !isProcessing else {
            #if DEBUG
            print("⚠️ [PatternLock] Already processing, ignoring pattern")
            #endif
            return
        }
        
        // Require minimum pattern length to prevent accidental taps
        guard pattern.count >= 6 else {
            #if DEBUG
            print("❌ [PatternLock] Pattern too short (\(pattern.count) nodes), minimum 6 required")
            #endif
            
            // Show error message to user
            errorMessage = "Pattern must connect at least 6 dots"
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
        
        #if DEBUG
        print("✅ [PatternLock] Pattern accepted, processing unlock...")
        #endif
        
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
            _ = await appState.unlockWithPattern(pattern, gridSize: 5, precomputedKey: derivedKey)

            await MainActor.run {
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
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Recovery")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

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

                Button(action: attemptRecovery) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Recover Vault")
                    }
                }
                .buttonStyle(.borderedProminent)
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
                    .background(Color.vaultHighlight.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }
            .padding()
        }
    }

    private func attemptRecovery() {
        isProcessing = true

        Task {
            do {
                // Use the recovery manager to recover the vault
                let patternKey = try await RecoveryPhraseManager.shared.recoverVault(using: phrase)
                
                #if DEBUG
                print("✅ [Recovery] Vault recovered successfully")
                #endif
                
                // Use the recovered pattern key to unlock the vault
                await MainActor.run {
                    appState.currentVaultKey = patternKey
                    appState.isUnlocked = true
                    dismiss()
                    
                    #if DEBUG
                    print("🔓 [Recovery] Vault unlocked with recovery phrase")
                    #endif
                }
            } catch RecoveryError.invalidPhrase {
                #if DEBUG
                print("❌ [Recovery] Invalid recovery phrase")
                #endif
                await MainActor.run {
                    showRecoveryError("Incorrect recovery phrase. Please check and try again.")
                }
            } catch {
                #if DEBUG
                print("❌ [Recovery] Recovery failed: \(error)")
                #endif
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
