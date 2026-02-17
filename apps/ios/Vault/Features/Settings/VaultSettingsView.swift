import SwiftUI
import os.log

private let vaultSettingsLogger = Logger(subsystem: "app.vaultaire.ios", category: "VaultSettings")

struct VaultSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var showingChangePattern = false
    @State private var showingRegeneratedPhrase = false
    @State private var regenerateErrorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingShareVault = false
    @State private var showingRegenerateConfirmation = false
    @State private var isSharedVault = false
    @State private var activeShareCount = 0
    @State private var showingCustomPhraseInput = false
    @State private var showingDuressConfirmation = false
    @State private var isDuressVault = false
    @State private var pendingDuressValue = false
    @State private var activeUploadCount = 0
    @State private var fileCount = 0
    @State private var storageUsed: Int64 = 0
    @State private var showingPaywall = false

    var body: some View {
        List {
            // Vault Info
            Section("This Vault") {
                HStack {
                    Text("Files")
                    Spacer()
                    Text("\(fileCount)")
                        .foregroundStyle(.vaultSecondaryText)
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(formatBytes(storageUsed))
                        .foregroundStyle(.vaultSecondaryText)
                }
            }

            // Pattern Management
            Section("Pattern") {
                Button("Change pattern for this vault") {
                    showingChangePattern = true
                }
                .accessibilityIdentifier("settings_change_pattern")
            }

            // Recovery
            Section("Recovery") {
                Button("Regenerate recovery phrase") {
                    showingRegenerateConfirmation = true
                }
                .accessibilityIdentifier("settings_regen_phrase")

                Button("Set custom recovery phrase") {
                    showingCustomPhraseInput = true
                }
                .accessibilityIdentifier("settings_custom_phrase")
            }

            // Sharing
            Section {
                if isSharedVault {
                    HStack {
                        Text("This is a shared vault")
                        Spacer()
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.vaultSecondaryText)
                    }
                } else {
                    Button("Share This Vault") {
                        if subscriptionManager.canCreateSharedVault() {
                            showingShareVault = true
                        } else {
                            showingPaywall = true
                        }
                    }
                    .accessibilityIdentifier("settings_share_vault")
                    if activeShareCount > 0 {
                        HStack {
                            Text("Shared with")
                            Spacer()
                            Text("\(activeShareCount) \(activeShareCount == 1 ? "person" : "people")")
                                .foregroundStyle(.vaultSecondaryText)
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
                if Self.shouldDisableDuressForSharing(
                    isSharedVault: isSharedVault,
                    activeShareCount: activeShareCount,
                    activeUploadCount: activeUploadCount
                ) {
                    Text("Vaults with active sharing cannot be set as duress vaults")
                        .foregroundStyle(.vaultSecondaryText)
                } else if !subscriptionManager.canCreateDuressVault() {
                    Button("Use as duress vault") {
                        showingPaywall = true
                    }
                    .foregroundStyle(.primary)
                } else {
                    Toggle("Use as duress vault", isOn: $isDuressVault)
                        .accessibilityIdentifier("settings_duress_toggle")
                }

                DisclosureGroup {
                    Text("When you enter this pattern while under duress, your real vaults are silently destroyed. The person watching sees normal-looking content and has no way to know your real data ever existed.")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                } label: {
                    Text("What is this?")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                }
            } header: {
                Text("Duress")
            }

            // App Settings
            Section("App") {
                NavigationLink("App Settings") {
                    AppSettingsView()
                }
                .accessibilityIdentifier("settings_app_settings")
            }

            // Danger
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete this vault")
                }
                .accessibilityIdentifier("settings_delete_vault")
            } footer: {
                Text("Permanently deletes all files in this vault. This cannot be undone.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationTitle("Vault Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("vault_settings_done")
            }
        }
        .fullScreenCover(isPresented: $showingChangePattern) {
            ChangePatternView()
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showingRegeneratedPhrase) {
            RecoveryPhraseView()
        }
        .fullScreenCover(isPresented: $showingShareVault) {
            ShareVaultView()
        }
        .fullScreenCover(isPresented: $showingCustomPhraseInput) {
            CustomRecoveryPhraseInputView()
                .interactiveDismissDisabled()
        }
        .ignoresSafeArea(.keyboard)
        .alert("Delete Vault?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { /* No-op */ }
            Button("Delete", role: .destructive) {
                deleteVault()
            }
        } message: {
            Text("All files in this vault will be permanently deleted. This cannot be undone.")
        }
        .alert("Regenerate Recovery Phrase?", isPresented: $showingRegenerateConfirmation) {
            Button("Cancel", role: .cancel) { /* No-op */ }
            Button("Regenerate", role: .destructive) {
                regenerateRecoveryPhrase()
            }
        } message: {
            Text("Your current recovery phrase will no longer work. Write down the new phrase immediately.")
        }
        .alert("Error", isPresented: Binding(
            get: { regenerateErrorMessage != nil },
            set: { if !$0 { regenerateErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { regenerateErrorMessage = nil }
        } message: {
            Text(regenerateErrorMessage ?? "An unexpected error occurred.")
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
            let duressDisabledBySharing = Self.shouldDisableDuressForSharing(
                isSharedVault: isSharedVault,
                activeShareCount: activeShareCount,
                activeUploadCount: activeUploadCount
            )
            guard !duressDisabledBySharing else {
                isDuressVault = oldValue
                return
            }
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
        .task {
            loadVaultStatistics()
        }
        .onChange(of: showingShareVault) { _, isShowing in
            if !isShowing { loadVaultStatistics() }
        }
        .premiumPaywall(isPresented: $showingPaywall)
    }

    private func setAsDuressVault() {
        guard let key = appState.currentVaultKey else { return }
        EmbraceManager.shared.addBreadcrumb(category: "settings.duressToggled")
        Task {
            do {
                try await DuressHandler.shared.setAsDuressVault(key: key)
            } catch {
                EmbraceManager.shared.captureError(error)
            }
        }
    }

    private func removeDuressVault() {
        EmbraceManager.shared.addBreadcrumb(category: "settings.duressToggled")
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
            vaultSettingsLogger.error("Delete vault error: \(error.localizedDescription, privacy: .public)")
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
        EmbraceManager.shared.addBreadcrumb(category: "settings.phraseRegenerated")
        Task {
            do {
                do {
                    _ = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(for: key)
                } catch RecoveryError.vaultNotFound {
                    // No existing recovery data — create fresh entry
                    vaultSettingsLogger.info("No recovery data found, creating new recovery phrase")
                    let newPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                    try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                        phrase: newPhrase,
                        pattern: appState.currentPattern ?? [],
                        gridSize: 5,
                        patternKey: key
                    )
                }
                vaultSettingsLogger.debug("Recovery phrase regenerated")
                await MainActor.run {
                    showingRegeneratedPhrase = true
                }
            } catch {
                vaultSettingsLogger.error("Failed to regenerate phrase: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    regenerateErrorMessage = "Failed to regenerate recovery phrase. Please try again."
                }
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
                let ownerFingerprint = KeyDerivation.keyFingerprint(from: key)
                let duressInitiallyEnabled = await DuressHandler.shared.isDuressKey(key)

                // Load sharing info
                let index = try VaultStorage.shared.loadIndex(with: key)
                let shared = index.isSharedVault ?? false
                let shareCount = index.activeShares?.count ?? 0
                let activeUploadJobs = await MainActor.run {
                    ShareUploadManager.shared.jobs(forOwnerFingerprint: ownerFingerprint)
                        .filter { $0.canTerminate }
                }
                let uploadCount = activeUploadJobs.count
                let sharingDisablesDuress = Self.shouldDisableDuressForSharing(
                    isSharedVault: shared,
                    activeShareCount: shareCount,
                    activeUploadCount: uploadCount
                )
                if duressInitiallyEnabled && sharingDisablesDuress {
                    await DuressHandler.shared.clearDuressVault()
                    vaultSettingsLogger.info("Cleared duress because this vault has active sharing")
                }
                let isDuress = duressInitiallyEnabled && !sharingDisablesDuress

                await MainActor.run {
                    fileCount = files.count
                    storageUsed = totalSize
                    isDuressVault = isDuress
                    isSharedVault = shared
                    activeShareCount = shareCount
                    activeUploadCount = uploadCount
                }
            } catch {
                vaultSettingsLogger.error("Failed to load vault statistics: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    fileCount = 0
                    storageUsed = 0
                    activeUploadCount = 0
                }
            }
        }
    }

    static func shouldDisableDuressForSharing(
        isSharedVault: Bool,
        activeShareCount: Int,
        activeUploadCount: Int
    ) -> Bool {
        isSharedVault || activeShareCount > 0 || activeUploadCount > 0
    }
    
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        Self.byteCountFormatter.string(fromByteCount: bytes)
    }
}

// MARK: - Change Pattern

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if step != .complete {
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
                }

                if isMaestroHookEnabled {
                    maestroChangePatternTestHooks
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
                            .frame(height: 44, alignment: .top)
                    }
                    .padding(.horizontal)
                }

                // Content based on step
                switch step {
                case .verifyCurrent, .createNew, .confirmNew:
                    Spacer()
                    patternInputSection
                    Spacer()

                    // Validation feedback — fixed height to prevent layout shift
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
        }
    }
    
    // MARK: - Computed Properties

    private var step: ChangePatternStep {
        get { flow.step }
        nonmutating set { flow.step = newValue }
    }

    private var currentPattern: [Int] {
        get { flow.currentPattern }
        nonmutating set { flow.currentPattern = newValue }
    }

    private var newPattern: [Int] {
        get { flow.newPattern }
        nonmutating set { flow.newPattern = newValue }
    }

    private var validationResult: PatternValidationResult? {
        get { flow.validationResult }
        nonmutating set { flow.validationResult = newValue }
    }

    private var errorMessage: String? {
        get { flow.errorMessage }
        nonmutating set { flow.errorMessage = newValue }
    }

    private var isProcessing: Bool {
        get { flow.isProcessing }
        nonmutating set { flow.isProcessing = newValue }
    }

    private var newRecoveryPhrase: String {
        get { flow.newRecoveryPhrase }
        nonmutating set { flow.newRecoveryPhrase = newValue }
    }
    
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
            onPatternComplete: handlePatternComplete
        )
        .frame(width: 280, height: 280)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1)
    }

    private var isMaestroHookEnabled: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        ProcessInfo.processInfo.environment["MAESTRO_TEST"] == "true" ||
        ProcessInfo.processInfo.arguments.contains("-MAESTRO_TEST") ||
        ProcessInfo.processInfo.arguments.contains("MAESTRO_TEST")
        #endif
    }

    @ViewBuilder
    private var maestroChangePatternTestHooks: some View {
        switch step {
        case .verifyCurrent:
            Button("TEST: Skip Verify") {
                flow.skipVerifyForTesting(pattern: [0, 1, 2, 3, 4, 5])
                patternState.reset()
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("change_pattern_test_skip_verify")

        case .createNew:
            HStack(spacing: 8) {
                Button("TEST: Validation Error") {
                    let simulatedInvalid = PatternValidator.shared.validate([0, 1], gridSize: patternState.gridSize)
                    flow.showValidation(simulatedInvalid)
                    patternState.reset()
                    flow.endProcessing()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("change_pattern_test_set_validation_error")

                Button("TEST: Reused Error") {
                    flow.showError("This pattern is already used by another vault. Please choose a different pattern.")
                    patternState.reset()
                    flow.endProcessing()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("change_pattern_test_set_reused_error")
            }

        default:
            EmptyView()
        }
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
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            
            // Recovery phrase display
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.tint)
                    Text("Your New Recovery Phrase")
                        .font(.headline)
                }

                PhraseDisplayCard(phrase: newRecoveryPhrase)
                
                PhraseActionButtons(phrase: newRecoveryPhrase)
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 12) {
                Label("Write this down", systemImage: "pencil")
                Label("Store it somewhere safe", systemImage: "lock")
                Label("Never share it with anyone", systemImage: "person.slash")
            }
            .font(.subheadline)
            .foregroundStyle(.vaultSecondaryText)
        }
    }


    private var bottomButtons: some View {
        // Fixed height so grid position stays consistent across steps
        VStack(spacing: 12) {
            switch step {
            case .verifyCurrent:
                Button("Clear") {
                    patternState.reset()
                    flow.clearFeedback()
                }
                .disabled(patternState.selectedNodes.isEmpty || isProcessing)

                Button("Start Over") {
                    flow.resetForStartOver()
                    patternState.reset()
                }
                .hidden()

            case .createNew:
                Button("Clear") {
                    patternState.reset()
                    flow.clearFeedback()
                }
                .disabled(patternState.selectedNodes.isEmpty || isProcessing)

                Button("Start Over") {
                    flow.resetForStartOver()
                    patternState.reset()
                }
                .disabled(isProcessing)

            case .confirmNew:
                Button("Clear") {
                    patternState.reset()
                    flow.clearFeedback()
                }
                .hidden()

                Button("Start Over") {
                    flow.resetForStartOver()
                    patternState.reset()
                }
                .disabled(isProcessing)

            case .complete:
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
        }
    }

    // MARK: - Actions

    private func handlePatternComplete(_ pattern: [Int]) {
        vaultSettingsLogger.debug("Pattern completed in \(String(describing: step), privacy: .public) step")

        guard !isProcessing else {
            vaultSettingsLogger.debug("Ignoring pattern input while processing")
            return
        }
        
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
                    if enteredKey == currentKey {
                        // Pattern verified - move to next step
                        vaultSettingsLogger.debug("Current pattern verified")
                        flow.transitionToCreate(currentPattern: pattern)
                        patternState.reset()
                    } else {
                        // Pattern doesn't match
                        vaultSettingsLogger.debug("Current pattern incorrect")
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
                    let hasFiles = VaultStorage.shared.vaultHasFiles(for: newKey)

                    await MainActor.run {
                        if hasFiles {
                            vaultSettingsLogger.info("Pattern already used by a vault with files")
                            flow.showError("This pattern is already used by another vault. Please choose a different pattern.")
                            patternState.reset()
                        } else {
                            vaultSettingsLogger.debug("New pattern valid and unique")
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
                vaultSettingsLogger.debug("New pattern invalid")
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
        if !validation.isValid {
            flow.showError(validation.errors.first?.message ?? "Invalid pattern")
            patternState.reset()
            return
        }

        if pattern == newPattern {
            vaultSettingsLogger.debug("Patterns match, updating vault")
            updateVaultPattern(pattern)
        } else {
            vaultSettingsLogger.debug("Patterns don't match")
            flow.showError("Patterns don't match. Please try again.")
            patternState.reset()
        }
    }
    
    private func updateVaultPattern(_ newPattern: [Int]) {
        guard let oldKey = appState.currentVaultKey else {
            flow.showError("No vault key available")
            return
        }
        
        guard flow.beginProcessingIfIdle() else { return }
        
        Task {
            do {
                // 1. Derive new key from new pattern
                let newKey = try await KeyDerivation.deriveKey(from: newPattern, gridSize: patternState.gridSize)
                
                vaultSettingsLogger.trace("New key derived")
                
                // 2. Change vault key (instant operation - only re-encrypts master key)
                try VaultStorage.shared.changeVaultKey(from: oldKey, to: newKey)
                
                vaultSettingsLogger.debug("Vault key changed")
                
                // 3. Generate a new recovery phrase
                let recoveryPhrase = RecoveryPhraseGenerator.shared.generatePhrase()
                
                vaultSettingsLogger.trace("New recovery phrase generated")
                
                // 4. Save the new recovery phrase with the new key
                try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
                    phrase: recoveryPhrase,
                    pattern: newPattern,
                    gridSize: patternState.gridSize,
                    patternKey: newKey
                )
                
                vaultSettingsLogger.debug("Recovery phrase saved with new key")
                
                // 5. Delete old recovery data
                try await RecoveryPhraseManager.shared.deleteRecoveryData(for: oldKey)
                
                vaultSettingsLogger.debug("Old recovery data deleted")
                
                EmbraceManager.shared.addBreadcrumb(category: "settings.patternChanged")

                // 6. Update app state with new key
                await MainActor.run {
                    appState.currentVaultKey = newKey
                    flow.complete(with: recoveryPhrase)

                    vaultSettingsLogger.info("Pattern change complete")
                }
            } catch {
                vaultSettingsLogger.error("Error updating pattern: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    flow.showError("Failed to update pattern: \(error.localizedDescription)")
                    patternState.reset()
                    flow.endProcessing()
                }
            }
        }
    }
}

// MARK: - Custom Recovery Phrase Input

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
                Button("Cancel", role: .cancel) { /* No-op */ }
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
                        for: key,
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
                        patternKey: key
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

#Preview {
    VaultSettingsView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
