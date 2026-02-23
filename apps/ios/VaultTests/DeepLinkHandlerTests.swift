import XCTest
@testable import Vault

@MainActor
final class DeepLinkHandlerTests: XCTestCase {

    // MARK: - Test URLs

    private static let httpUrl = URL(string: "http://example.com/s#token123")!
    private static let wrongHostUrl = URL(string: "https://evil.com/s#token123")!
    private static let noFragmentUrl = URL(string: "vaultaire://s/")!
    private static let emptyFragmentUrl = URL(string: "vaultaire://s/#")!
    private static let unrelatedUrl = URL(string: "https://google.com")!
    private static let wrongPathUrl = URL(string: "vaultaire://x/something")!

    private var handler: DeepLinkHandler!

    override func setUp() {
        super.setUp()
        handler = DeepLinkHandler()
    }

    override func tearDown() {
        handler.clearPending()
        handler = nil
        super.tearDown()
    }

    // MARK: - Valid Share URLs

    func testValidShareUrlSetsPhrase() {
        // Generate a valid share URL
        guard let url = ShareLinkEncoder.shareURL(for: "test phrase for sharing") else {
            XCTFail("Could not generate share URL")
            return
        }

        let result = handler.handle(url)

        XCTAssertTrue(result)
        XCTAssertNotNil(handler.pendingSharePhrase)
        XCTAssertEqual(handler.pendingSharePhrase, "test phrase for sharing")
    }

    func testValidCustomSchemeUrlSetsPhrase() {
        // vaultaire://s/#<encoded>
        guard let url = ShareLinkEncoder.shareURL(for: "custom scheme phrase") else {
            XCTFail("Could not generate share URL")
            return
        }

        // Convert https URL to custom scheme
        guard let fragment = url.fragment else {
            XCTFail("No fragment in share URL")
            return
        }
        let customURL = URL(string: "vaultaire://s/#\(fragment)")!

        let result = handler.handle(customURL)

        XCTAssertTrue(result)
        XCTAssertEqual(handler.pendingSharePhrase, "custom scheme phrase")
    }

    // MARK: - Invalid URLs

    func testInvalidSchemeRejected() {
        let result = handler.handle(Self.httpUrl)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testWrongHostRejected() {
        let result = handler.handle(Self.wrongHostUrl)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testMissingFragmentRejected() {
        let result = handler.handle(Self.noFragmentUrl)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testEmptyFragmentRejected() {
        let result = handler.handle(Self.emptyFragmentUrl)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testMalformedUrlRejected() {
        let result = handler.handle(Self.unrelatedUrl)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testRandomCustomSchemeRejected() {
        let result = handler.handle(Self.wrongPathUrl)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    // MARK: - Clear Pending

    func testClearPendingRemovesPhrase() {
        guard let url = ShareLinkEncoder.shareURL(for: "will be cleared") else {
            XCTFail("Could not generate share URL")
            return
        }

        handler.handle(url)
        XCTAssertNotNil(handler.pendingSharePhrase)

        handler.clearPending()
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testClearPendingSafeWhenAlreadyNil() {
        handler.clearPending() // Should not crash
        XCTAssertNil(handler.pendingSharePhrase)
    }

    // MARK: - Round-Trip

    func testRoundTripPreservesPhrase() {
        let original = "my secret sharing phrase with spaces and punctuation!"
        guard let url = ShareLinkEncoder.shareURL(for: original) else {
            XCTFail("Could not generate share URL")
            return
        }

        handler.handle(url)

        XCTAssertEqual(handler.pendingSharePhrase, original)
    }

    func testRoundTripUnicodePhrase() {
        let original = "vault phrase with emojis"
        guard let url = ShareLinkEncoder.shareURL(for: original) else {
            XCTFail("Could not generate share URL")
            return
        }

        handler.handle(url)

        XCTAssertEqual(handler.pendingSharePhrase, original)
    }

    // MARK: - Overwrite Behavior

    func testSecondUrlOverwritesPrevious() {
        guard let url1 = ShareLinkEncoder.shareURL(for: "first phrase"),
              let url2 = ShareLinkEncoder.shareURL(for: "second phrase") else {
            XCTFail("Could not generate share URLs")
            return
        }

        handler.handle(url1)
        XCTAssertEqual(handler.pendingSharePhrase, "first phrase")

        handler.handle(url2)
        XCTAssertEqual(handler.pendingSharePhrase, "second phrase")
    }
}
