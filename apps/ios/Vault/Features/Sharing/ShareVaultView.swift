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
        case uploading(jobId: String, phrase: String, shareVaultId: String)
        case phraseReveal(phrase: String, shareVaultId: String)
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
    @State private var initializationGeneration = 0

    // Upload termination confirmation
    @State private var showTerminateConfirmation = false
    @State private var showCloseWhileUploadingConfirmation = false

    // Link copy feedback
    @State private var linkCopied = false

    // Screen-awake policy while uploads are running and this screen is visible
    @State private var didDisableIdleTimerForUploads = false
    @State private var isShareScreenVisible = false

    private var isUploading: Bool {
        if case .uploading = mode { return true }
        return false
    }

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
                    case .uploading(let jobId, _, _):
                        uploadingView(jobId: jobId)
                    case .phraseReveal(let phrase, _):
                        phraseRevealView(phrase: phrase)
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
                    if isUploading {
                        Button("Close") {
                            showCloseWhileUploadingConfirmation = true
                        }
                        .accessibilityIdentifier("share_close")
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                        .accessibilityIdentifier("share_close")
                    }
                }
            }
        }
        .interactiveDismissDisabled(isUploading)
        .alert("Upload in Progress", isPresented: $showCloseWhileUploadingConfirmation) {
            Button("Leave", role: .destructive) {
                dismiss()
            }
            Button("Cancel", role: .cancel) { /* Dismiss alert */ }
        } message: {
            Text("The upload will continue in the background, but may pause if the app is minimized.")
        }
        .alert("Terminate Upload?", isPresented: $showTerminateConfirmation) {
            Button("Terminate", role: .destructive) {
                if case .uploading(let jobId, let phrase, let shareVaultId) = mode {
                    // Check live state — the upload may have completed while the alert was showing
                    let liveJob = ShareUploadManager.shared.jobs.first(where: { $0.id == jobId })
                    if liveJob == nil || liveJob?.status == .complete {
                        // Upload finished while alert was showing — show phrase reveal
                        mode = .phraseReveal(phrase: phrase, shareVaultId: shareVaultId)
                    } else if let localJob = uploadJobs.first(where: { $0.id == jobId }) {
                        terminateUpload(localJob)
                        if case .uploading = mode {
                            mode = .newShare
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { /* Dismiss alert */ }
        } message: {
            Text("This will stop the upload and discard progress. You'll need to start over.")
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
                await refreshUploadJobs(reloadShares: false)
            }
        }
        .onChange(of: ShareSyncManager.shared.syncStatus) { _, newStatus in
            if case .upToDate = newStatus {
                Task { await reloadActiveShares() }
            }
        }
        .onAppear {
            isShareScreenVisible = true
            applyIdleTimerPolicy()
        }
        .onDisappear {
            isShareScreenVisible = false
            releaseIdleTimerPolicyIfNeeded()
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        guard let key = appState.currentVaultKey else {
            mode = .error("No vault key available")
            return
        }

        let generation = initializationGeneration &+ 1
        initializationGeneration = generation
        currentOwnerFingerprint = KeyDerivation.keyFingerprint(from: key.rawBytes)

        do {
            async let accountStatusTask = CloudKitSharingManager.shared.checkiCloudStatus()

            let localSnapshot = try await Self.loadLocalSnapshot(vaultKey: key)
            guard generation == initializationGeneration else { return }

            estimatedUploadSize = localSnapshot.estimatedUploadSize
            activeShares = localSnapshot.activeShares

            await refreshUploadJobs(reloadShares: false)
            guard generation == initializationGeneration else { return }
            updateModeForCurrentData()

            Task {
                await reconcileShareStatuses(
                    vaultKey: key,
                    initialShares: localSnapshot.activeShares,
                    generation: generation
                )
            }

            let status = await accountStatusTask
            guard generation == initializationGeneration else { return }
            guard status == .available || status == .temporarilyUnavailable else {
                mode = .iCloudUnavailable(status)
                return
            }
        } catch {
            mode = .error(error.localizedDescription)
        }
    }

    private func refreshUploadJobs(reloadShares: Bool = true) async {
        let previousRunningCount = runningUploadCount
        let latestJobs = ShareUploadManager.shared.jobs(forOwnerFingerprint: currentOwnerFingerprint)
        uploadJobs = latestJobs.filter(Self.shouldDisplayUploadJob)
        let shouldReloadShares = reloadShares || (previousRunningCount > 0 && runningUploadCount == 0)
        if shouldReloadShares {
            await reloadActiveShares()
        }
        applyIdleTimerPolicy()

        // Check if an uploading job just completed — transition to phraseReveal
        if case .uploading(let jobId, let phrase, let shareVaultId) = mode {
            let matchingJob = latestJobs.first(where: { $0.id == jobId })
            if matchingJob == nil || matchingJob?.status == .complete {
                // Job completed (and possibly already removed from manager)
                mode = .phraseReveal(phrase: phrase, shareVaultId: shareVaultId)
                return
            } else if let job = matchingJob, job.status == .failed || job.status == .cancelled {
                mode = .error(job.errorMessage ?? "Upload failed")
                return
            }
        }

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
            return .newShare
        case .uploading, .phraseReveal:
            // Don't auto-transition away from these — they have explicit transitions
            return currentMode
        case .iCloudUnavailable, .error:
            return currentMode
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            PixelLoader.standard(size: 60)
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

            Text("Generate a one-time share phrase. The phrase will be shown after the upload completes.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

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
                startUploadAndShowProgress(phrase: phrase)
            }
            .accessibilityIdentifier("share_generate_phrase")
            .vaultProminentButtonStyle()

            // If there are existing shares, show a button to go back to manage view
            if !activeShares.isEmpty || !uploadJobs.isEmpty {
                Button("Back to Active Shares") {
                    mode = .manageShares
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Uploading View (full-screen progress)

    private func uploadingView(jobId: String) -> some View {
        let job = uploadJobs.first(where: { $0.id == jobId })

        return VStack(spacing: 24) {
            Spacer().frame(height: 40)

            PixelLoader.standard(size: 60)

            Text("Uploading Vault")
                .font(.title2).fontWeight(.semibold)

            Text(job?.message ?? "Preparing...")
                .foregroundStyle(.vaultSecondaryText)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)

            ProgressView(value: Double(job?.progress ?? 0), total: Double(max(job?.total ?? 100, 1)))
                .tint(.accentColor)
                .padding(.horizontal)

            Text("\(job?.progress ?? 0)%")
                .font(.body.monospacedDigit())
                .foregroundStyle(.vaultSecondaryText)

            if let error = job?.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.vaultHighlight)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 8)

            Label {
                Text("Keep the app open. Minimizing may pause the upload.")
                    .lineLimit(nil)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.subheadline)
            .foregroundStyle(.vaultSecondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            Spacer().frame(height: 16)

            if job?.canResume == true {
                Button("Resume Upload") {
                    ShareUploadManager.shared.resumeUpload(jobId: jobId, vaultKey: appState.currentVaultKey)
                }
                .vaultProminentButtonStyle()
                .accessibilityIdentifier("share_upload_resume")
            }

            Button("Terminate Upload", role: .destructive) {
                showTerminateConfirmation = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("share_upload_terminate")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Phrase Reveal View (shown only after upload completes)

    private func phraseRevealView(phrase: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Upload Complete")
                .font(.title2).fontWeight(.semibold)

            Text("Share this phrase with the recipient. They'll use it to access your vault.")
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            PhraseDisplayCard(phrase: phrase)
            PhraseActionButtons(phrase: phrase)
            shareLinkButtons(for: phrase)

            Label {
                Text("This phrase is stored with the share. You can find it later in Active Shares until the recipient claims it.")
                    .lineLimit(nil)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.vaultSecondaryText)
            .multilineTextAlignment(.center)

            Button("Done") {
                mode = .manageShares
            }
            .vaultProminentButtonStyle()
            .accessibilityIdentifier("share_phrase_done")
        }
    }

    // MARK: - Manage Shares View

    private var manageSharesView: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Shares")
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
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
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
        let syncProgress = ShareSyncManager.shared.perShareProgress[share.id]
        let isSyncingShare = syncProgress != nil && {
            if case .done = syncProgress?.status { return false }
            if case .error = syncProgress?.status { return false }
            return true
        }()
        let isClaimed = share.isClaimed == true

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share #\(share.id.prefix(8))")
                        .font(.headline)
                    Text("Created \(relativeTimeString(from: share.createdAt))")
                        .font(.caption).foregroundStyle(.vaultSecondaryText)
                }
                Spacer()
                shareStatusBadge(isClaimed: isClaimed, isSyncing: isSyncingShare)
            }

            if isSyncingShare, let progress = syncProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fractionCompleted)
                        .tint(.accentColor)
                    Text(progress.message)
                        .font(.caption2)
                        .foregroundStyle(.vaultSecondaryText)
                }
            }

            // Policy summary
            policySummary(share.policy)

            // Phrase section — show only if not claimed
            if !isClaimed, let phrase = share.phrase {
                VStack(spacing: 8) {
                    Divider()
                    PhraseDisplayCard(phrase: phrase)
                    shareLinkButtons(for: phrase)
                }
            }

            Button("Revoke Access", role: .destructive) {
                Task { await revokeShare(share) }
            }
            .font(.subheadline)
        }
        .padding()
        .vaultGlassBackground(cornerRadius: 12)
    }

    @ViewBuilder
    private func shareStatusBadge(isClaimed: Bool, isSyncing: Bool) -> some View {
        if isSyncing {
            Text("Syncing")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())
        } else if isClaimed {
            Text("Accepted")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
        } else {
            Text("Pending")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func policySummary(_ policy: VaultStorage.SharePolicy) -> some View {
        let items = Self.policyDescriptionItems(policy)
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.vaultSecondaryText.opacity(0.1))
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
    }

    static func policyDescriptionItems(_ policy: VaultStorage.SharePolicy) -> [String] {
        var items: [String] = []
        if !policy.allowDownloads {
            items.append("No exports")
        }
        if let maxOpens = policy.maxOpens {
            items.append("\(maxOpens) opens max")
        }
        if let expiresAt = policy.expiresAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            items.append("Expires \(formatter.string(from: expiresAt))")
        }
        return items
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.vaultHighlight)
            Text("Sharing Failed")
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.vaultSecondaryText).multilineTextAlignment(.center)
                .lineLimit(nil)
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
                    PixelLoader.compact(size: 24)
                    Text("Syncing").font(.caption)
                }
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.vaultHighlight)
            }

            // Only show Sync Now button when there are shares to sync and not currently syncing
            if !activeShares.isEmpty && status != .upToDate && status != .syncing {
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

                ShareSheetHelper.present(items: [url.absoluteString]) {
                    // Share sheet dismissed
                }
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

    private func startUploadAndShowProgress(phrase: String) {
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

        // Find the newly created job to get its ID
        Task {
            // Brief delay for job to appear
            try? await Task.sleep(for: .milliseconds(100))
            let latestJobs = ShareUploadManager.shared.jobs(forOwnerFingerprint: currentOwnerFingerprint)
            // Find the job with this phrase
            if let job = latestJobs.first(where: { $0.phrase == phrase }) {
                uploadJobs = latestJobs.filter(Self.shouldDisplayUploadJob)
                mode = .uploading(jobId: job.id, phrase: phrase, shareVaultId: job.shareVaultId)
            } else {
                // Fallback: just show manage shares
                await refreshUploadJobs(reloadShares: false)
                mode = .manageShares
            }
        }
    }

    private func reloadActiveShares() async {
        guard let key = appState.currentVaultKey,
              let shares = try? await Self.loadActiveShares(vaultKey: key) else {
            activeShares = []
            return
        }
        // Sort by creation date, newest first
        activeShares = shares.sorted { $0.createdAt > $1.createdAt }
        updateModeForCurrentData()
    }

    /// Formats a date as relative time (e.g., "5 minutes ago", "1 day ago")
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)

        // Less than a minute
        if diff < 60 {
            return "just now"
        }
        // Less than an hour - show minutes
        else if diff < 3600 {
            let minutes = Int(diff / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        // Less than a day - show hours
        else if diff < 86400 {
            let hours = Int(diff / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        // Less than 30 days - show days
        else if diff < 2592000 {
            let days = Int(diff / 86400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        // More than 30 days - show the date
        else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private func revokeShare(_ share: VaultStorage.ShareRecord) async {
        guard let key = appState.currentVaultKey else { return }

        // Update local state first for instant UI response
        activeShares.removeAll { $0.id == share.id }

        // Check if this was the last share - if so, terminate any ongoing sync
        let remainingShares = activeShares
        let remainingJobs = uploadJobs.filter { $0.shareVaultId != share.id }

        if remainingShares.isEmpty && remainingJobs.isEmpty {
            // No more users - terminate any ongoing uploads for this specific share
            for job in uploadJobs where job.shareVaultId == share.id && job.canTerminate {
                ShareUploadManager.shared.terminateUpload(
                    jobId: job.id,
                    vaultKey: key,
                    cleanupRemote: true
                )
            }
            uploadJobs.removeAll { $0.shareVaultId == share.id }
            mode = .newShare
        }
        // If there are remaining shares, sync will continue for those users

        do {
            // Persist to index
            var index = try await VaultStorage.shared.loadIndex(with: key)
            index.activeShares?.removeAll { $0.id == share.id }
            try await VaultStorage.shared.saveIndex(index, with: key)
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
            var index = try await VaultStorage.shared.loadIndex(with: key)
            let sharesToDelete = index.activeShares ?? []
            index.activeShares = nil
            try await VaultStorage.shared.saveIndex(index, with: key)

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
        let shouldDisable = Self.shouldDisableIdleTimer(
            isShareScreenVisible: isShareScreenVisible,
            uploadJobs: uploadJobs
        )

        if shouldDisable && !didDisableIdleTimerForUploads {
            IdleTimerManager.shared.disable()
            didDisableIdleTimerForUploads = true
        } else if !shouldDisable && didDisableIdleTimerForUploads {
            IdleTimerManager.shared.enable()
            didDisableIdleTimerForUploads = false
        }
    }

    private func releaseIdleTimerPolicyIfNeeded() {
        if didDisableIdleTimerForUploads {
            IdleTimerManager.shared.enable()
            didDisableIdleTimerForUploads = false
        }
    }

    // MARK: - Reconcile Share Statuses (consumed + claimed)

    private func reconcileShareStatuses(
        vaultKey: VaultKey,
        initialShares: [VaultStorage.ShareRecord],
        generation: Int
    ) async {
        guard !initialShares.isEmpty else { return }

        let shareIds = initialShares.map(\.id)

        // Query both consumed and claimed statuses in parallel
        async let consumedTask = CloudKitSharingManager.shared.consumedStatusByShareVaultIds(shareIds)
        async let claimedTask = CloudKitSharingManager.shared.claimedStatusByShareVaultIds(shareIds)

        let consumedMap: [String: Bool]
        let claimedMap: [String: Bool]
        do {
            consumedMap = try await consumedTask
            claimedMap = try await claimedTask
        } catch {
            shareVaultLogger.warning("Failed to check share statuses: \(error.localizedDescription, privacy: .private)")
            return
        }

        let consumedIds = Set(consumedMap.compactMap { $0.value ? $0.key : nil })
        let claimedIds = Set(claimedMap.compactMap { $0.value ? $0.key : nil })

        // Nothing to update
        guard !consumedIds.isEmpty || !claimedIds.isEmpty else { return }

        do {
            let updatedShares = try await Task.detached(priority: .utility) { () -> [VaultStorage.ShareRecord] in
                var index = try await VaultStorage.shared.loadIndex(with: vaultKey)
                var shares = index.activeShares ?? []

                // Remove consumed shares
                shares.removeAll { consumedIds.contains($0.id) }

                // Update claimed status and clear phrase for claimed shares
                for i in shares.indices {
                    if claimedIds.contains(shares[i].id) {
                        shares[i].isClaimed = true
                        shares[i].phrase = nil
                    }
                }

                shares.sort { $0.createdAt > $1.createdAt }
                index.activeShares = shares.isEmpty ? nil : shares
                try await VaultStorage.shared.saveIndex(index, with: vaultKey)
                return shares
            }.value

            await MainActor.run {
                guard generation == initializationGeneration else { return }
                activeShares = updatedShares
                updateModeForCurrentData()
            }
        } catch {
            shareVaultLogger.error("Failed to reconcile share statuses: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private struct LocalSnapshot: Sendable {
        let estimatedUploadSize: Int
        let activeShares: [VaultStorage.ShareRecord]
    }

    private static func loadLocalSnapshot(vaultKey: VaultKey) async throws -> LocalSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
            let estimatedSize = index.files.filter { !$0.isDeleted }.reduce(0) { $0 + $1.size }
            let shares = index.activeShares ?? []
            // Sort by creation date, newest first (descending order)
            let sortedShares = shares.sorted { $0.createdAt > $1.createdAt }
            return LocalSnapshot(
                estimatedUploadSize: estimatedSize,
                activeShares: sortedShares
            )
        }.value
    }

    private static func loadActiveShares(vaultKey: VaultKey) async throws -> [VaultStorage.ShareRecord] {
        try await Task.detached(priority: .utility) {
            let index = try await VaultStorage.shared.loadIndex(with: vaultKey)
            let shares = index.activeShares ?? []
            // Sort by creation date, newest first
            return shares.sorted { $0.createdAt > $1.createdAt }
        }.value
    }

    static func shouldDisplayUploadJob(_ job: ShareUploadManager.UploadJob) -> Bool {
        if case .complete = job.status { return false }
        if case .cancelled = job.status { return false }
        return true
    }

    static func shouldDisableIdleTimer(
        isShareScreenVisible: Bool,
        uploadJobs: [ShareUploadManager.UploadJob]
    ) -> Bool {
        guard isShareScreenVisible else { return false }
        return uploadJobs.contains(where: { $0.status.isRunning })
            || ShareSyncManager.shared.syncStatus == .syncing
    }

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
