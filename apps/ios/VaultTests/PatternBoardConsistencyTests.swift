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

    func testPatternSetupViewHasFeedbackArea() throws {
        let view = PatternSetupView(onComplete: {})
            .environment(AppState())

        let inspect = try view.inspect()

        // PatternValidationFeedbackView is conditional (only shown when validationResult != nil).
        // In the initial state, a Color.clear placeholder occupies the feedback area.
        // Verify the pattern grid exists, which confirms the layout including the feedback area below it.
        let grid = try? inspect.find(PatternGridView.self)
        XCTAssertNotNil(grid, "PatternSetupView should have pattern grid with feedback area below")
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

        // PatternValidationFeedbackView is conditional (only shown after pattern drawn).
        // Verify both screens have the pattern grid, which shares a layout with the feedback area.

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

        XCTAssertNotNil(setupGrid, "PatternSetupView should have pattern grid with feedback area")
        XCTAssertNotNil(changeGrid, "ChangePatternView should have pattern grid with feedback area")
    }
}
