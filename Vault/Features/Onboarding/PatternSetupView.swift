import SwiftUI
import UIKit

struct PatternSetupView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @State private var patternState = PatternState()
    @State private var step: SetupStep = .create
    @State private var firstPattern: [Int] = []
    @State private var validationResult: PatternValidationResult?
    @State private var showRecoveryOption = false
    @State private var generatedPhrase = ""
    @State private var useCustomPhrase = false
    @State private var customPhrase = ""
    @State private var customPhraseValidation: RecoveryPhraseGenerator.PhraseValidation?
    @State private var showSaveConfirmation = false
    @State private var errorMessage: String?

    enum SetupStep {
        case create
        case confirm
        case recovery
        case complete
    }

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(stepIndex >= index ? Color.accentColor : Color.vaultSecondaryText.opacity(0.3))
                        .frame(width: 40, height: 4)
                }
            }
            .padding(.top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(stepIndex + 1) of 3")

            // Header — fixed height prevents grid from shifting between steps
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .frame(height: 44, alignment: .top)
            }
            .padding(.horizontal)

            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.vaultHighlight)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.vaultHighlight)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .vaultGlassTintedBackground(tint: Color.vaultHighlight, cornerRadius: 8)
                .transition(.scale.combined(with: .opacity))
            }

            // Content based on step
            switch step {
            case .create, .confirm:
                Spacer()
                patternInputSection
                Spacer()

                // Validation feedback — fixed height to prevent layout shift
                Group {
                    if let result = validationResult, step == .create {
                        validationFeedback(result)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 80)

            case .recovery:
                Spacer()
                recoverySection
                Spacer()

            case .complete:
                Spacer()
                completeSection
                Spacer()
            }

            // Bottom buttons
            bottomButtons
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var stepIndex: Int {
        switch step {
        case .create: return 0
        case .confirm: return 1
        case .recovery, .complete: return 2
        }
    }

    private var headerTitle: String {
        switch step {
        case .create: return "Create Your Pattern"
        case .confirm: return "Confirm Your Pattern"
        case .recovery: return "Recovery Phrase"
        case .complete: return "All Set!"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .create: return "Connect at least 6 dots on the 5×5 grid with 2+ direction changes"
        case .confirm: return "Draw the same pattern to confirm"
        case .recovery: return "Save this phrase to recover your vault if you forget the pattern"
        case .complete: return "Your vault is ready to use"
        }
    }

    // MARK: - Views

    private var patternInputSection: some View {
        PatternGridView(
            state: patternState,
            showFeedback: .constant(true),

            onPatternComplete: handlePatternComplete
        )
        .frame(width: 280, height: 280)
        .vaultPatternGridBackground()
        .padding()
    }

    private var recoverySection: some View {
        VStack(spacing: 20) {
            // Toggle between generated and custom phrase
            Picker("Phrase Type", selection: $useCustomPhrase) {
                Text("Auto-Generated").tag(false)
                Text("Custom Phrase").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Fixed-height phrase area — prevents layout shift between modes
            VStack(spacing: 12) {
                if useCustomPhrase {
                    Text("Enter Your Custom Recovery Phrase")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $customPhrase)
                            .autocorrectionDisabled()
                            .onChange(of: customPhrase) { _, newValue in
                                validateCustomPhrase(newValue)
                            }

                        if customPhrase.isEmpty {
                            Text("Type a memorable phrase with 6-9 words...")
                                .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.vaultSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.vaultSecondaryText.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Validation feedback — fixed height so layout doesn't shift
                    Group {
                        if let validation = customPhraseValidation {
                            HStack(spacing: 8) {
                                Image(systemName: validation.isAcceptable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(validation.isAcceptable ? .green : .orange)
                                Text(validation.message)
                                    .font(.caption)
                            }
                            .padding(.horizontal)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: 20)
                } else {
                    PhraseDisplayCard(phrase: generatedPhrase)
                        .frame(height: 148)
                }
            }
            .frame(height: 190, alignment: .top)
            .padding(.horizontal)

            PhraseActionButtons(phrase: useCustomPhrase ? customPhrase.trimmingCharacters(in: .whitespacesAndNewlines) : generatedPhrase)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Label("Write this down", systemImage: "pencil")
                Label("Store it somewhere safe", systemImage: "lock")
                Label("Never share it with anyone", systemImage: "person.slash")
            }
            .font(.subheadline)
            .foregroundStyle(.vaultSecondaryText)
        }
        .padding(.horizontal)
    }

    private var completeSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Your vault is ready!")
                .font(.title2)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func validationFeedback(_ result: PatternValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Errors
            ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.vaultHighlight)
                    Text(error.message)
                        .font(.caption)
                }
            }

            // Warnings (only if no errors)
            if result.errors.isEmpty {
                ForEach(Array(result.warnings.prefix(2).enumerated()), id: \.offset) { _, warning in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(warning.rawValue)
                            .font(.caption)
                    }
                }
            }

            // Complexity score
            if result.errors.isEmpty {
                let description = PatternValidator.shared.complexityDescription(for: result.metrics.complexityScore)
                HStack {
                    Image(systemName: "shield.fill")
                        .foregroundStyle(result.metrics.complexityScore >= 30 ? .green : .orange)
                    Text("Strength: \(description)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .vaultGlassBackground(cornerRadius: 12)
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            switch step {
            case .create:
                Button("Clear") {
                    patternState.reset()
                    validationResult = nil
                }
                .disabled(patternState.selectedNodes.isEmpty)

            case .confirm:
                Button("Start Over") {
                    step = .create
                    firstPattern = []
                    patternState.reset()
                    validationResult = nil
                }

            case .recovery:
                Button(action: {
                    showSaveConfirmation = true
                }) {
                    Text("I've saved it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .vaultProminentButtonStyle()
                .disabled(useCustomPhrase && !(customPhraseValidation?.isAcceptable ?? false))
                .alert("Are you sure?", isPresented: $showSaveConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Yes, I've saved it") {
                        if useCustomPhrase {
                            if let validation = customPhraseValidation, validation.isAcceptable {
                                saveCustomRecoveryPhrase()
                            }
                        } else {
                            step = .complete
                        }
                    }
                } message: {
                    Text("This recovery phrase will NEVER be shown again. Make sure you've written it down and stored it safely.")
                }

            case .complete:
                Button(action: onComplete) {
                    Text("Open Vaultaire")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .vaultProminentButtonStyle()
            }
        }
    }

    // MARK: - Actions

    private func handlePatternComplete(_ pattern: [Int]) {
        #if DEBUG
        print("🎨 [PatternSetup] Pattern completed in \(step) step: \(pattern) (count: \(pattern.count))")
        #endif
        
        switch step {
        case .create:
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
            validationResult = result

            #if DEBUG
            print("🎨 [PatternSetup] Validation result - isValid: \(result.isValid)")
            print("🎨 [PatternSetup] Errors: \(result.errors)")
            print("🎨 [PatternSetup] Warnings: \(result.warnings)")
            #endif

            if result.isValid {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                errorMessage = nil
                firstPattern = pattern
                step = .confirm
                patternState.reset()

                #if DEBUG
                print("✅ [PatternSetup] Pattern valid, moving to confirm step")
                print("✅ [PatternSetup] First pattern saved: \(firstPattern)")
                #endif
            } else {
                #if DEBUG
                print("❌ [PatternSetup] Pattern invalid, resetting")
                #endif
                patternState.reset()
            }

        case .confirm:
            #if DEBUG
            print("🎨 [PatternSetup] Confirming pattern")
            print("🎨 [PatternSetup] First pattern: \(firstPattern)")
            print("🎨 [PatternSetup] Confirm pattern: \(pattern)")
            print("🎨 [PatternSetup] Patterns match: \(pattern == firstPattern)")
            #endif
            
            if pattern == firstPattern {
                // Patterns match - save and continue
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                errorMessage = nil
                #if DEBUG
                print("✅ [PatternSetup] Patterns match! Saving...")
                #endif
                // Generate the phrase now, before saving
                if !useCustomPhrase {
                    generatedPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                }
                savePattern(pattern)
            } else {
                // Patterns don't match - show error and reset
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #if DEBUG
                print("❌ [PatternSetup] Patterns don't match! Resetting...")
                #endif
                errorMessage = "Patterns don't match. Try again."
                patternState.reset()
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run { errorMessage = nil }
                }
            }

        default:
            break
        }
    }

    private func savePattern(_ pattern: [Int]) {
        #if DEBUG
        print("🔐 [PatternSetup] Saving pattern with gridSize: \(patternState.gridSize)")
        #endif
        
        Task {
            do {
                // Derive key from pattern with the current grid size
                let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)
                
                #if DEBUG
                print("🔑 [PatternSetup] Key derived successfully. Key hash: \(key.hashValue)")
                #endif
                
                // Check if a vault already exists with this pattern
                if VaultStorage.shared.vaultExists(for: key) {
                    #if DEBUG
                    print("⚠️ [PatternSetup] Vault already exists for this pattern!")
                    #endif
                    
                    await MainActor.run {
                        // Reset to create step with error message
                        step = .create
                        patternState.reset()
                        firstPattern = []
                        
                        // Show validation error for duplicate pattern
                        validationResult = PatternValidationResult(
                            isValid: false,
                            errors: [.custom("This pattern is already used by another vault. Please choose a different pattern.")],
                            warnings: [],
                            metrics: PatternSerializer.PatternMetrics(
                                nodeCount: pattern.count,
                                directionChanges: 0,
                                startsAtCorner: (Set(pattern).count != 0),
                                endsAtCorner: false,
                                crossesCenter: false,
                                touchesAllQuadrants: false
                            )
                        )
                    }
                    return
                }

                // Initialize empty vault index for this key
                let emptyIndex = VaultStorage.VaultIndex(
                    files: [],
                    nextOffset: 0,
                    totalSize: 500 * 1024 * 1024
                )
                try VaultStorage.shared.saveIndex(emptyIndex, with: key)
                
                #if DEBUG
                print("💾 [PatternSetup] Empty vault index saved")
                #endif
                
                // Determine which phrase to use
                let finalPhrase = useCustomPhrase ? customPhrase.trimmingCharacters(in: .whitespacesAndNewlines) : generatedPhrase
                
                // Save recovery data using the new manager
                try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                    phrase: finalPhrase,
                    pattern: pattern,
                    gridSize: patternState.gridSize,
                    patternKey: key
                )
                
                #if DEBUG
                print("✅ [PatternSetup] Recovery phrase saved via RecoveryPhraseManager")
                #endif
                
                SentryManager.shared.addBreadcrumb(category: "onboarding.complete", data: ["gridSize": patternState.gridSize])

                // Unlock the vault with the new key
                await MainActor.run {
                    appState.currentVaultKey = key
                    appState.isUnlocked = true
                    let letters = GridLetterManager.shared.vaultName(for: pattern)
                    appState.updateVaultName(letters.isEmpty ? "Vault" : "Vault \(letters)")

                    #if DEBUG
                    print("🔓 [PatternSetup] Vault unlocked. currentVaultKey set: \(appState.currentVaultKey != nil)")
                    print("🔓 [PatternSetup] isUnlocked: \(appState.isUnlocked)")
                    #endif

                    // Move to recovery step AFTER everything is saved
                    step = .recovery
                }
            } catch {
                #if DEBUG
                print("❌ [PatternSetup] Error saving pattern: \(error)")
                #endif
                // TODO: Show error to user
            }
        }
    }
    
    private func saveCustomRecoveryPhrase() {
        guard let key = appState.currentVaultKey else { return }

        Task {
            do {
                try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                    phrase: customPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
                    pattern: firstPattern,
                    gridSize: patternState.gridSize,
                    patternKey: key
                )
                await MainActor.run {
                    step = .complete
                }
            } catch {
                #if DEBUG
                print("❌ [PatternSetup] Failed to save custom phrase: \(error)")
                #endif
            }
        }
    }

    private func validateCustomPhrase(_ phrase: String) {
        guard !phrase.isEmpty else {
            customPhraseValidation = nil
            return
        }
        customPhraseValidation = RecoveryPhraseGenerator.shared.validatePhrase(phrase)
    }
    
    private struct RecoveryData: Codable {
        let pattern: [Int]
        let gridSize: Int
        let patternKey: Data
    }
}



#Preview {
    PatternSetupView(onComplete: {})
        .environment(AppState())
}
