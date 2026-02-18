import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import os.log

private let vmLogger = Logger(subsystem: "app.vaultaire.ios", category: "VaultViewModel")

@MainActor
@Observable
final class VaultViewModel {

    // MARK: - Dependencies (set via configure())

    private(set) weak var appState: AppState?
    private(set) weak var subscriptionManager: SubscriptionManager?

    // MARK: - Core Data State

    var files: [VaultFileItem] = []
    var masterKey: MasterKey?
    var isLoading = true

    // MARK: - Import State

    var importProgress: (completed: Int, total: Int)?
    var activeImportTask: Task<Void, Never>?
    var activeLoadTask: Task<Void, Never>?
    var isImportingPendingFiles = false
    var pendingImport: PendingImport?

    // MARK: - Batch Edit State

    var isEditing = false
    var selectedIds: Set<UUID> = []
    var isDeleteInProgress = false
    var showingBatchDeleteConfirmation = false

    // MARK: - Export State

    var exportURLs: [URL] = []

    // MARK: - Shared Vault State

    var isSharedVault = false
    var sharePolicy: VaultStorage.SharePolicy?
    var sharedVaultId: String?
    var updateAvailable = false
    var isUpdating = false
    var hasCountedOpenThisSession = false
    var selfDestructMessage: String?
    var showSelfDestructAlert = false

    // MARK: - Filter / Sort State

    var searchText = ""
    var sortOrder: SortOrder = .dateNewest
    var fileFilter: FileFilter = FileFilter(rawValue: UserDefaults.standard.string(forKey: "vaultFileFilter") ?? FileFilter.all.rawValue) ?? .all

    // MARK: - Toast

    var toastMessage: ToastMessage?

    // MARK: - Transfer Manager

    var transferManager = BackgroundShareTransferManager.shared

    // MARK: - Visible Files (computed from observed properties)

    // MARK: - Computed

    var useDateGrouping: Bool {
        sortOrder == .dateNewest || sortOrder == .dateOldest
    }

    var fileOptimization: String = UserDefaults.standard.string(forKey: "fileOptimization") ?? "optimized"

    // MARK: - Init

    func configure(appState: AppState, subscriptionManager: SubscriptionManager) {
        self.appState = appState
        self.subscriptionManager = subscriptionManager
    }

    // MARK: - Visible Files

    func computeVisibleFiles() -> VaultView.VisibleFiles {
        var visible = files
        switch fileFilter {
        case .all:
            break
        case .media:
            visible = visible.filter {
                let mime = $0.mimeType ?? ""
                return mime.hasPrefix("image/") || mime.hasPrefix("video/")
            }
        case .documents:
            visible = visible.filter {
                let mime = $0.mimeType ?? ""
                return !mime.hasPrefix("image/") && !mime.hasPrefix("video/")
            }
        }
        if !searchText.isEmpty {
            visible = visible.filter {
                ($0.filename ?? "").localizedStandardContains(searchText)
            }
        }
        switch sortOrder {
        case .dateNewest:
            visible.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .dateOldest:
            visible.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .sizeSmallest:
            visible.sort { $0.size < $1.size }
        case .sizeLargest:
            visible.sort { $0.size > $1.size }
        case .name:
            visible.sort { ($0.filename ?? "").localizedStandardCompare($1.filename ?? "") == .orderedAscending }
        }

        let media = visible.filter { $0.isMedia }
        let documents = visible.filter { !$0.isMedia }
        let mediaIndexById = Dictionary(
            uniqueKeysWithValues: media.enumerated().map { ($1.id, $0) }
        )
        return VaultView.VisibleFiles(
            all: visible,
            media: media,
            documents: documents,
            mediaIndexById: mediaIndexById
        )
    }

    /// Persists fileFilter to UserDefaults and updates the stored property.
    func setFileFilter(_ filter: FileFilter) {
        fileFilter = filter
        UserDefaults.standard.set(filter.rawValue, forKey: "vaultFileFilter")
    }

    // MARK: - Load

    func loadVault() {
        guard appState?.currentVaultKey != nil else {
            isLoading = false
            return
        }
        loadFiles()
        checkSharedVaultStatus()
    }

