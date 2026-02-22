import CoreGraphics

/// Pure geometry helpers for grid drag-to-select behavior.
/// Computes which item indices fall within a row span for Photos-app-style
/// vertical drag selection. Extracted for testability — no UIKit/SwiftUI deps.
enum DragRowSelector {

    /// Returns all item indices in rows spanned from the row containing `startIndex`
    /// to the row containing `endIndex` (inclusive, bidirectional).
    ///
    /// Example: 3 columns, 10 items, startIndex=1, endIndex=7
    ///   Row 0: indices 0,1,2  (row of startIndex)
    ///   Row 1: indices 3,4,5
    ///   Row 2: indices 6,7,8  (row of endIndex)
    ///   → returns {0,1,2,3,4,5,6,7,8}
    static func indicesInRowSpan(
        itemCount: Int,
        columns: Int,
        startIndex: Int,
        endIndex: Int
    ) -> Set<Int> {
        guard columns > 0, itemCount > 0 else { return [] }
        let clamp = { (i: Int) in max(0, min(i, itemCount - 1)) }
        let s = clamp(startIndex)
        let e = clamp(endIndex)
        let minRow = min(s / columns, e / columns)
        let maxRow = max(s / columns, e / columns)
        let first = minRow * columns
        let last = min((maxRow + 1) * columns, itemCount)
        return Set(first..<last)
    }
}
