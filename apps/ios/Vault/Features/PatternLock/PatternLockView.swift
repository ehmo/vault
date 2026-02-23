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
    @State private var lockoutRemaining: TimeInterval = 0
    @State private var lockoutTimerTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lockoutEndTimeKey = "patternLockout.endTime"

    private var isLockedOut: Bool { lockoutRemaining > 0 }

    /// Progressive delay schedule for failed pattern attempts.
    static func bruteForceDelay(forAttempts count: Int) -> TimeInterval {
        switch count {
        case 0...3: return 0
        case 4...5: return 5
        case 6...8: return 30
        case 9...10: return 300   // 5 minutes
        default:     return 900   // 15 minutes
        }
    }

    private var isVoiceOverActive: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    private var patternGridOpacity: Double {
        if isVoiceOverActive {
            return 0.3
        } else if isProcessing {
            return 0.5
        } else {
            return 1
        }
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

            // Pattern Grid - fixed position, never moves
            PatternGridView(
                state: patternState,
                showFeedback: $showFeedback,
                onPatternComplete: handlePatternComplete
            )
            .frame(width: 280, height: 280)
            .disabled(isProcessing || isLockedOut)
            .opacity(isLockedOut ? 0.3 : patternGridOpacity)
            .accessibilityIdentifier("unlock_pattern_grid")

            // Error / lockout message - BELOW the pattern, fixed height prevents layout shift
            Group {
                if isLockedOut {
                    VStack(spacing: 4) {
                        Text("Too many attempts")
                            .font(.subheadline.weight(.medium))
                        Text(formatCountdown(lockoutRemaining))
                            .font(.title2.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.vaultHighlight.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("unlock_lockout_countdown")
                } else if showError, let message = errorMessage {
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
                } else {
                    Color.clear
                }
            }
            .frame(minHeight: 80, maxHeight: 80)

            // Fixed spacer instead of flexible
            Color.clear
                .frame(height: 20)

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
        .onAppear { checkLockout() }
        .onDisappear { lockoutTimerTask?.cancel() }
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: showError)
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: isLockedOut)
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

        guard !isLockedOut else {
            patternLockLogger.debug("Locked out, ignoring pattern")
            patternState.reset()
            return
        }

        // Require minimum pattern length to prevent accidental taps
        guard pattern.count >= 6 else {
            patternLockLogger.debug("Pattern too short: \(pattern.count) nodes, minimum 6 required")

            errorMessage = "Pattern must connect at least 6 dots"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation { showError = true }

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { withAnimation { showError = false } }
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
            if !subscriptionManager.isPremium, let key = derivedKey,
               !VaultStorage.shared.vaultExists(for: VaultKey(key)) {
                let vaultCount = VaultStorage.shared.existingVaultCount()
                if !subscriptionManager.canCreateVault(currentCount: vaultCount) {
                    await MainActor.run {
                        // Vault limit hit — likely brute-force attempt
                        SecureEnclaveManager.shared.incrementWipeCounter()
                        let count = SecureEnclaveManager.shared.getWipeCounter()
                        let delay = Self.bruteForceDelay(forAttempts: count)
                        patternLockLogger.info("Vault limit hit: attempt \(count), delay=\(delay)s")
                        if delay > 0 {
                            applyLockout(duration: delay)
                        } else {
                            showingPaywall = true
                        }
                        isProcessing = false
                        patternState.reset()
                    }
                    return
                }
            }

            // Attempt to unlock, passing pre-derived key to avoid double PBKDF2
            let unlocked = await appState.unlockWithPattern(pattern, gridSize: 5, precomputedKey: derivedKey)

            await MainActor.run {
                if unlocked {
                    SecureEnclaveManager.shared.resetWipeCounter()
                    clearLockout()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    SecureEnclaveManager.shared.incrementWipeCounter()
                    let count = SecureEnclaveManager.shared.getWipeCounter()
                    let delay = Self.bruteForceDelay(forAttempts: count)
                    patternLockLogger.info("Unlock failed: attempt \(count), delay=\(delay)s")
                    if delay > 0 {
                        applyLockout(duration: delay)
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                isProcessing = false
                patternState.reset()
            }
        }
    }

    // MARK: - Lockout Helpers

    private func checkLockout() {
        if let endTime = UserDefaults.standard.object(forKey: Self.lockoutEndTimeKey) as? Date {
            let remaining = endTime.timeIntervalSinceNow
            if remaining > 0 {
                lockoutRemaining = remaining
                startLockoutTimer(until: endTime)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lockoutEndTimeKey)
            }
        }
    }

    private func applyLockout(duration: TimeInterval) {
        let endTime = Date().addingTimeInterval(duration)
        UserDefaults.standard.set(endTime, forKey: Self.lockoutEndTimeKey)
        lockoutRemaining = duration
        startLockoutTimer(until: endTime)
    }

    private func clearLockout() {
        lockoutTimerTask?.cancel()
        lockoutTimerTask = nil
        lockoutRemaining = 0
        UserDefaults.standard.removeObject(forKey: Self.lockoutEndTimeKey)
    }

    private func startLockoutTimer(until endTime: Date) {
        lockoutTimerTask?.cancel()
        lockoutTimerTask = Task {
            while !Task.isCancelled {
                let remaining = endTime.timeIntervalSinceNow
                if remaining <= 0 {
                    lockoutRemaining = 0
                    UserDefaults.standard.removeObject(forKey: Self.lockoutEndTimeKey)
                    break
                }
                lockoutRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func formatCountdown(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "\(seconds)s"
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
                    .scrollContentBackground(.hidden)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Recovery Failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.vaultHighlight)
                            .font(.subheadline.weight(.medium))
                        Text(error)
                            .foregroundStyle(.vaultSecondaryText)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vaultGlassBackground(cornerRadius: 12)
                    .accessibilityIdentifier("unlock_recovery_error")
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.vaultBackground)
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
                
                // Use unlockWithKey to show the same loading ceremony as pattern unlock
                await appState.unlockWithKey(patternKey, isRecovery: true)
                
                await MainActor.run {
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
