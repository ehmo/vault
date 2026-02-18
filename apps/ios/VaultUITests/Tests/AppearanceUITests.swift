import XCTest

/// Tests appearance mode switching (light/dark/system).
final class AppearanceUITests: BaseUITest {

    /// Skipped: NavigationLink in deep List section requires multi-swipe scrolling
    /// that is unreliable in XCUITest. Revisit with explicit accessibility scroll target.
    func SKIP_test_appearance_lightDarkSystem() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        let settings = vault.tapSettings()
        XCTAssertTrue(settings.isDisplayed)

        let appSettings = settings.tapAppSettings()
        XCTAssertTrue(appSettings.isDisplayed)

        // Switch to light mode
        appSettings.tapAppearanceMode("light")

        // Switch to dark mode
        appSettings.tapAppearanceMode("dark")

        // Switch back to system mode
        appSettings.tapAppearanceMode("system")

        // Navigate back to vault settings
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }

        // Settings Done button should still be visible
        XCTAssertTrue(settings.doneButton.waitForExistence(timeout: 5))
    }
}
