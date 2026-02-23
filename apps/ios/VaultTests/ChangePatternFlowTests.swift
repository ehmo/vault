import XCTest
@testable import Vault

final class ChangePatternFlowTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStepIsVerifyCurrent() {
        let flow = ChangePatternFlowState()
        XCTAssertEqual(flow.step, .verifyCurrent)
        XCTAssertTrue(flow.currentPattern.isEmpty)
        XCTAssertTrue(flow.newPattern.isEmpty)
        XCTAssertNil(flow.validationResult)
        XCTAssertNil(flow.errorMessage)
        XCTAssertFalse(flow.isProcessing)
        XCTAssertTrue(flow.newRecoveryPhrase.isEmpty)
    }

    // MARK: - skipVerification

    func testSkipVerificationTransitionsToCreateNew() {
        var flow = ChangePatternFlowState()
        flow.skipVerification()
        XCTAssertEqual(flow.step, .createNew)
    }

    func testSkipVerificationClearsState() {
        var flow = ChangePatternFlowState()
        flow.currentPattern = [1, 2, 3]
        flow.newPattern = [4, 5, 6]
        flow.showError("some error")
        flow.isProcessing = true

        flow.skipVerification()

        XCTAssertTrue(flow.currentPattern.isEmpty)
        XCTAssertTrue(flow.newPattern.isEmpty)
        XCTAssertNil(flow.errorMessage)
        XCTAssertNil(flow.validationResult)
        XCTAssertFalse(flow.isProcessing)
    }

    func testSkipVerificationAfterPartialProgressClearsState() {
        var flow = ChangePatternFlowState()
        // Simulate partial progress: verified current, started creating new
        flow.transitionToCreate(currentPattern: [0, 1, 2, 7, 12, 17, 22])
        flow.transitionToConfirm(newPattern: [5, 10, 15, 20, 21, 22])

        flow.skipVerification()

        XCTAssertEqual(flow.step, .createNew)
        XCTAssertTrue(flow.currentPattern.isEmpty)
        XCTAssertTrue(flow.newPattern.isEmpty)
        XCTAssertFalse(flow.isProcessing)
    }

    // MARK: - Transitions

    func testTransitionToCreateSetsPattern() {
        var flow = ChangePatternFlowState()
        let pattern = [0, 1, 2, 7, 12, 17, 22]
        flow.transitionToCreate(currentPattern: pattern)

        XCTAssertEqual(flow.step, .createNew)
        XCTAssertEqual(flow.currentPattern, pattern)
        XCTAssertNil(flow.errorMessage)
        XCTAssertFalse(flow.isProcessing)
    }

    func testTransitionToConfirmSetsNewPattern() {
        var flow = ChangePatternFlowState()
        let pattern = [5, 10, 15, 20, 21, 22]
        flow.transitionToConfirm(newPattern: pattern)

        XCTAssertEqual(flow.step, .confirmNew)
        XCTAssertEqual(flow.newPattern, pattern)
        XCTAssertNil(flow.errorMessage)
        XCTAssertFalse(flow.isProcessing)
    }

    func testCompleteSetsRecoveryPhrase() {
        var flow = ChangePatternFlowState()
        let phrase = "alpha bravo charlie delta echo foxtrot"
        flow.complete(with: phrase)

        XCTAssertEqual(flow.step, .complete)
        XCTAssertEqual(flow.newRecoveryPhrase, phrase)
        XCTAssertNil(flow.errorMessage)
        XCTAssertFalse(flow.isProcessing)
    }

    // MARK: - resetForStartOver

    func testResetForStartOverResetsToVerify() {
        var flow = ChangePatternFlowState()
        flow.transitionToCreate(currentPattern: [0, 1, 2, 7, 12, 17, 22])
        flow.transitionToConfirm(newPattern: [5, 10, 15, 20, 21, 22])

        flow.resetForStartOver()

        XCTAssertEqual(flow.step, .verifyCurrent)
        XCTAssertTrue(flow.currentPattern.isEmpty)
        XCTAssertTrue(flow.newPattern.isEmpty)
        XCTAssertFalse(flow.isProcessing)
    }

    func testResetForStartOverAfterSkipVerificationResetsToVerify() {
        var flow = ChangePatternFlowState()
        flow.skipVerification()
        XCTAssertEqual(flow.step, .createNew)

        flow.resetForStartOver()

        XCTAssertEqual(flow.step, .verifyCurrent)
        XCTAssertTrue(flow.currentPattern.isEmpty)
        XCTAssertTrue(flow.newPattern.isEmpty)
    }

    // MARK: - Processing Guards

    func testBeginProcessingIfIdlePreventsDoubleProcessing() {
        var flow = ChangePatternFlowState()
        XCTAssertTrue(flow.beginProcessingIfIdle())
        XCTAssertTrue(flow.isProcessing)
        XCTAssertFalse(flow.beginProcessingIfIdle()) // second call blocked
    }

    func testEndProcessingAllowsNewProcessing() {
        var flow = ChangePatternFlowState()
        XCTAssertTrue(flow.beginProcessingIfIdle())
        flow.endProcessing()
        XCTAssertFalse(flow.isProcessing)
        XCTAssertTrue(flow.beginProcessingIfIdle()) // now allowed again
    }

    // MARK: - Feedback

    func testShowErrorSetsErrorAndClearsValidation() {
        var flow = ChangePatternFlowState()
        flow.showError("Something went wrong")
        XCTAssertEqual(flow.errorMessage, "Something went wrong")
        XCTAssertNil(flow.validationResult)
    }

    func testClearFeedbackClearsErrorAndValidation() {
        var flow = ChangePatternFlowState()
        flow.showError("err")
        flow.clearFeedback()
        XCTAssertNil(flow.errorMessage)
        XCTAssertNil(flow.validationResult)
    }

    // MARK: - Step Index (used by progress indicator)

    func testStepIndexWithVerification() {
        // In normal 3-step flow, stepIndex maps as:
        // verifyCurrent=0, createNew=0, confirmNew=1, complete=2
        var flow = ChangePatternFlowState()
        XCTAssertEqual(flow.step, .verifyCurrent)

        flow.transitionToCreate(currentPattern: [0, 1, 2, 7, 12, 17, 22])
        XCTAssertEqual(flow.step, .createNew)

        flow.transitionToConfirm(newPattern: [5, 10, 15, 20, 21, 22])
        XCTAssertEqual(flow.step, .confirmNew)

        flow.complete(with: "phrase")
        XCTAssertEqual(flow.step, .complete)
    }

    func testStepIndexWithSkippedVerification() {
        // In 2-step flow (skipped verification), createNew=0, confirmNew=1, complete=2
        var flow = ChangePatternFlowState()
        flow.skipVerification()
        XCTAssertEqual(flow.step, .createNew)

        flow.transitionToConfirm(newPattern: [5, 10, 15, 20, 21, 22])
        XCTAssertEqual(flow.step, .confirmNew)

        flow.complete(with: "phrase")
        XCTAssertEqual(flow.step, .complete)
    }
}
