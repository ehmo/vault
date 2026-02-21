import CloudKit

extension CKDatabase {
    /// Saves a CKRecord with automatic retry on transient CloudKit errors.
    /// Handles serverRecordChanged by fetching the server record and retrying.
    func saveWithRetry(_ record: CKRecord, maxRetries: Int = 3) async throws {
        var currentRecord = record
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try await save(currentRecord)
                return
            } catch let error as CKError {
                // Handle "record already exists" by fetching server version and updating it
                if error.code == .serverRecordChanged, attempt < maxRetries {
                    if let serverRecord = try? await self.record(for: currentRecord.recordID) {
                        for key in currentRecord.allKeys() {
                            serverRecord[key] = currentRecord[key]
                        }
                        currentRecord = serverRecord
                        continue
                    }
                    // Fetch failed — retry with delay
                    lastError = error
                    let delay = ckRetryDelay(for: error, attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                if isCKRetryable(error) && attempt < maxRetries {
                    lastError = error
                    let delay = ckRetryDelay(for: error, attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
        throw lastError!
    }

    /// Deletes a CKRecord by ID with automatic retry on transient CloudKit errors.
    func deleteWithRetry(_ recordID: CKRecord.ID, maxRetries: Int = 3) async throws {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try await deleteRecord(withID: recordID)
                return
            } catch let error as CKError {
                if isCKRetryable(error) && attempt < maxRetries {
                    lastError = error
                    let delay = ckRetryDelay(for: error, attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
        throw lastError!
    }
}

private func isCKRetryable(_ error: CKError) -> Bool {
    switch error.code {
    case .networkUnavailable, .networkFailure, .serviceUnavailable,
         .zoneBusy, .requestRateLimited,
         .notAuthenticated, .accountTemporarilyUnavailable:
        return true
    default:
        return false
    }
}

private func ckRetryDelay(for error: CKError, attempt: Int) -> TimeInterval {
    if let retryAfter = error.retryAfterSeconds {
        return retryAfter
    }
    return pow(2.0, Double(attempt)) // 1, 2, 4 seconds
}