    func loadFiles() {
        vmLogger.debug("loadFiles() called (current files.count=\(self.files.count), importActive=\(self.activeImportTask != nil))")

        guard let key = appState?.currentVaultKey else {
            vmLogger.warning("loadFiles(): no vault key, aborting")
            isLoading = false
            return
        }

        activeLoadTask?.cancel()
        activeLoadTask = Task.detached(priority: .userInitiated) {
            do {
                let result = try VaultStorage.shared.listFilesLightweight(with: key)
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
                    vmLogger.info("loadFiles() loaded \(items.count) files from disk (was \(self.files.count))")
                    self.masterKey = MasterKey(result.masterKey)
                    self.files = items
                    self.isLoading = false

                    // Auto-detect best filter based on vault contents
                    if !items.isEmpty {
                        let hasNonMedia = items.contains { !$0.isMedia }
                        if !hasNonMedia && self.fileFilter == .all {
                            self.setFileFilter(.media)
                        } else if hasNonMedia && self.fileFilter == .media {
                            self.setFileFilter(.all)
                        }
                    }

                    EmbraceManager.shared.addBreadcrumb(category: "vault.opened", data: ["fileCount": items.count])
                }
            } catch {
                vmLogger.error("loadFiles() failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    // Don't clear files on error - preserves in-memory state after imports
                    // If vault truly failed to load, user would see previous files or empty with error
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Selection

    func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    // MARK: - Batch Operations

    func batchDelete() {
        guard let key = appState?.currentVaultKey else { return }
        let idsToDelete = selectedIds
        let count = idsToDelete.count

        isDeleteInProgress = true
        importProgress = (0, count)
        IdleTimerManager.shared.disable()
        isEditing = false

        activeImportTask?.cancel()
        activeImportTask = Task.detached(priority: .userInitiated) {
            do {
                try VaultStorage.shared.deleteFiles(ids: idsToDelete, with: key) { deleted in
                    Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        self.importProgress = (deleted, count)
                    }
                }
            } catch {
                await MainActor.run {
                    self.toastMessage = .error("Delete failed: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.files.removeAll { idsToDelete.contains($0.id) }
                self.selectedIds.removeAll()
                self.importProgress = nil
                self.isDeleteInProgress = false
                IdleTimerManager.shared.enable()
                self.toastMessage = .filesDeleted(count)
            }

            if !Task.isCancelled {
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
                }
            }
        }
    }

    func batchExport() {
        guard let key = appState?.currentVaultKey else { return }
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
            FileUtilities.cleanupTemporaryFile(at: url)
        }
        exportURLs = []
    }

    func deleteFileById(_ id: UUID) {
        guard let key = appState?.currentVaultKey else { return }
        Task.detached(priority: .userInitiated) {
            do {
                try VaultStorage.shared.deleteFile(id: id, with: key)
                await MainActor.run {
                    if let idx = self.files.firstIndex(where: { $0.id == id }) {
                        self.files.remove(at: idx)
                    }
                    self.toastMessage = .filesDeleted(1)
                }
            } catch {
                await MainActor.run {
                    self.toastMessage = .error("Failed to delete file: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Import: Camera Capture

    func handleCapturedImage(_ imageData: Data) {
        guard !isSharedVault, let key = appState?.currentVaultKey else { return }
        let currentMasterKey = self.masterKey
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        Task.detached(priority: .userInitiated) {
            do {
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
                let thumbnail = FileUtilities.generateThumbnail(fromFileURL: optimizedURL)

                let fileId = try VaultStorage.shared.storeFileFromURL(
                    optimizedURL, filename: filename, mimeType: mimeType,
                    with: key, thumbnailData: thumbnail
                )
                let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: currentMasterKey?.rawBytes ?? key.rawBytes) }
                if let encThumb {
                    await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
                }
                await MainActor.run {
                    if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count + 1) {
                        self.toastMessage = .milestone(milestone)
                    } else {
                        self.toastMessage = .fileEncrypted()
                    }
                    self.loadFiles()
                }

                await ShareSyncManager.shared.scheduleSync(vaultKey: key)
            } catch {
                await MainActor.run {
                    self.toastMessage = .importFailed(1, imported: 0, reason: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Import: Photo Picker

    /// Returns limit info (remaining, selected) if the user hit the free plan cap, nil if import proceeds normally.
    func handleSelectedPhotos(_ results: [PHPickerResult]) -> (remaining: Int, selected: Int)? {
        guard !isSharedVault, appState?.currentVaultKey != nil else { return nil }
        guard let subscriptionManager else { return nil }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - files.count)
            if remaining == 0 {
                return (0, results.count)
            }
            if results.count > remaining {
                pendingImport = .photos(results)
                return (remaining, results.count)
            }
        }

        performPhotoImport(results)
        return nil
    }

    func performPhotoImport(_ results: [PHPickerResult]) {
        guard let key = appState?.currentVaultKey else { return }
        let encryptionKey = self.masterKey?.rawBytes ?? key.rawBytes
        let count = results.count
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        activeImportTask?.cancel()
        importProgress = (0, count)
        IdleTimerManager.shared.disable()

        activeImportTask = Task.detached(priority: .userInitiated) {
            var successCount = 0
            var failedCount = 0
            var lastErrorReason: String?
            for (index, result) in results.enumerated() {
                guard !Task.isCancelled else { break }

                let provider = result.itemProvider
                let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

                do {
                    if isVideo {
                        let tempVideoURL = try await VaultView.loadVideoURL(from: provider)
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

                        let metadata = await VaultView.generateVideoMetadata(from: optimizedURL)
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
                    print("❌ [VaultViewModel] Failed to import item \(index): \(error)")
                    #endif
                }
            }

            let imported = successCount
            let failed = failedCount
            let errorReason = lastErrorReason
            await MainActor.run {
                guard !Task.isCancelled else {
                    vmLogger.warning("Photo import task cancelled before completion (imported=\(imported), failed=\(failed))")
                    return
                }
                self.importProgress = nil
                IdleTimerManager.shared.enable()
                if failed > 0 && imported == 0 {
                    self.toastMessage = .importFailed(failed, imported: 0, reason: errorReason)
                } else if failed > 0 {
                    self.toastMessage = .importFailed(failed, imported: imported, reason: errorReason)
                } else if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
                    self.toastMessage = .milestone(milestone)
                } else {
                    self.toastMessage = .filesImported(imported)
                }
                vmLogger.info("Photo import complete: imported=\(imported), failed=\(failed), files.count=\(self.files.count)")
                // Safety net: reload from disk to ensure in-memory state matches persisted state.
                // Guards against edge cases where files were stored but in-memory array diverged.
                if imported > 0 {
                    self.loadFiles()
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
                }
            }
        }
    }

    // MARK: - Import: File Importer

    /// Returns limit info (remaining, selected) if the user hit the free plan cap, nil if import proceeds normally.
    func handleImportedFiles(_ result: Result<[URL], Error>) -> (remaining: Int, selected: Int)? {
        guard !isSharedVault, appState?.currentVaultKey != nil else { return nil }
        guard case .success(let urls) = result else { return nil }
        guard let subscriptionManager else { return nil }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - files.count)
            if remaining == 0 {
                return (0, urls.count)
            }
            if urls.count > remaining {
                pendingImport = .files(urls)
                return (remaining, urls.count)
            }
        }

        performFileImport(urls)
        return nil
    }

    func performFileImport(_ urls: [URL]) {
        guard let key = appState?.currentVaultKey else { return }
        let encryptionKey = self.masterKey?.rawBytes ?? key.rawBytes
        let count = urls.count
        let showProgress = count > 1
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        activeImportTask?.cancel()
        if showProgress {
            importProgress = (0, count)
        }
        IdleTimerManager.shared.disable()

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
                        let metadata = await VaultView.generateVideoMetadata(from: optimizedURL)
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
                guard !Task.isCancelled else {
                    vmLogger.warning("File import task cancelled before completion (imported=\(imported), failed=\(failed))")
                    return
                }
                self.importProgress = nil
                IdleTimerManager.shared.enable()
                if failed > 0 && imported == 0 {
                    self.toastMessage = .importFailed(failed, imported: 0, reason: errorReason)
                } else if failed > 0 {
                    self.toastMessage = .importFailed(failed, imported: imported, reason: errorReason)
                } else {
                    self.toastMessage = .filesImported(imported)
                }
                vmLogger.info("File import complete: imported=\(imported), failed=\(failed), files.count=\(self.files.count)")
                if imported > 0 {
                    self.loadFiles()
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
                }
            }
        }
    }

    // MARK: - Import: Pending Files

    func importPendingFiles() {
        guard !isImportingPendingFiles else { return }
        guard let vaultKey = appState?.currentVaultKey else { return }

        isImportingPendingFiles = true
        IdleTimerManager.shared.disable()

        let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey.rawBytes)
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
                self.isImportingPendingFiles = false
                self.importProgress = nil
                IdleTimerManager.shared.enable()
            }

            guard !Task.isCancelled else { return }

            let remainingImportable = StagedImportManager.pendingImportableFileCount(for: fingerprint)
            await MainActor.run {
                guard let appState = self.appState else { return }
                appState.hasPendingImports = remainingImportable > 0
                appState.pendingImportCount = remainingImportable

                if result.imported > 0 {
                    self.loadFiles()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    if result.failed > 0 {
                        self.toastMessage = .importFailed(result.failed, imported: result.imported, reason: result.failureReason)
                    } else {
                        self.toastMessage = .filesImported(result.imported)
                    }
                } else if result.failed > 0 {
                    self.toastMessage = .importFailed(result.failed, imported: 0, reason: result.failureReason)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                } else {
                    appState.hasPendingImports = false
                    appState.pendingImportCount = 0
                }
            }
        }
    }

