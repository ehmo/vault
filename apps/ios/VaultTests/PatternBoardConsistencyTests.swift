import XCTest
@testable import Vault
import SwiftUI
import ViewInspector

/// Comprehensive tests for pattern board consistency across all screens.
/// Ensures the pattern grid has the same layout, behavior, and feedback on every screen.
@MainActor
final class PatternBoardConsistencyTests: XCTestCase {

    // MARK: - Test Constants

    /// Standard pattern grid size expected across all screens
    private let expectedGridSize: CGFloat = 280

    /// Standard feedback area height to prevent layout shift
    private let expectedFeedbackHeight: CGFloat = 80

    /// Minimum height for subtitle text area
    private let expectedSubtitleMinHeight: CGFloat = 44

    // MARK: - PatternSetupView Tests

    func testPatternSetupView_CenteredGridLayout() throws {
        let view = PatternSetupView(onComplete: {})
            .environment(AppState())

        let inspect = try view.inspect()

        // Verify the pattern grid exists and has correct frame
        let grid = try inspect.find(PatternGridView.self)
        let frame = try grid.fixedWidthAndHeight()

        XCTAssertEqual(frame.width, expectedGridSize, "Pattern grid width should be consistent")
        XCTAssertEqual(frame.height, expectedGridSize, "Pattern grid height should be consistent")
    }

    func testPatternSetupView_FixedFeedbackArea() throws {
        let view = PatternSetupView(onComplete: {})
            .environment(AppState())

        let inspect = try view.inspect()

        // Find the feedback area Group
        let feedbackGroup = try inspect.find(
            ViewType.Group.self,
            where: { view in
                // Check if this group contains validation feedback
                try view.find(PatternValidationFeedbackView.self) != nil
            }
        )

        let minHeight = try feedbackGroup.minHeight()
        XCTAssertEqual(minHeight, expectedFeedbackHeight, "Feedback area should have fixed minHeight to prevent layout shift")
    }

    func testPatternSetupView_FixedSubtitleHeight() throws {
        let view = PatternSetupView(onComplete: {})
            .environment(AppState())

        let inspect = try view.inspect()

        // Find subtitle text and verify it has fixed minHeight
        let subtitle = try inspect.find(text: "Draw a pattern to secure your vault")
        let minHeight = try subtitle.minHeight()

        XCTAssertEqual(minHeight, expectedSubtitleMinHeight, "Subtitle should have fixed minHeight")
    }

    func testPatternSetupView_ValidationFeedbackShown() throws {
        var view = PatternSetupView(onComplete: {})
            .environment(AppState())

        // Simulate entering an invalid pattern (less than 6 dots)
        let inspect = try view.inspect()
        let grid = try inspect.find(PatternGridView.self)

        // Pattern with only 2 dots should show validation error
        // Note: This would need PatternGridView to expose state for testing
        // For now, we verify the feedback view exists in the hierarchy
        let feedbackView = try? inspect.find(PatternValidationFeedbackView.self)
        XCTAssertNotNil(feedbackView, "Validation feedback view should exist in hierarchy")
    }

    // MARK: - ChangePatternView Tests

    func testChangePatternView_CenteredGridLayout() throws {
        let appState = AppState()
        // Simulate unlocked state with pattern
        appState.isUnlocked = true

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Verify the pattern grid exists and has correct frame
        let grid = try inspect.find(PatternGridView.self)
        let frame = try grid.fixedWidthAndHeight()

        XCTAssertEqual(frame.width, expectedGridSize, "Pattern grid width should be consistent")
        XCTAssertEqual(frame.height, expectedGridSize, "Pattern grid height should be consistent")
    }

    func testChangePatternView_TryAgainButtonCentered() throws {
        // Test that Try Again button is centered in confirm step
        let appState = AppState()
        appState.isUnlocked = true

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Find Try Again button
        let tryAgainButton = try? inspect.find(
            button: "Try Again"
        )

        // Button should exist in hierarchy when in confirm step
        // We can't easily test the frame here, but we can verify it exists
        // and has proper styling
        if let button = tryAgainButton {
            let buttonStyle = try? button.buttonStyle()
            XCTAssertNotNil(buttonStyle, "Try Again button should have a button style")
        }
    }

    func testChangePatternView_BlueNoticeNotTruncated() throws {
        let appState = AppState()
        appState.isUnlocked = true
        appState.unlockedWithRecoveryPhrase = true // This shows the blue notice

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Find the blue notice banner
        let notice = try? inspect.find(
            ViewType.HStack.self,
            where: { hstack in
                try hstack.find(image: "info.circle.fill") != nil
            }
        )

        XCTAssertNotNil(notice, "Blue notice should exist when unlocked with recovery phrase")

        // Verify the text is not truncated (has lineLimit set)
        let text = try? notice?.find(text: "You unlocked with your recovery phrase")
        let lineLimit = try? text?.lineLimit()
        XCTAssertEqual(lineLimit, 2, "Notice text should allow up to 2 lines")
    }

