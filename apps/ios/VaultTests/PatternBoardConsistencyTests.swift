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

    // MARK: - PatternSetupView Tests

    func testPatternSetupViewContainsPatternGrid() throws {
        let view = PatternSetupView(onComplete: {})
            .environment(AppState())

        let inspect = try view.inspect()

        // Verify the pattern grid exists in the hierarchy
        let grid = try? inspect.find(PatternGridView.self)
        XCTAssertNotNil(grid, "PatternSetupView should contain a PatternGridView")
    }

    func testPatternSetupViewValidationFeedbackExists() throws {
        let view = PatternSetupView(onComplete: {})
            .environment(AppState())

        let inspect = try view.inspect()

        // Verify the feedback view exists in the hierarchy
        let feedbackView = try? inspect.find(PatternValidationFeedbackView.self)
        XCTAssertNotNil(feedbackView, "Validation feedback view should exist in hierarchy")
    }

    // MARK: - ChangePatternView Tests

    func testChangePatternViewContainsPatternGrid() throws {
        let appState = AppState()
        appState.isUnlocked = true

        let view = ChangePatternView()
            .environment(appState)

        let inspect = try view.inspect()

        // Verify the pattern grid exists in the hierarchy
        let grid = try? inspect.find(PatternGridView.self)
        XCTAssertNotNil(grid, "ChangePatternView should contain a PatternGridView")
    }

    func testChangePatternViewSkipVerificationOnlyWithRecoveryPhrase() throws {
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
        let notice = try? inspect2.find(text: "You unlocked with your recovery phrase")
        XCTAssertNotNil(notice, "Should show blue notice when skipping verification")
    }

    // MARK: - Pattern Grid Consistency Tests

    func testAllPatternScreensContainPatternGrid() throws {
        let appState = AppState()
        appState.isUnlocked = true

        // Test PatternSetupView
        let setupView = PatternSetupView(onComplete: {})
            .environment(appState)
        let setupInspect = try setupView.inspect()
        let setupGrid = try? setupInspect.find(PatternGridView.self)

        // Test ChangePatternView
        let changeView = ChangePatternView()
            .environment(appState)
        let changeInspect = try changeView.inspect()
        let changeGrid = try? changeInspect.find(PatternGridView.self)

        XCTAssertNotNil(setupGrid, "PatternSetupView should contain a PatternGridView")
        XCTAssertNotNil(changeGrid, "ChangePatternView should contain a PatternGridView")
    }

    func testAllPatternScreensHaveFeedbackArea() throws {
        let appState = AppState()
        appState.isUnlocked = true

        // Test PatternSetupView
        let setupView = PatternSetupView(onComplete: {})
            .environment(appState)
        let setupInspect = try setupView.inspect()
        let setupFeedback = try? setupInspect.find(PatternValidationFeedbackView.self)

        // Test ChangePatternView
        let changeView = ChangePatternView()
            .environment(appState)
        let changeInspect = try changeView.inspect()
        let changeFeedback = try? changeInspect.find(PatternValidationFeedbackView.self)

        XCTAssertNotNil(setupFeedback, "PatternSetupView should have feedback area")
        XCTAssertNotNil(changeFeedback, "ChangePatternView should have feedback area")
    }
}
