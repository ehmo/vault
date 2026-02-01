import SwiftUI
import CloudKit

struct ShareVaultView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ViewMode = .loading

    enum ViewMode {
        case loading
        case iCloudUnavailable(CKAccountStatus)
        case newShare
        case phraseReady(String)
        case backgroundUploadStarted(String) // phrase
        case manageShares
        case error(String)
    }

    // New share settings
    @State private var expiresAt: Date?
    @State private var hasExpiration = false
    @State private var maxOpens: Int?
    @State private var hasMaxOpens = false
    @State private var allowDownloads = true
    @State private var copiedToClipboard = false
    @State private var isStopping = false

    // Active shares data
    @State private var activeShares: [VaultStorage.ShareRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Share Vault")
                    .font(.headline)
                Spacer()
                Button("Cancel") { }.opacity(0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    switch mode {
                    case .loading:
                        loadingView
                    case .iCloudUnavailable(let status):
                        iCloudUnavailableView(status)
                    case .newShare:
                        newShareSettingsView
                    case .phraseReady(let phrase):
                        phraseReadyView(phrase)
                    case .backgroundUploadStarted(let phrase):
                        backgroundUploadStartedView(phrase)
                    case .manageShares:
                        manageSharesView
                    case .error(let message):
                        errorView(message)
                    }
                }
                .padding()
            }
        }
        .task {
            await initialize()
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        let status = await CloudKitSharingManager.shared.checkiCloudStatus()
        guard status == .available || status == .temporarilyUnavailable else {
            mode = .iCloudUnavailable(status)
            return
        }

        // Check if vault already has active shares
        guard let key = appState.currentVaultKey else {
            mode = .error("No vault key available")
            return
        }

        do {
            let index = try VaultStorage.shared.loadIndex(with: key)
            if let shares = index.activeShares, !shares.isEmpty {
                activeShares = shares
                mode = .manageShares
            } else {
                mode = .newShare
            }
        } catch {
            mode = .error(error.localizedDescription)
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            PixelAnimation.loading(size: 60)
            Text("Checking sharing status...")
                .foregroundStyle(.vaultSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func iCloudUnavailableView(_ status: CKAccountStatus) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(.vaultSecondaryText)
            Text("iCloud Required")
                .font(.title2).fontWeight(.semibold)
            Text(iCloudStatusMessage(status))
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var newShareSettingsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Share This Vault")
                .font(.title2).fontWeight(.semibold)

            Text("Generate a one-time share phrase. After your recipient uses it, it cannot be reused.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            // Policy settings
            VStack(spacing: 16) {
                // Expiration
                Toggle("Set expiration date", isOn: $hasExpiration)
                if hasExpiration {
                    DatePicker("Expires", selection: Binding(
                        get: { expiresAt ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())! },
                        set: { expiresAt = $0 }
                    ), in: Date()..., displayedComponents: .date)
                }

                Divider()

                // Max opens
                Toggle("Limit number of opens", isOn: $hasMaxOpens)
                if hasMaxOpens {
                    Stepper("Max opens: \(maxOpens ?? 10)", value: Binding(
                        get: { maxOpens ?? 10 },
                        set: { maxOpens = $0 }
                    ), in: 1...1000)
                }

                Divider()

                // Allow downloads
                Toggle("Allow file exports", isOn: $allowDownloads)
            }
            .padding()
            .background(Color.vaultSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Estimated size
            if let key = appState.currentVaultKey,
               let files = try? VaultStorage.shared.listFiles(with: key) {
                let totalSize = files.reduce(0) { $0 + $1.size }
                HStack {
                    Text("Estimated upload")
                        .foregroundStyle(.vaultSecondaryText)
                    Spacer()
                    Text(formatBytes(totalSize))
                        .foregroundStyle(.vaultSecondaryText)
                }
                .font(.subheadline)
            }

            Button("Generate Share Phrase") {
                generatePhrase()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func phraseReadyView(_ phrase: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Share Phrase (one-time use)")
                .font(.title2).fontWeight(.semibold)

            phraseDisplay(phrase)

            // Warning
            VStack(alignment: .leading, spacing: 12) {
                Label("One-time use", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.vaultHighlight)
                Text("This phrase works once. After your recipient uses it, it will no longer work.")
                    .font(.subheadline).foregroundStyle(.vaultSecondaryText)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vaultHighlight.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Upload Vault") {
                startBackgroundUpload(phrase: phrase)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func backgroundUploadStartedView(_ phrase: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Uploading in Background")
                .font(.title2).fontWeight(.semibold)

            Text("You can dismiss this screen. You'll be notified when the upload completes.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            phraseDisplay(phrase)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding(.top, 40)
    }

    private var manageSharesView: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared with \(activeShares.count) \(activeShares.count == 1 ? "person" : "people")")
                        .font(.title3).fontWeight(.semibold)

                    if let lastSync = ShareSyncManager.shared.lastSyncedAt {
                        Text("Last synced: \(lastSync, style: .relative) ago")
                            .font(.caption).foregroundStyle(.vaultSecondaryText)
                    }
                }
                Spacer()
                syncStatusBadge
            }

            // Share list
            ForEach(activeShares) { share in
                shareRow(share)
            }

            Divider()

            Button("Share with someone new") {
                mode = .newShare
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                Task { await stopAllSharing() }
            } label: {
                if isStopping {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Stopping all shares...")
                    }
                } else {
                    Text("Stop All Sharing")
                }
            }
            .disabled(isStopping)
        }
    }

    private func shareRow(_ share: VaultStorage.ShareRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share #\(share.id.prefix(8))")
                        .font(.headline)
                    Text("Created \(share.createdAt, style: .date)")
                        .font(.caption).foregroundStyle(.vaultSecondaryText)
                }
                Spacer()
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }

            if let expires = share.policy.expiresAt {
                HStack {
                    Text("Expires")
                    Spacer()
                    Text(expires, style: .date)
                }
                .font(.subheadline).foregroundStyle(.vaultSecondaryText)
            }

            if let lastAccessed = share.lastSyncedAt {
                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(lastAccessed, style: .relative)
                }
                .font(.subheadline).foregroundStyle(.vaultSecondaryText)
            }

            Button("Revoke Access", role: .destructive) {
                Task { await revokeShare(share) }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color.vaultSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.vaultHighlight)
            Text("Sharing Failed")
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.vaultSecondaryText).multilineTextAlignment(.center)
            Button("Try Again") { mode = .newShare }
                .buttonStyle(.borderedProminent).padding(.top)
        }
        .padding(.top, 60)
    }

    // MARK: - Components

    private func phraseDisplay(_ phrase: String) -> some View {
        VStack(spacing: 12) {
            Text(phrase)
                .font(.system(.body, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.vaultSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: { copyToClipboard(phrase) }) {
                HStack {
                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                    Text(copiedToClipboard ? "Copied!" : "Copy to Clipboard")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        switch ShareSyncManager.shared.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 4) {
                PixelAnimation.syncing(size: 24)
                Text("Syncing").font(.caption)
            }
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .error(let msg):
            VStack(alignment: .trailing, spacing: 4) {
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.vaultHighlight)
                Button("Retry") {
                    guard let key = appState.currentVaultKey else { return }
                    ShareSyncManager.shared.syncNow(vaultKey: key)
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    // MARK: - Actions

    private func generatePhrase() {
        let phrase = RecoveryPhraseGenerator.shared.generatePhrase()
        mode = .phraseReady(phrase)
    }

    private func startBackgroundUpload(phrase: String) {
        guard let vaultKey = appState.currentVaultKey else {
            mode = .error("No vault key available")
            return
        }

        BackgroundShareTransferManager.shared.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: phrase,
            hasExpiration: hasExpiration,
            expiresAt: expiresAt,
            hasMaxOpens: hasMaxOpens,
            maxOpens: maxOpens,
            allowDownloads: allowDownloads
        )

        mode = .backgroundUploadStarted(phrase)
    }

    private func revokeShare(_ share: VaultStorage.ShareRecord) async {
        guard let key = appState.currentVaultKey else { return }

        do {
            try await CloudKitSharingManager.shared.revokeShare(shareVaultId: share.id)

            // Remove from index
            var index = try VaultStorage.shared.loadIndex(with: key)
            index.activeShares?.removeAll { $0.id == share.id }
            try VaultStorage.shared.saveIndex(index, with: key)

            activeShares = index.activeShares ?? []
            if activeShares.isEmpty {
                mode = .newShare
            }
        } catch {
            mode = .error("Failed to revoke: \(error.localizedDescription)")
        }
    }

    private func stopAllSharing() async {
        guard let key = appState.currentVaultKey else { return }

        isStopping = true

        do {
            // Immediately clear local shares so UI feels responsive
            var index = try VaultStorage.shared.loadIndex(with: key)
            let sharesToDelete = index.activeShares ?? []
            index.activeShares = nil
            try VaultStorage.shared.saveIndex(index, with: key)

            activeShares = []
            mode = .newShare
            isStopping = false

            // Delete from CloudKit in background
            for share in sharesToDelete {
                try? await CloudKitSharingManager.shared.deleteSharedVault(shareVaultId: share.id)
            }
        } catch {
            isStopping = false
            mode = .error("Failed to stop sharing: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        copiedToClipboard = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedToClipboard = false
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

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
    ShareVaultView()
        .environment(AppState())
}
