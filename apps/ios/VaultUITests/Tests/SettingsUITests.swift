import XCTest

/// Tests for vault settings navigation and actions.
final class SettingsUITests: BaseUITest {

    func test_settings_opensAndCloses() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        let settings = vault.tapSettings()
        XCTAssertTrue(settings.isDisplayed, "Settings should be visible")
        XCTAssertTrue(settings.changePatternButton.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.regenPhraseButton.exists)

        // Delete vault button is at the bottom of the list — scroll to it
        let deleteButton = settings.deleteVaultButton
        if !deleteButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))

        let vaultAgain = settings.tapDone()
        XCTAssertTrue(vaultAgain.isDisplayed, "Vault should show after dismissing settings")
    }

    func test_changePattern_flow() throws {
        // Skip: Pattern gesture drawing is unreliable in XCUITest.
        // The change pattern flow requires drawing a pattern on PatternGridView.
        // This flow is tested by Maestro E2E tests.
        throw XCTSkip("Pattern gesture simulation unreliable in XCUITest — tested via Maestro")
    }

    func test_regenerateRecoveryPhrase() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        let settings = vault.tapSettings()
        XCTAssertTrue(settings.isDisplayed)

        settings.tapRegenPhrase()

        // Confirm regeneration in alert
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let buttons = alert.buttons
        if buttons.count > 1 {
            buttons.element(boundBy: buttons.count - 1).tap()
        } else {
            buttons.firstMatch.tap()
        }

        // Recovery phrase view should appear — check for the "I've saved it" button
        let recoveryPhrase = RecoveryPhraseScreen(app: app)
        XCTAssertTrue(recoveryPhrase.isDisplayed, "Recovery phrase should be displayed")
    }

    func test_deleteVault_confirmsAndLocks() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        let settings = vault.tapSettings()
        XCTAssertTrue(settings.isDisplayed)

        // Scroll to delete button if needed
        settings.tapDeleteVault()

        // Confirm deletion in alert
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let buttons = alert.buttons
        if buttons.count > 1 {
            buttons.element(boundBy: buttons.count - 1).tap()
        } else {
            buttons.firstMatch.tap()
        }

        // Should return to pattern lock screen
        let patternLock = PatternLockScreen(app: app)
        XCTAssertTrue(patternLock.isDisplayed, "Should show pattern lock after vault deletion")
    }
}
