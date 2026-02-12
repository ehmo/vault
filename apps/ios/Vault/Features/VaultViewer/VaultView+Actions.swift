import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Actions

extension VaultView {

    func lockVault() {
        appState.lockVault()
    }

    func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func batchDelete() {
        guard let key = appState.currentVaultKey else { return }
        let idsToDelete = selectedIds
        let count = idsToDelete.count

        // Show progress and prevent sleep
        isDeleteInProgress = true
        importProgress = (0, count)
        UIApplication.shared.isIdleTimerDisabled = true
        isEditing = false

        activeImportTask?.cancel()
        activeImportTask = Task.detached(priority: .userInitiated) {
            try? VaultStorage.shared.deleteFiles(ids: idsToDelete, with: key) { deleted in
                Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    self.importProgress = (deleted, count)
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                files.removeAll { idsToDelete.contains($0.id) }
                selectedIds.removeAll()
                importProgress = nil
                isDeleteInProgress = false
                UIApplication.shared.isIdleTimerDisabled = false
                toastMessage = .filesDeleted(count)
            }

            if !Task.isCancelled {
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
                }
            }
        }
    }

    func batchExport() {
        guard let key = appState.currentVaultKey else { return }
        let idsToExport = selectedIds
        let filesList = files

        Task.detached(priority: .userInitiated) {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            var urls: [URL] = []

            for id in idsToExport {
                guard !Task.isCancelled else { break }
                guard let result = try? VaultStorage.shared.retrieveFile(id: id, with: key) else { continue }
                let file = filesList.first { $0.id == id }
                let filename = file?.filename ?? "Export_\(id.uuidString)"
                let url = tempDir.appendingPathComponent(filename)
                try? result.content.write(to: url, options: [.atomic])
                urls.append(url)
            }

            let finalizedURLs = urls

            await MainActor.run { [finalizedURLs] in
                guard !Task.isCancelled else { return }
                self.exportURLs = finalizedURLs
            }
        }
    }

    func cleanupExportFiles() {
        for url in exportURLs {
            try? FileManager.default.removeItem(at: url)
        }
        exportURLs = []
    }

    func deleteFileById(_ id: UUID) {
        guard let key = appState.currentVaultKey else { return }
        Task.detached(priority: .userInitiated) {
            try? VaultStorage.shared.deleteFile(id: id, with: key)
            await MainActor.run {
                if let idx = self.files.firstIndex(where: { $0.id == id }) {
                    self.files.remove(at: idx)
                }
                self.toastMessage = .filesDeleted(1)
            }
        }
    }

    /// Loads the vault index once and uses it for both file listing and shared-vault checks.
    func loadVault() {
        guard appState.currentVaultKey != nil else {
            isLoading = false
            return
        }

        // File listing runs off main thread; shared vault check can run concurrently
        loadFiles()
        checkSharedVaultStatus()
    }

    func importPendingFiles() {
        guard let vaultKey = appState.currentVaultKey else { return }
        Task {
            let result = await ImportIngestor.processPendingImports(for: vaultKey)
            await MainActor.run {
                appState.hasPendingImports = false
                appState.pendingImportCount = 0
                if result.imported > 0 {
                    loadFiles()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }
    }

    func loadFiles() {
        #if DEBUG
        print("📂 [VaultView] loadFiles() called")
        #endif

        guard let key = appState.currentVaultKey else {
            isLoading = false
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                let result = try VaultStorage.shared.listFilesLightweight(with: key)
                let items = result.files.map { entry in
                    VaultFileItem(
                        id: entry.fileId,
                        size: entry.size,
                        encryptedThumbnail: entry.encryptedThumbnail,
                        mimeType: entry.mimeType,
                        filename: entry.filename,
                        createdAt: entry.createdAt
                    )
                }
                await MainActor.run {
                    self.masterKey = result.masterKey
                    self.files = items
                    self.isLoading = false
                    SentryManager.shared.addBreadcrumb(category: "vault.opened", data: ["fileCount": items.count])
                }
            } catch {
                #if DEBUG
                print("❌ [VaultView] Error loading files: \(error)")
                #endif
                await MainActor.run {
                    self.files = []
                    self.isLoading = false
                }
            }
        }
    }

    func handleCapturedImage(_ imageData: Data) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }
        let currentMasterKey = self.masterKey

        Task.detached(priority: .userInitiated) {
            do {
                let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                let thumbnail = FileUtilities.generateThumbnail(from: imageData)
                let fileId = try VaultStorage.shared.storeFile(
                    data: imageData,
                    filename: filename,
                    mimeType: "image/jpeg",
                    with: key,
                    thumbnailData: thumbnail
                )
                // Re-encrypt thumbnail for in-memory model (matches what's stored in index)
                let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: currentMasterKey ?? key) }
                await MainActor.run { [encThumb] in
                    self.files.append(VaultFileItem(
                        id: fileId,
                        size: imageData.count,
                        encryptedThumbnail: encThumb,
                        mimeType: "image/jpeg",
                        filename: filename
                    ))
                    if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
                        self.toastMessage = .milestone(milestone)
                    } else {
                        self.toastMessage = .fileEncrypted()
                    }
                }

                // Trigger sync if sharing
                await ShareSyncManager.shared.scheduleSync(vaultKey: key)
            } catch {
                // Handle error silently
            }
        }
    }

    func handleSelectedPhotos(_ results: [PHPickerResult]) {
        guard !isSharedVault, appState.currentVaultKey != nil else { return }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - files.count)
            if remaining == 0 {
                showingPaywall = true
                return
            }
            if results.count > remaining {
                pendingImport = .photos(results)
                limitAlertSelected = results.count
                limitAlertRemaining = remaining
                showingLimitAlert = true
                return
            }
        }

        performPhotoImport(results)
    }

    func performPhotoImport(_ results: [PHPickerResult]) {
        guard let key = appState.currentVaultKey else { return }
        let encryptionKey = self.masterKey ?? key
        let count = results.count

        // Cancel any existing import before starting a new one
        activeImportTask?.cancel()

        // Show progress IMMEDIATELY — before any async image loading
        importProgress = (0, count)
        UIApplication.shared.isIdleTimerDisabled = true

        activeImportTask = Task.detached(priority: .userInitiated) {
            var successCount = 0
            for (index, result) in results.enumerated() {
                // Stop immediately if vault was locked or switched
                guard !Task.isCancelled else { break }

                let provider = result.itemProvider
                let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

                do {
                    let (data, filename, mimeType, thumbnail): (Data, String, String, Data?)

                    if isVideo {
                        // Load video via file representation
                        let videoData = try await Self.loadVideoData(from: provider)
                        guard !Task.isCancelled else { break }
                        let ext = provider.suggestedName.flatMap { URL(string: $0)?.pathExtension } ?? "mov"
                        let mime = FileUtilities.mimeType(forExtension: ext)
                        let thumbData = await Self.generateVideoThumbnail(from: videoData)

                        data = videoData
                        filename = provider.suggestedName ?? "VID_\(Date().timeIntervalSince1970)_\(index).\(ext)"
                        mimeType = mime.hasPrefix("video/") ? mime : "video/quicktime"
                        thumbnail = thumbData
                    } else {
                        // Load image via UIImage
                        guard provider.canLoadObject(ofClass: UIImage.self) else {
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }

                        let image: UIImage? = await withCheckedContinuation { continuation in
                            provider.loadObject(ofClass: UIImage.self) { object, _ in
                                continuation.resume(returning: object as? UIImage)
                            }
                        }
                        guard !Task.isCancelled else { break }

                        guard let image, let jpegData = image.jpegData(compressionQuality: 0.8) else {
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }

                        data = jpegData
                        filename = "IMG_\(Date().timeIntervalSince1970)_\(index).jpg"
                        mimeType = "image/jpeg"
                        thumbnail = FileUtilities.generateThumbnail(from: jpegData)
                    }

                    guard !Task.isCancelled else { break }

                    let fileId = try VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: mimeType,
                        with: key,
                        thumbnailData: thumbnail
                    )
                    let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.files.append(VaultFileItem(
                            id: fileId,
                            size: data.count,
                            encryptedThumbnail: encThumb,
                            mimeType: mimeType,
                            filename: filename
                        ))
                        self.importProgress = (index + 1, count)
                    }
                    successCount += 1
                } catch {
                    if Task.isCancelled { break }
                    await MainActor.run { self.importProgress = (index + 1, count) }
                    #if DEBUG
                    print("❌ [VaultView] Failed to import item \(index): \(error)")
                    #endif
                }
            }

            let imported = successCount
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.importProgress = nil
                UIApplication.shared.isIdleTimerDisabled = false
                if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
                    self.toastMessage = .milestone(milestone)
                } else {
                    self.toastMessage = .filesImported(imported)
                }
                // Switch to Media filter so imported photos/videos are visible
                if imported > 0 && self.fileFilter == .documents {
                    self.fileFilter = .media
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
                }
            }
        }
    }

    /// Load video data from a PHPicker item provider
    static func loadVideoData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                // Must copy data before the callback returns — the URL is temporary
                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate a thumbnail from video data using AVAssetImageGenerator
    static func generateVideoThumbnail(from data: Data) async -> Data? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try data.write(to: tempURL)
            let asset = AVAsset(url: tempURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            return nil
        }
    }

    func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard !isSharedVault, appState.currentVaultKey != nil else { return }
        guard case .success(let urls) = result else { return }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - files.count)
            if remaining == 0 {
                showingPaywall = true
                return
            }
            if urls.count > remaining {
                pendingImport = .files(urls)
                limitAlertSelected = urls.count
                limitAlertRemaining = remaining
                showingLimitAlert = true
                return
            }
        }

        performFileImport(urls)
    }

    func performFileImport(_ urls: [URL]) {
        guard let key = appState.currentVaultKey else { return }
        let encryptionKey = self.masterKey ?? key
        let count = urls.count
        let showProgress = count > 1

        // Cancel any existing import before starting a new one
        activeImportTask?.cancel()

        // Show progress immediately on main actor before detaching
        if showProgress {
            importProgress = (0, count)
        }
        UIApplication.shared.isIdleTimerDisabled = true

        activeImportTask = Task.detached(priority: .userInitiated) {
            var successCount = 0
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else { continue }
                guard !Task.isCancelled else { break }

                let filename = url.lastPathComponent
                let mimeType = FileUtilities.mimeType(forExtension: url.pathExtension)
                let thumbnail = mimeType.hasPrefix("image/") ? FileUtilities.generateThumbnail(from: data) : nil

                guard let fileId = try? VaultStorage.shared.storeFile(
                    data: data,
                    filename: filename,
                    mimeType: mimeType,
                    with: key,
                    thumbnailData: thumbnail
                ) else { continue }

                let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.files.append(VaultFileItem(
                        id: fileId,
                        size: data.count,
                        encryptedThumbnail: encThumb,
                        mimeType: mimeType,
                        filename: filename
                    ))
                    if showProgress {
                        self.importProgress = (index + 1, count)
                    }
                }
                successCount += 1
            }

            let imported = successCount
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.importProgress = nil
                UIApplication.shared.isIdleTimerDisabled = false
                self.toastMessage = .filesImported(imported)
                // Switch to All filter so imported files are visible
                if imported > 0 && self.fileFilter != .all {
                    self.fileFilter = .all
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
                }
            }
        }
    }

    func proceedWithLimitedImport() {
        guard let pending = pendingImport else { return }
        let remaining = limitAlertRemaining
        pendingImport = nil

        switch pending {
        case .photos(let results):
            performPhotoImport(Array(results.prefix(remaining)))
        case .files(let urls):
            performFileImport(Array(urls.prefix(remaining)))
        }
    }
}
