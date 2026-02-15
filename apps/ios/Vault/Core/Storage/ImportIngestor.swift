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

    struct ImportResult {
        let imported: Int
        let failed: Int
        let batchesCleaned: Int
        /// Primary failure reason (e.g. "Storage expansion requires premium")
        let failureReason: String?
    }

    /// Processes all pending batches matching the given vault key.
    /// Decrypts each file, stores it via VaultStorage, and cleans up the batch.
    static func processPendingImports(for vaultKey: Data) async -> ImportResult {
        let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey)
        let batches = StagedImportManager.pendingBatches(for: fingerprint)

        guard !batches.isEmpty else {
            return ImportResult(imported: 0, failed: 0, batchesCleaned: 0, failureReason: nil)
        }

        var totalImported = 0
        var totalFailed = 0
        var batchesCleaned = 0
        var lastFailureReason: String?

        for batch in batches {
            let batchResult = await processBatch(batch, vaultKey: vaultKey)
            totalImported += batchResult.imported
            totalFailed += batchResult.failed
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
                    SentryManager.shared.captureError(
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

        return ImportResult(imported: totalImported, failed: totalFailed, batchesCleaned: batchesCleaned, failureReason: lastFailureReason)
    }

    private static func processBatch(
        _ batch: StagedImportManifest,
        vaultKey: Data
    ) async -> (imported: Int, failed: Int, failureReason: String?) {
        var imported = 0
        var failed = 0
        var failureReason: String?

        for file in batch.files {
            do {
                // Get encrypted file URL (never loads entire file into memory)
                guard let encryptedURL = StagedImportManager.encryptedFileURL(
                    batchId: batch.batchId,
                    fileId: file.fileId
                ) else {
                    importIngestorLogger.error("Encrypted file not found: \(file.fileId, privacy: .public)")
                    failed += 1
                    continue
                }

                // Decrypt directly to temp file — streaming format uses ~256KB peak memory,
                // single-shot loads only small files (≤1MB) into memory
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(file.fileId.uuidString)_import")
                    .appendingPathExtension(URL(string: file.filename)?.pathExtension ?? "dat")
                try CryptoEngine.decryptStagedFileToURL(from: encryptedURL, to: tempURL, with: vaultKey)

                // Decrypt thumbnail if available from share extension (always small, safe in memory)
                var thumbnailData: Data?
                if file.hasThumbnail,
                   let encThumb = StagedImportManager.readEncryptedThumbnail(
                       batchId: batch.batchId,
                       fileId: file.fileId
                   ) {
                    thumbnailData = try? CryptoEngine.decrypt(encThumb, with: vaultKey)
                }

                // Generate thumbnail if the share extension didn't provide one
                if thumbnailData == nil {
                    thumbnailData = await generateThumbnail(for: tempURL, mimeType: file.mimeType)
                }

                // Store via VaultStorage using URL-based API (streams to blob)
                _ = try VaultStorage.shared.storeFileFromURL(
                    tempURL,
                    filename: file.filename,
                    mimeType: file.mimeType,
                    with: vaultKey,
                    thumbnailData: thumbnailData
                )

                try? FileManager.default.removeItem(at: tempURL)
                imported += 1
                importIngestorLogger.info("Imported file \(imported)/\(batch.files.count): \(file.filename, privacy: .public)")
            } catch {
                failed += 1
                failureReason = error.localizedDescription
                importIngestorLogger.error("Failed to import file \(file.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return (imported, failed, failureReason)
    }

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail from the decrypted temp file for files
    /// where the share extension didn't provide one (e.g. videos).
    private static func generateThumbnail(for fileURL: URL, mimeType: String) async -> Data? {
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
