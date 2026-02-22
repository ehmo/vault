import XCTest
@testable import Vault

final class DragRowSelectorTests: XCTestCase {

    // MARK: - indicesInRowSpan

    /// Dragging within one row returns only that row's items.
    func testSingleRow() {
        // 3 columns, 9 items. Start index 0, end index 2 → both in row 0.
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 9, columns: 3, startIndex: 0, endIndex: 2
        )
        XCTAssertEqual(result, Set(0..<3))
    }

    /// Dragging across multiple rows returns all items in spanned rows.
    func testMultipleRows() {
        // 3 columns, 12 items. Start index 1 (row 0), end index 7 (row 2).
        // Rows 0, 1, 2 → indices 0..<9
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 12, columns: 3, startIndex: 1, endIndex: 7
        )
        XCTAssertEqual(result, Set(0..<9))
    }

    /// Dragging upward (endIndex < startIndex) produces the same result as downward.
    func testReverseDirection() {
        let forward = DragRowSelector.indicesInRowSpan(
            itemCount: 12, columns: 3, startIndex: 1, endIndex: 7
        )
        let reverse = DragRowSelector.indicesInRowSpan(
            itemCount: 12, columns: 3, startIndex: 7, endIndex: 1
        )
        XCTAssertEqual(forward, reverse)
    }

    /// Last row with fewer items than columns is handled correctly.
    func testLastRowPartial() {
        // 3 columns, 10 items. Last row has 1 item (index 9).
        // Start index 0 (row 0), end index 9 (row 3).
        // Rows 0-3 → indices 0..<10
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 10, columns: 3, startIndex: 0, endIndex: 9
        )
        XCTAssertEqual(result, Set(0..<10))
    }

    /// Partial last row included when dragging into it.
    func testPartialLastRowIncluded() {
        // 3 columns, 7 items. Row 0: 0,1,2. Row 1: 3,4,5. Row 2: 6.
        // Start row 1, end row 2 → indices 3,4,5,6
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 7, columns: 3, startIndex: 4, endIndex: 6
        )
        XCTAssertEqual(result, Set(3...6))
    }

    /// Empty grid returns empty set.
    func testEmptyGrid() {
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 0, columns: 3, startIndex: 0, endIndex: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Zero columns returns empty set (guard).
    func testZeroColumns() {
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 10, columns: 0, startIndex: 0, endIndex: 5
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Single column: each item is its own row.
    func testSingleColumn() {
        // 1 column, 5 items. Start index 1, end index 3 → items 1,2,3
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 5, columns: 1, startIndex: 1, endIndex: 3
        )
        XCTAssertEqual(result, Set(1...3))
    }

    /// First to last spans the entire grid.
    func testEntireGrid() {
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 12, columns: 3, startIndex: 0, endIndex: 11
        )
        XCTAssertEqual(result, Set(0..<12))
    }

    /// Start and end on the same item returns that item's entire row.
    func testSameIndex() {
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 9, columns: 3, startIndex: 4, endIndex: 4
        )
        // Index 4 is in row 1 → indices 3,4,5
        XCTAssertEqual(result, Set(3...5))
    }

    /// Out-of-bounds indices are clamped.
    func testOutOfBoundsClamped() {
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 9, columns: 3, startIndex: -5, endIndex: 100
        )
        // Clamped to 0 and 8 → rows 0-2 → all 9 items
        XCTAssertEqual(result, Set(0..<9))
    }

    /// Verifies correct row calculation for 4-column grid.
    func testFourColumns() {
        // 4 columns, 13 items.
        // Row 0: 0,1,2,3. Row 1: 4,5,6,7. Row 2: 8,9,10,11. Row 3: 12.
        // Start index 5 (row 1), end index 10 (row 2) → indices 4..<12
        let result = DragRowSelector.indicesInRowSpan(
            itemCount: 13, columns: 4, startIndex: 5, endIndex: 10
        )
        XCTAssertEqual(result, Set(4..<12))
    }
}
