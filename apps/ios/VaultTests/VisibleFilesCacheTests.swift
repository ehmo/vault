import XCTest
@testable import Vault

/// Tests for the cached `visibleFiles` pipeline in VaultViewModel.
///
/// Verifies that:
/// - `recomputeVisibleFiles()` produces correct filter, sort, and grouping results
/// - `didSet` triggers on `files`, `searchText`, `sortOrder`, `fileFilter` invalidate the cache
/// - `dateGroups` are populated only for date-based sort orders
/// - `handleVaultKeyChange` resets the cache to empty
/// - `VisibleFiles.empty` is truly empty
/// - `mediaIndexById` maps correctly
@MainActor
final class VisibleFilesCacheTests: XCTestCase {

    private var viewModel: VaultViewModel!
    private var appState: AppState!
    private var subscriptionManager: SubscriptionManager!
    private var testKey: VaultKey!

    override func setUp() {
        super.setUp()
        // Clear persisted filter so tests start with a known state
        UserDefaults.standard.removeObject(forKey: "vaultFileFilter")

        appState = AppState()
        subscriptionManager = SubscriptionManager.shared
        testKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        appState.currentVaultKey = testKey

        viewModel = VaultViewModel()
        viewModel.configure(appState: appState, subscriptionManager: subscriptionManager)
        // Ensure default filter
        viewModel.fileFilter = .all
    }

    override func tearDown() {
        viewModel = nil
        appState = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeItem(
        id: UUID = UUID(),
        size: Int = 1024,
        mimeType: String? = "image/png",
        filename: String? = "photo.png",
        createdAt: Date? = Date(),
        originalDate: Date? = nil
    ) -> VaultFileItem {
        VaultFileItem(
            id: id,
            size: size,
            hasThumbnail: false,
            mimeType: mimeType,
            filename: filename,
            createdAt: createdAt,
            originalDate: originalDate
        )
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: startOfToday)!
            .addingTimeInterval(3600)
    }

    // MARK: - VisibleFiles.empty

    func testVisibleFilesEmptyIsEmpty() {
        let empty = VaultView.VisibleFiles.empty
        XCTAssertTrue(empty.all.isEmpty)
        XCTAssertTrue(empty.media.isEmpty)
        XCTAssertTrue(empty.documents.isEmpty)
        XCTAssertTrue(empty.mediaIndexById.isEmpty)
        XCTAssertTrue(empty.dateGroups.isEmpty)
    }

    func testInitialVisibleFilesIsEmpty() {
        XCTAssertEqual(viewModel.visibleFiles, VaultView.VisibleFiles.empty,
                       "Before any files are set, visibleFiles should be .empty")
    }

    // MARK: - didSet Triggers Recompute

    func testSettingFilesTriggersCacheUpdate() {
        let item = makeItem()
        viewModel.files = [item]

        XCTAssertEqual(viewModel.visibleFiles.all.count, 1,
                       "Setting files should trigger recompute and populate visibleFiles")
        XCTAssertEqual(viewModel.visibleFiles.all.first?.id, item.id)
    }

    func testSettingSameFilesStillRecomputes() {
        let item = makeItem()
        viewModel.files = [item]
        let first = viewModel.visibleFiles

        // didSet fires even when setting the same value (no guard on files)
        viewModel.files = [item]
        let second = viewModel.visibleFiles

        XCTAssertEqual(first, second, "Same files should produce identical visibleFiles")
    }

