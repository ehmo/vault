import UIKit
import AVFoundation
import UniformTypeIdentifiers
import OSLog

private let parallelImporterLogger = Logger(subsystem: "app.vaultaire.ios", category: "ParallelImporter")

/// Runs import work off MainActor with dedicated worker tasks.
/// 2 video-priority workers + 2 image-priority workers = 4 parallel workers.
/// Workers drain their primary queue first, then steal from the other queue.
/// Results stream back to MainActor via AsyncStream for real-time UI updates.
enum ParallelImporter {

    // MARK: - Work Items

    /// Photo picker work item — wraps NSItemProvider (thread-safe by design)
    struct PickerWorkItem: @unchecked Sendable {
        let originalIndex: Int
        let provider: NSItemProvider
    }

    /// File/document picker work item
    struct URLWorkItem: @unchecked Sendable {
        let originalIndex: Int
        let url: URL
    }

    // MARK: - Config

    /// Groups common import parameters to reduce function parameter count.
    struct ImportConfig: Sendable {
        let key: VaultKey
        let encryptionKey: Data
        let optimizationMode: MediaOptimizer.Mode
    }

    // MARK: - Events

    enum ImportEvent: Sendable {
        case imported(VaultFileItem)
        case failed(reason: String?)
    }

    // MARK: - Thread-Safe Queue

    actor Queue<T: Sendable> {
        private var items: [T]
        private var idx = 0

        init(_ items: [T]) { self.items = items }

        func next() -> T? {
            guard idx < items.count else { return nil }
            let item = items[idx]
            idx += 1
            return item
        }

        func remainingCount() -> Int {
            return items.count - idx
        }
    }

    // MARK: - Generic Worker Runner

