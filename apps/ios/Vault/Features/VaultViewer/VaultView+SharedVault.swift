import AVFoundation
import SwiftUI

// MARK: - Shared Vault

extension VaultView {

    // MARK: - Shared Vault Banner

    var sharedVaultBannerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared Vault")
                        .font(.caption).fontWeight(.medium)

                    if let expires = viewModel.sharePolicy?.expiresAt {
                        Text("Expires: \(expires, style: .date)")
                            .font(.caption2).foregroundStyle(.vaultSecondaryText)
                    }
                }

                Spacer()

                if viewModel.updateAvailable {
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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            if viewModel.updateAvailable {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    Text("New files available")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
            }
        }
        .vaultBannerBackground()
    }

    // MARK: - Download Update

    func downloadUpdate() async {
        guard let key = appState.currentVaultKey,
              let vaultId = viewModel.sharedVaultId else { return }

        viewModel.isUpdating = true
        defer { viewModel.isUpdating = false }

        do {
            let index = try VaultStorage.shared.loadIndex(with: key)

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
                shareKey: shareKey
            )

            if SVDFSerializer.isSVDF(data) {
                // SVDF v4 delta import: only import new files, delete removed files
                try await importSVDFDelta(data: data, shareKey: shareKeyData, vaultKey: key, index: index)
            } else {
                // Legacy v1-v3: full wipe-and-replace
                try await importLegacyFull(data: data, shareKey: shareKeyData, vaultKey: key, index: index)
            }

            // Store the new version to avoid false "new files available"
            if let newVersion = try? await CloudKitSharingManager.shared.checkForUpdates(
                shareVaultId: vaultId, currentVersion: 0
            ) {
                var updatedIndex = try VaultStorage.shared.loadIndex(with: key)
                updatedIndex.sharedVaultVersion = newVersion
                try VaultStorage.shared.saveIndex(updatedIndex, with: key)
            }

            viewModel.updateAvailable = false
            viewModel.loadFiles()
        } catch {
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
                        try? VaultStorage.shared.deleteFile(id: uuid, with: vaultKey)
                    }
                }
            }
        }

        // Import only new files
        let newIds = remoteFileIds.subtracting(localFileIds)
        #if DEBUG
        print("📥 [importSVDFDelta] Importing \(newIds.count) new files")
        #endif
        for entry in manifest where newIds.contains(entry.id) && !entry.deleted {
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

            _ = try VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData,
                duration: file.duration
            )
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
            try? VaultStorage.shared.deleteFile(id: existingFile.fileId, with: vaultKey)
        }

        // Import all files
        for file in sharedVault.files {
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

            _ = try VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData,
                duration: file.duration
            )
        }
    }
}
