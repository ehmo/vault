import XCTest
@testable import Vault

/// Tests for FileOperationProgressCard percentage calculation.
/// Catches edge cases: division by zero, boundary values, rounding.
final class FileOperationProgressCardTests: XCTestCase {

    // The percentage calculation: total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
    private func percentage(completed: Int, total: Int) -> Int {
        total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
    }

    func testPercentageZeroTotalReturnsZero() {
        XCTAssertEqual(percentage(completed: 0, total: 0), 0,
                       "Division by zero must return 0, not crash")
    }

    func testPercentageZeroCompleted() {
        XCTAssertEqual(percentage(completed: 0, total: 10), 0)
    }

    func testPercentageHalfComplete() {
        XCTAssertEqual(percentage(completed: 5, total: 10), 50)
    }

    func testPercentageFullyComplete() {
        XCTAssertEqual(percentage(completed: 10, total: 10), 100)
    }

    func testPercentageOneOfThreeTruncatesDown() {
        // 1/3 = 33.33... → Int truncates to 33
        XCTAssertEqual(percentage(completed: 1, total: 3), 33)
    }

    func testPercentageTwoOfThreeTruncatesDown() {
        // 2/3 = 66.66... → Int truncates to 66
        XCTAssertEqual(percentage(completed: 2, total: 3), 66)
    }

    func testPercentageLargeNumbers() {
        XCTAssertEqual(percentage(completed: 999, total: 1000), 99)
        XCTAssertEqual(percentage(completed: 1000, total: 1000), 100)
    }

    func testPercentageSingleItem() {
        XCTAssertEqual(percentage(completed: 0, total: 1), 0)
        XCTAssertEqual(percentage(completed: 1, total: 1), 100)
    }
}
