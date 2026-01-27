import SwiftUI

struct PatternLockView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var patternState = PatternState()

    @AppStorage("showPatternFeedback") private var showFeedback = true
    @AppStorage("randomizeGrid") private var randomizeGrid = false
    @AppStorage("gridSize") private var gridSize = 4

    @State private var isProcessing = false
    @State private var showRecoveryOption = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Draw your pattern")
                    .font(.title2)
                    .fontWeight(.medium)
            }

            Spacer()

            // Pattern Grid
            PatternGridView(
                state: patternState,
                showFeedback: $showFeedback,
                randomizeGrid: $randomizeGrid,
                onPatternComplete: handlePatternComplete
            )
            .frame(maxWidth: 280, maxHeight: 280)
            .disabled(isProcessing)
            .opacity(isProcessing ? 0.5 : 1)

            Spacer()

            // Recovery option
            Button(action: { showRecoveryOption = true }) {
                Text("Use recovery phrase")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showRecoveryOption) {
            RecoveryPhraseInputView()
        }
        .onAppear {
            patternState.gridSize = gridSize
        }
    }

    private func handlePatternComplete(_ pattern: [Int]) {
        #if DEBUG
        print("🎯 Pattern completed: \(pattern) (count: \(pattern.count))")
        #endif
        
        guard !isProcessing else {
            #if DEBUG
            print("⚠️ Already processing, ignoring pattern")
            #endif
            return
        }
        
        // Require minimum pattern length to prevent accidental taps
        guard pattern.count >= 4 else {
            #if DEBUG
            print("❌ Pattern too short (\(pattern.count) nodes), minimum 4 required")
            #endif
            patternState.reset()
            return
        }

        #if DEBUG
        print("✅ Pattern accepted, processing unlock...")
        #endif
        
        isProcessing = true

        Task {
            // Attempt to unlock with the pattern, using the current grid size
            _ = await appState.unlockWithPattern(pattern, gridSize: gridSize)

            await MainActor.run {
                isProcessing = false
                patternState.reset()
            }
        }
    }
}

// MARK: - Recovery Phrase Input

struct RecoveryPhraseInputView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var isProcessing = false

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
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextEditor(text: $phrase)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
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

                Spacer()
            }
            .padding()
        }
    }

    private func attemptRecovery() {
        isProcessing = true

        Task {
            do {
                let key = try await KeyDerivation.deriveKey(from: phrase)
                await MainActor.run {
                    appState.currentVaultKey = key
                    appState.isUnlocked = true
                    dismiss()
                }
            } catch {
                // Recovery failed - show empty vault anyway
                await MainActor.run {
                    appState.isUnlocked = true
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    PatternLockView()
        .environmentObject(AppState())
}
