import XCTest

/// Page object for the pattern lock (unlock) screen.
struct PatternLockScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var patternGrid: XCUIElement {
        app.otherElements[AID.unlockPatternGrid]
    }

    var recoveryLink: XCUIElement {
        app.buttons[AID.unlockRecoveryLink]
    }

    var joinLink: XCUIElement {
        app.buttons[AID.unlockJoinLink]
    }

    var recoveryPhraseInput: XCUIElement {
        app.textFields[AID.unlockRecoveryPhraseInput]
    }

    var recoveryError: XCUIElement {
        app.staticTexts[AID.unlockRecoveryError]
    }

    var recoveryCancelButton: XCUIElement {
        app.buttons[AID.unlockRecoveryCancel]
    }

    /// Check if the pattern lock screen is displayed.
    var isDisplayed: Bool {
        patternGrid.waitForExistence(timeout: 5)
    }

    // MARK: - Actions

    /// Draw a pattern on the unlock grid.
    @discardableResult
    func drawPattern() -> Self {
        XCTAssertTrue(patternGrid.waitForExistence(timeout: 5))
        let grid = patternGrid
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        let mid = start.withOffset(CGVector(dx: 0, dy: grid.frame.height * 0.4))
        let end = mid.withOffset(CGVector(dx: grid.frame.width * 0.4, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: mid)
        mid.press(forDuration: 0.1, thenDragTo: end)
        return self
    }

    @discardableResult
    func tapRecoveryLink() -> Self {
        XCTAssertTrue(recoveryLink.waitForExistence(timeout: 5))
        recoveryLink.tap()
        return self
    }
}
