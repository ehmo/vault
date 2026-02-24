import SwiftUI
import os.log

private let changePatternLogger = Logger(subsystem: "app.vaultaire.ios", category: "ChangePattern")

enum ChangePatternStep: Equatable {
    case verifyCurrent
    case createNew
    case confirmNew
    case complete
}

struct ChangePatternFlowState {
    var step: ChangePatternStep = .verifyCurrent
    var currentPattern: [Int] = []
    var newPattern: [Int] = []
    var validationResult: PatternValidationResult?
    var errorMessage: String?
    var isProcessing = false
    var newRecoveryPhrase = ""

    mutating func clearFeedback() {
        validationResult = nil
        errorMessage = nil
    }

    mutating func showValidation(_ result: PatternValidationResult) {
        validationResult = result
        errorMessage = nil
    }

    mutating func showError(_ message: String) {
        errorMessage = message
        validationResult = nil
    }

    mutating func beginProcessingIfIdle() -> Bool {
        guard !isProcessing else { return false }
        isProcessing = true
        return true
    }

    mutating func endProcessing() {
        isProcessing = false
    }

    mutating func resetForStartOver() {
        step = .verifyCurrent
        currentPattern = []
        newPattern = []
        clearFeedback()
        isProcessing = false
    }

    mutating func skipVerification() {
        step = .createNew
        currentPattern = []
        newPattern = []
        clearFeedback()
        isProcessing = false
    }

    mutating func skipVerifyForTesting(pattern: [Int]) {
        step = .createNew
        currentPattern = pattern
        newPattern = []
        clearFeedback()
        isProcessing = false
    }

    mutating func transitionToCreate(currentPattern pattern: [Int]) {
        currentPattern = pattern
        step = .createNew
        clearFeedback()
        isProcessing = false
    }

    mutating func transitionToConfirm(newPattern pattern: [Int]) {
        newPattern = pattern
        step = .confirmNew
        clearFeedback()
        isProcessing = false
    }

    mutating func complete(with recoveryPhrase: String) {
        step = .complete
        newRecoveryPhrase = recoveryPhrase
        clearFeedback()
        isProcessing = false
    }
}

