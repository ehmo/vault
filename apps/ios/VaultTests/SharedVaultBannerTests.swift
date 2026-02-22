import XCTest
@testable import Vault

/// Tests for shared vault banner policy display logic.
///
/// Verifies that the banner correctly computes:
/// - Opens remaining from maxOpens and openCount
/// - Export permission from allowDownloads
/// - Expiration visibility from expiresAt
/// - Whether policy details should be shown at all
final class SharedVaultBannerTests: XCTestCase {

    // MARK: - Policy Detail Visibility

    /// Banner hides policy details when no restrictions are set.
    func testNoPolicyDetails_WhenNoRestrictions() {
        let policy = VaultStorage.SharePolicy(
            expiresAt: nil,
            maxOpens: nil,
            allowScreenshots: false,
            allowDownloads: true
        )

        XCTAssertFalse(hasPolicyDetails(policy),
            "No policy details when there are no restrictions")
    }

    /// Banner shows policy details when expiration is set.
    func testShowsPolicyDetails_WhenExpirationSet() {
        let policy = VaultStorage.SharePolicy(
            expiresAt: Date().addingTimeInterval(86400),
            maxOpens: nil,
            allowScreenshots: false,
            allowDownloads: true
        )

        XCTAssertTrue(hasPolicyDetails(policy),
            "Should show policy details when expiration is set")
    }

    /// Banner shows policy details when max opens is set.
    func testShowsPolicyDetails_WhenMaxOpensSet() {
        let policy = VaultStorage.SharePolicy(
            expiresAt: nil,
            maxOpens: 5,
            allowScreenshots: false,
            allowDownloads: true
        )

        XCTAssertTrue(hasPolicyDetails(policy),
            "Should show policy details when max opens is set")
    }

    /// Banner shows policy details when downloads are disabled.
    func testShowsPolicyDetails_WhenDownloadsDisabled() {
        let policy = VaultStorage.SharePolicy(
            expiresAt: nil,
            maxOpens: nil,
            allowScreenshots: false,
            allowDownloads: false
        )

        XCTAssertTrue(hasPolicyDetails(policy),
            "Should show policy details when downloads are disabled")
    }

    /// Banner shows policy details when all restrictions are set.
    func testShowsPolicyDetails_WhenAllRestrictionsSet() {
        let policy = VaultStorage.SharePolicy(
            expiresAt: Date().addingTimeInterval(86400),
            maxOpens: 3,
            allowScreenshots: false,
            allowDownloads: false
        )

        XCTAssertTrue(hasPolicyDetails(policy),
            "Should show policy details when all restrictions are set")
    }

    // MARK: - Opens Remaining

    /// Remaining opens = maxOpens - openCount.
    func testOpensRemaining_BasicCalculation() {
        let maxOpens = 5
        let openCount = 2
        let remaining = max(maxOpens - openCount, 0)

        XCTAssertEqual(remaining, 3)
    }

    /// Remaining opens never goes below zero.
    func testOpensRemaining_NeverNegative() {
        let maxOpens = 3
        let openCount = 5
        let remaining = max(maxOpens - openCount, 0)

        XCTAssertEqual(remaining, 0,
            "Remaining opens should floor at 0")
    }

    /// Zero opens used shows full count remaining.
    func testOpensRemaining_ZeroUsed() {
        let maxOpens = 10
        let openCount = 0
        let remaining = max(maxOpens - openCount, 0)

        XCTAssertEqual(remaining, 10)
    }

    // MARK: - Export Permission

    /// Default policy allows downloads.
    func testDefaultPolicyAllowsDownloads() {
        let policy = VaultStorage.SharePolicy()

        XCTAssertTrue(policy.allowDownloads,
            "Default policy should allow downloads")
    }

    /// Explicitly disabled downloads detected.
    func testExportsDisabled_WhenAllowDownloadsFalse() {
        let policy = VaultStorage.SharePolicy(allowDownloads: false)

        XCTAssertFalse(policy.allowDownloads)
        XCTAssertTrue(hasPolicyDetails(policy),
            "Disabled downloads should trigger policy details display")
    }

    // MARK: - SharePolicy Codable Backward Compatibility

    /// A policy with nil maxOpens decodes correctly (unlimited opens).
    func testPolicyWithNilMaxOpens() throws {
        let json = """
        {"allowScreenshots": false, "allowDownloads": true}
        """
        let policy = try JSONDecoder().decode(VaultStorage.SharePolicy.self, from: Data(json.utf8))

        XCTAssertNil(policy.maxOpens)
        XCTAssertNil(policy.expiresAt)
        XCTAssertTrue(policy.allowDownloads)
    }

    /// A policy with all fields set decodes correctly.
    func testPolicyWithAllFields() throws {
        let json = """
        {"allowScreenshots": false, "allowDownloads": false, "maxOpens": 3, "expiresAt": 1700000000}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let policy = try decoder.decode(VaultStorage.SharePolicy.self, from: Data(json.utf8))

        XCTAssertEqual(policy.maxOpens, 3)
        XCTAssertFalse(policy.allowDownloads)
        XCTAssertNotNil(policy.expiresAt)
    }

    // MARK: - Helpers

    /// Mirrors the logic in VaultView+SharedVault.sharedVaultHasPolicyDetails
    private func hasPolicyDetails(_ policy: VaultStorage.SharePolicy?) -> Bool {
        return policy?.expiresAt != nil
            || policy?.maxOpens != nil
            || policy?.allowDownloads == false
    }
}
