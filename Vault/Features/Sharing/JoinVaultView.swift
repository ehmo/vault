import SwiftUI
import CloudKit

struct JoinVaultView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var mode: ViewMode = .input
    @State private var iCloudStatus: CKAccountStatus?
    @State private var downloadedData: Data?
    @State private var downloadedPolicy: VaultStorage.SharePolicy?
    @State private var downloadedShareVaultId: String?

    // Pattern setup for shared vault
    @StateObject private var patternState = PatternState()
    @State private var newPattern: [Int] = []
    @State private var confirmPattern: [Int] = []
    @State private var patternStep: PatternStep = .create

    enum ViewMode {
        case input
        case downloading(Int, Int)
        case patternSetup
        case importing
        case success(Int)
        case backgroundImportStarted
        case error(String)
    }

    enum PatternStep {
        case create
        case confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Join Shared Vault")
                    .font(.headline)
                Spacer()
                Button("Cancel") { }.opacity(0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    if let status = iCloudStatus, status != .available && status != .temporarilyUnavailable {
                        iCloudUnavailableView(status)
                    } else {
                        switch mode {
                        case .input:
                            inputView
                        case .downloading(let current, let total):
                            downloadingView(current: current, total: total)
                        case .patternSetup:
                            patternSetupView
                        case .importing:
                            importingView
                        case .success(let fileCount):
                            successView(fileCount)
                        case .backgroundImportStarted:
                            backgroundImportStartedView
                        case .error(let message):
                            errorView(message)
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            let status = await CloudKitSharingManager.shared.checkiCloudStatus()
            iCloudStatus = status
        }
    }

    // MARK: - Views

    private var inputView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Enter Share Phrase")
                .font(.title2).fontWeight(.semibold)

            Text("Enter the one-time share phrase you received.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $phrase)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: { Task { await joinVault() } }) {
                Text("Join Vault")
            }
            .buttonStyle(.borderedProminent)
            .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Label("How it works", systemImage: "info.circle")
                    .font(.headline)
                Text("The share phrase downloads and decrypts the shared vault. Each phrase can only be used once.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func downloadingView(current: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(current), total: Double(total))
            Text("Downloading vault... (\(current) of \(total) chunks)")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 100)
    }

    private var patternSetupView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(patternStep == .create ? "Set a Pattern" : "Confirm Pattern")
                    .font(.title2).fontWeight(.semibold)

                Text(patternStep == .create
                    ? "Draw a pattern to unlock this shared vault"
                    : "Draw the same pattern to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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

            if patternStep == .confirm {
                Button("Start Over") {
                    patternStep = .create
                    newPattern = []
                    confirmPattern = []
                    patternState.reset()
                }
                .font(.subheadline)
            }
        }
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Setting up shared vault...")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 100)
    }

    private var backgroundImportStartedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Setting Up Vault")
                .font(.title2).fontWeight(.semibold)

            Text("Your shared vault is being set up in the background. You'll be notified when it's ready.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding(.top, 40)
    }

    private func successView(_ fileCount: Int) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Vault Joined!")
                .font(.title2).fontWeight(.semibold)

            Text("You now have access to the shared vault with \(fileCount) files.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let policy = downloadedPolicy {
                policyInfoView(policy)
            }

            Button("Open Vault") {
                appState.isUnlocked = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(.top, 40)
    }

    private func policyInfoView(_ policy: VaultStorage.SharePolicy) -> some View {
        VStack(spacing: 8) {
            if let expires = policy.expiresAt {
                HStack {
                    Image(systemName: "clock")
                    Text("Expires: \(expires, style: .date)")
                    Spacer()
                }
            }
            if let maxOpens = policy.maxOpens {
                HStack {
                    Image(systemName: "eye")
                    Text("Max opens: \(maxOpens)")
                    Spacer()
                }
            }
            if !policy.allowScreenshots {
                HStack {
                    Image(systemName: "camera.metering.none")
                    Text("Screenshots blocked")
                    Spacer()
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("Could Not Join")
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Try Again") { mode = .input }
                    .buttonStyle(.bordered)
                Button("Edit Phrase") { mode = .input }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding(.top, 60)
    }

    private func iCloudUnavailableView(_ status: CKAccountStatus) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("iCloud Required")
                .font(.title2).fontWeight(.semibold)
            Text(iCloudStatusMessage(status))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func joinVault() async {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else { return }

        mode = .downloading(0, 1)

        do {
            let result = try await CloudKitSharingManager.shared.downloadSharedVault(
                phrase: trimmedPhrase,
                onProgress: { current, total in
                    Task { @MainActor in
                        mode = .downloading(current, total)
                    }
                }
            )

            downloadedData = result.data
            downloadedPolicy = result.policy
            downloadedShareVaultId = result.shareVaultId

            mode = .patternSetup
        } catch let error as CloudKitSharingError {
            mode = .error(error.errorDescription ?? error.localizedDescription)
        } catch {
            mode = .error(error.localizedDescription)
        }
    }

    private func handlePatternComplete(_ pattern: [Int]) {
        guard pattern.count >= 6 else {
            patternState.reset()
            return
        }

        switch patternStep {
        case .create:
            newPattern = pattern
            patternStep = .confirm
            patternState.reset()

        case .confirm:
            if pattern == newPattern {
                confirmPattern = pattern
                patternState.reset()
                Task { await setupSharedVault() }
            } else {
                // Patterns don't match
                patternState.reset()
                patternStep = .create
                newPattern = []
            }
        }
    }

    private func setupSharedVault() async {
        guard let vaultData = downloadedData,
              let policy = downloadedPolicy,
              let shareVaultId = downloadedShareVaultId else {
            mode = .error("Missing vault data")
            return
        }

        do {
            // Derive key from the pattern
            let patternKey = try await KeyDerivation.deriveKey(from: newPattern, gridSize: 5)

            // Set app state so user can navigate the app while import runs
            appState.currentVaultKey = patternKey
            appState.currentPattern = newPattern

            // Start background import
            BackgroundShareTransferManager.shared.startBackgroundImport(
                downloadedData: vaultData,
                downloadedPolicy: policy,
                shareVaultId: shareVaultId,
                phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines),
                patternKey: patternKey,
                pattern: newPattern
            )

            mode = .backgroundImportStarted
        } catch {
            mode = .error("Failed to set up vault: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func iCloudStatusMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "iCloud is available"
        case .noAccount: return "Please sign in to iCloud in Settings"
        case .restricted: return "iCloud access is restricted"
        case .couldNotDetermine: return "Could not determine iCloud status"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        @unknown default: return "iCloud is not available"
        }
    }
}

#Preview {
    JoinVaultView()
        .environmentObject(AppState())
}