struct ChangePatternView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var patternState = PatternState()
    @State private var flow = ChangePatternFlowState()
    @State private var showSaveConfirmation = false
    @State private var showDoneConfirmation = false
    @AppStorage("showPatternFeedback") private var showPatternFeedback = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if step != .complete {
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(0..<totalSteps, id: \.self) { index in
                            Capsule()
                                .fill(stepIndex >= index ? Color.accentColor : Color.vaultSecondaryText.opacity(0.3))
                                .frame(width: 40, height: 4)
                        }
                    }
                    .padding(.top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(stepIndex + 1) of \(totalSteps)")
                }

                if isMaestroHookEnabled {
                    maestroChangePatternTestHooks
                }

                if skipVerification && step != .complete {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("You unlocked with your recovery phrase, so pattern verification is not required.")
                            .font(.caption)
                            .foregroundStyle(.vaultSecondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vaultGlassBackground(cornerRadius: 10)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("change_pattern_skip_info_banner")
                }

                if step != .complete {
                    // Title and subtitle — fixed height prevents grid from shifting between steps
                    VStack(spacing: 8) {
                        Text(stepTitle)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(stepSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.vaultSecondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44, alignment: .top)
                    }
                    .padding(.horizontal)
                }

                // Content based on step
                switch step {
                case .verifyCurrent, .createNew, .confirmNew:
                    // Main content area - centered with pattern + feedback
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // Pattern board - fixed position, never moves
                        patternInputSection

                        // Validation feedback - BELOW the pattern, fixed height
                        Group {
                            if let result = validationResult, step == .createNew {
                                PatternValidationFeedbackView(result: result)
                                    .accessibilityIdentifier("change_pattern_validation_feedback")
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
                                .accessibilityIdentifier("change_pattern_error_message")
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 80)
                        
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)

                case .complete:
                    ScrollView {
                        completeSection
                            .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                }

                // Bottom buttons
                bottomButtons
            }
            .padding()
            .background(Color.vaultBackground.ignoresSafeArea())
            .navigationTitle("Change Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Save New Pattern?", isPresented: $showSaveConfirmation) {
                Button("Review", role: .cancel) {
                    // No-op: dismiss handled by SwiftUI
                }
                Button("Save", role: .destructive) {
                    completePatternChange()
                }
            } message: {
                if isBackupEnabled {
                    Text("Your current pattern will no longer work. Make sure you've written down your new recovery phrase.\n\nYour iCloud backup will be automatically updated with your new pattern.")
                } else {
                    Text("Your current pattern will no longer work. Make sure you've written down your new recovery phrase.")
                }
            }
            .alert("Are you sure?", isPresented: $showDoneConfirmation) {
                Button("Cancel", role: .cancel) {
                    // No-op: dismiss handled by SwiftUI
                }
                Button("Yes, I've saved it") { dismiss() }
            } message: {
                Text("This recovery phrase will NEVER be shown again. Make sure you've written it down and stored it safely. It's the only way to recover your vault if you forget your pattern.")
            }
            .onAppear {
                if skipVerification {
                    changePatternLogger.debug("Recovery unlock detected — skipping pattern verification")
                    flow.skipVerification()
                    patternState.reset()
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var patternInputSection: some View {
        PatternGridView(
            state: patternState,
            showFeedback: .constant(showPatternFeedback),
            onPatternComplete: handlePatternComplete
        )
        .frame(width: 280, height: 280)
        .disabled(flow.isProcessing)
        .opacity(flow.isProcessing ? 0.6 : 1)
        .accessibilityIdentifier("change_pattern_grid")
    }

    private var completeSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Pattern Changed")
                .font(.title2)
                .fontWeight(.bold)

            Text("Your vault is now protected by your new pattern. Your recovery phrase has been regenerated.")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Recovery phrase display with actions
            if !flow.newRecoveryPhrase.isEmpty {
                PhraseDisplayCard(phrase: flow.newRecoveryPhrase)
                    .padding(.horizontal)
                
                PhraseActionButtons(phrase: flow.newRecoveryPhrase)
                    .padding(.horizontal)
            }

            Text("Write this down now. If you forget your pattern, this is the only way to recover your vault.")
                .font(.caption)
                .foregroundStyle(.vaultHighlight)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        Group {
            if step == .complete {
                Button("Done") {
                    showDoneConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("change_pattern_done")
            } else if step == .createNew {
                // Placeholder for layout consistency
                Color.clear
                    .frame(height: 50)
            } else {
                // Center the Try Again button below the pattern
                HStack {
                    if step == .confirmNew {
                        Button("Try Again") {
                            if skipVerification {
                                flow.skipVerification()
                            } else {
                                flow.resetForStartOver()
                            }
                            patternState.reset()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityIdentifier("change_pattern_try_again")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
    }

    @ViewBuilder
    private var maestroChangePatternTestHooks: some View {
        #if DEBUG
        // Only visible in DEBUG builds when specific launch args are present
        if ProcessInfo.processInfo.arguments.contains("MAESTRO_CHANGE_PATTERN_TEST") {
            VStack {
                Button("[TEST] Skip Verify") {
                    if let testPattern = appState.currentPattern {
                        flow.skipVerifyForTesting(pattern: testPattern)
                        patternState.reset()
                    }
                }
                .font(.caption)
                .foregroundStyle(.vaultSecondaryText)
                .accessibilityIdentifier("maestro_change_pattern_skip_verify")
            }
        }
        #endif
    }

    // MARK: - Computed Properties

    private var skipVerification: Bool {
        appState.unlockedWithRecoveryPhrase
    }

    private var step: ChangePatternStep { flow.step }
    private var totalSteps: Int { skipVerification ? 2 : 3 }
    private var stepIndex: Int {
        switch step {
        case .verifyCurrent: return 0
        case .createNew: return 0
        case .confirmNew: return 1
        case .complete: return 2
        }
    }

    private var stepTitle: String {
        switch step {
        case .verifyCurrent:
            return "Verify Current Pattern"
        case .createNew:
            return "Create New Pattern"
        case .confirmNew:
            return "Confirm Pattern"
        case .complete:
            return "Pattern Changed"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .verifyCurrent:
            return "Enter your current pattern to begin"
        case .createNew:
            return "Draw a new pattern with at least 6 dots"
        case .confirmNew:
            return "Draw the same pattern again to confirm"
        case .complete:
            return "Your vault is now protected by your new pattern"
        }
    }

    private var validationResult: PatternValidationResult? { flow.validationResult }
    private var errorMessage: String? { flow.errorMessage }

    private var isBackupEnabled: Bool {
        UserDefaults.standard.bool(forKey: "iCloudBackupEnabled")
    }

    private var isMaestroHookEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("MAESTRO_CHANGE_PATTERN_TEST")
        #else
        return false
        #endif
    }

    // MARK: - Logic

    private func handlePatternComplete(_ pattern: [Int]) {
        switch step {
        case .verifyCurrent:
            verifyCurrentPattern(pattern)

        case .createNew:
            validateNewPattern(pattern)

        case .confirmNew:
            confirmNewPattern(pattern)

        case .complete:
            break
        }
    }

    private func verifyCurrentPattern(_ pattern: [Int]) {
        guard let currentKey = appState.currentVaultKey else {
            flow.showError("No vault key available")
            patternState.reset()
            return
        }

        // Validate pattern structure first
        let validation = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
        if !validation.isValid {
            flow.showError(validation.errors.first?.message ?? "Invalid pattern")
            patternState.reset()
            return
        }

        guard flow.beginProcessingIfIdle() else { return }

        Task {
            do {
                // Derive key from entered pattern and check if it matches current key
                let enteredKey = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)

                await MainActor.run {
                    if enteredKey == currentKey.rawBytes {
                        // Pattern verified - move to next step
                        changePatternLogger.debug("Current pattern verified")
                        flow.transitionToCreate(currentPattern: pattern)
                        patternState.reset()
                    } else {
                        // Pattern doesn't match
                        changePatternLogger.debug("Current pattern incorrect")
                        flow.showError("Incorrect pattern. Please try again.")
                        patternState.reset()
                    }
                    flow.endProcessing()
                }
            } catch {
                await MainActor.run {
                    flow.showError("Error verifying pattern: \(error.localizedDescription)")
                    patternState.reset()
                    flow.endProcessing()
                }
            }
        }
    }

    private func validateNewPattern(_ pattern: [Int]) {
        guard flow.beginProcessingIfIdle() else { return }

        Task {
            // First, validate the pattern structure
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)

            if result.isValid {
                // Pattern valid — don't show feedback yet (avoids brief flash before transition)
                do {
                    let newKey = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)
                    let hasFiles = await VaultStorage.shared.vaultHasFiles(for: VaultKey(newKey))

                    await MainActor.run {
                        if hasFiles {
                            changePatternLogger.info("Pattern already used by a vault with files")
                            flow.showError("This pattern is already used by another vault. Please choose a different pattern.")
                            patternState.reset()
                        } else {
                            changePatternLogger.debug("New pattern valid and unique")
                            flow.transitionToConfirm(newPattern: pattern)
                            patternState.reset()
                        }
                        flow.endProcessing()
                    }
                } catch {
                    await MainActor.run {
                        flow.showError("Error checking pattern: \(error.localizedDescription)")
                        patternState.reset()
                        flow.endProcessing()
                    }
                }
            } else {
                changePatternLogger.debug("New pattern invalid")
                await MainActor.run {
                    flow.showValidation(result)
                    patternState.reset()
                    flow.endProcessing()
                }
            }
        }
    }

    private func confirmNewPattern(_ pattern: [Int]) {
        let validation = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)

        guard validation.isValid else {
            flow.showError("Invalid pattern. Please try again.")
            patternState.reset()
            return
        }

        // Check if pattern matches the new pattern
        if pattern != flow.newPattern {
            flow.showError("Patterns don't match. Try again.")
            patternState.reset()

            // Auto-clear error after 2.5s
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                await MainActor.run {
                    if flow.errorMessage == "Patterns don't match. Try again." {
                        flow.clearFeedback()
                    }
                }
            }
            return
        }

        // Patterns match — show confirmation
        showSaveConfirmation = true
    }

    private func completePatternChange() {
        guard let currentKey = appState.currentVaultKey,
              !flow.newPattern.isEmpty else {
            return
        }

        guard flow.beginProcessingIfIdle() else { return }

        Task {
            do {
                // Derive new key from new pattern
                let newKey = try await KeyDerivation.deriveKey(from: flow.newPattern, gridSize: patternState.gridSize)

                // Change the vault key
                try await VaultStorage.shared.changeVaultKey(from: currentKey, to: VaultKey(newKey))

                // Update app state with new key and pattern
                await MainActor.run {
                    appState.currentVaultKey = VaultKey(newKey)
                    appState.currentPattern = flow.newPattern
                }

                // Regenerate recovery phrase
                let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                    phrase: newPhrase,
                    pattern: flow.newPattern,
                    gridSize: 5,
                    patternKey: newKey
                )

                await MainActor.run {
                    flow.complete(with: newPhrase)
                }

                // Force iCloud backup with new key so backup matches new pattern
                if UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") {
                    UserDefaults.standard.set(0, forKey: "lastBackupTimestamp")
                    await MainActor.run {
                        iCloudBackupManager.shared.performBackupIfNeeded(with: newKey)
                    }
                    changePatternLogger.info("Triggered iCloud backup after pattern change")
                }

                changePatternLogger.info("Pattern changed successfully")

            } catch {
                changePatternLogger.error("Failed to change pattern: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    flow.showError("Failed to change pattern: \(error.localizedDescription)")
                    flow.endProcessing()
                }
            }
        }
    }
}
