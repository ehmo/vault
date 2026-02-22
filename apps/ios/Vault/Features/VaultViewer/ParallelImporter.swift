import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// Runs import work off MainActor with dedicated worker tasks.
/// 1 video worker + 2 image workers for photo picker imports.
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
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let videoQueue = Queue(videoWork)
        let imageQueue = Queue(imageWork)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<videoWorkerCount {
                group.addTask {
                    while let item = await videoQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importVideo(item: item, key: key, encryptionKey: encryptionKey, optimizationMode: optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                            // nil return means Task was cancelled — don't count as failure
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                }
            }

            for _ in 0..<imageWorkerCount {
                group.addTask {
                    while let item = await imageQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importImage(item: item, key: key, encryptionKey: encryptionKey, optimizationMode: optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                            // nil return means Task was cancelled — don't count as failure
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
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let videoQueue = Queue(videoWork)
        let otherQueue = Queue(otherWork)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<videoWorkerCount {
                group.addTask {
                    while let item = await videoQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importFileFromURL(url: item.url, key: key, encryptionKey: encryptionKey, optimizationMode: optimizationMode) {
                                continuation.yield(.imported(file))
                            }
                        } catch {
                            continuation.yield(.failed(reason: error.localizedDescription))
                        }
                    }
                }
            }

            for _ in 0..<otherWorkerCount {
                group.addTask {
                    while let item = await otherQueue.next() {
                        guard !Task.isCancelled else { return }
                        do {
                            if let file = try await importFileFromURL(url: item.url, key: key, encryptionKey: encryptionKey, optimizationMode: optimizationMode) {
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

        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: tempVideoURL, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
        }

        let baseFilename = item.provider.suggestedName.map { name -> String in
            if (name as NSString).pathExtension.isEmpty { return name + ".\(ext)" }
            return name
        } ?? "VID_\(Date().timeIntervalSince1970)_\(item.originalIndex).\(ext)"
        let filename = wasOptimized ? MediaOptimizer.updatedFilename(baseFilename, newMimeType: mimeType) : baseFilename

        let metadata = await generateVideoMetadata(from: optimizedURL)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

        let fileId = try VaultStorage.shared.storeFileFromURL(
            optimizedURL, filename: filename, mimeType: mimeType,
            with: key, thumbnailData: metadata.thumbnail, duration: metadata.duration
        )

        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
        if let encThumb {
            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
        }

        return VaultFileItem(
            id: fileId, size: fileSize,
            hasThumbnail: encThumb != nil, mimeType: mimeType,
            filename: filename, createdAt: Date(), duration: metadata.duration
        )
    }

    private static func importImage(
        item: PickerWorkItem,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode
    ) async throws -> VaultFileItem? {
        guard !Task.isCancelled else { return nil }

        guard item.provider.canLoadObject(ofClass: UIImage.self) else {
            throw ImportError.unsupportedFormat
        }

        let image: UIImage? = await withCheckedContinuation { continuation in
            item.provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }

        guard !Task.isCancelled else { return nil }
        guard let image else { throw ImportError.conversionFailed }

        let tempInputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw ImportError.conversionFailed
        }
        try jpegData.write(to: tempInputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: tempInputURL) }

        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: tempInputURL, mimeType: "image/jpeg", mode: optimizationMode
        )
        defer {
            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
        }

        let ext = mimeType == "image/heic" ? "heic" : "jpg"
        let filename = "IMG_\(Date().timeIntervalSince1970)_\(item.originalIndex).\(ext)"

        let thumbnail = FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

        let fileId = try VaultStorage.shared.storeFileFromURL(
            optimizedURL, filename: filename, mimeType: mimeType,
            with: key, thumbnailData: thumbnail
        )

        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
        if let encThumb {
            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
        }

        return VaultFileItem(
            id: fileId, size: fileSize,
            hasThumbnail: encThumb != nil, mimeType: mimeType,
            filename: filename, createdAt: Date()
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
            let metadata = await generateVideoMetadata(from: optimizedURL)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

            let fileId = try VaultStorage.shared.storeFileFromURL(
                optimizedURL, filename: filename, mimeType: mimeType,
                with: key, thumbnailData: metadata.thumbnail, duration: metadata.duration
            )

            let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
            if let encThumb { await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb) }

            return VaultFileItem(
                id: fileId, size: fileSize,
                hasThumbnail: encThumb != nil, mimeType: mimeType,
                filename: filename, createdAt: Date(), duration: metadata.duration
            )
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
            if let encThumb { await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb) }

            return VaultFileItem(
                id: fileId, size: fileSize,
                hasThumbnail: encThumb != nil, mimeType: mimeType,
                filename: filename, createdAt: Date()
            )
        }
    }

    // MARK: - Utilities (nonisolated — no MainActor dependency)

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

    /// Generates thumbnail + duration from a video URL.
    private static func generateVideoMetadata(from url: URL) async -> (thumbnail: Data?, duration: TimeInterval?) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        var thumbnail: Data?
        var duration: TimeInterval?

        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 { duration = seconds }
        }

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            thumbnail = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
        }

        return (thumbnail, duration)
    }

    enum ImportError: Error {
        case unsupportedFormat
        case conversionFailed
        case accessDenied
    }
}
