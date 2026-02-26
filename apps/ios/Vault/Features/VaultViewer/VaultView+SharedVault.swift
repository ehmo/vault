import AVFoundation
import SwiftUI
import UIKit

// MARK: - Shared Vault

extension VaultView {

    // MARK: - Shared Vault Banner

    var sharedVaultBannerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .accessibilityHidden(true)

                Text("Shared Vault")
                    .font(.caption).fontWeight(.medium)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if sharedVaultHasPolicyDetails {
                sharedVaultPolicyDetailsView
            }

            if viewModel.updateAvailable {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    Text("New files available")
                        .font(.caption)
                    Spacer()
                    Button(action: { Task { await downloadUpdate() } }) {
                        if viewModel.isUpdating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Update Now")
                                .font(.caption).fontWeight(.medium)
                        }
                    }
                    .vaultProminentButtonStyle()
                    .controlSize(.mini)
                    .disabled(viewModel.isUpdating)
                    .accessibilityLabel(viewModel.isUpdating ? "Updating shared vault" : "Update shared vault")
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
            }
        }
        .vaultBannerBackground()
        .accessibilityElement(children: .combine)
    }

    private var sharedVaultHasPolicyDetails: Bool {
        let policy = viewModel.sharePolicy
        return policy?.expiresAt != nil
            || policy?.maxOpens != nil
            || policy?.allowDownloads == false
    }

    private var sharedVaultPolicyDetailsView: some View {
        HStack(spacing: 12) {
            if let maxOpens = viewModel.sharePolicy?.maxOpens {
                let remaining = max(maxOpens - viewModel.sharedVaultOpenCount, 0)
                Label("\(remaining) of \(maxOpens) opens left", systemImage: "lock.open.display")
                    .accessibilityIdentifier("shared_vault_opens_left")
            }

            if viewModel.sharePolicy?.allowDownloads == false {
                Label("Exports disabled", systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                    .accessibilityIdentifier("shared_vault_exports_disabled")
            }

            if let expires = viewModel.sharePolicy?.expiresAt {
                Label {
                    Text("Expires \(expires, style: .date)")
                } icon: {
                    Image(systemName: "calendar")
                }
                .accessibilityIdentifier("shared_vault_expires")
            }
        }
        .font(.caption2)
        .foregroundStyle(.vaultSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - Download Update

    func downloadUpdate() async {
        guard let key = appState.currentVaultKey,
              let vaultId = viewModel.sharedVaultId else { return }

        viewModel.isUpdating = true
        viewModel.sharedVaultUpdateProgress = (completed: 0, total: 100, message: "Downloading update...")
        IdleTimerManager.shared.disable()

        var bgTaskCleaned = false
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "SharedVaultUpdate") {
            // Expiration handler — clean up progress state so the overlay disappears
            bgTaskCleaned = true
            Task { @MainActor [weak viewModel] in
                viewModel?.sharedVaultUpdateProgress = nil
                viewModel?.isUpdating = false
                IdleTimerManager.shared.enable()
            }
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
        }

        defer {
            viewModel.isUpdating = false
            viewModel.sharedVaultUpdateProgress = nil
            if !bgTaskCleaned {
                // Only re-enable here if the expiration handler hasn't already;
                // otherwise we'd double-decrement the ref-counted idle timer.
                IdleTimerManager.shared.enable()
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                }
            }
        }

        do {
            let index = try await VaultStorage.shared.loadIndex(with: key)

            // Use the stored phrase-derived share key
            guard let shareKeyData = index.shareKeyData else {
                #if DEBUG
                print("❌ [VaultView] No share key stored in vault index")
                #endif
                return
            }

            let shareKey = ShareKey(shareKeyData)
            let data = try await CloudKitSharingManager.shared.downloadUpdatedVault(
                shareVaultId: vaultId,
                shareKey: shareKey,
                onProgress: { @Sendable [weak viewModel] completed, total in
                    Task { @MainActor in
                        // Map download progress to 0→70% range
                        let pct = total > 0 ? Int(Double(completed) / Double(total) * 70) : 0
                        viewModel?.sharedVaultUpdateProgress = (completed: pct, total: 100, message: "Downloading update...")
                    }
                }
            )

            if SVDFSerializer.isSVDF(data) {
                try await importSVDFDelta(data: data, shareKey: shareKeyData, vaultKey: key, index: index)
            } else {
                try await importLegacyFull(data: data, shareKey: shareKeyData, vaultKey: key, index: index)
            }

            // Store the new version to avoid false "new files available"
            if let newVersion = try? await CloudKitSharingManager.shared.checkForUpdates(
                shareVaultId: vaultId, currentVersion: 0
            ) {
                var updatedIndex = try await VaultStorage.shared.loadIndex(with: key)
                updatedIndex.sharedVaultVersion = newVersion
                try await VaultStorage.shared.saveIndex(updatedIndex, with: key)
            }

            viewModel.updateAvailable = false
            viewModel.loadFiles()
        } catch {
            viewModel.toastMessage = .error("Update failed: \(error.localizedDescription)")
            #if DEBUG
            print("❌ [VaultView] Failed to download update: \(error)")
            #endif
        }
    }

    /// SVDF v4/v5 delta import: parse manifest, diff file IDs vs local, import only new files.
    func importSVDFDelta(data: Data, shareKey: Data, vaultKey: VaultKey, index: VaultStorage.VaultIndex) async throws {
        let vaultKeyFingerprint = vaultKey.rawBytes.hashValue
        let header = try SVDFSerializer.parseHeader(from: data)
        let manifest = try SVDFSerializer.parseManifest(from: data, shareKey: shareKey)
        let remoteFileIds = Set(manifest.filter { !$0.deleted }.map { $0.id })
        let localFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })
        
        #if DEBUG
        print("🔐 [importSVDFDelta] Vault key hash: \(vaultKeyFingerprint), Local files: \(localFileIds.count), Remote files: \(remoteFileIds.count)")
        #endif

        // Delete files that were removed remotely
        let removedIds = localFileIds.subtracting(remoteFileIds)
        if !removedIds.isEmpty {
            // Safety check: don't delete if it would remove ALL local files
            // This indicates a problem with the remote manifest
            if removedIds.count == localFileIds.count && !remoteFileIds.isEmpty {
                #if DEBUG
                print("⚠️ [importSVDFDelta] SAFETY: Skipping deletion of all files - manifest mismatch detected")
                #endif
            } else {
                #if DEBUG
                print("🗑️ [importSVDFDelta] Deleting \(removedIds.count) files: \(removedIds)")
                #endif
                for removedId in removedIds {
                    if let uuid = UUID(uuidString: removedId) {
                        try? await VaultStorage.shared.deleteFile(id: uuid, with: vaultKey)
                    }
                }
            }
        }

        // Import only new files
        let newIds = remoteFileIds.subtracting(localFileIds)
        let newEntries = manifest.filter { newIds.contains($0.id) && !$0.deleted }
        #if DEBUG
        print("📥 [importSVDFDelta] Importing \(newEntries.count) new files")
        #endif
        for (idx, entry) in newEntries.enumerated() {
            let file = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size, version: header.version)
            let decrypted = try CryptoEngine.decrypt(file.encryptedContent, with: shareKey)

            // Decrypt thumbnail from shared file if available
            var thumbnailData: Data? = nil
            if let encryptedThumb = file.encryptedThumbnail {
                thumbnailData = try? CryptoEngine.decrypt(encryptedThumb, with: shareKey)
            }
            // Generate thumbnail for images/videos if not provided
            if thumbnailData == nil {
                if file.mimeType.hasPrefix("image/") {
                    thumbnailData = FileUtilities.generateThumbnail(from: decrypted)
                } else if file.mimeType.hasPrefix("video/") {
                    thumbnailData = await generateVideoThumbnail(from: decrypted)
                }
            }

            _ = try await VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData,
                duration: file.duration,
                fileId: file.id  // <- Preserve original file ID from shared vault
            )

            // Map import progress to 70→100% range
            let pct = newEntries.count > 0 ? 70 + Int(Double(idx + 1) / Double(newEntries.count) * 30) : 100
            viewModel.sharedVaultUpdateProgress = (completed: pct, total: 100, message: "Importing \(idx + 1) of \(newEntries.count)...")
        }

        #if DEBUG
        print("📦 [VaultView] SVDF delta: \(newIds.count) new, \(removedIds.count) removed, \(localFileIds.intersection(remoteFileIds).count) unchanged")
        #endif
    }
    
    /// Generates a thumbnail from video data.
    private func generateVideoThumbnail(from data: Data) async -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        do {
            try data.write(to: tempURL, options: [.atomic])
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            let asset = AVAsset(url: tempURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)
            
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let uiImage = UIImage(cgImage: cgImage)
                return uiImage.jpegData(compressionQuality: 0.7)
            }
        } catch {
            // Silently fail - thumbnail generation is best-effort
        }
        
        return nil
    }

    /// Legacy v1-v3 full wipe-and-replace import.
    func importLegacyFull(data: Data, shareKey: Data, vaultKey: VaultKey, index: VaultStorage.VaultIndex) async throws {
        let sharedVault = try SharedVaultData.decode(from: data)

        // Delete all existing files
        for existingFile in index.files where !existingFile.isDeleted {
            try? await VaultStorage.shared.deleteFile(id: existingFile.fileId, with: vaultKey)
        }

        // Import all files
        let totalFiles = sharedVault.files.count
        for (idx, file) in sharedVault.files.enumerated() {
            let decrypted = try CryptoEngine.decrypt(file.encryptedContent, with: shareKey)

            // Decrypt thumbnail from shared file if available
            var thumbnailData: Data? = nil
            if let encryptedThumb = file.encryptedThumbnail {
                thumbnailData = try? CryptoEngine.decrypt(encryptedThumb, with: shareKey)
            }
            // Generate thumbnail for images/videos if not provided
            if thumbnailData == nil {
                if file.mimeType.hasPrefix("image/") {
                    thumbnailData = FileUtilities.generateThumbnail(from: decrypted)
                } else if file.mimeType.hasPrefix("video/") {
                    thumbnailData = await generateVideoThumbnail(from: decrypted)
                }
            }

            _ = try await VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData,
                duration: file.duration,
                fileId: file.id  // <- Preserve original file ID from shared vault
            )

            // Map import progress to 70→100% range
            let pct = totalFiles > 0 ? 70 + Int(Double(idx + 1) / Double(totalFiles) * 30) : 100
            viewModel.sharedVaultUpdateProgress = (completed: pct, total: 100, message: "Importing \(idx + 1) of \(totalFiles)...")
        }
    }
}
