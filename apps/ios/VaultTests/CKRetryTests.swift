import XCTest
import CloudKit
@testable import Vault

/// Tests for CKDatabase+Retry retry logic, error classification, and backoff.
final class CKRetryTests: XCTestCase {

    // MARK: - isCKRetryable Classification

    func testRetryableErrors() {
        let retryableCodes: [CKError.Code] = [
            .networkUnavailable, .networkFailure, .serviceUnavailable,
            .zoneBusy, .requestRateLimited,
            .notAuthenticated, .accountTemporarilyUnavailable
        ]

        for code in retryableCodes {
            let error = CKError(code)
            XCTAssertTrue(
                isCKRetryable(error),
                "\(code.rawValue) should be retryable"
            )
        }
    }

    func testNonRetryableErrors() {
        let nonRetryableCodes: [CKError.Code] = [
            .unknownItem, .invalidArguments, .badContainer,
            .permissionFailure, .assetFileNotFound,
            .constraintViolation, .incompatibleVersion
        ]

        for code in nonRetryableCodes {
            let error = CKError(code)
            XCTAssertFalse(
                isCKRetryable(error),
                "\(code.rawValue) should NOT be retryable"
            )
        }
    }

    // MARK: - ckRetryDelay Backoff

    func testExponentialBackoffWithoutRetryAfter() {
        // No retryAfterSeconds → exponential: 2^attempt
        let error = CKError(.networkFailure)

        XCTAssertEqual(ckRetryDelay(for: error, attempt: 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(ckRetryDelay(for: error, attempt: 1), 2.0, accuracy: 0.01)
        XCTAssertEqual(ckRetryDelay(for: error, attempt: 2), 4.0, accuracy: 0.01)
    }

    func testRetryAfterHeaderTakesPrecedence() {
        // When CKError has retryAfterSeconds, use that instead of exponential
        let error = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 7.5])
        XCTAssertEqual(ckRetryDelay(for: error, attempt: 0), 7.5, accuracy: 0.01)
        XCTAssertEqual(ckRetryDelay(for: error, attempt: 2), 7.5, accuracy: 0.01)
    }

    // MARK: - serverRecordChanged Handling

    func testServerRecordChangedIsNotClassifiedAsRetryable() {
        // serverRecordChanged has special handling in saveWithRetry (fetch+retry),
        // but isCKRetryable should return false (it's not a generic retryable)
        let error = CKError(.serverRecordChanged)
        XCTAssertFalse(isCKRetryable(error))
    }
}

// MARK: - CKError Convenience Init

private extension CKError {
    init(_ code: CKError.Code, userInfo: [String: Any] = [:]) {
        let nsError = NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: userInfo)
        self = CKError(_nsError: nsError)
    }
}
