import SwiftUI
import os.log

private let customPhraseLogger = Logger(subsystem: "app.vaultaire.ios", category: "CustomRecoveryPhrase")

struct CustomRecoveryPhraseInputView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var customPhrase = ""
    @State private var validation: RecoveryPhraseGenerator.PhraseValidation?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if showSuccess {
                    successView
                } else {
                    inputView
                }
            }
            .navigationTitle("Custom Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.vaultBackground)
            .toolbarBackground(Color.vaultBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !showSuccess {
                    ToolbarItem(placement: .confirmationAction) {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Button("Save") { saveCustomPhrase() }
                                .disabled(!(validation?.isAcceptable ?? false))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .background(Color.vaultBackground.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }

    private var inputView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    Text("Set Your Custom Phrase")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Enter a memorable sentence that you'll use to recover this vault. It should be unique and difficult to guess.")
                        .font(.subheadline)
                        .foregroundStyle(.vaultSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                // Phrase input
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $customPhrase)
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled()
                        .onChange(of: customPhrase) { _, newValue in
                            validatePhrase(newValue)
                        }

                    if customPhrase.isEmpty {
                        Text("Type a memorable phrase with 6-9 words...")
                            .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 120)
                .padding(8)
                .background(Color.vaultSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.vaultSecondaryText.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Validation feedback
                if let validation = validation {
                    HStack(spacing: 8) {
                        Image(systemName: validation.isAcceptable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(validation.isAcceptable ? .green : .orange)
                        Text(validation.message)
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(validation.isAcceptable ? Color.green.opacity(0.1) : Color.vaultHighlight.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Error message
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(error)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.vaultHighlight.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Guidelines
                VStack(alignment: .leading, spacing: 12) {
                    Label("Use at least 6-9 words", systemImage: "text.word.spacing")
                    Label("Mix common and uncommon words", systemImage: "shuffle")
                    Label("Make it memorable but unique", systemImage: "brain.head.profile")
                }
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .vaultGlassBackground(cornerRadius: 12)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Custom Phrase Set!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your custom recovery phrase has been saved. Make sure to write it down in a safe place.")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            PhraseDisplayCard(phrase: customPhrase.trimmingCharacters(in: .whitespacesAndNewlines))
                .padding(.horizontal)

            PhraseActionButtons(phrase: customPhrase.trimmingCharacters(in: .whitespacesAndNewlines))
                .padding(.horizontal)

            Spacer()

            Button(action: { showSaveConfirmation = true }) {
                Text("I've saved it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .vaultProminentButtonStyle()
            .padding()
            .alert("Are you sure?", isPresented: $showSaveConfirmation) {
                Button("Cancel", role: .cancel) {
                    // No-op: dismiss handled by SwiftUI
                }
                Button("Yes, I've saved it") { dismiss() }
            } message: {
                Text("This recovery phrase will NEVER be shown again. Make sure you've written it down and stored it safely.")
            }
        }
    }

    private func validatePhrase(_ phrase: String) {
        guard !phrase.isEmpty else {
            validation = nil
            return
        }
        validation = RecoveryPhraseGenerator.shared.validatePhrase(phrase)
    }
    
    private func saveCustomPhrase() {
        guard let key = appState.currentVaultKey else {
            errorMessage = "No vault key available"
            return
        }
        
        guard let validation = validation, validation.isAcceptable else {
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let phrase = customPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    _ = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(
                        for: key.rawBytes,
                        customPhrase: phrase
                    )
                } catch RecoveryError.vaultNotFound {
                    // Vault has no recovery data yet — create it
                    guard let pattern = appState.currentPattern else {
                        throw RecoveryError.vaultNotFound
                    }
                    try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                        phrase: phrase,
                        pattern: pattern,
                        gridSize: 5,
                        patternKey: key.rawBytes
                    )
                }

                await MainActor.run {
                    isProcessing = false
                    showSuccess = true
                }
            } catch RecoveryError.weakPhrase(let message) {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = message
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to set custom phrase: \(error.localizedDescription)"
                }
            }
        }
    }
}
