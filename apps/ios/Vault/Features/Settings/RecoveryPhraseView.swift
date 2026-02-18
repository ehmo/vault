import SwiftUI
import CryptoKit
import os.log

private let recoveryPhraseViewLogger = Logger(subsystem: "app.vaultaire.ios", category: "RecoveryPhraseView")

struct RecoveryPhraseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var phrase: String = ""
    @State private var errorMessage: String?
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Header — matches onboarding style
                VStack(spacing: 12) {
                    Text("Recovery Phrase")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Save this phrase to recover your vault if you forget the pattern")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                        .multilineTextAlignment(.center)
                }

                // Error banner (only on error)
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
                    .padding(.horizontal)
                }

                // Phrase display
                if !phrase.isEmpty {
                    PhraseDisplayCard(phrase: phrase)
                        .padding(.horizontal)

                    PhraseActionButtons(phrase: phrase)
                        .padding(.horizontal)
                }

                // Instructions — matches onboarding
                VStack(alignment: .leading, spacing: 12) {
                    Label("Write this down", systemImage: "pencil")
                    Label("Store it somewhere safe", systemImage: "lock")
                    Label("Never share it with anyone", systemImage: "person.slash")
                }
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)

                Spacer()

                // "I've saved it" button with confirmation
                Button(action: { showSaveConfirmation = true }) {
                    Text("I've saved it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .vaultProminentButtonStyle()
                .accessibilityIdentifier("recovery_phrase_saved")
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .alert("Are you sure?", isPresented: $showSaveConfirmation) {
                    Button("Cancel", role: .cancel) { /* No-op */ }
                    Button("Yes, I've saved it") { dismiss() }
                } message: {
                    Text("This recovery phrase will NEVER be shown again. Make sure you've written it down and stored it safely.")
                }
            }
            .navigationTitle("Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.vaultBackground.ignoresSafeArea())
        }
        .task {
            generateOrLoadPhrase()
        }
    }

    private func generateOrLoadPhrase() {
        guard let currentKey = appState.currentVaultKey else {
            errorMessage = "No vault key available"
            return
        }

        Task {
            do {
                if let loadedPhrase = try await RecoveryPhraseManager.shared.loadRecoveryPhrase(for: currentKey.rawBytes) {
                    await MainActor.run {
                        phrase = loadedPhrase
                    }
                } else {
                    recoveryPhraseViewLogger.info("No recovery phrase found, generating one")

                    let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()

                    try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                        phrase: newPhrase,
                        pattern: [],
                        gridSize: 5,
                        patternKey: currentKey.rawBytes
                    )

                    await MainActor.run {
                        phrase = newPhrase
                    }
                }
            } catch {
                recoveryPhraseViewLogger.error("Error loading phrase: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    errorMessage = "Failed to load recovery phrase: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    RecoveryPhraseView()
        .environment(AppState())
}
