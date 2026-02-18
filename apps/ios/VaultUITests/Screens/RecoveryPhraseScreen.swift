import XCTest

/// Page object for the recovery phrase display screen (from Settings regen).
struct RecoveryPhraseScreen {
    let app: XCUIApplication

    var savedButton: XCUIElement {
        app.buttons[AID.recoveryPhraseSaved]
    }

    var isDisplayed: Bool {
        savedButton.waitForExistence(timeout: 10)
    }

    @discardableResult
    func tapSaved() -> SettingsScreen {
        XCTAssertTrue(savedButton.waitForExistence(timeout: 5))
        savedButton.tap()
        return SettingsScreen(app: app)
    }
}