    func proceedWithLimitedImport(limitAlertRemaining: Int) {
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

    // MARK: - Shared Vault

    func checkSharedVaultStatus() {
        guard let key = appState?.currentVaultKey else { return }

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

                if let expires = index.sharePolicy?.expiresAt, Date() > expires {
                    await MainActor.run {
                        selfDestructMessage = "This shared vault has expired. The vault owner set an expiration date of \(expires.formatted(date: .abbreviated, time: .omitted)). All shared files have been removed."
                        showSelfDestructAlert = true
                    }
                    return
                }

                if !hasCountedOpenThisSession {
                    let currentOpens = (index.openCount ?? 0) + 1
                    if let maxOpens = index.sharePolicy?.maxOpens, currentOpens > maxOpens {
                        await MainActor.run {
                            selfDestructMessage = "This shared vault has reached its maximum number of opens. All shared files have been removed."
                            showSelfDestructAlert = true
                        }
                        return
                    }

                    index.openCount = currentOpens
                    try VaultStorage.shared.saveIndex(index, with: key)
                    await MainActor.run { hasCountedOpenThisSession = true }
                }

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
                        #if DEBUG
                        print("⚠️ [VaultViewModel] Failed to check for updates: \(error)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("❌ [VaultViewModel] Failed to check shared vault status: \(error)")
                #endif
            }
        }
    }

