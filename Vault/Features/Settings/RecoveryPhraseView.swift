import SwiftUI
import CryptoKit

struct RecoveryPhraseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var phrase: String = ""
    @State private var errorMessage: String?
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Error or warning banner
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
                if !phrase.isEmpty {
                    PhraseDisplayCard(phrase: phrase)

                    PhraseActionButtons(phrase: phrase)
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

                // "I've saved it" button with confirmation
                Button(action: { showSaveConfirmation = true }) {
                    Text("I've saved it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .vaultProminentButtonStyle()
                .alert("Are you sure?", isPresented: $showSaveConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Yes, I've saved it") { dismiss() }
                } message: {
                    Text("This recovery phrase will NEVER be shown again. Make sure you've written it down and stored it safely.")
                }
            }
            .padding()
            .navigationTitle("Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
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
                if let loadedPhrase = try await RecoveryPhraseManager.shared.loadRecoveryPhrase(for: currentKey) {
                    await MainActor.run {
                        phrase = loadedPhrase
                    }
                } else {
                    #if DEBUG
                    print("[RecoveryPhraseView] No recovery phrase found - generating one now")
                    #endif

                    let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()

                    try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                        phrase: newPhrase,
                        pattern: [],
                        gridSize: 5,
                        patternKey: currentKey
                    )

                    await MainActor.run {
                        phrase = newPhrase
                    }
                }
            } catch {
                #if DEBUG
                print("[RecoveryPhraseView] Error loading phrase: \(error)")
                #endif
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
