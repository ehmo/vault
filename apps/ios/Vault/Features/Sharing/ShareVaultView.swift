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

    // Active shares and jobs
    @State private var activeShares: [VaultStorage.ShareRecord] = []
    @State private var uploadJobs: [ShareUploadManager.UploadJob] = []
    @State private var currentOwnerFingerprint: String?

    // Phrase display
    @State private var activePhrase: String?
    @State private var linkCopied = false

    // Screen-awake policy while uploads are running and this screen is visible
    @State private var didDisableIdleTimerForUploads = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch mode {
                    case .loading:
                        loadingView
                    case .iCloudUnavailable(let status):
                        iCloudUnavailableView(status)
                    case .newShare:
                        newShareSettingsView
                    case .manageShares:
                        manageSharesView
                    case .error(let message):
                        errorView(message)
                    }
                }
                .padding()
            }
            .background(Color.vaultBackground.ignoresSafeArea())
            .navigationTitle("Share Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("share_cancel")
                }
            }
        }
        .sheet(item: Binding(
            get: { activePhrase.map(SharePhraseSheetItem.init(phrase:)) },
            set: { activePhrase = $0?.phrase }
        )) { item in
            phraseSheet(phrase: item.phrase)
                .presentationDetents([.medium, .large])
        }
        .task {
            await initialize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await initialize() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await refreshUploadJobs()
            }
        }
        .onChange(of: ShareSyncManager.shared.syncStatus) { _, newStatus in
            if case .upToDate = newStatus {
                reloadActiveShares()
            }
        }
        .onAppear {
            applyIdleTimerPolicy()
        }
        .onDisappear {
            releaseIdleTimerPolicyIfNeeded()
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

        currentOwnerFingerprint = KeyDerivation.keyFingerprint(from: key)

        do {
            var index = try VaultStorage.shared.loadIndex(with: key)
            estimatedUploadSize = index.files.filter { !$0.isDeleted }.reduce(0) { $0 + $1.size }

            if var shares = index.activeShares, !shares.isEmpty {
                // Check for consumed shares and remove them
                let consumedMap = await CloudKitSharingManager.shared.consumedStatusByShareVaultIds(
                    shares.map(\.id)
                )
                let consumedIds = Set(consumedMap.compactMap { $0.value ? $0.key : nil })
                if !consumedIds.isEmpty {
                    shares.removeAll { consumedIds.contains($0.id) }
                    index.activeShares = shares.isEmpty ? nil : shares
                    try VaultStorage.shared.saveIndex(index, with: key)
                }
                activeShares = shares
            } else {
                activeShares = []
            }

            await refreshUploadJobs()
            updateModeForCurrentData()
        } catch {
            mode = .error(error.localizedDescription)
        }
    }

    private func refreshUploadJobs() async {
        uploadJobs = ShareUploadManager.shared.jobs(forOwnerFingerprint: currentOwnerFingerprint)
        applyIdleTimerPolicy()
        updateModeForCurrentData()
    }

    private func updateModeForCurrentData() {
        mode = Self.resolveMode(
            currentMode: mode,
            hasShareData: !uploadJobs.isEmpty || !activeShares.isEmpty
        )
    }

    static func resolveMode(currentMode: ViewMode, hasShareData: Bool) -> ViewMode {
        switch currentMode {
        case .loading:
            return hasShareData ? .manageShares : .newShare
        case .manageShares:
            return hasShareData ? .manageShares : .newShare
        case .newShare:
            // Keep user in manual "share with someone new" flow even while
            // uploads/shares are changing in the background.
            return .newShare
        case .iCloudUnavailable, .error:
            return currentMode
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

            Text("Generate one-time share phrases. You can start multiple uploads in parallel.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)

            // Policy settings
            VStack(spacing: 16) {
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

                Toggle("Limit number of opens", isOn: $hasMaxOpens)
                    .accessibilityIdentifier("share_max_opens_toggle")
                if hasMaxOpens {
                    Stepper("Max opens: \(maxOpens ?? 10)", value: Binding(
                        get: { maxOpens ?? 10 },
                        set: { maxOpens = $0 }
                    ), in: 1...1000)
                }

                Divider()

                Toggle("Allow file exports", isOn: $allowDownloads)
                    .accessibilityIdentifier("share_allow_exports_toggle")
            }
            .padding()
            .vaultGlassBackground(cornerRadius: 12)

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

    private var manageSharesView: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared with \(activeShares.count) \(activeShares.count == 1 ? "person" : "people")")
                        .font(.title3).fontWeight(.semibold)

                    if !uploadJobs.isEmpty {
                        Text("\(runningUploadCount) upload\(runningUploadCount == 1 ? "" : "s") running")
                            .font(.caption)
                            .foregroundStyle(.vaultSecondaryText)
                    }
                }
                Spacer()
                syncStatusBadge
            }

            if !uploadJobs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Uploads")
                        .font(.headline)
                        .foregroundStyle(.vaultSecondaryText)
                        .accessibilityIdentifier("share_uploads_header")

                    ForEach(uploadJobs) { job in
                        uploadJobRow(job)
                    }
                }
            }

            if !activeShares.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Active Shares")
                        .font(.headline)
                        .foregroundStyle(.vaultSecondaryText)

                    ForEach(activeShares) { share in
                        shareRow(share)
                    }
                }
            }

            Divider()

            Button("Share with someone new") {
                mode = .newShare
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("share_new_share")

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

    private var runningUploadCount: Int {
        uploadJobs.reduce(into: 0) { count, job in
            if job.status.isRunning { count += 1 }
        }
    }

    private func uploadJobRow(_ job: ShareUploadManager.UploadJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share #\(job.shareVaultId.prefix(8))")
                        .font(.headline)
                    Text("Started \(job.createdAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                }
                Spacer()
                uploadStatusBadge(job)
            }

            Text(job.message)
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)

            ProgressView(value: Double(job.progress), total: Double(max(job.total, 1)))
                .tint(.accentColor)

            HStack {
                Text("\(job.progress)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.vaultSecondaryText)
                Spacer()
                if let error = job.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.vaultHighlight)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: 10) {
                if job.canResume {
                    Button("Resume") {
                        ShareUploadManager.shared.resumeUpload(jobId: job.id, vaultKey: appState.currentVaultKey)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share_upload_resume")
                }

                if let phrase = job.phrase {
                    Button("Show Phrase") {
                        activePhrase = phrase
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share_upload_show_phrase")
                }

                Spacer()

                if job.canTerminate {
                    Button("Terminate", role: .destructive) {
                        terminateUpload(job)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share_upload_terminate")
                }
            }
        }
        .padding()
        .vaultGlassBackground(cornerRadius: 12)
        .accessibilityIdentifier("share_upload_row")
    }

    @ViewBuilder
    private func uploadStatusBadge(_ job: ShareUploadManager.UploadJob) -> some View {
        switch job.status {
        case .preparing, .uploading, .finalizing:
            Text("Running")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
        case .paused:
            Text("Paused")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())
        case .failed:
            Text("Failed")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .clipShape(Capsule())
        case .complete:
            Text("Complete")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
        case .cancelled:
            Text("Stopped")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .clipShape(Capsule())
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

    private func phraseSheet(phrase: String) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PhraseDisplayCard(phrase: phrase)
                    PhraseActionButtons(phrase: phrase)
                    shareLinkButtons(for: phrase)

                    Label {
                        Text("Save this phrase now. You can continue using the app while upload runs in the background.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Color.vaultBackground.ignoresSafeArea())
            .navigationTitle("Share Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        activePhrase = nil
                    }
                    .accessibilityIdentifier("share_phrase_done")
                }
            }
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

        ShareUploadManager.shared.startBackgroundUpload(
            vaultKey: vaultKey,
            phrase: phrase,
            hasExpiration: hasExpiration,
            expiresAt: expiresAt,
            hasMaxOpens: hasMaxOpens,
            maxOpens: maxOpens,
            allowDownloads: allowDownloads
        )

        activePhrase = phrase
        mode = .manageShares
        Task { await refreshUploadJobs() }
    }

    private func reloadActiveShares() {
        guard let key = appState.currentVaultKey,
              let index = try? VaultStorage.shared.loadIndex(with: key),
              let shares = index.activeShares, !shares.isEmpty else {
            activeShares = []
            return
        }
        activeShares = shares
    }

    private func revokeShare(_ share: VaultStorage.ShareRecord) async {
        guard let key = appState.currentVaultKey else { return }

        // Update local state first for instant UI response
        activeShares.removeAll { $0.id == share.id }
        if activeShares.isEmpty && uploadJobs.isEmpty {
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
            // Cancel all upload jobs for this vault first
            for job in uploadJobs where job.canTerminate {
                ShareUploadManager.shared.terminateUpload(
                    jobId: job.id,
                    vaultKey: key,
                    cleanupRemote: true
                )
            }

            // Immediately clear local shares so UI feels responsive
            var index = try VaultStorage.shared.loadIndex(with: key)
            let sharesToDelete = index.activeShares ?? []
            index.activeShares = nil
            try VaultStorage.shared.saveIndex(index, with: key)

            activeShares = []
            uploadJobs = []
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

    private func terminateUpload(_ job: ShareUploadManager.UploadJob) {
        ShareUploadManager.shared.terminateUpload(
            jobId: job.id,
            vaultKey: appState.currentVaultKey,
            cleanupRemote: true
        )

        uploadJobs.removeAll { $0.id == job.id }
        activeShares.removeAll { $0.id == job.shareVaultId }
        if uploadJobs.isEmpty && activeShares.isEmpty {
            mode = .newShare
        }
    }

    // MARK: - Idle timer

    private func applyIdleTimerPolicy() {
        let shouldDisable = uploadJobs.contains(where: { $0.status.isRunning })

        if shouldDisable && !didDisableIdleTimerForUploads {
            UIApplication.shared.isIdleTimerDisabled = true
            didDisableIdleTimerForUploads = true
        } else if !shouldDisable && didDisableIdleTimerForUploads {
            UIApplication.shared.isIdleTimerDisabled = false
            didDisableIdleTimerForUploads = false
        }
    }

    private func releaseIdleTimerPolicyIfNeeded() {
        if didDisableIdleTimerForUploads {
            UIApplication.shared.isIdleTimerDisabled = false
            didDisableIdleTimerForUploads = false
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

private struct SharePhraseSheetItem: Identifiable {
    let phrase: String
    var id: String { phrase }
}

#Preview {
    ShareVaultView()
        .environment(AppState())
}