    func selfDestruct() {
        guard let key = appState?.currentVaultKey else { return }

        do {
            let index = try VaultStorage.shared.loadIndex(with: key)

            if let vaultId = index.sharedVaultId {
                Task {
                    do {
                        try await CloudKitSharingManager.shared.markShareConsumed(shareVaultId: vaultId)
                    } catch {
                        vmLogger.error("Failed to mark share consumed during self-destruct: \(error.localizedDescription, privacy: .public)")
                        EmbraceManager.shared.captureError(error, context: ["action": "markShareConsumed", "vaultId": vaultId])
                    }
                }
            }

            for file in index.files where !file.isDeleted {
                do {
                    try VaultStorage.shared.deleteFile(id: file.fileId, with: key)
                } catch {
                    vmLogger.error("Failed to delete file during self-destruct \(file.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    EmbraceManager.shared.captureError(error, context: ["action": "deleteFile", "fileId": file.fileId])
                }
            }
            try VaultStorage.shared.deleteVaultIndex(for: key)
        } catch {
            vmLogger.error("Self-destruct error: \(error.localizedDescription, privacy: .public)")
            EmbraceManager.shared.captureError(error, context: ["action": "selfDestruct"])
        }

        appState?.lockVault()
    }

    // MARK: - Vault Key Change

    func handleVaultKeyChange(oldKey: VaultKey?, newKey: VaultKey?) {
        if activeImportTask != nil {
            vmLogger.warning("Vault key changed during active import — cancelling import (files.count=\(self.files.count))")
        }
        activeImportTask?.cancel()
        activeImportTask = nil
        importProgress = nil
        isDeleteInProgress = false
        IdleTimerManager.shared.enable()

        if oldKey != newKey {
            vmLogger.info("Vault key changed: clearing files (had \(self.files.count) files)")
            files = []
            masterKey = nil
            Task { await ThumbnailCache.shared.clear() }
            isLoading = false
            isSharedVault = false
        }

        if newKey != nil {
            ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "vault_key_changed")
        }
    }

    // MARK: - Filter Helpers

    func updateFilterAfterImport() {
        let hasNonMedia = files.contains { !$0.isMedia }
        if hasNonMedia && fileFilter == .media {
            setFileFilter(.all)
        } else if !hasNonMedia && fileFilter != .media {
            setFileFilter(.media)
        }
    }
}
