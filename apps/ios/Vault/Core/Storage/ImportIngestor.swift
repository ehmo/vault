import AVFoundation
import CoreMedia
import Foundation
import UIKit
import UserNotifications
import os.log

/// Processes staged imports from the share extension into the main vault storage.
/// Called after vault unlock when pending imports exist for the matching fingerprint.
private let importIngestorLogger = Logger(subsystem: "app.vaultaire.ios", category: "ImportIngestor")

enum ImportIngestor {

    struct ImportProgress: Sendable {
        let completed: Int
        let total: Int
    }

    struct ImportResult {
        let imported: Int
        let failed: Int
        let batchesCleaned: Int
        /// Primary failure reason (e.g. "Storage expansion requires premium")
        let failureReason: String?
    }

    /// Processes all pending batches matching the given vault key.
    /// Decrypts each file, stores it via VaultStorage, and cleans up the batch.
    static func processPendingImports(
        for vaultKey: VaultKey,
        onProgress: (@Sendable (ImportProgress) async -> Void)? = nil
    ) async -> ImportResult {
        let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey.rawBytes)
        let batches = StagedImportManager.pendingBatches(for: fingerprint)

        guard !batches.isEmpty else {
            return ImportResult(imported: 0, failed: 0, batchesCleaned: 0, failureReason: nil)
        }

        let totalImportable = batches.reduce(0) { total, batch in
            total + StagedImportManager.importableFileCount(in: batch)
        }
        if totalImportable > 0, let onProgress {
            await onProgress(ImportProgress(completed: 0, total: totalImportable))
        }

        var totalImported = 0
        var totalFailed = 0
        var batchesCleaned = 0
        var lastFailureReason: String?
        var totalProcessed = 0

        for batch in batches {
            let batchResult = await processBatch(
                batch,
                vaultKey: vaultKey,
                completedOffset: totalProcessed,
                totalImportable: totalImportable,
                onProgress: onProgress
            )
            totalImported += batchResult.imported
            totalFailed += batchResult.failed
            totalProcessed += batchResult.processed
            if let reason = batchResult.failureReason {
                lastFailureReason = reason
            }

            if batchResult.failed == 0 {
                // All files imported successfully — delete the batch
                StagedImportManager.deleteBatch(batch.batchId)
                batchesCleaned += 1
            } else {
                // Some files failed — increment retry or delete
                let deleted = StagedImportManager.incrementRetryOrDelete(batchId: batch.batchId)
                if deleted {
                    batchesCleaned += 1
                    EmbraceManager.shared.captureError(
                        NSError(
                            domain: "ImportIngestor",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Batch \(batch.batchId) deleted after 2 retries"]
                        )
                    )
                }
            }
        }

        // Cancel any pending import notifications
        cancelPendingImportNotifications()

        // Clean up orphaned batches while we're at it
        StagedImportManager.cleanupOrphans()

        if totalImportable > 0, totalProcessed < totalImportable, let onProgress {
            await onProgress(ImportProgress(completed: totalImportable, total: totalImportable))
        }

