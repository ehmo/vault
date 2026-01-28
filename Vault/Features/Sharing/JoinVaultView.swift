import SwiftUI
import CloudKit

struct JoinVaultView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joinSuccess = false
    @State private var iCloudStatus: CKAccountStatus?
    @State private var downloadedVault: SharedVaultData?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Join Shared Vault")
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
                    if let status = iCloudStatus, status != .available {
                        iCloudUnavailableView(status)
                    } else if joinSuccess, let vault = downloadedVault {
                        successView(vault)
                    } else if let error = joinError {
                        errorView(error)
                    } else {
                        inputView
                    }
                }
                .padding()
            }
        }
        .task {
            await checkiCloud()
        }
    }

    // MARK: - Views

    private var inputView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Enter Share Phrase")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter the share phrase you received from someone who shared a vault with you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Phrase input
            TextEditor(text: $phrase)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            // Join button
            Button(action: {
                Task { await joinVault() }
            }) {
                if isJoining {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Joining...")
                    }
                } else {
                    Text("Join Vault")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)

            // Info section
            VStack(alignment: .leading, spacing: 8) {
                Label("How it works", systemImage: "info.circle")
                    .font(.headline)

                Text("The share phrase identifies and decrypts the shared vault. Once joined, you'll see all files shared by the vault owner.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Could Not Join")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Try Again") {
                    joinError = nil
                }
                .buttonStyle(.bordered)

                Button("Edit Phrase") {
                    joinError = nil
                }
                .buttonStyle(.borderedProminent)
            }
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

            Text("Joining shared vaults requires iCloud.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private func successView(_ vault: SharedVaultData) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Vault Joined!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You now have access to the shared vault.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Vault info
            VStack(spacing: 12) {
                HStack {
                    Text("Files")
                    Spacer()
                    Text("\(vault.files.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Size")
                    Spacer()
                    Text(formatBytes(vault.files.reduce(0) { $0 + $1.size }))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Shared")
                    Spacer()
                    Text(vault.metadata.sharedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Open Vault") {
                openSharedVault()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func checkiCloud() async {
        let status = await CloudKitSharingManager.shared.checkiCloudStatus()
        await MainActor.run {
            iCloudStatus = status
        }
    }

    private func joinVault() async {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else { return }

        await MainActor.run {
            isJoining = true
            joinError = nil
        }

        do {
            // Download shared vault
            let vault = try await CloudKitSharingManager.shared.downloadSharedVault(phrase: trimmedPhrase)

            await MainActor.run {
                downloadedVault = vault
                isJoining = false
                joinSuccess = true
            }
        } catch CloudKitSharingError.vaultNotFound {
            await MainActor.run {
                isJoining = false
                joinError = "No vault found with this phrase. Check that the phrase is correct and try again."
            }
        } catch CloudKitSharingError.decryptionFailed {
            await MainActor.run {
                isJoining = false
                joinError = "Could not decrypt the vault. The phrase may be incorrect."
            }
        } catch {
            await MainActor.run {
                isJoining = false
                joinError = error.localizedDescription
            }
        }
    }

    private func openSharedVault() {
        guard let vault = downloadedVault else { return }

        // Derive the share key and set it as the current vault key
        do {
            let shareKey = try CloudKitSharingManager.deriveShareKey(from: phrase)

            // Import files to local storage
            Task {
                await importSharedFiles(vault: vault, key: shareKey)

                await MainActor.run {
                    appState.currentVaultKey = shareKey
                    appState.isUnlocked = true
                    dismiss()
                }
            }
        } catch {
            joinError = "Failed to open vault: \(error.localizedDescription)"
        }
    }

    private func importSharedFiles(vault: SharedVaultData, key: Data) async {
        // Import each file to local storage
        for file in vault.files {
            do {
                // Decrypt with share key
                let decrypted = try CryptoEngine.shared.decrypt(file.encryptedContent, with: key)

                // Store locally
                _ = try VaultStorage.shared.storeFile(
                    data: decrypted,
                    filename: file.filename,
                    mimeType: file.mimeType,
                    with: key
                )
            } catch {
                #if DEBUG
                print("Failed to import file \(file.filename): \(error)")
                #endif
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
    JoinVaultView()
        .environmentObject(AppState())
}