    /// Runs concurrent workers consuming from queues, streaming results via continuation.
    /// Each (queue, workerCount) pair spawns `workerCount` tasks pulling from that queue.
    static func runWorkers<Work: Sendable>(
        queues: [(Queue<Work>, Int)],
        process: @escaping @Sendable (Work) async throws -> VaultFileItem?,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for (queue, count) in queues {
                for _ in 0..<count {
                    group.addTask {
                        while let item = await queue.next() {
                            guard !Task.isCancelled else { return }
                            do {
                                if let file = try await process(item) {
                                    continuation.yield(.imported(file))
                                }
                            } catch {
                                continuation.yield(.failed(reason: error.localizedDescription))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo Picker Import

    static func runPhotoImport(
        videoWork: [PickerWorkItem],
        imageWork: [PickerWorkItem],
        videoWorkerCount: Int,
        imageWorkerCount: Int,
        config: ImportConfig,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let videoQueue = Queue(videoWork)
        let imageQueue = Queue(imageWork)

        await withTaskGroup(of: Void.self) { group in
            // Video-priority workers: drain videos first, then steal from image queue
            for _ in 0..<videoWorkerCount {
                group.addTask {
                    while let item = await videoQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importVideo(item: item, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                    // Steal remaining images
                    while let item = await imageQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importImage(item: item, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                }
            }

            // Image-priority workers: drain images first, then steal from video queue
            for _ in 0..<imageWorkerCount {
                group.addTask {
                    while let item = await imageQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importImage(item: item, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                    // Steal remaining videos
                    while let item = await videoQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importVideo(item: item, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                }
            }
        }
    }

    // MARK: - File Import

    static func runFileImport(
        videoWork: [URLWorkItem],
        otherWork: [URLWorkItem],
        videoWorkerCount: Int,
        otherWorkerCount: Int,
        config: ImportConfig,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let videoQueue = Queue(videoWork)
        let otherQueue = Queue(otherWork)

        await withTaskGroup(of: Void.self) { group in
            // Video-priority workers: drain videos first, then steal from other queue
            for _ in 0..<videoWorkerCount {
                group.addTask {
                    while let item = await videoQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importFileFromURL(url: item.url, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                    // Steal remaining non-video files
                    while let item = await otherQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importFileFromURL(url: item.url, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                }
            }

            // Other-priority workers: drain other files first, then steal from video queue
            for _ in 0..<otherWorkerCount {
                group.addTask {
                    while let item = await otherQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importFileFromURL(url: item.url, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                    // Steal remaining videos
                    while let item = await videoQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importFileFromURL(url: item.url, key: config.key, encryptionKey: config.encryptionKey, optimizationMode: config.optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Individual Import Operations (run off MainActor)

    private static func importVideo(
        item: PickerWorkItem,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode
    ) async throws -> VaultFileItem? {
        guard !Task.isCancelled else { return nil }

        let tempVideoURL = try await loadVideoURL(from: item.provider)
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        guard !Task.isCancelled else { return nil }

        let ext = tempVideoURL.pathExtension.isEmpty ? "mov" : tempVideoURL.pathExtension
        let mime = FileUtilities.mimeType(forExtension: ext)
        let sourceMimeType = mime.hasPrefix("video/") ? mime : "video/quicktime"

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: tempVideoURL, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) }
        }

        let baseFilename = item.provider.suggestedName.map { name -> String in
            if (name as NSString).pathExtension.isEmpty { return name + ".\(ext)" }
            return name
        } ?? "VID_\(Date().timeIntervalSince1970)_\(item.originalIndex).\(ext)"
        let filename = result.wasOptimized ? MediaOptimizer.updatedFilename(baseFilename, newMimeType: result.mimeType) : baseFilename

        let metadata = await generateVideoMetadata(from: result.url, knownDuration: result.duration, knownCreationDate: result.creationDate)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int) ?? 0

        let fileId = try await VaultStorage.shared.storeFileFromURL(
            result.url, filename: filename, mimeType: result.mimeType,
            with: key, options: FileStoreOptions(thumbnailData: metadata.thumbnail, duration: metadata.duration, originalDate: metadata.creationDate)
        )

        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
        if let encThumb {
            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
        }

        return VaultFileItem(
            id: fileId, size: fileSize,
            hasThumbnail: encThumb != nil, mimeType: result.mimeType,
            filename: filename, createdAt: Date(), duration: metadata.duration,
            originalDate: metadata.creationDate
        )
    }

    private static func importImage(
        item: PickerWorkItem,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode
    ) async throws -> VaultFileItem? {
        guard !Task.isCancelled else { return nil }

        // Load image via file representation to preserve EXIF data for original date extraction
        let tempImageURL = try await loadImageURL(from: item.provider)
        defer { try? FileManager.default.removeItem(at: tempImageURL) }

        // Extract EXIF creation date before any conversion
        let originalDate = FileUtilities.extractImageCreationDate(from: tempImageURL)

        guard !Task.isCancelled else { return nil }

        // Pass source file directly to MediaOptimizer — it uses CGImageSource which handles
        // any image format natively. Avoids the old UIImage → jpegData → disk → re-decode path
        // that doubled CPU work and peak memory per image.
        // Fall back to image/jpeg for uncommon formats (WebP, TIFF, BMP, DNG, etc.) where
        // FileUtilities returns application/octet-stream — we know it's an image from PHPicker.
        let detectedMime = FileUtilities.mimeType(forExtension: tempImageURL.pathExtension)
        let sourceMimeType = detectedMime.hasPrefix("image/") ? detectedMime : "image/jpeg"
        let result = try await MediaOptimizer.shared.optimize(
            fileURL: tempImageURL, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) }
        }

        let ext: String
        if result.mimeType == "image/heic" {
            ext = "heic"
        } else {
            let sourceExt = tempImageURL.pathExtension.lowercased()
            ext = sourceExt.isEmpty ? "jpg" : sourceExt
        }
        let filename = "IMG_\(Date().timeIntervalSince1970)_\(item.originalIndex).\(ext)"

        // Use optimizer's thumbnail if available (generated from in-memory CGImage),
        // otherwise fall back to re-decoding from disk
        let thumbnail: Data? = result.thumbnailData ?? autoreleasepool {
            FileUtilities.generateThumbnail(fromFileURL: result.url)
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int) ?? 0

        let fileId = try await VaultStorage.shared.storeFileFromURL(
            result.url, filename: filename, mimeType: result.mimeType,
            with: key, thumbnailData: thumbnail, originalDate: originalDate
        )

        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
        if let encThumb {
            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
        }

        return VaultFileItem(
            id: fileId, size: fileSize,
            hasThumbnail: encThumb != nil, mimeType: result.mimeType,
            filename: filename, createdAt: Date(), originalDate: originalDate
        )
    }

    private static func importFileFromURL(
        url: URL,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode
    ) async throws -> VaultFileItem? {
        guard !Task.isCancelled else { return nil }

        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let originalFilename = url.lastPathComponent
        let sourceMimeType = FileUtilities.mimeType(forExtension: url.pathExtension)

        let result = try await MediaOptimizer.shared.optimize(
            fileURL: url, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if result.wasOptimized { try? FileManager.default.removeItem(at: result.url) }
        }

        let filename = result.wasOptimized
            ? MediaOptimizer.updatedFilename(originalFilename, newMimeType: result.mimeType)
            : originalFilename

        // Extract original date from the source file's filesystem creation date
        let resourceOriginalDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        if result.mimeType.hasPrefix("video/") {
            let metadata = await generateVideoMetadata(from: result.url, knownDuration: result.duration, knownCreationDate: result.creationDate)
            let originalDate = metadata.creationDate ?? resourceOriginalDate
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int) ?? 0

            let fileId = try await VaultStorage.shared.storeFileFromURL(
                result.url, filename: filename, mimeType: result.mimeType,
                with: key, options: FileStoreOptions(thumbnailData: metadata.thumbnail, duration: metadata.duration, originalDate: originalDate)
            )

            let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
            if let encThumb { await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb) }

            return VaultFileItem(
                id: fileId, size: fileSize,
                hasThumbnail: encThumb != nil, mimeType: result.mimeType,
                filename: filename, createdAt: Date(), duration: metadata.duration,
                originalDate: originalDate
            )
        } else {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int) ?? 0
            // Use optimizer's thumbnail for images if available, otherwise re-decode from disk
            let thumbnail = result.mimeType.hasPrefix("image/")
                ? (result.thumbnailData ?? FileUtilities.generateThumbnail(fromFileURL: result.url))
                : nil

            // For images, try EXIF first, then fall back to filesystem date
            let originalDate: Date? = result.mimeType.hasPrefix("image/")
                ? (FileUtilities.extractImageCreationDate(from: url) ?? resourceOriginalDate)
                : resourceOriginalDate

            let fileId = try await VaultStorage.shared.storeFileFromURL(
                result.url, filename: filename, mimeType: result.mimeType,
                with: key, thumbnailData: thumbnail, originalDate: originalDate
            )

            let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
            if let encThumb { await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb) }

            return VaultFileItem(
                id: fileId, size: fileSize,
                hasThumbnail: encThumb != nil, mimeType: result.mimeType,
                filename: filename, createdAt: Date(), originalDate: originalDate
            )
        }
    }

    // MARK: - Utilities (nonisolated — no MainActor dependency)

    /// Loads an image from PHPicker provider to a temp URL, preserving EXIF metadata.
    private static func loadImageURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Loads a video from PHPicker provider to a temp URL.
    private static func loadVideoURL(from provider: NSItemProvider) async throws -> URL {
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

    /// Generates thumbnail + duration + creation date from a video URL.
    /// If duration/creationDate are already known (from MediaOptimizer), pass them to avoid
    /// redundantly re-opening the AVAsset just for metadata.
    private static func generateVideoMetadata(
        from url: URL,
        knownDuration: TimeInterval? = nil,
        knownCreationDate: Date? = nil
    ) async -> (thumbnail: Data?, duration: TimeInterval?, creationDate: Date?) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        var thumbnail: Data?
        let duration: TimeInterval?
        let creationDate: Date?

        // Use pre-loaded metadata from optimizer if available
        if let known = knownDuration {
            duration = known
        } else if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            duration = seconds.isFinite && seconds > 0 ? seconds : nil
        } else {
            duration = nil
        }

        if let known = knownCreationDate {
            creationDate = known
        } else if let metadataItems = try? await asset.load(.commonMetadata) {
            let dateItems = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierCreationDate)
            if let dateItem = dateItems.first, let dateValue = try? await dateItem.load(.dateValue) {
                creationDate = dateValue
            } else {
                creationDate = nil
            }
        } else {
            creationDate = nil
        }

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        // autoreleasepool releases CGImage + UIImage immediately after JPEG encoding
        autoreleasepool {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                thumbnail = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
            }
        }

        return (thumbnail, duration, creationDate)
    }

    enum ImportError: Error {
        case unsupportedFormat
        case conversionFailed
        case accessDenied
    }
}
