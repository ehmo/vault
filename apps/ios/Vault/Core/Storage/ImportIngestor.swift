import Foundation
import UserNotifications

/// Processes staged imports from the share extension into the main vault storage.
/// Called after vault unlock when pending imports exist for the matching fingerprint.
enum ImportIngestor {

    struct ImportResult {
        let imported: Int
        let failed: Int
        let batchesCleaned: Int
    }

    /// Processes all pending batches matching the given vault key.
    /// Decrypts each file, stores it via VaultStorage, and cleans up the batch.
    static func processPendingImports(for vaultKey: Data) async -> ImportResult {
        let fingerprint = KeyDerivation.keyFingerprint(from: vaultKey)
        let batches = StagedImportManager.pendingBatches(for: fingerprint)

        guard !batches.isEmpty else {
            return ImportResult(imported: 0, failed: 0, batchesCleaned: 0)
        }

        var totalImported = 0
        var totalFailed = 0
        var batchesCleaned = 0

        for batch in batches {
            let (imported, failed) = await processBatch(batch, vaultKey: vaultKey)
            totalImported += imported
            totalFailed += failed

            if failed == 0 {
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

        return ImportResult(imported: totalImported, failed: totalFailed, batchesCleaned: batchesCleaned)
    }

    private static func processBatch(
        _ batch: StagedImportManifest,
        vaultKey: Data
    ) async -> (imported: Int, failed: Int) {
        var imported = 0
        var failed = 0

        for file in batch.files {
            do {
                // Read encrypted file
                guard let encryptedData = StagedImportManager.readEncryptedFile(
                    batchId: batch.batchId,
                    fileId: file.fileId
                ) else {
                    failed += 1
                    continue
                }

                // Decrypt (handles both streaming and single-shot)
                let decryptedData = try CryptoEngine.decryptStaged(encryptedData, with: vaultKey)

                // Decrypt thumbnail if available
                var thumbnailData: Data?
                if file.hasThumbnail,
                   let encThumb = StagedImportManager.readEncryptedThumbnail(
                       batchId: batch.batchId,
                       fileId: file.fileId
                   ) {
                    thumbnailData = try? CryptoEngine.decrypt(encThumb, with: vaultKey)
                }

                // Store via VaultStorage (this handles master key encryption internally)
                _ = try VaultStorage.shared.storeFile(
                    data: decryptedData,
                    filename: file.filename,
                    mimeType: file.mimeType,
                    with: vaultKey,
                    thumbnailData: thumbnailData
                )

                imported += 1
            } catch {
                failed += 1
                #if DEBUG
                print("❌ [ImportIngestor] Failed to import file \(file.fileId): \(error)")
                #endif
            }
        }

        return (imported, failed)
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