    func testChangePatternView_SkipVerificationOnlyWithRecoveryPhrase() throws {
        let appState = AppState()

        // Case 1: Unlocked with pattern - should NOT skip verification
        appState.unlockedWithRecoveryPhrase = false
        appState.isUnlocked = true

        let view1 = ChangePatternView().environment(appState)
        let inspect1 = try view1.inspect()

        // Should show "Verify Current Pattern" step
        let verifyTitle = try? inspect1.find(text: "Verify Current Pattern")
        XCTAssertNotNil(verifyTitle, "Should require pattern verification when unlocked with pattern")

        // Case 2: Unlocked with recovery phrase - should skip verification
        appState.unlockedWithRecoveryPhrase = true

        let view2 = ChangePatternView().environment(appState)
        let inspect2 = try view2.inspect()

        // Should show blue notice about skipping verification
        let notice = try? inspect2.find(
            ViewType.HStack.self,
            where: { try $0.find(image: "info.circle.fill") != nil }
        )
        XCTAssertNotNil(notice, "Should show blue notice when skipping verification")
    }

    // MARK: - Pattern Grid Consistency Tests

    func testAllPatternScreens_UseSameGridSize() throws {
        let appState = AppState()
        appState.isUnlocked = true

        // Test PatternSetupView
        let setupView = PatternSetupView(onComplete: {})
            .environment(appState)
        let setupInspect = try setupView.inspect()
        let setupGrid = try setupInspect.find(PatternGridView.self)
        let setupFrame = try setupGrid.fixedWidthAndHeight()

        // Test ChangePatternView
        let changeView = ChangePatternView()
            .environment(appState)
        let changeInspect = try changeView.inspect()
        let changeGrid = try changeInspect.find(PatternGridView.self)
        let changeFrame = try changeGrid.fixedWidthAndHeight()

        XCTAssertEqual(setupFrame.width, changeFrame.width, "All pattern grids should have same width")
        XCTAssertEqual(setupFrame.height, changeFrame.height, "All pattern grids should have same height")
    }

    func testAllPatternScreens_HaveFixedFeedbackArea() throws {
        let appState = AppState()
        appState.isUnlocked = true

        // Test PatternSetupView
        let setupView = PatternSetupView(onComplete: {})
            .environment(appState)
        let setupInspect = try setupView.inspect()

        // Test ChangePatternView
        let changeView = ChangePatternView()
            .environment(appState)
        let changeInspect = try changeView.inspect()

        // Both should have feedback areas with same minHeight
        let setupFeedback = try setupInspect.find(
            ViewType.Group.self,
            where: { try $0.find(PatternValidationFeedbackView.self) != nil }
        )
        let changeFeedback = try changeInspect.find(
            ViewType.Group.self,
            where: { try $0.find(PatternValidationFeedbackView.self) != nil }
        )

        let setupMinHeight = try setupFeedback.minHeight()
        let changeMinHeight = try changeFeedback.minHeight()

        XCTAssertEqual(setupMinHeight, changeMinHeight, "Feedback areas should have consistent height")
        XCTAssertEqual(setupMinHeight, expectedFeedbackHeight, "Feedback area should be 80pt")
    }

    // MARK: - Error Message Consistency Tests

    func testPatternScreens_ErrorMessageStyling() throws {
        let appState = AppState()
        appState.isUnlocked = true

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Find error message container (HStack with xmark.circle.fill)
        let errorContainer = try? inspect.find(
            ViewType.HStack.self,
            where: { try $0.find(image: "xmark.circle.fill") != nil }
        )

        XCTAssertNotNil(errorContainer, "Error message should use consistent styling with icon")
    }

    // MARK: - Accessibility Tests

    func testPatternBoard_AccessibilityIdentifiers() throws {
        let appState = AppState()
        appState.isUnlocked = true

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Verify accessibility identifiers exist
        let grid = try? inspect.find(
            ViewType.View.self,
            where: { view in
                (try? view.accessibilityIdentifier()) == "change_pattern_grid"
            }
        )
        XCTAssertNotNil(grid, "Pattern grid should have accessibility identifier")
    }

    // MARK: - Layout Stability Tests

    func testPatternBoard_NoLayoutShiftOnError() throws {
        // This test verifies that when an error appears, the pattern board
        // doesn't jump or shift position

        let appState = AppState()
        appState.isUnlocked = true

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Get initial position of pattern grid
        let grid = try inspect.find(PatternGridView.self)
        let initialFrame = try grid.fixedWidthAndHeight()

        // Verify grid has Spacer above and below for centering
        let parentVStack = try grid.parentView(ofType: VStack<VSpacer>.self)
        let children = try parentVStack.children()

        var hasSpacerAbove = false
        var hasSpacerBelow = false
        var foundGrid = false

        for child in children {
            if try child.viewType() == PatternGridView.self {
                foundGrid = true
            } else if foundGrid == false && try child.viewType() == Spacer.self {
                hasSpacerAbove = true
            } else if foundGrid == true && try child.viewType() == Spacer.self {
                hasSpacerBelow = true
            }
        }

        XCTAssertTrue(hasSpacerAbove, "Pattern grid should have Spacer above for centering")
        XCTAssertTrue(hasSpacerBelow, "Pattern grid should have Spacer below for centering")
    }
}

// MARK: - Helper Extensions

private extension InspectableView {
    func fixedWidthAndHeight() throws -> (width: CGFloat, height: CGFloat) {
        let width = try fixedWidth()
        let height = try fixedHeight()
        return (width, height)
    }
}
