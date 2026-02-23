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
    private var importGeneration = 0
    var activeLoadTask: Task<Void, Never>?
    var isImportingPendingFiles = false
    var pendingImport: PendingImport?

    var isImporting: Bool {
        importProgress != nil || isImportingPendingFiles
    }

    /// Unified progress for all file operations (import, delete, shared vault download).
    var activeOperationProgress: (completed: Int, total: Int, message: String)? {
        if let p = importProgress {
            let msg = isDeleteInProgress
                ? "Deleting \(p.completed) of \(p.total)..."
                : "Importing \(p.completed) of \(p.total)..."
            return (completed: p.completed, total: p.total, message: msg)
        }
        if case .importing = transferManager.status {
            let p = max(0, min(transferManager.displayProgress, 100))
            return (completed: p, total: 100, message: transferManager.currentMessage)
        }
        if let p = sharedVaultUpdateProgress {
            return p
        }
        return nil
    }

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
    var sharedVaultUpdateProgress: (completed: Int, total: Int, message: String)?
    var hasCountedOpenThisSession = false
    var sharedVaultOpenCount: Int = 0
    var selfDestructMessage: String?
    var showSelfDestructAlert = false

    // MARK: - Filter / Sort State

    var searchText = ""
    var sortOrder: SortOrder = .dateNewest
    var fileFilter: FileFilter = FileFilter(rawValue: UserDefaults.standard.string(forKey: "vaultFileFilter") ?? FileFilter.all.rawValue) ?? .all

    // MARK: - Toast

    var toastMessage: ToastMessage?

    // MARK: - Transfer Manager

    var transferManager = ShareImportManager.shared

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
            media.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
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
                let rawName = file?.filename ?? "Export_\(id.uuidString)"
                let filename = FileUtilities.filenameWithExtension(rawName, mimeType: file?.mimeType)
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

    // MARK: - Cancel Operation

    /// Cancels the currently running operation (import, delete, or shared vault download).
    func cancelCurrentOperation() {
        vmLogger.info("User requested cancellation of current operation")

        // Cancel active import/delete task
        if activeImportTask != nil {
            activeImportTask?.cancel()
            activeImportTask = nil
            importProgress = nil
            isDeleteInProgress = false
            IdleTimerManager.shared.enable()
        }

        // Cancel shared vault import
        if case .importing = transferManager.status {
            transferManager.cancel()
        }

        // Cancel shared vault update
        if sharedVaultUpdateProgress != nil {
            // The shared vault update will check isUpdating flag and cancel itself
            isUpdating = false
            sharedVaultUpdateProgress = nil
        }
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
                
                // Trigger sync for shared vaults after deletion
                await MainActor.run {
                    ShareSyncManager.shared.scheduleSync(vaultKey: key)
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

                EmbraceManager.shared.trackFeatureUsage("camera_capture", context: [
                    "optimized": String(wasOptimized),
                    "mime_type": mimeType
                ])

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
        vmLogger.info("📸 handleSelectedPhotos called with \(results.count) results")
        guard !isSharedVault, appState?.currentVaultKey != nil else {
            vmLogger.warning("❌ handleSelectedPhotos: guard failed - isSharedVault=\(self.isSharedVault), hasKey=\(self.appState?.currentVaultKey != nil)")
            return nil
        }
        guard let subscriptionManager else {
            vmLogger.warning("❌ handleSelectedPhotos: no subscriptionManager")
            return nil
        }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - self.files.count)
            vmLogger.info("💰 Free tier check: remaining=\(remaining), files.count=\(self.files.count)")
            if remaining == 0 {
                return (0, results.count)
            }
            if results.count > remaining {
                pendingImport = .photos(results)
                return (remaining, results.count)
            }
        }

        vmLogger.info("✅ Proceeding with photo import of \(results.count) photos")
        performPhotoImport(results)
        return nil
    }

    func performPhotoImport(_ results: [PHPickerResult]) {
        vmLogger.info("performPhotoImport START with \(results.count) photos")
        guard let key = appState?.currentVaultKey else {
            vmLogger.error("performPhotoImport: no vault key")
            return
        }
        let encryptionKey = self.masterKey?.rawBytes ?? key.rawBytes
        let count = results.count
        let optimizationMode = MediaOptimizer.Mode(rawValue: fileOptimization) ?? .optimized

        activeImportTask?.cancel()
        importGeneration += 1
        let myGeneration = importGeneration
        importProgress = (0, count)
        IdleTimerManager.shared.disable()

        // Separate videos and images for prioritized parallel processing:
        // 2 video-priority workers + 1 image worker = 3 parallel workers
        // Workers steal from the other queue when their primary queue is drained.
        var videoWork: [ParallelImporter.PickerWorkItem] = []
        var imageWork: [ParallelImporter.PickerWorkItem] = []

        for (index, result) in results.enumerated() {
            let isVideo = result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            let item = ParallelImporter.PickerWorkItem(originalIndex: index, provider: result.itemProvider)
            if isVideo { videoWork.append(item) } else { imageWork.append(item) }
        }

        let videoWorkerCount = videoWork.isEmpty ? 0 : 2
        let imageWorkerCount = videoWork.isEmpty ? 3 : 1
        vmLogger.info("Import: \(videoWork.count) videos, \(imageWork.count) images — \(videoWorkerCount) video + \(imageWorkerCount) image workers")

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        activeImportTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Launch parallel workers off MainActor
            let workerTask = Task.detached(priority: .userInitiated) {
                await ParallelImporter.runPhotoImport(
                    videoWork: videoWork,
                    imageWork: imageWork,
                    videoWorkerCount: videoWorkerCount,
                    imageWorkerCount: imageWorkerCount,
                    config: .init(key: key, encryptionKey: encryptionKey, optimizationMode: optimizationMode),
                    continuation: continuation
                )
                continuation.finish()
            }

            // Consume events on MainActor for real-time UI updates
            var successCount = 0
            var failedCount = 0
            var lastErrorReason: String?

            for await event in stream {
                guard !Task.isCancelled else { break }

                if case .imported(let file) = event {
                    successCount += 1
                    self.files.append(file)
                } else if case .failed(let reason) = event {
                    failedCount += 1
                    if let reason { lastErrorReason = reason }
                }
                self.importProgress = (successCount + failedCount, count)
            }

            // Cancel workers if we were cancelled
            if Task.isCancelled {
                workerTask.cancel()
                vmLogger.warning("Photo import cancelled (imported=\(successCount), failed=\(failedCount))")
            }

            // Only clean up state if we're still the current import — a newer import
            // may have already set its own importProgress and disabled IdleTimerManager
            guard self.importGeneration == myGeneration else { return }

            self.importProgress = nil
            IdleTimerManager.shared.enable()

            guard !Task.isCancelled else { return }

            vmLogger.info("Import complete — success: \(successCount), failed: \(failedCount), files.count: \(self.files.count)")

            if failedCount > 0 && successCount == 0 {
                self.toastMessage = .importFailed(failedCount, imported: 0, reason: lastErrorReason)
            } else if failedCount > 0 {
                self.toastMessage = .importFailed(failedCount, imported: successCount, reason: lastErrorReason)
            } else if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
                self.toastMessage = .milestone(milestone)
            } else {
                self.toastMessage = .filesImported(successCount)
            }

            if successCount > 0 {
                self.updateFilterAfterImport()
                ShareSyncManager.shared.scheduleSync(vaultKey: key)
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
        importGeneration += 1
        let myGeneration = importGeneration
        if showProgress { importProgress = (0, count) }
        IdleTimerManager.shared.disable()

        // Separate videos and non-videos for prioritized parallel processing:
        // 2 video-priority workers + 1 other worker = 3 parallel workers
        // Workers steal from the other queue when their primary queue is drained.
        var videoWork: [ParallelImporter.URLWorkItem] = []
        var otherWork: [ParallelImporter.URLWorkItem] = []

        for (index, url) in urls.enumerated() {
            let mime = FileUtilities.mimeType(forExtension: url.pathExtension)
            let item = ParallelImporter.URLWorkItem(originalIndex: index, url: url)
            if mime.hasPrefix("video/") { videoWork.append(item) } else { otherWork.append(item) }
        }

        let videoWorkerCount = videoWork.isEmpty ? 0 : 2
        let otherWorkerCount = videoWork.isEmpty ? 3 : 1
        vmLogger.info("File import: \(videoWork.count) videos, \(otherWork.count) other — \(videoWorkerCount + otherWorkerCount) workers")

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        activeImportTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let workerTask = Task.detached(priority: .userInitiated) {
                await ParallelImporter.runFileImport(
                    videoWork: videoWork,
                    otherWork: otherWork,
                    videoWorkerCount: videoWorkerCount,
                    otherWorkerCount: otherWorkerCount,
                    config: .init(key: key, encryptionKey: encryptionKey, optimizationMode: optimizationMode),
                    continuation: continuation
                )
                continuation.finish()
            }

            var successCount = 0
            var failedCount = 0
            var lastErrorReason: String?

            for await event in stream {
                guard !Task.isCancelled else { break }

                if case .imported(let file) = event {
                    successCount += 1
                    self.files.append(file)
                } else if case .failed(let reason) = event {
                    failedCount += 1
                    if let reason { lastErrorReason = reason }
                }
                if showProgress {
                    self.importProgress = (successCount + failedCount, count)
                }
            }

            if Task.isCancelled {
                workerTask.cancel()
                vmLogger.warning("File import cancelled (imported=\(successCount), failed=\(failedCount))")
            }

            // Only clean up state if we're still the current import
            guard self.importGeneration == myGeneration else { return }

            self.importProgress = nil
            IdleTimerManager.shared.enable()

            guard !Task.isCancelled else { return }

            if failedCount > 0 && successCount == 0 {
                self.toastMessage = .importFailed(failedCount, imported: 0, reason: lastErrorReason)
            } else if failedCount > 0 {
                self.toastMessage = .importFailed(failedCount, imported: successCount, reason: lastErrorReason)
            } else {
                self.toastMessage = .filesImported(successCount)
            }

            vmLogger.info("File import complete: imported=\(successCount), failed=\(failedCount)")
            if successCount > 0 {
                self.updateFilterAfterImport()
                ShareSyncManager.shared.scheduleSync(vaultKey: key)
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

        if case .photos(let results) = pending {
            performPhotoImport(Array(results.prefix(remaining)))
        } else if case .files(let urls) = pending {
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
                    sharedVaultOpenCount = index.openCount ?? 0
                }

                guard shared else { return }

                EmbraceManager.shared.trackFeatureUsage("shared_vault_opened", context: [
                    "vault_id": sharedVaultId ?? "unknown",
                    "has_expiration": String(index.sharePolicy?.expiresAt != nil),
                    "has_max_opens": String(index.sharePolicy?.maxOpens != nil)
                ])

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
                    await MainActor.run {
                        hasCountedOpenThisSession = true
                        sharedVaultOpenCount = currentOpens
                    }
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
        if sharedVaultUpdateProgress != nil {
            sharedVaultUpdateProgress = nil
            isUpdating = false
        }
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