        return ImportResult(imported: totalImported, failed: totalFailed, batchesCleaned: batchesCleaned, failureReason: lastFailureReason)
    }

    private static func processBatch(
        _ batch: StagedImportManifest,
        vaultKey: VaultKey,
        completedOffset: Int,
        totalImportable: Int,
        onProgress: (@Sendable (ImportProgress) async -> Void)?
    ) async -> (imported: Int, failed: Int, processed: Int, failureReason: String?) {
        // Parallel processing with concurrency control
        let maxConcurrentImports = min(4, ProcessInfo.processInfo.processorCount)

        await VaultStorage.shared.beginImportBatch()

        // PHASE 1: Pre-allocate blob space for all importable files
        let importableFiles = batch.files.filter { file in
            StagedImportManager.encryptedFileURL(batchId: batch.batchId, fileId: file.fileId) != nil
        }

        guard !importableFiles.isEmpty else {
            return (0, 0, 0, nil)
        }

        // Get master key and allocate space (single actor call)
        let sizes = importableFiles.map { $0.encryptedSize }
        let (allocations, masterKey): ([VaultStorage.BlobAllocation], MasterKey)
        do {
            (allocations, masterKey) = try await VaultStorage.shared.allocateBatchSpaceWithMasterKey(
                sizes: sizes,
                key: vaultKey
            )
        } catch {
            importIngestorLogger.error("Failed to allocate batch space: \(error.localizedDescription, privacy: .public)")
            return (0, importableFiles.count, importableFiles.count, error.localizedDescription)
        }

        // PHASE 2: Parallel workers decrypt, optimize, and prepare entries
        actor ImportBuffer {
            var entries: [VaultStorage.PreparedEntry] = []
            var allocations: [VaultStorage.BlobAllocation] = []
            var imported = 0
            var failed = 0
            var lastError: Error?
            var activeWorkers = 0
            var workersFinished = false

            func startWorker() { activeWorkers += 1 }
            func endWorker() {
                activeWorkers -= 1
                if activeWorkers == 0 { workersFinished = true }
            }
            func allWorkersFinished() -> Bool { return workersFinished && activeWorkers == 0 }

            func append(entry: VaultStorage.PreparedEntry, allocation: VaultStorage.BlobAllocation) {
                entries.append(entry)
                allocations.append(allocation)
            }

            func recordImported() { imported += 1 }
            func recordFailed(error: Error?) {
                failed += 1
                if let error = error { lastError = error }
            }

            func getBatch() -> (entries: [VaultStorage.PreparedEntry], allocations: [VaultStorage.BlobAllocation]) {
                let result = (entries, allocations)
                entries.removeAll()
                allocations.removeAll()
                return result
            }

            func getAll() -> (entries: [VaultStorage.PreparedEntry], allocations: [VaultStorage.BlobAllocation], imported: Int, failed: Int, lastError: Error?) {
                return (entries, allocations, imported, failed, lastError)
            }

            var count: Int { entries.count }
        }

        let importBuffer = ImportBuffer()
        let progressInterval: TimeInterval = 0.5
        var lastProgressUpdate = Date()

        await withTaskGroup(of: Void.self) { group in
            // Launch parallel workers
            for i in 0..<maxConcurrentImports {
                group.addTask {
                    await importBuffer.startWorker()
                    defer { Task { await importBuffer.endWorker() } }
                    
                    var fileIndex = i
                    while fileIndex < importableFiles.count {
                        let file = importableFiles[fileIndex]
                        let allocation = allocations[fileIndex]

                        guard !Task.isCancelled else { return }

                        do {
                            // Decrypt to temp file
                            guard let encryptedFileURL = StagedImportManager.encryptedFileURL(
                                batchId: batch.batchId,
                                fileId: file.fileId
                            ) else {
                                await importBuffer.recordFailed(error: nil)
                                fileIndex += maxConcurrentImports
                                continue
                            }

                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("\(file.fileId.uuidString)_import")
                                .appendingPathExtension(URL(string: file.filename)?.pathExtension ?? "dat")

                            try CryptoEngine.decryptStagedFileToURL(
                                from: encryptedFileURL,
                                to: tempURL,
                                with: vaultKey.rawBytes
                            )

                            // Optimize media
                            let optimizationModeStr = UserDefaults.standard.string(forKey: "fileOptimization") ?? "optimized"
                            let optimizationMode = MediaOptimizer.Mode(rawValue: optimizationModeStr) ?? .optimized

                            let (optimizedURL, optimizedMimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
                                fileURL: tempURL, mimeType: file.mimeType, mode: optimizationMode
                            )

                            let storedFilename = wasOptimized
                                ? MediaOptimizer.updatedFilename(file.filename, newMimeType: optimizedMimeType)
                                : file.filename

                            // Generate thumbnail
                            let thumbnailData: Data? = autoreleasepool {
                                if optimizedMimeType.hasPrefix("image/") {
                                    return FileUtilities.generateThumbnail(fromFileURL: optimizedURL)
                                } else if optimizedMimeType.hasPrefix("video/") {
                                    let asset = AVAsset(url: optimizedURL)
                                    let generator = AVAssetImageGenerator(asset: asset)
                                    generator.appliesPreferredTrackTransform = true
                                    generator.maximumSize = CGSize(width: 400, height: 400)
                                    let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                                    guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
                                    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
                                }
                                return nil
                            }

                            // Use existing thumbnail if available
                            let finalThumbnail: Data? = thumbnailData ?? (file.hasThumbnail
                                ? StagedImportManager.readEncryptedThumbnail(batchId: batch.batchId, fileId: file.fileId)
                                    .flatMap { try? CryptoEngine.decrypt($0, with: vaultKey.rawBytes) }
                                : nil)

                            // Prepare entry (no actor contact)
                            let preparedEntry = try VaultStorage.shared.prepareFileEntry(
                                fileURL: optimizedURL,
                                filename: storedFilename,
                                mimeType: optimizedMimeType,
                                thumbnailData: finalThumbnail,
                                duration: nil,
                                originalDate: nil,
                                masterKey: masterKey,
                                allocation: allocation
                            )

                            await importBuffer.append(entry: preparedEntry, allocation: allocation)
                            await importBuffer.recordImported()

                            // Cleanup
                            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                            try? FileManager.default.removeItem(at: tempURL)
                            StagedImportManager.deleteEncryptedFile(batchId: batch.batchId, fileId: file.fileId)

                            importIngestorLogger.info("Imported file: \(file.filename, privacy: .public)")
                        } catch {
                            await importBuffer.recordFailed(error: error)
                            importIngestorLogger.error("Failed to import \(file.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }

                        fileIndex += maxConcurrentImports
                    }
                }
            }

            // Batch commit coordinator - waits for all workers to finish
            group.addTask {
                var committedCount = 0
                let totalFiles = importableFiles.count

                while true {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    let count = await importBuffer.count
                    let workersFinished = await importBuffer.allWorkersFinished()
                    
                    // Commit batch if we have enough
                    if count >= 20 {
                        let (entries, allocs) = await importBuffer.getBatch()
                        guard !entries.isEmpty else { continue }

                        do {
                            try await VaultStorage.shared.commitEntries(entries, allocations: allocs, key: vaultKey)
                            committedCount += entries.count
                            importIngestorLogger.info("Batch committed: \(entries.count) files, total: \(committedCount)/\(totalFiles)")
                        } catch {
                            importIngestorLogger.error("Batch commit failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }

                    // Update progress
                    let totalImported = await importBuffer.imported
                    let totalFailed = await importBuffer.failed
                    if totalImported + totalFailed > 0 {
                        let now = Date()
                        if now.timeIntervalSince(lastProgressUpdate) >= progressInterval {
                            lastProgressUpdate = now
                            if let onProgress = onProgress {
                                await onProgress(ImportProgress(
                                    completed: min(completedOffset + totalImported + totalFailed, totalImportable),
                                    total: totalImportable
                                ))
                            }
                        }
                    }

                    // Exit condition: all workers finished AND buffer is empty
                    if workersFinished && count == 0 {
                        importIngestorLogger.info("Coordinator exiting: all workers finished, buffer empty, committed: \(committedCount)/\(totalFiles)")
                        break
                    }
                    
                    // Final commit: workers finished but we still have items
                    if workersFinished && count > 0 && count < 20 {
                        let (entries, allocs) = await importBuffer.getBatch()
                        guard !entries.isEmpty else { continue }

                        do {
                            try await VaultStorage.shared.commitEntries(entries, allocations: allocs, key: vaultKey)
                            committedCount += entries.count
                            importIngestorLogger.info("Final batch committed: \(entries.count) files, total: \(committedCount)/\(totalFiles)")
                        } catch {
                            importIngestorLogger.error("Final batch commit failed: \(error.localizedDescription, privacy: .public)")
                        }
                        break
                    }
                }
            }
        }

        // Final commit of any remaining entries (should be empty if coordinator worked correctly)
        let (entries, allocs, imported, failed, lastError) = await importBuffer.getAll()
        if !entries.isEmpty {
            do {
                try await VaultStorage.shared.commitEntries(entries, allocations: allocs, key: vaultKey)
                importIngestorLogger.info("Final cleanup commit: \(entries.count) files")
            } catch {
                importIngestorLogger.error("Final cleanup commit failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Note: Handles are closed by commitEntries when it commits entries
        // If there were uncommitted entries above, commitEntries closed those handles
        // No additional handle cleanup needed here

        // Final progress update
        if let onProgress = onProgress {
            await onProgress(ImportProgress(
                completed: min(completedOffset + imported + failed, totalImportable),
                total: totalImportable
            ))
        }

        do {
            try await VaultStorage.shared.endImportBatch(key: vaultKey)
        } catch {
            importIngestorLogger.error("Failed to flush import batch: \(error.localizedDescription, privacy: .public)")
        }

        // Extract failure reason from last error
        let failureReason = lastError?.localizedDescription

        return (imported, failed, imported + failed, failureReason)
    }

    /// Resolves thumbnail data and stores the file inside an autoreleasepool.
    private static func storeWithThumbnail(
        batch: StagedImportManifest,
        file: StagedFileMetadata,
        optimizedURL: URL,
        storedFilename: String,
        optimizedMimeType: String,
        vaultKey: VaultKey
    ) async throws {
        // Resolve thumbnail inside autoreleasepool so UIImage/CGImage temporaries are released
        let thumbnailData: Data? = autoreleasepool {
            var thumb: Data?
            if file.hasThumbnail,
               let encThumb = StagedImportManager.readEncryptedThumbnail(
                   batchId: batch.batchId, fileId: file.fileId
               ) {
                thumb = try? CryptoEngine.decrypt(encThumb, with: vaultKey.rawBytes)
            }
            if thumb == nil {
                thumb = generateThumbnailSync(for: optimizedURL, mimeType: optimizedMimeType)
            }
            return thumb
        }
        // storeFileFromURL is now async — must be called outside autoreleasepool
        _ = try await VaultStorage.shared.storeFileFromURL(
            optimizedURL,
            filename: storedFilename,
            mimeType: optimizedMimeType,
            with: vaultKey,
            thumbnailData: thumbnailData
        )
    }

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail synchronously from the decrypted temp file.
    /// Runs inside autoreleasepool so UIImage/CGImage temporaries are released.
    private static func generateThumbnailSync(for fileURL: URL, mimeType: String) -> Data? {
        if mimeType.hasPrefix("image/") {
            return FileUtilities.generateThumbnail(fromFileURL: fileURL)
        } else if mimeType.hasPrefix("video/") {
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
        }
        return nil
    }

    private static func cancelPendingImportNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let importIds = requests
                .filter { $0.identifier.hasPrefix("pending-import-") }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: importIds)
        }
    }
}