    func testSettingSearchTextTriggersCacheUpdate() {
        let a = makeItem(filename: "apple.png")
        let b = makeItem(mimeType: "image/jpeg", filename: "banana.jpg")
        viewModel.files = [a, b]
        XCTAssertEqual(viewModel.visibleFiles.all.count, 2)

        viewModel.searchText = "apple"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "apple.png")
    }

    func testSettingSameSearchTextDoesNotRecompute() {
        // Guard: if searchText != oldValue
        viewModel.searchText = "test"
        let before = viewModel.visibleFiles

        viewModel.searchText = "test" // same value
        let after = viewModel.visibleFiles

        XCTAssertEqual(before, after)
    }

    func testSettingSortOrderTriggersCacheUpdate() {
        let small = makeItem(size: 100, filename: "small.png")
        let big = makeItem(size: 99999, filename: "big.png")
        viewModel.files = [small, big]

        viewModel.sortOrder = .sizeLargest
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "big.png",
                       "sizeLargest should put the bigger file first")

        viewModel.sortOrder = .sizeSmallest
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "small.png",
                       "sizeSmallest should put the smaller file first")
    }

    func testSettingFileFilterTriggersCacheUpdate() {
        let photo = makeItem(mimeType: "image/jpeg", filename: "photo.jpg")
        let doc = makeItem(mimeType: "application/pdf", filename: "doc.pdf")
        viewModel.files = [photo, doc]
        XCTAssertEqual(viewModel.visibleFiles.all.count, 2)

        viewModel.fileFilter = .media
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "photo.jpg")

        viewModel.fileFilter = .documents
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "doc.pdf")

        viewModel.fileFilter = .all
        XCTAssertEqual(viewModel.visibleFiles.all.count, 2)
    }

    // MARK: - Filter Correctness

    func testMediaFilterIncludesImagesAndVideos() {
        let image = makeItem(mimeType: "image/png", filename: "img.png")
        let video = makeItem(mimeType: "video/mp4", filename: "vid.mp4")
        let pdf = makeItem(mimeType: "application/pdf", filename: "doc.pdf")
        let text = makeItem(mimeType: "text/plain", filename: "notes.txt")
        viewModel.files = [image, video, pdf, text]

        viewModel.fileFilter = .media
        XCTAssertEqual(viewModel.visibleFiles.all.count, 2)
        let filenames = Set(viewModel.visibleFiles.all.compactMap(\.filename))
        XCTAssertEqual(filenames, ["img.png", "vid.mp4"])
    }

    func testDocumentsFilterExcludesImagesAndVideos() {
        let image = makeItem(mimeType: "image/jpeg", filename: "img.jpg")
        let pdf = makeItem(mimeType: "application/pdf", filename: "doc.pdf")
        viewModel.files = [image, pdf]

        viewModel.fileFilter = .documents
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "doc.pdf")
    }

    func testNilMimeTypeTreatedAsNonMedia() {
        let nilMime = makeItem(mimeType: nil, filename: "unknown")
        viewModel.files = [nilMime]

        viewModel.fileFilter = .media
        XCTAssertEqual(viewModel.visibleFiles.all.count, 0,
                       "nil mimeType should not match media filter")

        viewModel.fileFilter = .documents
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1,
                       "nil mimeType should appear under documents filter")
    }

    // MARK: - Sort Correctness

    func testSortDateNewest() {
        let old = makeItem(filename: "old.png", createdAt: daysAgo(5))
        let new = makeItem(filename: "new.png", createdAt: Date())
        viewModel.files = [old, new]
        viewModel.sortOrder = .dateNewest

        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "new.png")
    }

    func testSortDateOldest() {
        let old = makeItem(filename: "old.png", createdAt: daysAgo(5))
        let new = makeItem(filename: "new.png", createdAt: Date())
        viewModel.files = [old, new]
        viewModel.sortOrder = .dateOldest

        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "old.png")
    }

    func testSortFileDate() {
        let noOriginal = makeItem(filename: "no-orig.png", createdAt: daysAgo(1), originalDate: nil)
        let withOriginal = makeItem(filename: "has-orig.png", createdAt: daysAgo(5), originalDate: Date())
        viewModel.files = [noOriginal, withOriginal]
        viewModel.sortOrder = .fileDate

        // fileDate sorts by originalDate ?? createdAt, newest first
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "has-orig.png",
                       "Item with today's originalDate should sort before one from yesterday")
    }

    func testSortByName() {
        let b = makeItem(filename: "Banana.png")
        let a = makeItem(filename: "Apple.png")
        let c = makeItem(filename: "Cherry.png")
        viewModel.files = [b, a, c]
        viewModel.sortOrder = .name

        let names = viewModel.visibleFiles.all.compactMap(\.filename)
        XCTAssertEqual(names, ["Apple.png", "Banana.png", "Cherry.png"])
    }

    func testSortNilCreatedAtTreatedAsDistantPast() {
        let withDate = makeItem(filename: "dated.png", createdAt: daysAgo(100))
        let noDate = makeItem(filename: "nodate.png", createdAt: nil)
        viewModel.files = [noDate, withDate]

        viewModel.sortOrder = .dateNewest
        XCTAssertEqual(viewModel.visibleFiles.all.first?.filename, "dated.png",
                       "nil createdAt should sort as distantPast, after any real date in newest-first")
    }

    // MARK: - Search Filter

    func testSearchIsLocalizedCaseInsensitive() {
        let item = makeItem(filename: "MyPhoto.PNG")
        viewModel.files = [item]

        viewModel.searchText = "myphoto"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1,
                       "Search should be case-insensitive")

        viewModel.searchText = "MYPHOTO"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)
    }

    func testSearchWithEmptyStringShowsAll() {
        let items = [makeItem(filename: "a.png"), makeItem(filename: "b.png")]
        viewModel.files = items

        viewModel.searchText = "a"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)

        viewModel.searchText = ""
        XCTAssertEqual(viewModel.visibleFiles.all.count, 2,
                       "Empty search should show all files")
    }

    func testSearchMatchesPartialFilename() {
        let item = makeItem(mimeType: "image/jpeg", filename: "vacation-photo-2024.jpg")
        viewModel.files = [item]

        viewModel.searchText = "vacation"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)

        viewModel.searchText = "photo"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)

        viewModel.searchText = "2024"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)

        viewModel.searchText = "xyz-no-match"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 0)
    }

    func testNilFilenameDoesNotMatchSearch() {
        let noName = makeItem(filename: nil)
        viewModel.files = [noName]

        viewModel.searchText = "test"
        XCTAssertEqual(viewModel.visibleFiles.all.count, 0,
                       "Item with nil filename should not match any search term")
    }

    // MARK: - Media / Documents Split

    func testMediaAndDocumentsSplitCorrectly() {
        let photo = makeItem(mimeType: "image/jpeg", filename: "photo.jpg")
        let video = makeItem(mimeType: "video/mp4", filename: "video.mp4")
        let pdf = makeItem(mimeType: "application/pdf", filename: "doc.pdf")
        let text = makeItem(mimeType: "text/plain", filename: "notes.txt")
        viewModel.files = [photo, video, pdf, text]

        let visible = viewModel.visibleFiles
        XCTAssertEqual(visible.all.count, 4)
        XCTAssertEqual(visible.media.count, 2, "photo + video should be media")
        XCTAssertEqual(visible.documents.count, 2, "pdf + text should be documents")
    }

    // MARK: - mediaIndexById

    func testMediaIndexByIdMapsCorrectly() {
        // Give distinct dates so dateNewest sort is deterministic
        let a = makeItem(mimeType: "image/png", filename: "a.png", createdAt: Date())
        let b = makeItem(mimeType: "image/jpeg", filename: "b.jpg", createdAt: daysAgo(1))
        let doc = makeItem(mimeType: "application/pdf", filename: "doc.pdf", createdAt: daysAgo(2))
        viewModel.files = [a, b, doc]

        let visible = viewModel.visibleFiles
        XCTAssertEqual(visible.media.count, 2)
        // dateNewest: a (today) comes first, b (yesterday) second
        XCTAssertEqual(visible.mediaIndexById[a.id], 0)
        XCTAssertEqual(visible.mediaIndexById[b.id], 1)
        XCTAssertNil(visible.mediaIndexById[doc.id],
                     "Non-media items should not be in mediaIndexById")
    }

    func testMediaIndexByIdRespectsCurrentSort() {
        let old = makeItem(mimeType: "image/png", filename: "old.png", createdAt: daysAgo(5))
        let new = makeItem(mimeType: "image/jpeg", filename: "new.jpg", createdAt: Date())
        viewModel.files = [old, new]

        viewModel.sortOrder = .dateNewest
        XCTAssertEqual(viewModel.visibleFiles.mediaIndexById[new.id], 0,
                       "Newest media should be at index 0 in dateNewest sort")
        XCTAssertEqual(viewModel.visibleFiles.mediaIndexById[old.id], 1)

        viewModel.sortOrder = .dateOldest
        XCTAssertEqual(viewModel.visibleFiles.mediaIndexById[old.id], 0,
                       "Oldest media should be at index 0 in dateOldest sort")
        XCTAssertEqual(viewModel.visibleFiles.mediaIndexById[new.id], 1)
    }

    // MARK: - Date Groups

    func testDateGroupsPopulatedForDateNewest() {
        let today = makeItem(filename: "today.png", createdAt: Date())
        let yesterday = makeItem(filename: "yesterday.png", createdAt: daysAgo(1))
        viewModel.files = [today, yesterday]
        viewModel.sortOrder = .dateNewest

        let groups = viewModel.visibleFiles.dateGroups
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Today")
        XCTAssertEqual(groups[1].title, "Yesterday")
    }

    func testDateGroupsPopulatedForDateOldest() {
        let today = makeItem(filename: "today.png", createdAt: Date())
        let yesterday = makeItem(filename: "yesterday.png", createdAt: daysAgo(1))
        viewModel.files = [today, yesterday]
        viewModel.sortOrder = .dateOldest

        let groups = viewModel.visibleFiles.dateGroups
        XCTAssertEqual(groups.count, 2)
        // Oldest first → Yesterday comes before Today
        XCTAssertEqual(groups[0].title, "Yesterday")
        XCTAssertEqual(groups[1].title, "Today")
    }

    func testDateGroupsPopulatedForFileDate() {
        let item = makeItem(filename: "item.png", createdAt: daysAgo(5), originalDate: Date())
        viewModel.files = [item]
        viewModel.sortOrder = .fileDate

        let groups = viewModel.visibleFiles.dateGroups
        XCTAssertEqual(groups.count, 1)
        // fileDate uses originalDate → today
        XCTAssertEqual(groups[0].title, "Today")
    }

    func testDateGroupsEmptyForNonDateSorts() {
        let items = [makeItem(filename: "a.png"), makeItem(filename: "b.png")]
        viewModel.files = items

        for nonDateSort: Vault.SortOrder in [.name, .sizeSmallest, .sizeLargest] {
            viewModel.sortOrder = nonDateSort
            XCTAssertTrue(viewModel.visibleFiles.dateGroups.isEmpty,
                          "dateGroups should be empty for sort order \(nonDateSort.rawValue)")
        }
    }

    func testDateGroupsContainCorrectMediaFileSplit() {
        let photo = makeItem(mimeType: "image/jpeg", filename: "photo.jpg", createdAt: Date())
        let pdf = makeItem(mimeType: "application/pdf", filename: "doc.pdf", createdAt: Date())
        viewModel.files = [photo, pdf]
        viewModel.sortOrder = .dateNewest

        let groups = viewModel.visibleFiles.dateGroups
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[0].media.count, 1)
        XCTAssertEqual(groups[0].files.count, 1)
    }

    // MARK: - Combined Filter + Sort + Search

    func testFilterSortSearchCombination() {
        let photoA = makeItem(mimeType: "image/png", filename: "alpha.png", createdAt: daysAgo(3))
        let photoB = makeItem(mimeType: "image/jpeg", filename: "beta.jpg", createdAt: Date())
        let doc = makeItem(mimeType: "application/pdf", filename: "alpha-doc.pdf", createdAt: Date())
        viewModel.files = [photoA, photoB, doc]

        viewModel.fileFilter = .media
        viewModel.sortOrder = .dateNewest
        viewModel.searchText = "alpha"

        let visible = viewModel.visibleFiles
        XCTAssertEqual(visible.all.count, 1, "Only alpha.png should match: media + 'alpha' search")
        XCTAssertEqual(visible.all.first?.filename, "alpha.png")
    }

    // MARK: - handleVaultKeyChange Clears Cache

    func testHandleVaultKeyChangeClearsVisibleFiles() {
        viewModel.files = [makeItem(), makeItem(), makeItem()]
        XCTAssertEqual(viewModel.visibleFiles.all.count, 3)

        let newKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
        viewModel.handleVaultKeyChange(oldKey: testKey, newKey: newKey)

        XCTAssertEqual(viewModel.visibleFiles, VaultView.VisibleFiles.empty,
                       "Vault key change clears files which triggers recompute to .empty")
    }

    func testHandleVaultKeyChangeSameKeyDoesNotClearFiles() {
        viewModel.files = [makeItem(), makeItem()]
        XCTAssertEqual(viewModel.visibleFiles.all.count, 2)

        // Same key → no clear
        viewModel.handleVaultKeyChange(oldKey: testKey, newKey: testKey)

        XCTAssertEqual(viewModel.visibleFiles.all.count, 2,
                       "Same vault key should not clear files")
    }

    // MARK: - Equatable Conformance

    func testVisibleFilesEquatable() {
        let item = makeItem()
        viewModel.files = [item]
        let a = viewModel.visibleFiles

        // Recompute with same inputs
        viewModel.files = [item]
        let b = viewModel.visibleFiles

        XCTAssertEqual(a, b, "Same inputs should produce equal VisibleFiles")
    }

    func testVisibleFilesNotEqualAfterFilterChange() {
        let photo = makeItem(mimeType: "image/jpeg", filename: "photo.jpg", createdAt: Date())
        let doc = makeItem(mimeType: "application/pdf", filename: "doc.pdf", createdAt: daysAgo(1))
        viewModel.fileFilter = .all
        viewModel.files = [photo, doc]
        let allFilter = viewModel.visibleFiles
        XCTAssertEqual(allFilter.all.count, 2, "All filter should show both files")

        viewModel.fileFilter = .media
        let mediaFilter = viewModel.visibleFiles
        XCTAssertEqual(mediaFilter.all.count, 1, "Media filter should show only photo")

        XCTAssertNotEqual(allFilter, mediaFilter,
                          "Different filters should produce non-equal VisibleFiles")
    }

    // MARK: - Empty Files

    func testEmptyFilesProducesEmptyVisibleFiles() {
        viewModel.files = []
        let visible = viewModel.visibleFiles
        XCTAssertTrue(visible.all.isEmpty)
        XCTAssertTrue(visible.media.isEmpty)
        XCTAssertTrue(visible.documents.isEmpty)
        XCTAssertTrue(visible.mediaIndexById.isEmpty)
        XCTAssertTrue(visible.dateGroups.isEmpty)
    }

    // MARK: - useDateGrouping Property

    func testUseDateGrouping() {
        viewModel.sortOrder = .dateNewest
        XCTAssertTrue(viewModel.useDateGrouping)

        viewModel.sortOrder = .dateOldest
        XCTAssertTrue(viewModel.useDateGrouping)

        viewModel.sortOrder = .fileDate
        XCTAssertTrue(viewModel.useDateGrouping)

        viewModel.sortOrder = .name
        XCTAssertFalse(viewModel.useDateGrouping)

        viewModel.sortOrder = .sizeSmallest
        XCTAssertFalse(viewModel.useDateGrouping)

        viewModel.sortOrder = .sizeLargest
        XCTAssertFalse(viewModel.useDateGrouping)
    }

    // MARK: - setFileFilter Persists and Updates

    func testSetFileFilterUpdatesVisibleFiles() {
        let photo = makeItem(mimeType: "image/jpeg", filename: "photo.jpg")
        let doc = makeItem(mimeType: "text/plain", filename: "note.txt")
        viewModel.files = [photo, doc]

        viewModel.setFileFilter(.media)
        XCTAssertEqual(viewModel.visibleFiles.all.count, 1)
        XCTAssertEqual(viewModel.fileFilter, .media)
    }

    // MARK: - Large Dataset Sanity

    func testLargeFileListProducesCorrectCounts() {
        var items: [VaultFileItem] = []
        for i in 0..<500 {
            let isMedia = i % 3 != 0
            items.append(makeItem(
                mimeType: isMedia ? "image/jpeg" : "application/pdf",
                filename: "file\(i).\(isMedia ? "jpg" : "pdf")",
                createdAt: daysAgo(i % 30)
            ))
        }
        viewModel.files = items

        let visible = viewModel.visibleFiles
        XCTAssertEqual(visible.all.count, 500)
        let expectedMedia = items.filter { $0.isMedia }.count
        let expectedDocs = items.filter { !$0.isMedia }.count
        XCTAssertEqual(visible.media.count, expectedMedia)
        XCTAssertEqual(visible.documents.count, expectedDocs)
        XCTAssertEqual(visible.media.count + visible.documents.count, 500)
    }
}
