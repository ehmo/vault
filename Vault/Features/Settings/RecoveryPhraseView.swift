import SwiftUI
import CryptoKit

struct RecoveryPhraseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var phrase: String = ""
    @State private var isRevealed = false
    @State private var showingCopiedAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recovery Phrase")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            VStack(spacing: 24) {
                // Error message if any
                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(errorMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color.vaultHighlight.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Warning
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text("Keep this phrase secret and secure")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color.vaultHighlight.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Phrase display
                VStack(spacing: 12) {
                    if isRevealed {
                        Text(phrase)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.vaultSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button(action: copyPhrase) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: revealPhrase) {
                            VStack(spacing: 8) {
                                Image(systemName: "eye.fill")
                                    .font(.title)
                                Text("Tap to reveal")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.vaultSecondaryText)
                            .padding(40)
                            .frame(maxWidth: .infinity)
                            .background(Color.vaultSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Spacer()

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Write it down and store safely", systemImage: "pencil.and.list.clipboard")
                    Label("Never share it with anyone", systemImage: "person.2.slash")
                    Label("Use it to recover this vault if you forget the pattern", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
            }
            .padding()
        }
        .task {
            generateOrLoadPhrase()
        }
        .alert("Copied!", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Recovery phrase copied to clipboard. Clear your clipboard after use.")
        }
    }

    private func generateOrLoadPhrase() {
        // Load the saved recovery phrase for the current vault
        guard let currentKey = appState.currentVaultKey else {
            errorMessage = "No vault key available"
            return
        }
        
        Task {
            do {
                // Load the recovery phrase from the manager
                if let loadedPhrase = try await RecoveryPhraseManager.shared.loadRecoveryPhrase(for: currentKey) {
                    await MainActor.run {
                        phrase = loadedPhrase
                    }
                } else {
                    #if DEBUG
                    print("⚠️ [RecoveryPhraseView] No recovery phrase found - generating one now")
                    #endif
                    
                    // Generate and save a recovery phrase if one doesn't exist
                    // This handles the edge case where a vault was created without a recovery phrase
                    let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                    
                    // We need the pattern to save it, but we don't have it
                    // So we save with an empty pattern array (the phrase alone is enough for recovery)
                    try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                        phrase: newPhrase,
                        pattern: [], // Empty pattern since we don't know what it is
                        gridSize: 5, // Default grid size
                        patternKey: currentKey
                    )
                    
                    await MainActor.run {
                        phrase = newPhrase
                    }
                    
                    #if DEBUG
                    print("✅ [RecoveryPhraseView] New recovery phrase generated and saved: \(newPhrase)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("❌ [RecoveryPhraseView] Error loading phrase: \(error)")
                #endif
                await MainActor.run {
                    errorMessage = "Failed to load recovery phrase: \(error.localizedDescription)"
                }
            }
        }
    }

    private func revealPhrase() {
        withAnimation {
            isRevealed = true
        }
    }

    private func copyPhrase() {
        UIPasteboard.general.string = phrase
        showingCopiedAlert = true

        // Clear clipboard after 60 seconds
        Task {
            try? await Task.sleep(for: .seconds(60))
            if UIPasteboard.general.string == phrase {
                UIPasteboard.general.string = ""
            }
        }
    }
}

#Preview {
    RecoveryPhraseView()
        .environment(AppState())
}
