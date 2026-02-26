import AVFoundation
import CoreMedia
import Foundation
import UIKit
@preconcurrency import UserNotifications
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

        actor BatchState {
            var imported = 0
            var skipped = 0
            var failed = 0
            var failureReason: String?
            var processed = 0

            func recordImported() { imported += 1 }
            func recordSkipped() { skipped += 1 }
            func recordFailed(reason: String?) {
                failed += 1
                if let reason { failureReason = reason }
            }
            func incrementProcessed() { processed += 1 }
        }

        let state = BatchState()
        let progressInterval: TimeInterval = 0.5
        var lastProgressUpdate = Date()

        await VaultStorage.shared.beginImportBatch()
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var fileIndex = 0
            let files = batch.files

            func addTasksUpToLimit() {
                while inFlight < maxConcurrentImports && fileIndex < files.count {
                    let file = files[fileIndex]
                    fileIndex += 1
                    inFlight += 1

                    group.addTask {
                        // Check if file was already imported
                        guard let encryptedFileURL = StagedImportManager.encryptedFileURL(
                            batchId: batch.batchId,
                            fileId: file.fileId
                        ) else {
                            await state.recordSkipped()
                            await state.incrementProcessed()
                            return
                        }

                        do {
                            // Decrypt to temp file
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

                            // Process thumbnail and store
                            try await storeWithThumbnail(
                                batch: batch, file: file, optimizedURL: optimizedURL,
                                storedFilename: storedFilename, optimizedMimeType: optimizedMimeType,
                                vaultKey: vaultKey
                            )

                            if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                            try? FileManager.default.removeItem(at: tempURL)

                            StagedImportManager.deleteEncryptedFile(batchId: batch.batchId, fileId: file.fileId)

                            await state.recordImported()
                            importIngestorLogger.info("Imported file: \(file.filename, privacy: .public)")
                        } catch {
                            await state.recordFailed(reason: error.localizedDescription)
                            importIngestorLogger.error("Failed to import \(file.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }

                        await state.incrementProcessed()
                    }
                }
            }

            addTasksUpToLimit()

            for await _ in group {
                inFlight -= 1
                addTasksUpToLimit()

                // Throttled progress updates
                let now = Date()
                let processed = await state.processed
                if now.timeIntervalSince(lastProgressUpdate) >= progressInterval || processed == files.count {
                    lastProgressUpdate = now
                    if totalImportable > 0, let onProgress {
                        await onProgress(
                            ImportProgress(
                                completed: min(completedOffset + processed, totalImportable),
                                total: totalImportable
                            )
                        )
                    }
                }
            }
        }

        do {
            try await VaultStorage.shared.endImportBatch(key: vaultKey)
        } catch {
            importIngestorLogger.error("Failed to flush import batch: \(error.localizedDescription, privacy: .public)")
        }

        let skipped = await state.skipped
        if skipped > 0 {
            importIngestorLogger.info("Batch \(batch.batchId, privacy: .public): skipped \(skipped) already-imported files")
        }

        return (await state.imported, await state.failed, await state.processed, await state.failureReason)
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
