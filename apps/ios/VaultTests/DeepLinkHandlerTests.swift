import XCTest
@testable import Vault

@MainActor
final class DeepLinkHandlerTests: XCTestCase {

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

    func testValidShareURL_setsPhrase() {
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

    func testValidCustomSchemeURL_setsPhrase() {
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

    func testInvalidScheme_rejected() {
        let url = URL(string: "http://example.com/s#token123")!
        let result = handler.handle(url)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testWrongHost_rejected() {
        let url = URL(string: "https://evil.com/s#token123")!
        let result = handler.handle(url)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testMissingFragment_rejected() {
        let url = URL(string: "vaultaire://s/")!
        let result = handler.handle(url)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testEmptyFragment_rejected() {
        let url = URL(string: "vaultaire://s/#")!
        let result = handler.handle(url)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testMalformedURL_rejected() {
        // Totally unrelated URL
        let url = URL(string: "https://google.com")!
        let result = handler.handle(url)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testRandomCustomScheme_rejected() {
        let url = URL(string: "vaultaire://x/something")!
        let result = handler.handle(url)

        XCTAssertFalse(result)
        XCTAssertNil(handler.pendingSharePhrase)
    }

    // MARK: - Clear Pending

    func testClearPending_removesPhrase() {
        guard let url = ShareLinkEncoder.shareURL(for: "will be cleared") else {
            XCTFail("Could not generate share URL")
            return
        }

        handler.handle(url)
        XCTAssertNotNil(handler.pendingSharePhrase)

        handler.clearPending()
        XCTAssertNil(handler.pendingSharePhrase)
    }

    func testClearPending_safeWhenAlreadyNil() {
        handler.clearPending() // Should not crash
        XCTAssertNil(handler.pendingSharePhrase)
    }

    // MARK: - Round-Trip

    func testRoundTrip_preservesPhrase() {
        let original = "my secret sharing phrase with spaces and punctuation!"
        guard let url = ShareLinkEncoder.shareURL(for: original) else {
            XCTFail("Could not generate share URL")
            return
        }

        handler.handle(url)

        XCTAssertEqual(handler.pendingSharePhrase, original)
    }

    func testRoundTrip_unicodePhrase() {
        let original = "vault phrase with emojis"
        guard let url = ShareLinkEncoder.shareURL(for: original) else {
            XCTFail("Could not generate share URL")
            return
        }

        handler.handle(url)

        XCTAssertEqual(handler.pendingSharePhrase, original)
    }

    // MARK: - Overwrite Behavior

    func testSecondURL_overwritesPrevious() {
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
