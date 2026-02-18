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

                    if let expires = sharePolicy?.expiresAt {
                        Text("Expires: \(expires, style: .date)")
                            .font(.caption2).foregroundStyle(.vaultSecondaryText)
                    }
                }

                Spacer()

                if updateAvailable {
                    Button(action: { Task { await downloadUpdate() } }) {
                        if isUpdating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Update Now")
                                .font(.caption).fontWeight(.medium)
                        }
                    }
                    .vaultProminentButtonStyle()
                    .controlSize(.mini)
                    .disabled(isUpdating)
                    .accessibilityLabel(isUpdating ? "Updating shared vault" : "Update shared vault")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            if updateAvailable {
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

    // MARK: - Shared Vault Checks

    func checkSharedVaultStatus() {
        guard let key = appState.currentVaultKey else { return }

        Task {
            do {
                var index = try VaultStorage.shared.loadIndex(with: key)

                let shared = index.isSharedVault ?? false
                await MainActor.run {
                    isSharedVault = shared
                    sharePolicy = index.sharePolicy
                    sharedVaultId = index.sharedVaultId
                }

                guard shared else { return }

                // Check expiration
                if let expires = index.sharePolicy?.expiresAt, Date() > expires {
                    await MainActor.run {
                        selfDestructMessage = "This shared vault has expired. The vault owner set an expiration date of \(expires.formatted(date: .abbreviated, time: .omitted)). All shared files have been removed."
                        showSelfDestructAlert = true
                    }
                    return
                }

                // Check view count — only increment once per unlock session
                if !hasCountedOpenThisSession {
                    let currentOpens = (index.openCount ?? 0) + 1
                    if let maxOpens = index.sharePolicy?.maxOpens, currentOpens > maxOpens {
                        await MainActor.run {
                            selfDestructMessage = "This shared vault has reached its maximum number of opens. All shared files have been removed."
                            showSelfDestructAlert = true
                        }
                        return
                    }

                    // Increment open count
                    index.openCount = currentOpens
                    try VaultStorage.shared.saveIndex(index, with: key)
                    await MainActor.run { hasCountedOpenThisSession = true }
                }

                // Check for revocation / updates
                if let vaultId = index.sharedVaultId {
                    do {
                        let currentVersion = index.sharedVaultVersion ?? 1
                        if let _ = try await CloudKitSharingManager.shared.checkForUpdates(
                            shareVaultId: vaultId, currentVersion: currentVersion
                        ) {
                            await MainActor.run {
                                updateAvailable = true
                            }
                        }
                    } catch CloudKitSharingError.revoked {
                        await MainActor.run {
                            selfDestructMessage = "The vault owner has revoked your access to this shared vault. All shared files have been removed."
                            showSelfDestructAlert = true
                        }
                    } catch {
                        // Network error - continue with cached data
                        #if DEBUG
                        print("⚠️ [VaultView] Failed to check for updates: \(error)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("❌ [VaultView] Failed to check shared vault status: \(error)")
                #endif
            }
        }
    }

    func downloadUpdate() async {
        guard let key = appState.currentVaultKey,
              let vaultId = sharedVaultId else { return }

        isUpdating = true
        defer { isUpdating = false }

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

            updateAvailable = false
            loadFiles()
        } catch {
            #if DEBUG
            print("❌ [VaultView] Failed to download update: \(error)")
            #endif
        }
    }

    /// SVDF v4 delta import: parse manifest, diff file IDs vs local, import only new files.
    func importSVDFDelta(data: Data, shareKey: Data, vaultKey: VaultKey, index: VaultStorage.VaultIndex) async throws {
        let manifest = try SVDFSerializer.parseManifest(from: data, shareKey: shareKey)
        let remoteFileIds = Set(manifest.filter { !$0.deleted }.map { $0.id })
        let localFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })

        // Delete files that were removed remotely
        let removedIds = localFileIds.subtracting(remoteFileIds)
        for removedId in removedIds {
            if let uuid = UUID(uuidString: removedId) {
                try? VaultStorage.shared.deleteFile(id: uuid, with: vaultKey)
            }
        }

        // Import only new files
        let newIds = remoteFileIds.subtracting(localFileIds)
        for entry in manifest where newIds.contains(entry.id) && !entry.deleted {
            let file = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
            let decrypted = try CryptoEngine.decrypt(file.encryptedContent, with: shareKey)

            var thumbnailData: Data? = nil
            if file.mimeType.hasPrefix("image/") {
                thumbnailData = FileUtilities.generateThumbnail(from: decrypted)
            }

            _ = try VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData
            )
        }

        #if DEBUG
        print("📦 [VaultView] SVDF delta: \(newIds.count) new, \(removedIds.count) removed, \(localFileIds.intersection(remoteFileIds).count) unchanged")
        #endif
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

            var thumbnailData: Data? = nil
            if file.mimeType.hasPrefix("image/") {
                thumbnailData = FileUtilities.generateThumbnail(from: decrypted)
            }

            _ = try VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData
            )
        }
    }

    func selfDestruct() {
        guard let key = appState.currentVaultKey else { return }

        // Delete all files and the vault index
        do {
            let index = try VaultStorage.shared.loadIndex(with: key)

            // Signal consumed to sender before deleting local data
            if let vaultId = index.sharedVaultId {
                Task {
                    try? await CloudKitSharingManager.shared.markShareConsumed(shareVaultId: vaultId)
                }
            }

            for file in index.files where !file.isDeleted {
                try? VaultStorage.shared.deleteFile(id: file.fileId, with: key)
            }
            try VaultStorage.shared.deleteVaultIndex(for: key)
        } catch {
            #if DEBUG
            print("❌ [VaultView] Self-destruct error: \(error)")
            #endif
        }

        appState.lockVault()
    }
}
