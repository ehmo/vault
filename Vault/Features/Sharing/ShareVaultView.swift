import SwiftUI
import CloudKit

struct ShareVaultView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sharePhrase: String = ""
    @State private var isGenerating = true
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var uploadSuccess = false
    @State private var iCloudStatus: CKAccountStatus?
    @State private var copiedToClipboard = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Share Vault")
                    .font(.headline)
                Spacer()
                // Invisible button for balance
                Button("Cancel") { }
                    .opacity(0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    if isGenerating {
                        generatingView
                    } else if let error = uploadError {
                        errorView(error)
                    } else if uploadSuccess {
                        successView
                    } else if let status = iCloudStatus, status != .available {
                        iCloudUnavailableView(status)
                    } else {
                        phraseReadyView
                    }
                }
                .padding()
            }
        }
        .task {
            await checkiCloudAndGeneratePhrase()
        }
    }

    // MARK: - Views

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating share phrase...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Sharing Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                uploadError = nil
                Task {
                    await uploadVault()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(.top, 60)
    }

    private func iCloudUnavailableView(_ status: CKAccountStatus) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("iCloud Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text(iCloudStatusMessage(status))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Sharing requires iCloud to sync vaults between devices.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var phraseReadyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Share Phrase")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Send this phrase to anyone you want to share this vault with. They can enter it in the Vault app to access the same files.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Phrase display
            VStack(spacing: 12) {
                Text(sharePhrase)
                    .font(.system(.body, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: copyToClipboard) {
                    HStack {
                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        Text(copiedToClipboard ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()
                .padding(.vertical)

            // Warning section
            VStack(alignment: .leading, spacing: 12) {
                Label("Important", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text("Anyone with this phrase has full access to this vault. They can view, add, and delete files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("You cannot revoke access once shared.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Upload button
            Button(action: {
                Task { await uploadVault() }
            }) {
                if isUploading {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Uploading...")
                    }
                } else {
                    Text("Upload & Share")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUploading)
            .padding(.top)
        }
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Vault Shared!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your vault has been uploaded to iCloud. Share the phrase with others to give them access.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Phrase display (again for reference)
            VStack(spacing: 12) {
                Text(sharePhrase)
                    .font(.system(.body, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: copyToClipboard) {
                    HStack {
                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        Text(copiedToClipboard ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .buttonStyle(.bordered)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func checkiCloudAndGeneratePhrase() async {
        // Check iCloud status
        let status = await CloudKitSharingManager.shared.checkiCloudStatus()
        await MainActor.run {
            iCloudStatus = status
        }

        guard status == .available else {
            await MainActor.run {
                isGenerating = false
            }
            return
        }

        // Generate share phrase
        let phrase = RecoveryPhraseGenerator.shared.generatePhrase()
        await MainActor.run {
            sharePhrase = phrase
            isGenerating = false
        }
    }

    private func uploadVault() async {
        guard let vaultKey = appState.currentVaultKey else {
            uploadError = "No vault key available"
            return
        }

        await MainActor.run {
            isUploading = true
            uploadError = nil
        }

        do {
            // Load current vault data
            let index = try VaultStorage.shared.loadIndex(with: vaultKey)

            // Build shared vault data
            var sharedFiles: [SharedVaultData.SharedFile] = []

            for entry in index.files where !entry.isDeleted {
                let (header, content) = try VaultStorage.shared.retrieveFile(id: entry.fileId, with: vaultKey)

                // Re-encrypt with the share key
                let shareKey = try CloudKitSharingManager.deriveShareKey(from: sharePhrase)
                let reencrypted = try CryptoEngine.shared.encrypt(content, with: shareKey)

                sharedFiles.append(SharedVaultData.SharedFile(
                    id: header.fileId,
                    filename: header.originalFilename,
                    mimeType: header.mimeType,
                    size: Int(header.originalSize),
                    encryptedContent: reencrypted,
                    createdAt: header.createdAt
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

            // Upload to CloudKit
            try await CloudKitSharingManager.shared.uploadSharedVault(sharedData, phrase: sharePhrase)

            await MainActor.run {
                isUploading = false
                uploadSuccess = true
            }
        } catch {
            await MainActor.run {
                isUploading = false
                uploadError = error.localizedDescription
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = sharePhrase
        copiedToClipboard = true

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }

    private func iCloudStatusMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "iCloud is available"
        case .noAccount:
            return "Please sign in to iCloud in Settings"
        case .restricted:
            return "iCloud access is restricted"
        case .couldNotDetermine:
            return "Could not determine iCloud status"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        @unknown default:
            return "iCloud is not available"
        }
    }
}

#Preview {
    ShareVaultView()
        .environmentObject(AppState())
}
