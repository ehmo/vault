import SwiftUI
import CloudKit

struct ShareVaultView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ViewMode = .loading

    enum ViewMode {
        case loading
        case iCloudUnavailable(CKAccountStatus)
        case newShare
        case phraseReady(String)
        case uploading(String, Int, Int) // phrase, current, total
        case uploadComplete(String)
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
                    case .uploading(let phrase, let current, let total):
                        uploadingView(phrase: phrase, current: current, total: total)
                    case .uploadComplete(let phrase):
                        uploadCompleteView(phrase)
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
            ProgressView().scaleEffect(1.5)
            Text("Checking sharing status...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func iCloudUnavailableView(_ status: CKAccountStatus) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("iCloud Required")
                .font(.title2).fontWeight(.semibold)
            Text(iCloudStatusMessage(status))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var newShareSettingsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Share This Vault")
                .font(.title2).fontWeight(.semibold)

            Text("Generate a one-time share phrase. After your recipient uses it, it cannot be reused.")
                .foregroundStyle(.secondary)
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
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Estimated size
            if let key = appState.currentVaultKey,
               let files = try? VaultStorage.shared.listFiles(with: key) {
                let totalSize = files.reduce(0) { $0 + $1.size }
                HStack {
                    Text("Estimated upload")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatBytes(totalSize))
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.blue)

            Text("Share Phrase (one-time use)")
                .font(.title2).fontWeight(.semibold)

            phraseDisplay(phrase)

            // Warning
            VStack(alignment: .leading, spacing: 12) {
                Label("One-time use", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text("This phrase works once. After your recipient uses it, it will no longer work.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Upload actions
            VStack(spacing: 12) {
                Button("Upload & Wait") {
                    startInlineUpload(phrase: phrase)
                }
                .buttonStyle(.borderedProminent)

                Button("Upload in Background") {
                    startBackgroundUpload(phrase: phrase)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func backgroundUploadStartedView(_ phrase: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Uploading in Background")
                .font(.title2).fontWeight(.semibold)

            Text("You can dismiss this screen. You'll be notified when the upload completes.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            phraseDisplay(phrase)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding(.top, 40)
    }

    private func uploadingView(phrase: String, current: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            phraseDisplay(phrase)

            VStack(spacing: 8) {
                ProgressView(value: Double(current), total: Double(total))
                Text("Uploading: \(current) of \(total) chunks...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uploadCompleteView(_ phrase: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Vault Shared!")
                .font(.title2).fontWeight(.semibold)

            Text("Share this phrase with your recipient. It can only be used once.")
                .foregroundStyle(.secondary)
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
                            .font(.caption).foregroundStyle(.secondary)
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

            Button("Stop All Sharing", role: .destructive) {
                Task { await stopAllSharing() }
            }
        }
    }

    private func shareRow(_ share: VaultStorage.ShareRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share #\(share.id.prefix(8))")
                        .font(.headline)
                    Text("Created \(share.createdAt, style: .date)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }

            if let expires = share.policy.expiresAt {
                HStack {
                    Text("Expires")
                    Spacer()
                    Text(expires, style: .date)
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }

            if let lastAccessed = share.lastSyncedAt {
                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(lastAccessed, style: .relative)
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }

            Button("Revoke Access", role: .destructive) {
                Task { await revokeShare(share) }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("Sharing Failed")
                .font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                .background(Color(.systemGray6))
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
                ProgressView().scaleEffect(0.6)
                Text("Syncing").font(.caption)
            }
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .error(let msg):
            VStack(alignment: .trailing, spacing: 4) {
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
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

    private func startInlineUpload(phrase: String) {
        guard let vaultKey = appState.currentVaultKey else {
            mode = .error("No vault key available")
            return
        }

        Task {
            do {
                let shareVaultId = CloudKitSharingManager.generateShareVaultId()
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: phrase)

                let policy = VaultStorage.SharePolicy(
                    expiresAt: hasExpiration ? expiresAt : nil,
                    maxOpens: hasMaxOpens ? maxOpens : nil,
                    allowScreenshots: false,
                    allowDownloads: allowDownloads
                )

                // Build vault data
                let index = try VaultStorage.shared.loadIndex(with: vaultKey)
                var sharedFiles: [SharedVaultData.SharedFile] = []

                // Get master key for decrypting thumbnails
                let masterKey = try CryptoEngine.shared.decrypt(index.encryptedMasterKey!, with: vaultKey)

                for entry in index.files where !entry.isDeleted {
                    let (header, content) = try VaultStorage.shared.retrieveFile(id: entry.fileId, with: vaultKey)
                    let reencrypted = try CryptoEngine.shared.encrypt(content, with: shareKey)

                    // Re-encrypt thumbnail with share key
                    var encryptedThumb: Data? = nil
                    if let thumbData = entry.thumbnailData {
                        let decryptedThumb = try CryptoEngine.shared.decrypt(thumbData, with: masterKey)
                        encryptedThumb = try CryptoEngine.shared.encrypt(decryptedThumb, with: shareKey)
                    }

                    sharedFiles.append(SharedVaultData.SharedFile(
                        id: header.fileId,
                        filename: header.originalFilename,
                        mimeType: header.mimeType,
                        size: Int(header.originalSize),
                        encryptedContent: reencrypted,
                        createdAt: header.createdAt,
                        encryptedThumbnail: encryptedThumb
                    ))
                }

                let sharedData = SharedVaultData(
                    files: sharedFiles,
                    metadata: SharedVaultData.SharedVaultMetadata(
                        ownerFingerprint: KeyDerivation.keyFingerprint(from: vaultKey),
                        sharedAt: Date()
                    ),
                    createdAt: Date(),
                    updatedAt: Date()
                )

                let encodedData = try JSONEncoder().encode(sharedData)

                await MainActor.run {
                    mode = .uploading(phrase, 0, 1)
                }

                try await CloudKitSharingManager.shared.uploadSharedVault(
                    shareVaultId: shareVaultId,
                    phrase: phrase,
                    vaultData: encodedData,
                    shareKey: shareKey,
                    policy: policy,
                    ownerFingerprint: KeyDerivation.keyFingerprint(from: vaultKey),
                    onProgress: { current, total in
                        Task { @MainActor in
                            mode = .uploading(phrase, current, total)
                        }
                    }
                )

                // Save share record to vault index
                let shareRecord = VaultStorage.ShareRecord(
                    id: shareVaultId,
                    createdAt: Date(),
                    policy: policy,
                    lastSyncedAt: Date(),
                    shareKeyData: shareKey
                )

                var updatedIndex = try VaultStorage.shared.loadIndex(with: vaultKey)
                if updatedIndex.activeShares == nil {
                    updatedIndex.activeShares = []
                }
                updatedIndex.activeShares?.append(shareRecord)
                try VaultStorage.shared.saveIndex(updatedIndex, with: vaultKey)

                await MainActor.run {
                    activeShares = updatedIndex.activeShares ?? []
                    mode = .uploadComplete(phrase)
                }
            } catch {
                await MainActor.run {
                    mode = .error(error.localizedDescription)
                }
            }
        }
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

        do {
            let index = try VaultStorage.shared.loadIndex(with: key)
            for share in index.activeShares ?? [] {
                try? await CloudKitSharingManager.shared.deleteSharedVault(shareVaultId: share.id)
            }

            var updatedIndex = index
            updatedIndex.activeShares = nil
            try VaultStorage.shared.saveIndex(updatedIndex, with: key)

            activeShares = []
            mode = .newShare
        } catch {
            mode = .error("Failed to stop sharing: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
        .environmentObject(AppState())
}
