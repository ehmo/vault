import SwiftUI
import CloudKit
import UIKit
import os.log

private let shareVaultLogger = Logger(subsystem: "app.vaultaire.ios", category: "ShareVault")

struct ShareVaultView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ViewMode = .loading

    enum ViewMode {
        case loading
        case iCloudUnavailable(CKAccountStatus)
        case newShare
        case uploading(phrase: String)
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
    @State private var uploadStatus: BackgroundShareTransferManager.TransferStatus = .idle
    @State private var linkCopied = false
    @State private var showDismissWarning = false

    // Active shares data
    @State private var activeShares: [VaultStorage.ShareRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    if case .uploading = mode {
                        showDismissWarning = true
                    } else {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("share_cancel")
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
                    // Upload status indicator
                    transferStatusBanner

                    switch mode {
                    case .loading:
                        loadingView
                    case .iCloudUnavailable(let status):
                        iCloudUnavailableView(status)
                    case .newShare:
                        newShareSettingsView
                    case .uploading(let phrase):
                        uploadingView(phrase)
                    case .manageShares:
                        manageSharesView
                    case .error(let message):
                        errorView(message)
                    }
                }
                .padding()
            }
        }
        .interactiveDismissDisabled({
            if case .uploading = mode { return true }
            return false
        }())
        .alert("Save Your Phrase?", isPresented: $showDismissWarning) {
            Button("Go Back", role: .cancel) { }
            Button("Close", role: .destructive) { dismiss() }
        } message: {
            Text("This phrase won't be shown again. Make sure you've saved it.")
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
                    // Don't navigate away when showing phrase — user needs to save it
                    if case .uploadComplete = newStatus, case .uploading = mode {
                        // Stay on uploading screen
                    } else if case .uploadComplete = newStatus {
                        await initialize()
                    }
                }
            }
        }
        .onChange(of: ShareSyncManager.shared.syncStatus) { _, newStatus in
            if case .upToDate = newStatus {
                reloadActiveShares()
            }
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        let status = await CloudKitSharingManager.shared.checkiCloudStatus()
        guard status == .available || status == .temporarilyUnavailable else {
            mode = .iCloudUnavailable(status)
            return
        }

        guard let key = appState.currentVaultKey else {
            mode = .error("No vault key available")
            return
        }

        let transferStatus = BackgroundShareTransferManager.shared.status
        uploadStatus = transferStatus

        do {
            var index = try VaultStorage.shared.loadIndex(with: key)
            estimatedUploadSize = index.files.filter { !$0.isDeleted }.reduce(0) { $0 + $1.size }
            if var shares = index.activeShares, !shares.isEmpty {
                // Check for consumed shares and remove them
                var consumedIds: Set<String> = []
                for share in shares {
                    if await CloudKitSharingManager.shared.isShareConsumed(shareVaultId: share.id) {
                        consumedIds.insert(share.id)
                    }
                }
                if !consumedIds.isEmpty {
                    shares.removeAll { consumedIds.contains($0.id) }
                    index.activeShares = shares.isEmpty ? nil : shares
                    try VaultStorage.shared.saveIndex(index, with: key)
                }

                activeShares = shares
                mode = shares.isEmpty ? .newShare : .manageShares
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
                    .accessibilityIdentifier("share_expiration_toggle")
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
                    .accessibilityIdentifier("share_max_opens_toggle")
                if hasMaxOpens {
                    Stepper("Max opens: \(maxOpens ?? 10)", value: Binding(
                        get: { maxOpens ?? 10 },
                        set: { maxOpens = $0 }
                    ), in: 1...1000)
                }

                Divider()

                // Allow downloads
                Toggle("Allow file exports", isOn: $allowDownloads)
                    .accessibilityIdentifier("share_allow_exports_toggle")
            }
            .padding()
            .vaultGlassBackground(cornerRadius: 12)

            // Estimated size
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

            Button("Share Vault") {
                let phrase = RecoveryPhraseGenerator.shared.generatePhrase()
                startBackgroundUpload(phrase: phrase)
            }
            .accessibilityIdentifier("share_generate_phrase")
            .vaultProminentButtonStyle()
        }
    }

    private func uploadingView(_ phrase: String) -> some View {
        VStack(spacing: 24) {
            PhraseDisplayCard(phrase: phrase)

            PhraseActionButtons(phrase: phrase)
            shareLinkButtons(for: phrase)

            // Upload status warning
            if case .uploading = uploadStatus {
                Label {
                    Text("Keep this screen open until upload finishes. Closing may pause the upload.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
            }

            Button("Done") {
                showDismissWarning = true
            }
            .accessibilityIdentifier("share_done")
            .vaultProminentButtonStyle()
            .padding(.top)
        }
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
    private var transferStatusBanner: some View {
        switch uploadStatus {
        case .uploading(let progress, let total):
            VaultSyncIndicator(
                style: .uploading,
                message: "Uploading shared vault...",
                progress: (current: progress, total: total)
            )
            .padding()
            .vaultGlassBackground(cornerRadius: 12)
        case .uploadFailed(let error):
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Upload Failed")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.vaultSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if BackgroundShareTransferManager.shared.hasPendingUpload {
                    Button {
                        BackgroundShareTransferManager.shared.resumePendingUpload(
                            vaultKey: appState.currentVaultKey
                        )
                    } label: {
                        Label("Resume Upload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .vaultGlassBackground(cornerRadius: 12)
        case .uploadComplete:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Upload complete")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding()
            .vaultGlassBackground(cornerRadius: 12)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        let status = ShareSyncManager.shared.syncStatus
        let isSyncing = status == .syncing

        VStack(alignment: .trailing, spacing: 4) {
            switch status {
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
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.vaultHighlight)
            }

            Button {
                guard let key = appState.currentVaultKey else { return }
                ShareSyncManager.shared.syncNow(vaultKey: key)
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isSyncing)
        }
    }

    private func shareLinkButtons(for phrase: String) -> some View {
        HStack(spacing: 12) {
            Button {
                guard let url = ShareLinkEncoder.shareURL(for: phrase) else { return }
                UIPasteboard.general.string = url.absoluteString
                linkCopied = true

                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run { linkCopied = false }
                }

                // Auto-clear clipboard after 60s
                let urlString = url.absoluteString
                Task {
                    try? await Task.sleep(for: .seconds(60))
                    if UIPasteboard.general.string == urlString {
                        UIPasteboard.general.string = ""
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: linkCopied ? "checkmark" : "link")
                    Text(linkCopied ? "Link Copied!" : "Copy Link")
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("share_copy_link")
            .buttonStyle(.bordered)

            Button {
                guard let url = ShareLinkEncoder.shareURL(for: phrase) else { return }
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.keyWindow?.rootViewController else { return }

                // Walk to topmost presented VC — rootViewController is already presenting this sheet
                var presenter = root
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }

                appState.suppressLockForShareSheet = true
                let activityVC = UIActivityViewController(activityItems: [url.absoluteString], applicationActivities: nil)
                activityVC.completionWithItemsHandler = { _, _, _, _ in
                    appState.suppressLockForShareSheet = false
                }
                presenter.present(activityVC, animated: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("share_share_link")
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

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

        mode = .uploading(phrase: phrase)
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
            shareVaultLogger.error("Failed to update index after revoke: \(error.localizedDescription, privacy: .public)")
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
