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
        guard !isImportingPendingFiles else { return }
        guard let vaultKey = appState.currentVaultKey else { return }

        isImportingPendingFiles = true
        UIApplication.shared.isIdleTimerDisabled = true

        let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey)
        let initialPendingCount = StagedImportManager.pendingImportableFileCount(for: fingerprint)
        if initialPendingCount > 0 {
            importProgress = (0, initialPendingCount)
        }

        activeImportTask?.cancel()
        activeImportTask = Task.detached(priority: .userInitiated) {
            let result = await ImportIngestor.processPendingImports(for: vaultKey) { progress in
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.importProgress = (progress.completed, progress.total)
                }
            }

            await MainActor.run {
                // Always perform cleanup, even if task was cancelled.
                self.isImportingPendingFiles = false
                self.importProgress = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }

            guard !Task.isCancelled else { return }

            let remainingImportable = StagedImportManager.pendingImportableFileCount(for: fingerprint)
            await MainActor.run {
                appState.hasPendingImports = remainingImportable > 0
                appState.pendingImportCount = remainingImportable

                if result.imported > 0 {
                    loadFiles()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    if result.failed > 0 {
                        toastMessage = .importFailed(result.failed, imported: result.imported, reason: result.failureReason)
                    } else {
                        toastMessage = .filesImported(result.imported)
                    }
                } else if result.failed > 0 {
                    // All imports failed — show error and keep banner visible for retry
                    toastMessage = .importFailed(result.failed, imported: 0, reason: result.failureReason)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                } else {
                    // No files to process
                    appState.hasPendingImports = false
                    appState.pendingImportCount = 0
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
                // Store encrypted thumbnails in cache, keep only hasThumbnail flag in items
                for entry in result.files {
                    if let encThumb = entry.encryptedThumbnail {
                        await ThumbnailCache.shared.storeEncrypted(id: entry.fileId, data: encThumb)
                    }
                }
                let items = result.files.map { entry in
                    VaultFileItem(
                        id: entry.fileId,
                        size: entry.size,
                        hasThumbnail: entry.encryptedThumbnail != nil,
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

                    // Auto-detect best filter based on vault contents
                    if !items.isEmpty && self.fileFilter == .all {
                        let hasNonMedia = items.contains { !$0.isMedia }
                        if !hasNonMedia {
                            self.fileFilter = .media
                        }
                    }

                    EmbraceManager.shared.addBreadcrumb(category: "vault.opened", data: ["fileCount": items.count])
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
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        Task.detached(priority: .userInitiated) {
            do {
                // Write camera data to temp file to avoid holding imageData + encrypted copy
                let tempInputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                try imageData.write(to: tempInputURL, options: [.atomic])

                let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
                    fileURL: tempInputURL, mimeType: "image/jpeg", mode: optimizationMode
                )
                defer {
                    if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                    try? FileManager.default.removeItem(at: tempInputURL)
                }

                let ext = mimeType == "image/heic" ? "heic" : "jpg"
                let filename = "IMG_\(Date().timeIntervalSince1970).\(ext)"
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0
                let thumbnail = FileUtilities.generateThumbnail(fromFileURL: optimizedURL)

                let fileId = try VaultStorage.shared.storeFileFromURL(
                    optimizedURL, filename: filename, mimeType: mimeType,
                    with: key, thumbnailData: thumbnail
                )
                let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: currentMasterKey ?? key) }
                if let encThumb {
                    await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
                }
                await MainActor.run {
                    self.files.append(VaultFileItem(
                        id: fileId,
                        size: fileSize,
                        hasThumbnail: encThumb != nil,
                        mimeType: mimeType,
                        filename: filename,
                        createdAt: Date()
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
                await MainActor.run {
                    self.toastMessage = .importFailed(1, imported: 0, reason: error.localizedDescription)
                }
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
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        // Cancel any existing import before starting a new one
        activeImportTask?.cancel()

        // Show progress IMMEDIATELY — before any async image loading
        importProgress = (0, count)
        UIApplication.shared.isIdleTimerDisabled = true

        activeImportTask = Task.detached(priority: .userInitiated) {
            var successCount = 0
            var failedCount = 0
            var lastErrorReason: String?
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
                        let sourceMimeType = mime.hasPrefix("video/") ? mime : "video/quicktime"

                        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
                            fileURL: tempVideoURL, mimeType: sourceMimeType, mode: optimizationMode
                        )
                        defer {
                            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                            try? FileManager.default.removeItem(at: tempVideoURL)
                        }

                        let baseFilename = provider.suggestedName.map { name -> String in
                            if (name as NSString).pathExtension.isEmpty { return name + ".\(ext)" }
                            return name
                        } ?? "VID_\(Date().timeIntervalSince1970)_\(index).\(ext)"
                        let filename = wasOptimized ? MediaOptimizer.updatedFilename(baseFilename, newMimeType: mimeType) : baseFilename

                        let metadata = await Self.generateVideoMetadata(from: optimizedURL)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

                        let fileId = try VaultStorage.shared.storeFileFromURL(
                            optimizedURL, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: metadata.thumbnail, duration: metadata.duration
                        )

                        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        if let encThumb {
                            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
                        }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: fileSize,
                                hasThumbnail: encThumb != nil, mimeType: mimeType,
                                filename: filename, createdAt: Date(), duration: metadata.duration
                            ))
                            self.importProgress = (index + 1, count)
                        }
                        successCount += 1
                    } else {
                        // Load image via UIImage → write to temp file → optimize
                        guard provider.canLoadObject(ofClass: UIImage.self) else {
                            failedCount += 1
                            lastErrorReason = "Unsupported file format"
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }

                        let image: UIImage? = await withCheckedContinuation { continuation in
                            provider.loadObject(ofClass: UIImage.self) { object, _ in
                                continuation.resume(returning: object as? UIImage)
                            }
                        }
                        guard !Task.isCancelled else { break }

                        guard let image else {
                            failedCount += 1
                            lastErrorReason = "Could not convert image"
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }

                        // Write to temp JPEG then optimize (avoids holding large Data + UIImage simultaneously)
                        let tempInputURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("jpg")
                        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
                            failedCount += 1
                            lastErrorReason = "Could not convert image"
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }
                        try jpegData.write(to: tempInputURL, options: [.atomic])

                        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
                            fileURL: tempInputURL, mimeType: "image/jpeg", mode: optimizationMode
                        )
                        defer {
                            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                            try? FileManager.default.removeItem(at: tempInputURL)
                        }

                        let ext = mimeType == "image/heic" ? "heic" : "jpg"
                        let filename = "IMG_\(Date().timeIntervalSince1970)_\(index).\(ext)"

                        let thumbnail = FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

                        guard !Task.isCancelled else { break }

                        let fileId = try VaultStorage.shared.storeFileFromURL(
                            optimizedURL, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: thumbnail
                        )
                        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        if let encThumb {
                            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
                        }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: fileSize,
                                hasThumbnail: encThumb != nil, mimeType: mimeType,
                                filename: filename, createdAt: Date()
                            ))
                            self.importProgress = (index + 1, count)
                        }
                        successCount += 1
                    }
                } catch {
                    if Task.isCancelled { break }
                    failedCount += 1
                    lastErrorReason = error.localizedDescription
                    EmbraceManager.shared.addBreadcrumb(
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
            let errorReason = lastErrorReason
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.importProgress = nil
                UIApplication.shared.isIdleTimerDisabled = false
                if failed > 0 && imported == 0 {
                    self.toastMessage = .importFailed(failed, imported: 0, reason: errorReason)
                } else if failed > 0 {
                    self.toastMessage = .importFailed(failed, imported: imported, reason: errorReason)
                } else if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
                    self.toastMessage = .milestone(milestone)
                } else {
                    self.toastMessage = .filesImported(imported)
                }
                // Switch filter so imported items are visible
                if imported > 0 {
                    let hasNonMedia = self.files.contains { !$0.isMedia }
                    if hasNonMedia && self.fileFilter == .media {
                        self.fileFilter = .all
                    } else if !hasNonMedia && self.fileFilter != .media {
                        self.fileFilter = .media
                    }
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
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        // Cancel any existing import before starting a new one
        activeImportTask?.cancel()

        // Show progress immediately on main actor before detaching
        if showProgress {
            importProgress = (0, count)
        }
        UIApplication.shared.isIdleTimerDisabled = true

        activeImportTask = Task.detached(priority: .userInitiated) {
            var successCount = 0
            var failedCount = 0
            var lastErrorReason: String?
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }
                guard url.startAccessingSecurityScopedResource() else {
                    failedCount += 1
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let originalFilename = url.lastPathComponent
                let sourceMimeType = FileUtilities.mimeType(forExtension: url.pathExtension)

                do {
                    // Optimize media files (images + videos); non-media passes through
                    let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
                        fileURL: url, mimeType: sourceMimeType, mode: optimizationMode
                    )
                    defer {
                        if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                    }

                    let filename = wasOptimized
                        ? MediaOptimizer.updatedFilename(originalFilename, newMimeType: mimeType)
                        : originalFilename

                    if mimeType.hasPrefix("video/") {
                        let metadata = await Self.generateVideoMetadata(from: optimizedURL)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

                        let fileId = try VaultStorage.shared.storeFileFromURL(
                            optimizedURL, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: metadata.thumbnail, duration: metadata.duration
                        )
                        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        if let encThumb {
                            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
                        }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: fileSize,
                                hasThumbnail: encThumb != nil, mimeType: mimeType,
                                filename: filename, createdAt: Date(), duration: metadata.duration
                            ))
                            if showProgress { self.importProgress = (index + 1, count) }
                        }
                    } else {
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0
                        let thumbnail = mimeType.hasPrefix("image/")
                            ? FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
                            : nil

                        let fileId = try VaultStorage.shared.storeFileFromURL(
                            optimizedURL, filename: filename, mimeType: mimeType,
                            with: key, thumbnailData: thumbnail
                        )
                        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                        if let encThumb {
                            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
                        }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.files.append(VaultFileItem(
                                id: fileId, size: fileSize,
                                hasThumbnail: encThumb != nil, mimeType: mimeType,
                                filename: filename, createdAt: Date()
                            ))
                            if showProgress { self.importProgress = (index + 1, count) }
                        }
                    }
                    successCount += 1
                } catch {
                    if Task.isCancelled { break }
                    failedCount += 1
                    lastErrorReason = error.localizedDescription
                    if showProgress {
                        await MainActor.run { self.importProgress = (index + 1, count) }
                    }
                }
            }

            let imported = successCount
            let failed = failedCount
            let errorReason = lastErrorReason
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.importProgress = nil
                UIApplication.shared.isIdleTimerDisabled = false
                if failed > 0 && imported == 0 {
                    self.toastMessage = .importFailed(failed, imported: 0, reason: errorReason)
                } else if failed > 0 {
                    self.toastMessage = .importFailed(failed, imported: imported, reason: errorReason)
                } else {
                    self.toastMessage = .filesImported(imported)
                }
                // Switch filter so imported files are visible
                if imported > 0 {
                    let hasNonMedia = self.files.contains { !$0.isMedia }
                    if hasNonMedia && self.fileFilter == .media {
                        self.fileFilter = .all
                    } else if !hasNonMedia && self.fileFilter != .media {
                        self.fileFilter = .media
                    }
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
