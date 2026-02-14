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
                        createdAt: entry.createdAt,
                        duration: entry.duration
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
            var failedCount = 0
            for (index, result) in results.enumerated() {
                // Stop immediately if vault was locked or switched
                guard !Task.isCancelled else { break }

                let provider = result.itemProvider
                let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

                do {
                    if isVideo {
                        // URL-based video import — never loads raw video into memory
                        let tempVideoURL = try await Self.loadVideoURL(from: provider)
                        guard !Task.isCancelled else {
                            try? FileManager.default.removeItem(at: tempVideoURL)
                            break
                        }

                        let ext = tempVideoURL.pathExtension.isEmpty ? "mov" : tempVideoURL.pathExtension
                        let mime = FileUtilities.mimeType(forExtension: ext)
                        let mimeType = mime.hasPrefix("video/") ? mime : "video/quicktime"
                        let filename = provider.suggestedName.map { name -> String in
                            if (name as NSString).pathExtension.isEmpty { return name + ".\(ext)" }
                            return name
                        } ?? "VID_\(Date().timeIntervalSince1970)_\(index).\(ext)"

                        let metadata = await Self.generateVideoMetadata(from: tempVideoURL)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempVideoURL.path)[.size] as? Int) ?? 0

                        let fileId = try VaultStorage.shared.storeFileFromURL(
                            tempVideoURL, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: metadata.thumbnail, duration: metadata.duration
                        )
                        try? FileManager.default.removeItem(at: tempVideoURL)

                        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: fileSize,
                                encryptedThumbnail: encThumb, mimeType: mimeType,
                                filename: filename, duration: metadata.duration
                            ))
                            self.importProgress = (index + 1, count)
                        }
                        successCount += 1
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

                        let thumbnail = FileUtilities.generateThumbnail(from: jpegData)
                        let filename = "IMG_\(Date().timeIntervalSince1970)_\(index).jpg"
                        let mimeType = "image/jpeg"

                        guard !Task.isCancelled else { break }

                        let fileId = try VaultStorage.shared.storeFile(
                            data: jpegData, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: thumbnail
                        )
                        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: jpegData.count,
                                encryptedThumbnail: encThumb, mimeType: mimeType,
                                filename: filename
                            ))
                            self.importProgress = (index + 1, count)
                        }
                        successCount += 1
                    }
                } catch {
                    if Task.isCancelled { break }
                    failedCount += 1
                    SentryManager.shared.addBreadcrumb(
                        category: "import.failed",
                        data: ["index": index, "isVideo": isVideo, "error": "\(error)"]
                    )
                    await MainActor.run { self.importProgress = (index + 1, count) }
                    #if DEBUG
                    print("❌ [VaultView] Failed to import item \(index): \(error)")
                    #endif
                }
            }

            let imported = successCount
            let failed = failedCount
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.importProgress = nil
                UIApplication.shared.isIdleTimerDisabled = false
                if failed > 0 && imported == 0 {
                    self.toastMessage = .importFailed(failed, imported: 0)
                } else if failed > 0 {
                    self.toastMessage = .importFailed(failed, imported: imported)
                } else if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
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

    /// Load a video from PHPicker to a temp URL without loading entire file into memory.
    /// The caller is responsible for cleaning up the returned URL.
    static func loadVideoURL(from provider: NSItemProvider) async throws -> URL {
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
                // Copy to our temp directory — provider URL is ephemeral
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate a thumbnail and capture duration from a video URL.
    static func generateVideoMetadata(from url: URL) async -> (thumbnail: Data?, duration: TimeInterval?) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        var thumbnail: Data?
        var duration: TimeInterval?

        // Capture duration
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 {
                duration = seconds
            }
        }

        // Generate thumbnail frame
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            let uiImage = UIImage(cgImage: cgImage)
            thumbnail = uiImage.jpegData(compressionQuality: 0.7)
        }

        return (thumbnail, duration)
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

                let filename = url.lastPathComponent
                let mimeType = FileUtilities.mimeType(forExtension: url.pathExtension)

                do {
                    if mimeType.hasPrefix("video/") {
                        // URL-based video import — avoids loading raw video into memory
                        let metadata = await Self.generateVideoMetadata(from: url)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

                        let fileId = try VaultStorage.shared.storeFileFromURL(
                            url, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: metadata.thumbnail, duration: metadata.duration
                        )
                        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: fileSize,
                                encryptedThumbnail: encThumb, mimeType: mimeType,
                                filename: filename, duration: metadata.duration
                            ))
                            if showProgress { self.importProgress = (index + 1, count) }
                        }
                    } else {
                        guard let data = try? Data(contentsOf: url) else { continue }
                        guard !Task.isCancelled else { break }

                        let thumbnail = mimeType.hasPrefix("image/") ? FileUtilities.generateThumbnail(from: data) : nil

                        let fileId = try VaultStorage.shared.storeFile(
                            data: data, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: thumbnail
                        )
                        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: data.count,
                                encryptedThumbnail: encThumb, mimeType: mimeType,
                                filename: filename
                            ))
                            if showProgress { self.importProgress = (index + 1, count) }
                        }
                    }
                    successCount += 1
                } catch {
                    if Task.isCancelled { break }
                    if showProgress {
                        await MainActor.run { self.importProgress = (index + 1, count) }
                    }
                }
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
