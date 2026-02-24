import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// Runs import work off MainActor with dedicated worker tasks.
/// 2 video-priority workers + 2 image-priority workers = 4 parallel workers.
/// Workers drain their primary queue first, then steal from the other queue.
/// Results stream back to MainActor via AsyncStream for real-time UI updates.
///
/// Uses scatter-gather pattern for maximum parallelism:
/// 1. Scatter: Pre-allocate blob space, workers encrypt & write in parallel (no actor contact)
/// 2. Gather: Batch commit entries to index periodically (minimal actor serialization)
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

    // MARK: - Thread-Safe Result Buffer

    /// Thread-safe buffer for collecting prepared entries from parallel workers.
    actor EntryBuffer {
        private var entries: [VaultStorage.PreparedEntry] = []
        private var allocations: [VaultStorage.BlobAllocation] = []
        private var importedFiles: [VaultFileItem] = []
        private var failedCount = 0

        func append(entry: VaultStorage.PreparedEntry, allocation: VaultStorage.BlobAllocation, file: VaultFileItem) {
            entries.append(entry)
            allocations.append(allocation)
            importedFiles.append(file)
        }

        func recordFailure() {
            failedCount += 1
        }

        func getBatch() -> (entries: [VaultStorage.PreparedEntry], allocations: [VaultStorage.BlobAllocation], files: [VaultFileItem]) {
            let result = (entries, allocations, importedFiles)
            entries.removeAll()
            allocations.removeAll()
            importedFiles.removeAll()
            return result
        }

        func getFailedCount() -> Int {
            return failedCount
        }

        func getAll() -> (entries: [VaultStorage.PreparedEntry], allocations: [VaultStorage.BlobAllocation], files: [VaultFileItem], failed: Int) {
            return (entries, allocations, importedFiles, failedCount)
        }

        var count: Int { entries.count }
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

    // MARK: - Scatter-Gather Photo Import

    /// Runs scatter-gather import for photo picker results.
    /// Pre-allocates blob space, workers encrypt in parallel, batch commits to index.
    static func runPhotoImportScatterGather(
        videoWork: [PickerWorkItem],
        imageWork: [PickerWorkItem],
        videoWorkerCount: Int,
        imageWorkerCount: Int,
        config: ImportConfig,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let totalCount = videoWork.count + imageWork.count
        guard totalCount > 0 else {
            continuation.finish()
            return
        }

        // PHASE 1: Pre-allocate blob space for all files (single actor call)
        // This is the ONLY actor contact before workers start
        let allWork = videoWork.map { (item: $0, isVideo: true) } + imageWork.map { (item: $0, isVideo: false) }
        // Allocate generous space: 100MB for videos, 50MB for images
        // This should accommodate most optimized files. If a file exceeds this,
        // the import will fail gracefully and report the error.
        let sizes = allWork.map { item, isVideo in
            isVideo ? 100 * 1024 * 1024 : 50 * 1024 * 1024
        }

        let (allocations, masterKey): ([VaultStorage.BlobAllocation], MasterKey)
        do {
            (allocations, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: sizes,
                key: config.key
            )
        } catch {
            // Allocation failed, report all as failed
            for _ in 0..<totalCount {
                continuation.yield(.failed(reason: error.localizedDescription))
            }
            continuation.finish()
            return
        }

        // Distribute allocations to video and image work
        var videoAllocations: [VaultStorage.BlobAllocation] = []
        var imageAllocations: [VaultStorage.BlobAllocation] = []

        var allocationIndex = 0
        for _ in videoWork {
            if allocationIndex < allocations.count {
                videoAllocations.append(allocations[allocationIndex])
                allocationIndex += 1
            }
        }
        for _ in imageWork {
            if allocationIndex < allocations.count {
                imageAllocations.append(allocations[allocationIndex])
                allocationIndex += 1
            }
        }

        // PHASE 2: Parallel workers encrypt and write to pre-allocated space
        let videoQueue = Queue(zip(videoWork, videoAllocations).map { ($0.0, $0.1) })
        let imageQueue = Queue(zip(imageWork, imageAllocations).map { ($0.0, $0.1) })
        let entryBuffer = EntryBuffer()

        await withTaskGroup(of: Void.self) { group in
            // Video workers
            for _ in 0..<videoWorkerCount {
                group.addTask {
                    await processVideoWorkWithAllocation(
                        queue: videoQueue,
                        entryBuffer: entryBuffer,
                        config: config,
                        masterKey: masterKey,
                        continuation: continuation
                    )
                }
            }

            // Image workers
            for _ in 0..<imageWorkerCount {
                group.addTask {
                    await processImageWorkWithAllocation(
                        queue: imageQueue,
                        entryBuffer: entryBuffer,
                        config: config,
                        masterKey: masterKey,
                        continuation: continuation
                    )
                }
            }

            // Batch commit coordinator
            group.addTask {
                await batchCommitCoordinator(
                    entryBuffer: entryBuffer,
                    key: config.key,
                    totalCount: totalCount,
                    continuation: continuation
                )
            }
        }

        // Final commit of any remaining entries
        let (entries, allocs, files, failed) = await entryBuffer.getAll()
        if !entries.isEmpty {
            do {
                try await VaultStorage.shared.commitEntries(entries, allocations: allocs, key: config.key)
                for file in files {
                    continuation.yield(.imported(file))
                }
            } catch {
                for _ in files {
                    continuation.yield(.failed(reason: error.localizedDescription))
                }
            }
        }
        for _ in 0..<failed {
            continuation.yield(.failed(reason: nil))
        }

        // Close any remaining handles
        for allocation in allocations {
            try? allocation.handle.close()
        }

        continuation.finish()
    }

    /// Process video work items with pre-allocated blob space.
    private static func processVideoWorkWithAllocation(
        queue: Queue<(PickerWorkItem, VaultStorage.BlobAllocation)>,
        entryBuffer: EntryBuffer,
        config: ImportConfig,
        masterKey: MasterKey,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        while let (item, allocation) = await queue.next() {
            guard !Task.isCancelled else { return }
            do {
                guard let result = try await importVideoWithAllocation(
                    item: item,
                    allocation: allocation,
                    key: config.key,
                    encryptionKey: config.encryptionKey,
                    optimizationMode: config.optimizationMode,
                    masterKey: masterKey
                ) else {
                    await entryBuffer.recordFailure()
                    continue
                }
                await entryBuffer.append(entry: result.entry, allocation: result.allocation, file: result.file)
            } catch {
                await entryBuffer.recordFailure()
            }
        }
    }

    /// Process image work items with pre-allocated blob space.
    private static func processImageWorkWithAllocation(
        queue: Queue<(PickerWorkItem, VaultStorage.BlobAllocation)>,
        entryBuffer: EntryBuffer,
        config: ImportConfig,
        masterKey: MasterKey,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        while let (item, allocation) = await queue.next() {
            guard !Task.isCancelled else { return }
            do {
                guard let result = try await importImageWithAllocation(
                    item: item,
                    allocation: allocation,
                    key: config.key,
                    encryptionKey: config.encryptionKey,
                    optimizationMode: config.optimizationMode,
                    masterKey: masterKey
                ) else {
                    await entryBuffer.recordFailure()
                    continue
                }
                await entryBuffer.append(entry: result.entry, allocation: result.allocation, file: result.file)
            } catch {
                await entryBuffer.recordFailure()
            }
        }
    }

    /// Coordinate periodic batch commits.
    private static func batchCommitCoordinator(
        entryBuffer: EntryBuffer,
        key: VaultKey,
        totalCount: Int,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let batchSize = 20
        var committedCount = 0

        while committedCount < totalCount {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms check interval

            let count = await entryBuffer.count
            if count >= batchSize {
                let (entries, allocations, files) = await entryBuffer.getBatch()
                guard !entries.isEmpty else { continue }

                do {
                    try await VaultStorage.shared.commitEntries(entries, allocations: allocations, key: key)
                    committedCount += files.count
                    for file in files {
                        continuation.yield(.imported(file))
                    }
                } catch {
                    for _ in files {
                        continuation.yield(.failed(reason: error.localizedDescription))
                    }
                }
            }

            // Check if all work is done
            if await entryBuffer.count == 0 && committedCount >= totalCount - 5 {
                // Near completion, let final commit handle remaining
                break
            }
        }
    }

    // MARK: - Photo Picker Import (Legacy)

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

    /// Runs scatter-gather import for file/document picker results.
    /// Pre-allocates blob space, workers encrypt in parallel, batch commits to index.
    static func runFileImportScatterGather(
        videoWork: [URLWorkItem],
        otherWork: [URLWorkItem],
        videoWorkerCount: Int,
        otherWorkerCount: Int,
        config: ImportConfig,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        let totalCount = videoWork.count + otherWork.count
        guard totalCount > 0 else {
            continuation.finish()
            return
        }

        // PHASE 1: Pre-allocate blob space for all files (single actor call)
        // This is the ONLY actor contact before workers start
        let allWork = videoWork.map { (item: $0, isVideo: true) } + otherWork.map { (item: $0, isVideo: false) }
        // Allocate generous space: 100MB for videos, 50MB for other files
        let sizes = allWork.map { item, isVideo in
            isVideo ? 100 * 1024 * 1024 : 50 * 1024 * 1024
        }

        let (allocations, masterKey): ([VaultStorage.BlobAllocation], MasterKey)
        do {
            (allocations, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: sizes,
                key: config.key
            )
        } catch {
            // Allocation failed, report all as failed
            for _ in 0..<totalCount {
                continuation.yield(.failed(reason: error.localizedDescription))
            }
            continuation.finish()
            return
        }

        // Distribute allocations to video and other work
        var videoAllocations: [VaultStorage.BlobAllocation] = []
        var otherAllocations: [VaultStorage.BlobAllocation] = []

        var allocationIndex = 0
        for _ in videoWork {
            if allocationIndex < allocations.count {
                videoAllocations.append(allocations[allocationIndex])
                allocationIndex += 1
            }
        }
        for _ in otherWork {
            if allocationIndex < allocations.count {
                otherAllocations.append(allocations[allocationIndex])
                allocationIndex += 1
            }
        }

        // PHASE 2: Parallel workers encrypt and write to pre-allocated space
        let videoQueue = Queue(zip(videoWork, videoAllocations).map { ($0.0, $0.1) })
        let otherQueue = Queue(zip(otherWork, otherAllocations).map { ($0.0, $0.1) })
        let entryBuffer = EntryBuffer()

        await withTaskGroup(of: Void.self) { group in
            // Video workers
            for _ in 0..<videoWorkerCount {
                group.addTask {
                    await processFileWorkWithAllocation(
                        queue: videoQueue,
                        entryBuffer: entryBuffer,
                        config: config,
                        masterKey: masterKey,
                        continuation: continuation
                    )
                }
            }

            // Other workers
            for _ in 0..<otherWorkerCount {
                group.addTask {
                    await processFileWorkWithAllocation(
                        queue: otherQueue,
                        entryBuffer: entryBuffer,
                        config: config,
                        masterKey: masterKey,
                        continuation: continuation
                    )
                }
            }

            // Batch commit coordinator
            group.addTask {
                await batchCommitCoordinator(
                    entryBuffer: entryBuffer,
                    key: config.key,
                    totalCount: totalCount,
                    continuation: continuation
                )
            }
        }

        // Final commit of any remaining entries
        let (entries, allocs, files, failed) = await entryBuffer.getAll()
        if !entries.isEmpty {
            do {
                try await VaultStorage.shared.commitEntries(entries, allocations: allocs, key: config.key)
                for file in files {
                    continuation.yield(.imported(file))
                }
            } catch {
                for _ in files {
                    continuation.yield(.failed(reason: error.localizedDescription))
                }
            }
        }
        for _ in 0..<failed {
            continuation.yield(.failed(reason: nil))
        }

        // Close any remaining handles
        for allocation in allocations {
            try? allocation.handle.close()
        }

        continuation.finish()
    }

    /// Process file work items with pre-allocated blob space.
    private static func processFileWorkWithAllocation(
        queue: Queue<(URLWorkItem, VaultStorage.BlobAllocation)>,
        entryBuffer: EntryBuffer,
        config: ImportConfig,
        masterKey: MasterKey,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async {
        while let (item, allocation) = await queue.next() {
            guard !Task.isCancelled else { return }
            do {
                guard let result = try await importFileFromURLWithAllocation(
                    item: item,
                    allocation: allocation,
                    key: config.key,
                    encryptionKey: config.encryptionKey,
                    optimizationMode: config.optimizationMode,
                    masterKey: masterKey
                ) else {
                    await entryBuffer.recordFailure()
                    continue
                }
                await entryBuffer.append(entry: result.entry, allocation: result.allocation, file: result.file)
            } catch {
                await entryBuffer.recordFailure()
            }
        }
    }

    /// Import file from URL using pre-allocated blob space (no actor contact).
    private static func importFileFromURLWithAllocation(
        item: URLWorkItem,
        allocation: VaultStorage.BlobAllocation,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode,
        masterKey: MasterKey
    ) async throws -> ScatterGatherResult? {
        guard !Task.isCancelled else { return nil }

        guard item.url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { item.url.stopAccessingSecurityScopedResource() }

        let originalFilename = item.url.lastPathComponent
        let sourceMimeType = FileUtilities.mimeType(forExtension: item.url.pathExtension)

        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: item.url, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
        }

        let filename = wasOptimized
            ? MediaOptimizer.updatedFilename(originalFilename, newMimeType: mimeType)
            : originalFilename

        // Extract original date from the source file's filesystem creation date
        let resourceOriginalDate = (try? item.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

        if mimeType.hasPrefix("video/") {
            let metadata = await generateVideoMetadata(from: optimizedURL)
            let originalDate = metadata.creationDate ?? resourceOriginalDate

            // Use scatter-gather prepare (no actor contact)
            let preparedEntry = try VaultStorage.shared.prepareFileEntry(
                fileURL: optimizedURL,
                filename: filename,
                mimeType: mimeType,
                thumbnailData: metadata.thumbnail,
                duration: metadata.duration,
                originalDate: originalDate,
                masterKey: masterKey,
                allocation: allocation
            )

            let file = VaultFileItem(
                id: preparedEntry.entry.fileId,
                size: fileSize,
                hasThumbnail: preparedEntry.thumbnailPlaintext != nil,
                mimeType: mimeType,
                filename: filename,
                createdAt: Date(),
                duration: metadata.duration,
                originalDate: originalDate
            )

            return ScatterGatherResult(entry: preparedEntry, allocation: allocation, file: file)
        } else {
            let thumbnail = mimeType.hasPrefix("image/")
                ? autoreleasepool { FileUtilities.generateThumbnail(fromFileURL: optimizedURL) }
                : nil

            // For images, try EXIF first, then fall back to filesystem date
            let originalDate: Date? = mimeType.hasPrefix("image/")
                ? (FileUtilities.extractImageCreationDate(from: item.url) ?? resourceOriginalDate)
                : resourceOriginalDate

            // Use scatter-gather prepare (no actor contact)
            let preparedEntry = try VaultStorage.shared.prepareFileEntry(
                fileURL: optimizedURL,
                filename: filename,
                mimeType: mimeType,
                thumbnailData: thumbnail,
                duration: nil,
                originalDate: originalDate,
                masterKey: masterKey,
                allocation: allocation
            )

            let file = VaultFileItem(
                id: preparedEntry.entry.fileId,
                size: fileSize,
                hasThumbnail: preparedEntry.thumbnailPlaintext != nil,
                mimeType: mimeType,
                filename: filename,
                createdAt: Date(),
                originalDate: originalDate
            )

            return ScatterGatherResult(entry: preparedEntry, allocation: allocation, file: file)
        }
    }

    // MARK: - File Import (Legacy)

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

        let fileId = try await VaultStorage.shared.storeFileFromURL(
            optimizedURL, filename: filename, mimeType: mimeType,
            with: key, options: FileStoreOptions(thumbnailData: metadata.thumbnail, duration: metadata.duration, originalDate: metadata.creationDate)
        )

        let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
        if let encThumb {
            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
        }

        return VaultFileItem(
            id: fileId, size: fileSize,
            hasThumbnail: encThumb != nil, mimeType: mimeType,
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
        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: tempImageURL, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
        }

        let ext: String
        if mimeType == "image/heic" {
            ext = "heic"
        } else {
            let sourceExt = tempImageURL.pathExtension.lowercased()
            ext = sourceExt.isEmpty ? "jpg" : sourceExt
        }
        let filename = "IMG_\(Date().timeIntervalSince1970)_\(item.originalIndex).\(ext)"

        // autoreleasepool releases CGImage/UIImage temporaries from thumbnail generation
        // before the async storeFileFromURL call, preventing memory accumulation across workers
        let thumbnail: Data? = autoreleasepool {
            FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

        let fileId = try await VaultStorage.shared.storeFileFromURL(
            optimizedURL, filename: filename, mimeType: mimeType,
            with: key, thumbnailData: thumbnail, originalDate: originalDate
        )

        let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
        if let encThumb {
            await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb)
        }

        return VaultFileItem(
            id: fileId, size: fileSize,
            hasThumbnail: encThumb != nil, mimeType: mimeType,
            filename: filename, createdAt: Date(), originalDate: originalDate
        )
    }

    // MARK: - Scatter-Gather Import Operations

    /// Result of scatter-gather import operation.
    private struct ScatterGatherResult {
        let entry: VaultStorage.PreparedEntry
        let allocation: VaultStorage.BlobAllocation
        let file: VaultFileItem
    }

    /// Import video using pre-allocated blob space (no actor contact).
    private static func importVideoWithAllocation(
        item: PickerWorkItem,
        allocation: VaultStorage.BlobAllocation,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode,
        masterKey: MasterKey
    ) async throws -> ScatterGatherResult? {
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

        // Use scatter-gather prepare (no actor contact)
        let preparedEntry = try VaultStorage.shared.prepareFileEntry(
            fileURL: optimizedURL,
            filename: filename,
            mimeType: mimeType,
            thumbnailData: metadata.thumbnail,
            duration: metadata.duration,
            originalDate: metadata.creationDate,
            masterKey: masterKey,
            allocation: allocation
        )

        let file = VaultFileItem(
            id: preparedEntry.entry.fileId,
            size: fileSize,
            hasThumbnail: preparedEntry.thumbnailPlaintext != nil,
            mimeType: mimeType,
            filename: filename,
            createdAt: Date(),
            duration: metadata.duration,
            originalDate: metadata.creationDate
        )

        return ScatterGatherResult(entry: preparedEntry, allocation: allocation, file: file)
    }

    /// Import image using pre-allocated blob space (no actor contact).
    private static func importImageWithAllocation(
        item: PickerWorkItem,
        allocation: VaultStorage.BlobAllocation,
        key: VaultKey,
        encryptionKey: Data,
        optimizationMode: MediaOptimizer.Mode,
        masterKey: MasterKey
    ) async throws -> ScatterGatherResult? {
        guard !Task.isCancelled else { return nil }

        // Load image via file representation to preserve EXIF data
        let tempImageURL = try await loadImageURL(from: item.provider)
        defer { try? FileManager.default.removeItem(at: tempImageURL) }

        // Extract EXIF creation date before any conversion
        let originalDate = FileUtilities.extractImageCreationDate(from: tempImageURL)

        guard !Task.isCancelled else { return nil }

        // Optimize image
        let detectedMime = FileUtilities.mimeType(forExtension: tempImageURL.pathExtension)
        let sourceMimeType = detectedMime.hasPrefix("image/") ? detectedMime : "image/jpeg"
        let (optimizedURL, mimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
            fileURL: tempImageURL, mimeType: sourceMimeType, mode: optimizationMode
        )
        defer {
            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
        }

        let ext: String
        if mimeType == "image/heic" {
            ext = "heic"
        } else {
            let sourceExt = tempImageURL.pathExtension.lowercased()
            ext = sourceExt.isEmpty ? "jpg" : sourceExt
        }
        let filename = "IMG_\(Date().timeIntervalSince1970)_\(item.originalIndex).\(ext)"

        // Generate thumbnail
        let thumbnail: Data? = autoreleasepool {
            FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

        // Use scatter-gather prepare (no actor contact)
        let preparedEntry = try VaultStorage.shared.prepareFileEntry(
            fileURL: optimizedURL,
            filename: filename,
            mimeType: mimeType,
            thumbnailData: thumbnail,
            duration: nil,
            originalDate: originalDate,
            masterKey: masterKey,
            allocation: allocation
        )

        let file = VaultFileItem(
            id: preparedEntry.entry.fileId,
            size: fileSize,
            hasThumbnail: preparedEntry.thumbnailPlaintext != nil,
            mimeType: mimeType,
            filename: filename,
            createdAt: Date(),
            originalDate: originalDate
        )

        return ScatterGatherResult(entry: preparedEntry, allocation: allocation, file: file)
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

        // Extract original date from the source file's filesystem creation date
        let resourceOriginalDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        if mimeType.hasPrefix("video/") {
            let metadata = await generateVideoMetadata(from: optimizedURL)
            let originalDate = metadata.creationDate ?? resourceOriginalDate
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0

            let fileId = try await VaultStorage.shared.storeFileFromURL(
                optimizedURL, filename: filename, mimeType: mimeType,
                with: key, options: FileStoreOptions(thumbnailData: metadata.thumbnail, duration: metadata.duration, originalDate: originalDate)
            )

            let encThumb = metadata.thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
            if let encThumb { await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb) }

            return VaultFileItem(
                id: fileId, size: fileSize,
                hasThumbnail: encThumb != nil, mimeType: mimeType,
                filename: filename, createdAt: Date(), duration: metadata.duration,
                originalDate: originalDate
            )
        } else {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: optimizedURL.path)[.size] as? Int) ?? 0
            let thumbnail = mimeType.hasPrefix("image/")
                ? FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
                : nil

            // For images, try EXIF first, then fall back to filesystem date
            let originalDate: Date? = mimeType.hasPrefix("image/")
                ? (FileUtilities.extractImageCreationDate(from: url) ?? resourceOriginalDate)
                : resourceOriginalDate

            let fileId = try await VaultStorage.shared.storeFileFromURL(
                optimizedURL, filename: filename, mimeType: mimeType,
                with: key, thumbnailData: thumbnail, originalDate: originalDate
            )

            let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
            if let encThumb { await ThumbnailCache.shared.storeEncrypted(id: fileId, data: encThumb) }

            return VaultFileItem(
                id: fileId, size: fileSize,
                hasThumbnail: encThumb != nil, mimeType: mimeType,
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
    private static func generateVideoMetadata(from url: URL) async -> (thumbnail: Data?, duration: TimeInterval?, creationDate: Date?) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        var thumbnail: Data?
        var duration: TimeInterval?
        var creationDate: Date?

        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 { duration = seconds }
        }

        // Extract creation date from video metadata
        if let metadataItems = try? await asset.load(.commonMetadata) {
            let dateItems = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierCreationDate)
            if let dateItem = dateItems.first, let dateValue = try? await dateItem.load(.dateValue) {
                creationDate = dateValue
            }
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
