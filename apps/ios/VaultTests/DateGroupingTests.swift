import XCTest
@testable import Vault

final class DateGroupingTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(
        id: UUID = UUID(),
        mimeType: String? = "image/png",
        createdAt: Date? = nil
    ) -> VaultFileItem {
        VaultFileItem(
            id: id,
            size: 1024,
            encryptedThumbnail: nil,
            mimeType: mimeType,
            filename: "test.png",
            createdAt: createdAt
        )
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: startOfToday)!
            .addingTimeInterval(3600) // 1am that day
    }

    // MARK: - Empty Input

    func testEmptyInputReturnsNoGroups() {
        let groups = groupFilesByDate([], newestFirst: true)
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Today / Yesterday Labels

    func testTodayItemsGetTodayTitle() {
        let item = makeItem(createdAt: Date()) // now = today
        let groups = groupFilesByDate([item])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Today")
    }

    func testYesterdayItemsGetYesterdayTitle() {
        let item = makeItem(createdAt: daysAgo(1))
        let groups = groupFilesByDate([item])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Yesterday")
    }

    func testOlderItemsGetFormattedDateTitle() {
        let item = makeItem(createdAt: daysAgo(5))
        let groups = groupFilesByDate([item])
        XCTAssertEqual(groups.count, 1)
        // Should NOT be "Today" or "Yesterday"
        XCTAssertNotEqual(groups[0].title, "Today")
        XCTAssertNotEqual(groups[0].title, "Yesterday")
        // Should contain day name (e.g., "Sunday, February 9")
        XCTAssertTrue(groups[0].title.contains(","),
                      "Formatted date should contain comma: got '\(groups[0].title)'")
    }

    // MARK: - Grouping by Day

    func testMultipleItemsSameDayGroupedTogether() {
        let morning = startOfToday.addingTimeInterval(3600) // 1am
        let afternoon = startOfToday.addingTimeInterval(50400) // 2pm
        let item1 = makeItem(createdAt: morning)
        let item2 = makeItem(createdAt: afternoon)

        let groups = groupFilesByDate([item1, item2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 2)
    }

    func testItemsOnDifferentDaysCreateSeparateGroups() {
        let todayItem = makeItem(createdAt: Date())
        let yesterdayItem = makeItem(createdAt: daysAgo(1))
        let olderItem = makeItem(createdAt: daysAgo(5))

        let groups = groupFilesByDate([todayItem, yesterdayItem, olderItem])
        XCTAssertEqual(groups.count, 3)
    }

    // MARK: - Sort Order

    func testNewestFirstSortOrder() {
        let todayItem = makeItem(createdAt: Date())
        let olderItem = makeItem(createdAt: daysAgo(3))

        let groups = groupFilesByDate([olderItem, todayItem], newestFirst: true)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Today")
    }

    func testOldestFirstSortOrder() {
        let todayItem = makeItem(createdAt: Date())
        let olderItem = makeItem(createdAt: daysAgo(3))

        let groups = groupFilesByDate([olderItem, todayItem], newestFirst: false)
        XCTAssertEqual(groups.count, 2)
        // Oldest should be first
        XCTAssertNotEqual(groups[0].title, "Today")
        XCTAssertEqual(groups[1].title, "Today")
    }

    // MARK: - Media / Files Split

    func testGroupSplitsMediaAndFiles() {
        let photo = makeItem(mimeType: "image/jpeg", createdAt: Date())
        let video = makeItem(mimeType: "video/mp4", createdAt: Date())
        let doc = makeItem(mimeType: "application/pdf", createdAt: Date())

        let groups = groupFilesByDate([photo, video, doc])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 3)
        XCTAssertEqual(groups[0].media.count, 2, "photo + video should be media")
        XCTAssertEqual(groups[0].files.count, 1, "pdf should be non-media file")
    }

    // MARK: - Nil Dates

    func testItemsWithNilDatesGroupTogether() {
        let item1 = makeItem(createdAt: nil)
        let item2 = makeItem(createdAt: nil)

        let groups = groupFilesByDate([item1, item2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 2)
    }

    // MARK: - Unique IDs

    func testGroupIdsAreUniqueISO8601Strings() {
        let todayItem = makeItem(createdAt: Date())
        let yesterdayItem = makeItem(createdAt: daysAgo(1))

        let groups = groupFilesByDate([todayItem, yesterdayItem])
        XCTAssertEqual(groups.count, 2)
        XCTAssertNotEqual(groups[0].id, groups[1].id)
        // IDs should be ISO8601 formatted strings
        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: groups[0].id),
                        "Group ID should be valid ISO8601: \(groups[0].id)")
        XCTAssertNotNil(formatter.date(from: groups[1].id),
                        "Group ID should be valid ISO8601: \(groups[1].id)")
    }

    // MARK: - Default Parameter

    func testDefaultSortIsNewestFirst() {
        let todayItem = makeItem(createdAt: Date())
        let olderItem = makeItem(createdAt: daysAgo(3))

        let groups = groupFilesByDate([olderItem, todayItem])
        XCTAssertEqual(groups[0].title, "Today",
                       "Default sort should be newest first")
    }
}
