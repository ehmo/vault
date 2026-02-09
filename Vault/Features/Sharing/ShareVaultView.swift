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
    @State private var isStopping = false
    @State private var estimatedUploadSize: Int?
    @State private var useCustomPhrase = false
    @State private var customPhrase = ""
    @State private var customPhraseValidation: RecoveryPhraseGenerator.PhraseValidation?
    @State private var uploadStatus: BackgroundShareTransferManager.TransferStatus = .idle

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
                    // Upload progress indicator
                    if case .uploading(let progress, let total) = uploadStatus {
                        VaultSyncIndicator(
                            style: .uploading,
                            message: "Uploading shared vault...",
                            progress: (current: progress, total: total)
                        )
                        .padding()
                        .vaultGlassBackground(cornerRadius: 12)
                    }

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
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await initialize() }
        }
        .task {
            // Poll upload status while view is visible
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let newStatus = BackgroundShareTransferManager.shared.status
                if newStatus != uploadStatus {
                    uploadStatus = newStatus
                    // Refresh share list when upload completes
                    if case .uploadComplete = newStatus {
                        await initialize()
                    }
                }
            }
        }
        .onChange(of: ShareSyncManager.shared.syncStatus) { _, newStatus in
            // Reload share records after sync so per-share "Last synced" updates
            if case .upToDate = newStatus {
                reloadActiveShares()
            }
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        let status = await CloudKitSharingManager.shared.checkiCloudStatus()
        // .available = fully ready, .temporarilyUnavailable = signed in but CloudKit still syncing
        // Both mean the user has an iCloud account — let them proceed.
        // Only block for .noAccount, .restricted, .couldNotDetermine.
        guard status == .available || status == .temporarilyUnavailable else {
            mode = .iCloudUnavailable(status)
            return
        }

        // Check if vault already has active shares
        guard let key = appState.currentVaultKey else {
            mode = .error("No vault key available")
            return
        }

        // Check for in-progress uploads
        let transferStatus = BackgroundShareTransferManager.shared.status
        uploadStatus = transferStatus

        do {
            let index = try VaultStorage.shared.loadIndex(with: key)
            // Pre-compute estimated upload size from index metadata (no decryption needed)
            estimatedUploadSize = index.files.filter { !$0.isDeleted }.reduce(0) { $0 + $1.size }
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

            Button { SettingsURLHelper.openICloudSettings() } label: {
                Label("Open iCloud Settings", systemImage: "gear")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Button("Retry") {
                mode = .loading
                Task { await initialize() }
            }
            .foregroundStyle(.vaultSecondaryText)
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
                    HStack {
                        DatePicker("Expires", selection: Binding(
                            get: { expiresAt ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())! },
                            set: { expiresAt = $0 }
                        ), in: Date()..., displayedComponents: .date)

                        Button("Today") { expiresAt = Date() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
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
            .vaultGlassBackground(cornerRadius: 12)

            // Estimated size (pre-computed in initialize, no decryption during render)
            if let totalSize = estimatedUploadSize {
                HStack {
                    Text("Estimated upload")
                        .foregroundStyle(.vaultSecondaryText)
                    Spacer()
                    Text(Self.byteCountFormatter.string(fromByteCount: Int64(totalSize)))
                        .foregroundStyle(.vaultSecondaryText)
                }
                .font(.subheadline)
            }

            Button("Generate Share Phrase") {
                generatePhrase()
            }
            .vaultProminentButtonStyle()
        }
    }

    private func phraseReadyView(_ phrase: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Share Phrase (one-time use)")
                .font(.title2).fontWeight(.semibold)

            // Auto / Custom phrase picker
            Picker("Phrase Type", selection: $useCustomPhrase) {
                Text("Auto-Generated").tag(false)
                Text("Custom Phrase").tag(true)
            }
            .pickerStyle(.segmented)

            if useCustomPhrase {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $customPhrase)
                        .autocorrectionDisabled()
                        .onChange(of: customPhrase) { _, newValue in
                            guard !newValue.isEmpty else { customPhraseValidation = nil; return }
                            customPhraseValidation = RecoveryPhraseGenerator.shared.validatePhrase(newValue)
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

                if let validation = customPhraseValidation {
                    HStack(spacing: 8) {
                        Image(systemName: validation.isAcceptable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(validation.isAcceptable ? .green : .orange)
                        Text(validation.message)
                            .font(.caption)
                    }
                }

                PhraseActionButtons(phrase: customPhrase.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                PhraseDisplayCard(phrase: phrase)

                PhraseActionButtons(phrase: phrase)
            }

            // Warning
            VStack(alignment: .leading, spacing: 12) {
                Label("Write this down", systemImage: "pencil")
                Label("Store it somewhere safe", systemImage: "lock")
                Label("One-time use only", systemImage: "exclamationmark.triangle")
            }
            .font(.subheadline)
            .foregroundStyle(.vaultSecondaryText)

            Button("Upload Vault") {
                let uploadPhrase = useCustomPhrase ? customPhrase.trimmingCharacters(in: .whitespacesAndNewlines) : phrase
                startBackgroundUpload(phrase: uploadPhrase)
            }
            .vaultProminentButtonStyle()
            .disabled(useCustomPhrase && !(customPhraseValidation?.isAcceptable ?? false))
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

            PhraseDisplayCard(phrase: phrase)

            PhraseActionButtons(phrase: phrase)

            Button("Done") { dismiss() }
                .vaultProminentButtonStyle()
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
        .vaultGlassBackground(cornerRadius: 12)
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
                .vaultProminentButtonStyle().padding(.top)
        }
        .padding(.top, 60)
    }

    // MARK: - Components

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

    private func reloadActiveShares() {
        guard let key = appState.currentVaultKey,
              let index = try? VaultStorage.shared.loadIndex(with: key),
              let shares = index.activeShares, !shares.isEmpty else { return }
        activeShares = shares
    }

    private func revokeShare(_ share: VaultStorage.ShareRecord) async {
        guard let key = appState.currentVaultKey else { return }

        // Update local state first for instant UI response
        activeShares.removeAll { $0.id == share.id }
        if activeShares.isEmpty {
            mode = .newShare
        }

        do {
            // Persist to index
            var index = try VaultStorage.shared.loadIndex(with: key)
            index.activeShares?.removeAll { $0.id == share.id }
            try VaultStorage.shared.saveIndex(index, with: key)
        } catch {
            #if DEBUG
            print("[ShareVault] Failed to update index after revoke: \(error)")
            #endif
        }

        // Delete from CloudKit in background (fire-and-forget)
        Task {
            try? await CloudKitSharingManager.shared.revokeShare(shareVaultId: share.id)
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

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func iCloudStatusMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "iCloud is available"
        case .noAccount: return "Please sign in to iCloud in Settings"
        case .restricted: return "iCloud access is restricted"
        case .couldNotDetermine: return "Could not determine iCloud status"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable. Please check your iCloud settings and try again."
        @unknown default: return "iCloud is not available"
        }
    }
}

#Preview {
    ShareVaultView()
        .environment(AppState())
}
