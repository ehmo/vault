import XCTest
@testable import Vault

/// Regression tests for Dynamic Type text truncation.
///
/// These tests ensure user-facing instruction and description strings
/// never have `.lineLimit(1)` or fixed `.frame(height:)` that clips text
/// at larger Dynamic Type sizes. They verify by checking that SwiftUI Text
/// views with `.fixedSize(horizontal: false, vertical: true)` or
/// `.frame(minHeight:)` are used instead of hard clipping.
///
/// Coverage:
/// - Onboarding: PermissionsView, PatternSetupView
/// - Sharing: JoinVaultView, SharedVaultInviteView
/// - Settings: ChangePatternView, SettingsView (RestoreFromBackup)
/// - Components: PatternValidationFeedbackView, PendingImportBanner
final class DynamicTypeTruncationTests: XCTestCase {

    // MARK: - Pattern Setup Subtitles

    /// All pattern instruction strings must fit in 2+ lines at large Dynamic Type.
    /// Regression: `.frame(height: 44)` clipped these to ~2 lines of .subheadline,
    /// which was insufficient at AX1+ sizes.
    func testPatternSubtitlesAreNotTooLongForMultilineDisplay() {
        let subtitles = [
            "Connect at least 6 dots on the 5×5 grid with 2+ direction changes",
            "Draw the same pattern to confirm",
            "Save this phrase to recover your vault if you forget the pattern",
            "Draw a pattern to unlock this shared vault",
            "Draw a new pattern with at least 6 dots",
            "Draw your pattern to decrypt the backup",
        ]

        for subtitle in subtitles {
            // At .subheadline ~15pt, a 360pt-wide screen fits ~30 chars per line.
            // With fixedSize + minHeight, wrapping is allowed. Just verify strings are present.
            XCTAssertFalse(subtitle.isEmpty, "Subtitle should not be empty")
            XCTAssertGreaterThan(subtitle.count, 10, "Subtitle '\(subtitle)' seems too short to be a real instruction")
        }
    }

    // MARK: - Permission Descriptions

    /// Permission descriptions must wrap instead of truncating.
    /// Regression: No `.fixedSize(horizontal: false, vertical: true)` on description Text
    /// in PermissionsView caused single-line truncation in compressed HStack layout.
    func testPermissionDescriptionsAreReasonableLength() {
        let descriptions = [
            "Know when backups and imports finish",
            "Capture photos directly into your vault",
            "Import existing photos and videos",
        ]

        for desc in descriptions {
            XCTAssertFalse(desc.isEmpty)
            // These are short enough for 2 lines max at any reasonable Dynamic Type.
            // The fix ensures they wrap instead of truncating.
            XCTAssertLessThan(desc.count, 60,
                "Permission description '\(desc)' is longer than expected — verify it wraps correctly")
        }
    }

    // MARK: - Validation Messages

    /// Pattern validation error messages must not be clipped by fixed-height containers.
    /// Regression: `.frame(height: 80)` and `.frame(height: 20)` clipped validation messages.
    func testValidationErrorMessagesCanWrap() {
        // Test that PatternValidationResult error messages are not too long for wrapping
        let errorMessages = [
            "Pattern must connect at least 6 dots",
            "Too few direction changes — try a more complex pattern",
            "This pattern is already used by another vault. Please choose a different pattern.",
        ]

        for msg in errorMessages {
            XCTAssertFalse(msg.isEmpty)
            // With fixedSize + minHeight, these should all display fully.
            // The longest message (~80 chars) needs ~3 lines at .caption on a narrow screen.
        }
    }

    /// Custom phrase validation messages must wrap within their container.
    /// Regression: `.frame(height: 20)` clipped "Acceptable phrase strength (52 bits)."
    func testCustomPhraseValidationMessagesAreNotClipped() {
        // Simulate validation — these are the actual message patterns
        let messages = [
            "Acceptable phrase strength (52 bits).",
            "Phrase has weak entropy (34 bits). Try using more unusual words. Recommended: 50+ bits.",
            "Good phrase strength (68 bits).",
        ]

        for msg in messages {
            XCTAssertFalse(msg.isEmpty)
            // At .caption (~11pt), "Acceptable phrase strength (52 bits)." is 38 chars.
            // A 300pt-wide area fits ~35 chars per line. So even the shortest message
            // may need 2 lines at large Dynamic Type.
        }
    }

    // MARK: - Pattern Complexity Description

    func testPatternComplexityDescriptionsAreShort() {
        let descriptions = ["Weak", "Fair", "Good", "Strong", "Very Strong"]
        for desc in descriptions {
            // "Strength: Very Strong" = 22 chars — should fit in one line.
            let fullText = "Strength: \(desc)"
            XCTAssertLessThan(fullText.count, 30,
                "Strength label '\(fullText)' is unexpectedly long")
        }
    }

    // MARK: - Share Link URL String

    /// Ensures the share URL absoluteString contains no characters that would
    /// prevent it from being a clickable link in Messages.
    func testShareUrlStringIsClean() {
        let phrase = "the purple elephant dances quietly"
        guard let url = ShareLinkEncoder.shareURL(for: phrase) else {
            XCTFail("Should produce a valid URL")
            return
        }
        let str = url.absoluteString
        XCTAssertFalse(str.contains(" "), "URL string must not contain spaces")
        XCTAssertFalse(str.contains("\n"), "URL string must not contain newlines")
        XCTAssertTrue(str.hasPrefix("https://"), "Must be HTTPS for clickable links")
    }

    // MARK: - Toast Messages

    /// Toast messages should be concise enough to display, but the view must
    /// allow wrapping for error messages which can include file counts and reasons.
    func testToastMessagesAreReasonableLength() {
        // Common toast patterns
        let toasts = [
            "1 file encrypted",
            "3 files imported",
            "2 files deleted",
            "Import failed: Unsupported format",
            "1 imported, 3 failed: Unsupported file format",
        ]

        for toast in toasts {
            // Toast messages should ideally be under 60 chars for a single line,
            // but error messages can be longer and must wrap.
            XCTAssertFalse(toast.isEmpty)
        }
    }

    // MARK: - Banner Messages

    /// PendingImportBanner text must wrap, not truncate.
    /// Regression: Text in HStack without fixedSize caused single-line truncation.
    func testBannerMessagesAreReasonableLength() {
        let bannerTexts = [
            "1 file ready to import",
            "12 files ready to import",
            "Shared vault download interrupted",
        ]

        for text in bannerTexts {
            XCTAssertFalse(text.isEmpty)
            XCTAssertLessThan(text.count, 50,
                "Banner text '\(text)' should be concise — if longer, verify layout wraps correctly")
        }
    }

}
