import XCTest

/// Tests auto-unlock (via MAESTRO_TEST) and pattern lock screen.
final class UnlockUITests: BaseUITest {

    func test_unlock_showsVault() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed, "Vault should show after auto-unlock")
        XCTAssertTrue(vault.addButton.waitForExistence(timeout: 5))
        XCTAssertTrue(vault.settingsButton.exists)
    }

    func test_lockButton_returnsToPatternLock() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        let patternLock = vault.tapLock()
        XCTAssertTrue(patternLock.isDisplayed, "Pattern lock should show after locking")
        XCTAssertTrue(patternLock.patternGrid.exists)
    }
}
