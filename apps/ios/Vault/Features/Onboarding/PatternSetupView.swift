import SwiftUI
import UIKit
import os.log

private let patternSetupLogger = Logger(subsystem: "app.vaultaire.ios", category: "PatternSetup")

struct PatternSetupView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @State private var patternState = PatternState()
    @State private var step: SetupStep = .create
    @State private var firstPattern: [Int] = []
    @State private var validationResult: PatternValidationResult?
    @State private var isSaving = false
    @State private var generatedPhrase = ""
    @State private var useCustomPhrase = false
    @State private var customPhrase = ""
    @State private var customPhraseValidation: RecoveryPhraseGenerator.PhraseValidation?
    @State private var showSaveConfirmation = false
    @State private var errorMessage: String?
    @State private var coordinator = PatternSetupCoordinator()

    enum SetupStep {
        case create
        case confirm
        case recovery
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .top)
            }
            .padding(.horizontal)

            // Content based on step
            switch step {
            case .create, .confirm:
                Spacer()
                patternInputSection
                Spacer()

                // Validation feedback — fixed height to prevent layout shift
                Group {
                    if let result = validationResult, step == .create {
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
                        .accessibilityIdentifier("pattern_error_message")
                    } else {
                        Color.clear
                    }
                }
                .frame(minHeight: 80)

            case .recovery:
                recoveryScrollSection
            }

            // Bottom buttons for pattern steps.
            // Recovery action is pinned via safeAreaInset so it stays visible above keyboard.
            if step != .recovery {
                bottomButtons
            }
        }
        .padding()
        .background(Color.vaultBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if step == .recovery {
                bottomButtons
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color.vaultBackground)
            }
        }
        .toolbar {
            if step == .recovery && useCustomPhrase {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
        .overlay {
            if isSaving {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MAESTRO_FORCE_ONBOARDING_RECOVERY") {
                step = .recovery
                useCustomPhrase = true
                generatedPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
            }
            #endif
        }
        .allowsHitTesting(!isSaving)
    }

    // MARK: - Computed Properties

    private var stepIndex: Int {
        switch step {
        case .create: return 0
        case .confirm: return 1
        case .recovery: return 2
        }
    }

    private var headerTitle: String {
        switch step {
        case .create: return "Create Your Pattern"
        case .confirm: return "Confirm Your Pattern"
        case .recovery: return "Recovery Phrase"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .create: return "Connect at least 6 dots on the 5×5 grid with 2+ direction changes"
        case .confirm: return "Draw the same pattern to confirm"
        case .recovery: return "Save this phrase to recover your vault if you forget the pattern"
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
        .accessibilityIdentifier("pattern_grid")
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
            .accessibilityIdentifier("recovery_picker")

            // Fixed-height phrase area — prevents layout shift between modes
            VStack(spacing: 12) {
                if useCustomPhrase {
                    Text("Enter Your Custom Recovery Phrase")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $customPhrase)
                            .scrollContentBackground(.hidden)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("recovery_custom_phrase_input")
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
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(minHeight: 20)
                } else {
                    PhraseDisplayCard(phrase: generatedPhrase)
                        .frame(minHeight: 148)
                }
            }
            .frame(minHeight: 190, alignment: .top)
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

    private var recoveryScrollSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                recoverySection
                    .padding(.top, 8)

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(error)
                            .font(.caption)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vaultGlassBackground(cornerRadius: 12)
                    .padding(.horizontal)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
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
                .accessibilityIdentifier("pattern_clear")

            case .confirm:
                Button("Start Over") {
                    step = .create
                    firstPattern = []
                    patternState.reset()
                    validationResult = nil
                }
                .accessibilityIdentifier("pattern_start_over")

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
                .accessibilityIdentifier("recovery_saved")
                .alert("Are you sure?", isPresented: $showSaveConfirmation) {
                    Button("Cancel", role: .cancel) { /* No-op */ }
                    Button("Yes, I've saved it") {
                        if useCustomPhrase {
                            // Validation already enforced by the disabled button guard;
                            // re-checking here caused a silent no-op when SwiftUI
                            // re-evaluated state during alert/keyboard transitions.
                            saveCustomRecoveryPhrase()
                        } else {
                            onComplete()
                        }
                    }
                } message: {
                    Text("This recovery phrase will NEVER be shown again. Make sure you've written it down and stored it safely.")
                }
            }
        }
    }

    // MARK: - Actions

    private func handlePatternComplete(_ pattern: [Int]) {
        patternSetupLogger.debug("Pattern completed in \(String(describing: step), privacy: .public) step, count: \(pattern.count)")
        
        switch step {
        case .create:
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
            validationResult = result

            patternSetupLogger.debug("Validation: isValid=\(result.isValid), errors=\(result.errors.count), warnings=\(result.warnings.count)")

            if result.isValid {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                errorMessage = nil
                firstPattern = pattern
                step = .confirm
                patternState.reset()

                patternSetupLogger.debug("Pattern valid, moving to confirm step")
            } else {
                patternSetupLogger.debug("Pattern invalid, resetting")
                patternState.reset()
            }

        case .confirm:
            patternSetupLogger.debug("Confirming pattern, match=\(pattern == firstPattern)")
            
            if pattern == firstPattern {
                // Patterns match - save and continue
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                errorMessage = nil
                patternSetupLogger.debug("Patterns match, saving")
                // Generate the phrase now, before saving
                if !useCustomPhrase {
                    generatedPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                }
                savePattern(pattern)
            } else {
                // Patterns don't match - show error and reset
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                patternSetupLogger.debug("Patterns don't match, resetting")
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
        patternSetupLogger.debug("Saving pattern, gridSize=\(patternState.gridSize)")
        isSaving = true

        Task {
            let phrase = useCustomPhrase ? customPhrase.trimmingCharacters(in: .whitespacesAndNewlines) : generatedPhrase
            let result = await coordinator.savePattern(pattern, gridSize: patternState.gridSize, phrase: phrase)

            await MainActor.run {
                switch result {
                case .success(let key):
                    patternSetupLogger.debug("Pattern saved successfully")
                    EmbraceManager.shared.addBreadcrumb(category: "onboarding.complete", data: ["gridSize": patternState.gridSize])

                    isSaving = false
                    appState.currentVaultKey = VaultKey(key)
                    let letters = GridLetterManager.shared.vaultName(for: pattern)
                    appState.updateVaultName(letters.isEmpty ? "Vault" : "Vault \(letters)")
                    step = .recovery

                case .duplicatePattern:
                    patternSetupLogger.info("Vault already exists for this pattern")
                    isSaving = false
                    step = .create
                    patternState.reset()
                    firstPattern = []
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

                case .error(let message):
                    patternSetupLogger.error("Error saving pattern: \(message, privacy: .public)")
                    isSaving = false
                    errorMessage = "Failed to save pattern. Please try again."
                    step = .create
                    patternState.reset()
                    firstPattern = []
                }
            }
        }
    }
    
    private func saveCustomRecoveryPhrase() {
        guard let key = appState.currentVaultKey else { return }
        isSaving = true

        Task {
            let phrase = customPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = await coordinator.saveCustomPhrase(phrase, pattern: firstPattern, gridSize: patternState.gridSize, key: key.rawBytes)

            await MainActor.run {
                isSaving = false
                switch result {
                case .success:
                    onComplete()
                case .duplicatePattern:
                    break // Not possible for custom phrase path
                case .error(let message):
                    patternSetupLogger.error("Failed to save custom phrase: \(message, privacy: .public)")
                    errorMessage = "Failed to save recovery phrase. Please try again."
                }
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}



#Preview {
    PatternSetupView(onComplete: {})
        .environment(AppState())
}
