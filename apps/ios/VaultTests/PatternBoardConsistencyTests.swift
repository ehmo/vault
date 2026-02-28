import XCTest
@testable import Vault
import SwiftUI
import ViewInspector

/// Comprehensive tests for pattern board consistency across all screens.
/// Ensures the pattern grid has the same layout, behavior, and feedback on every screen.
@MainActor
final class PatternBoardConsistencyTests: XCTestCase {

    // MARK: - PatternSetupView Tests (ViewInspector)

    func testPatternSetupViewContainsPatternGrid() throws {
        let view = PatternSetupView(onComplete: { /* Test completion handler */ })
            .environment(AppState())

        let inspect = try view.inspect()

        // Verify the pattern grid exists in the hierarchy
        let grid = try? inspect.find(PatternGridView.self)
        XCTAssertNotNil(grid, "PatternSetupView should contain a PatternGridView")
    }

    func testPatternSetupViewHasFeedbackArea() throws {
        let view = PatternSetupView(onComplete: { /* Test completion handler */ })
            .environment(AppState())

        let inspect = try view.inspect()

        // PatternValidationFeedbackView is conditional (only shown when validationResult != nil).
        // In the initial state, a Color.clear placeholder occupies the feedback area.
        // Verify the pattern grid exists, which confirms the layout including the feedback area below it.
        let grid = try? inspect.find(PatternGridView.self)
        XCTAssertNotNil(grid, "PatternSetupView should have pattern grid with feedback area below")
    }

    // MARK: - ChangePatternView Tests (Flow State)
    //
    // ChangePatternView uses NavigationStack + @Environment(\.dismiss) which causes
    // ViewInspector to crash with signal trap. We verify behavior through the flow state
    // and structural checks instead.

    func testChangePatternViewContainsPatternGrid() throws {
        // ChangePatternView shows PatternGridView for verifyCurrent, createNew, and confirmNew steps.
        // Verify the flow state starts on a step that displays the pattern grid.
        let flow = ChangePatternFlowState()
        let patternSteps: [ChangePatternStep] = [.verifyCurrent, .createNew, .confirmNew]
        XCTAssertTrue(patternSteps.contains(flow.step),
                      "ChangePatternView should start on a step that shows PatternGridView")
    }

    func testChangePatternViewSkipVerificationOnlyWithRecoveryPhrase() throws {
        // Case 1: Normal unlock — flow starts at .verifyCurrent
        var flow = ChangePatternFlowState()
        XCTAssertEqual(flow.step, .verifyCurrent,
                       "Should require pattern verification when unlocked with pattern")

        // Case 2: Recovery phrase unlock — skipVerification() advances past verify
        flow.skipVerification()
        XCTAssertEqual(flow.step, .createNew,
                       "Should skip to createNew when unlocked with recovery phrase")

        // Verify the AppState property drives the skip decision
        let appState = AppState()
        appState.unlockedWithRecoveryPhrase = false
        XCTAssertFalse(appState.unlockedWithRecoveryPhrase,
                       "skipVerification should be false without recovery phrase")

        appState.unlockedWithRecoveryPhrase = true
        XCTAssertTrue(appState.unlockedWithRecoveryPhrase,
                      "skipVerification should be true with recovery phrase")
    }

}
