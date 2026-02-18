import XCTest

/// Page object for the change pattern flow within settings.
struct ChangePatternScreen {
    let app: XCUIApplication

    var patternGrid: XCUIElement {
        app.otherElements[AID.patternGrid]
    }

    var skipVerifyButton: XCUIElement {
        app.buttons[AID.changePatternTestSkipVerify]
    }

    var errorMessage: XCUIElement {
        app.staticTexts[AID.changePatternErrorMessage]
    }

    var recoverySavedButton: XCUIElement {
        app.buttons[AID.recoverySaved]
    }

    var isDisplayed: Bool {
        patternGrid.waitForExistence(timeout: 5)
    }

    // MARK: - Actions

    /// Skip the verify-current-pattern step (debug button in test builds).
    @discardableResult
    func skipVerify() -> Self {
        if skipVerifyButton.waitForExistence(timeout: 3) {
            skipVerifyButton.tap()
        }
        return self
    }

    /// Draw a horizontal pattern across the top row (5 dots).
    @discardableResult
    func drawPattern() -> Self {
        XCTAssertTrue(patternGrid.waitForExistence(timeout: 5))
        let grid = patternGrid
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        let end = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1))
        start.press(forDuration: 0.1, thenDragTo: end)
        return self
    }

    /// Confirm the pattern (draw again).
    @discardableResult
    func confirmPattern() -> Self {
        sleep(2)
        return drawPattern()
    }

    /// Tap "I've saved it" after recovery phrase display.
    @discardableResult
    func tapRecoverySaved() -> SettingsScreen {
        XCTAssertTrue(recoverySavedButton.waitForExistence(timeout: 10))
        recoverySavedButton.tap()
        return SettingsScreen(app: app)
    }
}
