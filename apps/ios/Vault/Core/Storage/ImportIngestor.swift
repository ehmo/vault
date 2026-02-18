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
        for vaultKey: Data,
        onProgress: (@Sendable (ImportProgress) async -> Void)? = nil
    ) async -> ImportResult {
        let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey)
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
        vaultKey: Data,
        completedOffset: Int,
        totalImportable: Int,
        onProgress: (@Sendable (ImportProgress) async -> Void)?
    ) async -> (imported: Int, failed: Int, processed: Int, failureReason: String?) {
        var imported = 0
        var skipped = 0
        var failed = 0
        var failureReason: String?
        var processed = 0

        for file in batch.files {
            // If the .enc file is missing, this file was already imported in a
            // previous attempt (we delete .enc after each successful import).
            // Count as skipped, not failed — batch cleanup should still proceed.
            guard StagedImportManager.encryptedFileURL(
                batchId: batch.batchId,
                fileId: file.fileId
            ) != nil else {
                skipped += 1
                continue
            }

            // Wrap each file in autoreleasepool to release UIKit/Foundation
            // temporaries (CGImage, UIImage, AVAsset) between files — prevents
            // memory accumulation across large batches.
            do {
                // Decrypt directly to temp file — streaming format uses ~256KB peak,
                // single-shot loads only small files (≤1MB) into memory
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(file.fileId.uuidString)_import")
                    .appendingPathExtension(URL(string: file.filename)?.pathExtension ?? "dat")
                try CryptoEngine.decryptStagedFileToURL(
                    from: StagedImportManager.encryptedFileURL(batchId: batch.batchId, fileId: file.fileId)!,
                    to: tempURL,
                    with: vaultKey
                )

                // Optimize media before storing (async — video export needs AVFoundation)
                let optimizationModeStr = UserDefaults.standard.string(forKey: "fileOptimization") ?? "optimized"
                let optimizationMode = MediaOptimizer.Mode(rawValue: optimizationModeStr) ?? .optimized

                let (optimizedURL, optimizedMimeType, wasOptimized) = try await MediaOptimizer.shared.optimize(
                    fileURL: tempURL, mimeType: file.mimeType, mode: optimizationMode
                )

                let storedFilename = wasOptimized
                    ? MediaOptimizer.updatedFilename(file.filename, newMimeType: optimizedMimeType)
                    : file.filename

                // Wrap thumbnail + store in autoreleasepool to release UIKit/Foundation
                // temporaries (CGImage, UIImage) between files
                try autoreleasepool {
                    // Decrypt thumbnail if share extension provided one (always small)
                    var thumbnailData: Data?
                    if file.hasThumbnail,
                       let encThumb = StagedImportManager.readEncryptedThumbnail(
                           batchId: batch.batchId, fileId: file.fileId
                       ) {
                        thumbnailData = try? CryptoEngine.decrypt(encThumb, with: vaultKey)
                    }

                    // Generate thumbnail from optimized file if share extension didn't provide one
                    if thumbnailData == nil {
                        thumbnailData = generateThumbnailSync(for: optimizedURL, mimeType: optimizedMimeType)
                    }

                    // Store via VaultStorage (streams to blob, ~256KB peak)
                    _ = try VaultStorage.shared.storeFileFromURL(
                        optimizedURL,
                        filename: storedFilename,
                        mimeType: optimizedMimeType,
                        with: vaultKey,
                        thumbnailData: thumbnailData
                    )
                }

                if wasOptimized { try? FileManager.default.removeItem(at: optimizedURL) }
                try? FileManager.default.removeItem(at: tempURL)

                // Mark file as imported by deleting its .enc (and .thumb.enc).
                // On crash + retry, this file will be skipped above.
                StagedImportManager.deleteEncryptedFile(batchId: batch.batchId, fileId: file.fileId)

                imported += 1
                importIngestorLogger.info("Imported file \(imported)/\(batch.files.count): \(file.filename, privacy: .public)")
            } catch {
                failed += 1
                failureReason = error.localizedDescription
                importIngestorLogger.error("Failed to import \(file.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            processed += 1
            if totalImportable > 0, let onProgress {
                await onProgress(
                    ImportProgress(
                        completed: min(completedOffset + processed, totalImportable),
                        total: totalImportable
                    )
                )
            }
        }

        if skipped > 0 {
            importIngestorLogger.info("Batch \(batch.batchId, privacy: .public): skipped \(skipped) already-imported files")
        }

        return (imported, failed, processed, failureReason)
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
