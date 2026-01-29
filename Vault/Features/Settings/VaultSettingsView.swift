import SwiftUI

import SwiftUI

struct VaultSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingChangePattern = false
    @State private var showingRecoveryPhrase = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareVault = false
    @State private var showingRegenerateConfirmation = false
    @State private var isSharedVault = false
    @State private var activeShareCount = 0
    @State private var showingCustomPhraseInput = false
    @State private var showingDuressConfirmation = false
    @State private var isDuressVault = false
    @State private var pendingDuressValue = false
    @State private var fileCount = 0
    @State private var storageUsed: Int64 = 0

    var body: some View {
        List {
            // Vault Info
            Section("This Vault") {
                HStack {
                    Text("Files")
                    Spacer()
                    Text("\(fileCount)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(formatBytes(storageUsed))
                        .foregroundStyle(.secondary)
                }
            }

            // Pattern Management
            Section("Pattern") {
                Button("Change pattern for this vault") {
                    showingChangePattern = true
                }
            }

            // Recovery
            Section("Recovery") {
                Button("View recovery phrase") {
                    showingRecoveryPhrase = true
                }

                Button("Regenerate recovery phrase") {
                    showingRegenerateConfirmation = true
                }
                
                Button("Set custom recovery phrase") {
                    showingCustomPhraseInput = true
                }
            }

            // Sharing
            Section {
                if isSharedVault {
                    HStack {
                        Text("This is a shared vault")
                        Spacer()
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Share This Vault") {
                        showingShareVault = true
                    }
                    if activeShareCount > 0 {
                        HStack {
                            Text("Shared with")
                            Spacer()
                            Text("\(activeShareCount) \(activeShareCount == 1 ? "person" : "people")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Sharing")
            } footer: {
                if isSharedVault {
                    Text("This vault was shared with you. You cannot reshare it.")
                } else {
                    Text("Share this vault with others via a one-time phrase. You can revoke access individually.")
                }
            }

            // Duress
            Section {
                Toggle("Use as duress vault", isOn: $isDuressVault)
            } header: {
                Text("Duress")
            } footer: {
                Text("When this pattern is entered, all OTHER vaults are silently destroyed. This is irreversible and extremely destructive.")
            }

            // App Settings
            Section("App") {
                NavigationLink("App Settings") {
                    AppSettingsView()
                }
            }

            // Danger
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete this vault")
                }
            } footer: {
                Text("Permanently deletes all files in this vault. This cannot be undone.")
            }
        }
        .navigationTitle("Vault Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingChangePattern) {
            ChangePatternView()
        }
        .sheet(isPresented: $showingRecoveryPhrase) {
            RecoveryPhraseView()
        }
        .sheet(isPresented: $showingShareVault) {
            ShareVaultView()
        }
        .sheet(isPresented: $showingCustomPhraseInput) {
            CustomRecoveryPhraseInputView()
        }
        .alert("Delete Vault?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteVault()
            }
        } message: {
            Text("All files in this vault will be permanently deleted. This cannot be undone.")
        }
        .alert("Regenerate Recovery Phrase?", isPresented: $showingRegenerateConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Regenerate", role: .destructive) {
                regenerateRecoveryPhrase()
            }
        } message: {
            Text("Your current recovery phrase will no longer work. Write down the new phrase immediately.")
        }
        .alert("Enable Duress Vault?", isPresented: $showingDuressConfirmation) {
            Button("Cancel", role: .cancel) {
                isDuressVault = !pendingDuressValue
            }
            Button("Enable", role: .destructive) {
                setAsDuressVault()
            }
        } message: {
            Text("⚠️ EXTREMELY DESTRUCTIVE ⚠️\n\nWhen this pattern is entered, ALL OTHER VAULTS will be PERMANENTLY DESTROYED with no warning or confirmation.\n\nThis includes:\n• All files in other vaults\n• All recovery phrases for other vaults\n• No way to undo this action\n\nOnly use this if you understand you may lose important data under duress.\n\nAre you absolutely sure?")
        }
        .onChange(of: isDuressVault) { oldValue, newValue in
            if newValue != oldValue {
                pendingDuressValue = newValue
                if newValue {
                    // Trying to enable - show confirmation
                    showingDuressConfirmation = true
                } else {
                    // Trying to disable - allow without confirmation
                    removeDuressVault()
                }
            }
        }
        .onAppear {
            loadVaultStatistics()
        }
    }

    private func setAsDuressVault() {
        guard let key = appState.currentVaultKey else { return }
        Task {
            try? await DuressHandler.shared.setAsDuressVault(key: key)
        }
    }

    private func removeDuressVault() {
        Task {
            await DuressHandler.shared.clearDuressVault()
        }
    }

    private func deleteVault() {
        guard let key = appState.currentVaultKey else {
            dismiss()
            return
        }

        // Delete all files and the vault index
        do {
            let index = try VaultStorage.shared.loadIndex(with: key)
            for file in index.files where !file.isDeleted {
                try? VaultStorage.shared.deleteFile(id: file.fileId, with: key)
            }

            // Remove any active CloudKit shares
            if let shares = index.activeShares {
                for share in shares {
                    Task {
                        try? await CloudKitSharingManager.shared.deleteSharedVault(shareVaultId: share.id)
                    }
                }
            }

            try VaultStorage.shared.deleteVaultIndex(for: key)
        } catch {
            #if DEBUG
            print("❌ [VaultSettings] Delete vault error: \(error)")
            #endif
        }

        // Clean up recovery data and duress status
        Task {
            try? await RecoveryPhraseManager.shared.deleteRecoveryData(for: key)
            if await DuressHandler.shared.isDuressKey(key) {
                await DuressHandler.shared.clearDuressVault()
            }
        }

        appState.lockVault()
        dismiss()
    }
    
    private func regenerateRecoveryPhrase() {
        guard let key = appState.currentVaultKey else { return }
        Task {
            do {
                let newPhrase = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(for: key)
                #if DEBUG
                print("✅ [VaultSettings] Recovery phrase regenerated: \(newPhrase)")
                #endif
                // Show the new phrase
                await MainActor.run {
                    showingRecoveryPhrase = true
                }
            } catch {
                #if DEBUG
                print("❌ [VaultSettings] Failed to regenerate: \(error)")
                #endif
            }
        }
    }
    
    private func loadVaultStatistics() {
        guard let key = appState.currentVaultKey else { return }
        
        Task {
            do {
                let files = try VaultStorage.shared.listFiles(with: key)
                let totalSize = files.reduce(0) { $0 + Int64($1.size) }
                
                // Check if this is the duress vault
                let isDuress = await DuressHandler.shared.isDuressKey(key)

                // Load sharing info
                let index = try VaultStorage.shared.loadIndex(with: key)
                let shared = index.isSharedVault ?? false
                let shareCount = index.activeShares?.count ?? 0

                await MainActor.run {
                    fileCount = files.count
                    storageUsed = totalSize
                    isDuressVault = isDuress
                    isSharedVault = shared
                    activeShareCount = shareCount
                }
            } catch {
                #if DEBUG
                print("❌ [VaultSettings] Failed to load vault statistics: \(error)")
                #endif
                await MainActor.run {
                    fileCount = 0
                    storageUsed = 0
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Change Pattern

struct ChangePatternView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @StateObject private var patternState = PatternState()
    @State private var step: ChangeStep = .verifyCurrent
    @State private var currentPattern: [Int] = []
    @State private var newPattern: [Int] = []
    @State private var validationResult: PatternValidationResult?
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var newRecoveryPhrase: String = ""

    enum ChangeStep {
        case verifyCurrent
        case createNew
        case confirmNew
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { 
                    dismiss() 
                }
                Spacer()
                Text("Change Pattern")
                    .font(.headline)
                Spacer()
                // Invisible button for spacing
                Button("Cancel") { }
                    .opacity(0)
                    .disabled(true)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

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
                
                // Title and subtitle
                VStack(spacing: 8) {
                    Text(stepTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(stepSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Spacer()

                // Content based on step
                if step == .complete {
                    completeSection
                } else {
                    patternInputSection
                }

                Spacer()

                // Validation feedback
                if let result = validationResult, step == .createNew {
                    validationFeedback(result)
                }

                // Bottom buttons
                bottomButtons
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    
    private var stepIndex: Int {
        switch step {
        case .verifyCurrent: return 0
        case .createNew: return 1
        case .confirmNew, .complete: return 2
        }
    }
    
    private var stepTitle: String {
        switch step {
        case .verifyCurrent: return "Verify Current Pattern"
        case .createNew: return "Create New Pattern"
        case .confirmNew: return "Confirm New Pattern"
        case .complete: return "Pattern Changed!"
        }
    }
    
    private var stepSubtitle: String {
        switch step {
        case .verifyCurrent: return "Enter your current pattern to continue"
        case .createNew: return "Draw your new pattern (at least 6 dots with 2+ direction changes)"
        case .confirmNew: return "Draw the same pattern to confirm"
        case .complete: return "Your pattern has been updated successfully"
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
    
    private var completeSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Pattern Changed Successfully!")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text("A new recovery phrase has been generated for your vault.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            
            // Recovery phrase display
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.blue)
                    Text("Your New Recovery Phrase")
                        .font(.headline)
                }
                
                Text(newRecoveryPhrase)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Write this down immediately. You'll need it to recover your vault if you forget your pattern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    @ViewBuilder
    private func validationFeedback(_ result: PatternValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Errors
            ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error.message)
                        .font(.caption)
                }
            }

            // Warnings (only if no errors)
            if result.errors.isEmpty {
                ForEach(Array(result.warnings.prefix(2).enumerated()), id: \.offset) { _, warning in
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
            case .verifyCurrent, .createNew:
                Button("Clear") {
                    patternState.reset()
                    errorMessage = nil
                }
                .disabled(patternState.selectedNodes.isEmpty || isProcessing)
                
                if step == .createNew {
                    Button("Start Over") {
                        step = .verifyCurrent
                        currentPattern = []
                        newPattern = []
                        patternState.reset()
                        validationResult = nil
                        errorMessage = nil
                    }
                    .disabled(isProcessing)
                }
                
            case .confirmNew:
                Button("Start Over") {
                    step = .verifyCurrent
                    currentPattern = []
                    newPattern = []
                    patternState.reset()
                    validationResult = nil
                    errorMessage = nil
                }
                .disabled(isProcessing)

            case .complete:
                Button(action: { dismiss() }) {
                    Text("Done")
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
        #if DEBUG
        print("🔄 [ChangePattern] Pattern completed in \(step) step")
        #endif
        
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
            errorMessage = "No vault key available"
            patternState.reset()
            return
        }
        
        isProcessing = true
        
        Task {
            do {
                // Derive key from entered pattern and check if it matches current key
                let enteredKey = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)
                
                await MainActor.run {
                    if enteredKey == currentKey {
                        // Pattern verified - move to next step
                        #if DEBUG
                        print("✅ [ChangePattern] Current pattern verified")
                        #endif
                        currentPattern = pattern
                        step = .createNew
                        patternState.reset()
                        errorMessage = nil
                    } else {
                        // Pattern doesn't match
                        #if DEBUG
                        print("❌ [ChangePattern] Current pattern incorrect")
                        #endif
                        errorMessage = "Incorrect pattern. Please try again."
                        patternState.reset()
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error verifying pattern: \(error.localizedDescription)"
                    patternState.reset()
                    isProcessing = false
                }
            }
        }
    }
    
    private func validateNewPattern(_ pattern: [Int]) {
        isProcessing = true
        
        Task {
            // First, validate the pattern structure
            let result = PatternValidator.shared.validate(pattern, gridSize: patternState.gridSize)
            
            await MainActor.run {
                validationResult = result
            }
            
            if result.isValid {
                // Check if this pattern already exists as another vault
                do {
                    let newKey = try await KeyDerivation.deriveKey(from: pattern, gridSize: patternState.gridSize)
                    
                    // Check if a vault with this key already exists
                    let vaultExists = VaultStorage.shared.vaultExists(for: newKey)
                    
                    await MainActor.run {
                        if vaultExists {
                            #if DEBUG
                            print("❌ [ChangePattern] Pattern already used by another vault")
                            #endif
                            errorMessage = "This pattern is already used by another vault. Please choose a different pattern."
                            patternState.reset()
                        } else {
                            #if DEBUG
                            print("✅ [ChangePattern] New pattern valid and unique")
                            #endif
                            newPattern = pattern
                            step = .confirmNew
                            patternState.reset()
                            errorMessage = nil
                        }
                        isProcessing = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Error checking pattern: \(error.localizedDescription)"
                        patternState.reset()
                        isProcessing = false
                    }
                }
            } else {
                #if DEBUG
                print("❌ [ChangePattern] New pattern invalid")
                #endif
                await MainActor.run {
                    patternState.reset()
                    isProcessing = false
                }
            }
        }
    }
    
    private func confirmNewPattern(_ pattern: [Int]) {
        if pattern == newPattern {
            #if DEBUG
            print("✅ [ChangePattern] Patterns match - updating vault")
            #endif
            updateVaultPattern(pattern)
        } else {
            #if DEBUG
            print("❌ [ChangePattern] Patterns don't match")
            #endif
            errorMessage = "Patterns don't match. Please try again."
            patternState.reset()
        }
    }
    
    private func updateVaultPattern(_ newPattern: [Int]) {
        guard let oldKey = appState.currentVaultKey else {
            errorMessage = "No vault key available"
            return
        }
        
        isProcessing = true
        
        Task {
            do {
                // 1. Derive new key from new pattern
                let newKey = try await KeyDerivation.deriveKey(from: newPattern, gridSize: patternState.gridSize)
                
                #if DEBUG
                print("🔑 [ChangePattern] New key derived")
                #endif
                
                // 2. Change vault key (instant operation - only re-encrypts master key)
                try VaultStorage.shared.changeVaultKey(from: oldKey, to: newKey)
                
                #if DEBUG
                print("✅ [ChangePattern] Vault key changed instantly!")
                #endif
                
                // 3. Generate a new recovery phrase
                let recoveryPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                
                #if DEBUG
                print("📝 [ChangePattern] New recovery phrase generated: \(recoveryPhrase)")
                #endif
                
                // 4. Save the new recovery phrase with the new key
                try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                    phrase: recoveryPhrase,
                    pattern: newPattern,
                    gridSize: patternState.gridSize,
                    patternKey: newKey
                )
                
                #if DEBUG
                print("💾 [ChangePattern] Recovery phrase saved with new key")
                #endif
                
                // 5. Delete old recovery data
                try await RecoveryPhraseManager.shared.deleteRecoveryData(for: oldKey)
                
                #if DEBUG
                print("🗑️ [ChangePattern] Old recovery data deleted")
                #endif
                
                // 6. Update app state with new key
                await MainActor.run {
                    appState.currentVaultKey = newKey
                    newRecoveryPhrase = recoveryPhrase
                    step = .complete
                    isProcessing = false
                    errorMessage = nil
                    
                    #if DEBUG
                    print("✅ [ChangePattern] Pattern change complete! New recovery phrase shown to user.")
                    #endif
                }
            } catch {
                #if DEBUG
                print("❌ [ChangePattern] Error updating pattern: \(error)")
                #endif
                await MainActor.run {
                    errorMessage = "Failed to update pattern: \(error.localizedDescription)"
                    patternState.reset()
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Custom Recovery Phrase Input

struct CustomRecoveryPhraseInputView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var customPhrase = ""
    @State private var validation: RecoveryPhraseGenerator.PhraseValidation?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Custom Recovery Phrase")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()
            
            if showSuccess {
                successView
            } else {
                inputView
            }
        }
    }
    
    private var inputView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Set Your Custom Phrase")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter a memorable sentence that you'll use to recover this vault. It should be unique and difficult to guess.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            // Phrase input
            TextEditor(text: $customPhrase)
                .frame(height: 120)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .onChange(of: customPhrase) { _, newValue in
                    validatePhrase(newValue)
                }
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
                .background(validation.isAcceptable ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
            
            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Guidelines
            VStack(alignment: .leading, spacing: 12) {
                Label("Use at least 6-9 words", systemImage: "text.word.spacing")
                Label("Mix common and uncommon words", systemImage: "shuffle")
                Label("Make it memorable but unique", systemImage: "brain.head.profile")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            // Save button
            Button(action: saveCustomPhrase) {
                if isProcessing {
                    ProgressView()
                } else {
                    Text("Set Custom Phrase")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!(validation?.isAcceptable ?? false) || isProcessing)
            .padding()
        }
        .padding(.vertical)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
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
                _ = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(
                    for: key,
                    customPhrase: customPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
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

#Preview {
    VaultSettingsView()
        .environmentObject(AppState())
}
