import SwiftUI

struct PatternSetupView: View {
    let onComplete: () -> Void

    @StateObject private var patternState = PatternState()
    @State private var step: SetupStep = .create
    @State private var firstPattern: [Int] = []
    @State private var validationResult: PatternValidationResult?
    @State private var showRecoveryOption = false
    @State private var generatedPhrase = ""

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
                        .fill(stepIndex >= index ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 40, height: 4)
                }
            }
            .padding(.top)

            // Header
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Spacer()

            // Content based on step
            switch step {
            case .create, .confirm:
                patternInputSection
            case .recovery:
                recoverySection
            case .complete:
                completeSection
            }

            Spacer()

            // Validation feedback
            if let result = validationResult, step == .create {
                validationFeedback(result)
            }

            // Bottom buttons
            bottomButtons
        }
        .padding()
        .onChange(of: step) { _, newStep in
            if newStep == .recovery {
                generatedPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
            }
        }
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
        case .create: return "Connect at least 6 dots with 2+ direction changes"
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
            randomizeGrid: .constant(false),
            onPatternComplete: handlePatternComplete
        )
        .frame(width: 280, height: 280)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.3))
        )
        .padding()
    }

    private var recoverySection: some View {
        VStack(spacing: 20) {
            Text(generatedPhrase)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 12) {
                Label("Write this down", systemImage: "pencil")
                Label("Store it somewhere safe", systemImage: "lock")
                Label("Never share it with anyone", systemImage: "person.slash")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
            ForEach(result.errors, id: \.rawValue) { error in
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error.rawValue)
                        .font(.caption)
                }
            }

            // Warnings (only if no errors)
            if result.errors.isEmpty {
                ForEach(result.warnings.prefix(2), id: \.rawValue) { warning in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
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
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Button(action: { step = .complete }) {
                    Text("I've Saved It")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Button("Skip for Now") {
                    step = .complete
                }
                .font(.subheadline)

            case .complete:
                Button(action: onComplete) {
                    Text("Open Vault")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func handlePatternComplete(_ pattern: [Int]) {
        switch step {
        case .create:
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
            validationResult = result

            if result.isValid {
                firstPattern = pattern
                step = .confirm
                patternState.reset()
            } else {
                patternState.reset()
            }

        case .confirm:
            if pattern == firstPattern {
                // Patterns match - save and continue
                savePattern(pattern)
                step = .recovery
            } else {
                // Patterns don't match - show error and reset
                patternState.reset()
            }

        default:
            break
        }
    }

    private func savePattern(_ pattern: [Int]) {
        Task {
            do {
                // Derive key from pattern with the current grid size
                let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)

                // Initialize empty vault index for this key
                let emptyIndex = VaultStorage.VaultIndex(
                    files: [],
                    nextOffset: 0,
                    totalSize: 500 * 1024 * 1024
                )
                try VaultStorage.shared.saveIndex(emptyIndex, with: key)
            } catch {
                // Handle error silently - vault will be created on first use
            }
        }
    }
}

#Preview {
    PatternSetupView(onComplete: {})
}
