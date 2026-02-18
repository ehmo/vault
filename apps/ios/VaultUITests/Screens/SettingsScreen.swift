import XCTest

/// Page object for VaultSettingsView (vault-specific settings).
struct SettingsScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var doneButton: XCUIElement {
        app.buttons[AID.vaultSettingsDone]
    }

    var changePatternButton: XCUIElement {
        app.buttons[AID.settingsChangePattern]
    }

    var regenPhraseButton: XCUIElement {
        app.buttons[AID.settingsRegenPhrase]
    }

    var deleteVaultButton: XCUIElement {
        app.buttons[AID.settingsDeleteVault]
    }

    var appSettingsButton: XCUIElement {
        app.buttons[AID.settingsAppSettings]
    }

    var shareVaultButton: XCUIElement {
        app.buttons[AID.settingsShareVault]
    }

    /// Check if settings sheet is displayed.
    var isDisplayed: Bool {
        doneButton.waitForExistence(timeout: 5)
    }

    /// Scroll to an element in the settings list if not visible.
    private func scrollToIfNeeded(_ element: XCUIElement) {
        if !element.exists {
            app.swipeUp()
            _ = element.waitForExistence(timeout: 3)
        }
    }

    // MARK: - Actions

    @discardableResult
    func tapDone() -> VaultScreen {
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
        return VaultScreen(app: app)
    }

    @discardableResult
    func tapChangePattern() -> ChangePatternScreen {
        XCTAssertTrue(changePatternButton.waitForExistence(timeout: 5))
        changePatternButton.tap()
        return ChangePatternScreen(app: app)
    }

    @discardableResult
    func tapRegenPhrase() -> Self {
        scrollToIfNeeded(regenPhraseButton)
        XCTAssertTrue(regenPhraseButton.waitForExistence(timeout: 5))
        regenPhraseButton.tap()
        return self
    }

    @discardableResult
    func tapDeleteVault() -> Self {
        scrollToIfNeeded(deleteVaultButton)
        XCTAssertTrue(deleteVaultButton.waitForExistence(timeout: 5))
        deleteVaultButton.tap()
        return self
    }

    @discardableResult
    func tapAppSettings() -> AppSettingsScreen {
        scrollToIfNeeded(appSettingsButton)
        XCTAssertTrue(appSettingsButton.waitForExistence(timeout: 5))
        appSettingsButton.tap()
        return AppSettingsScreen(app: app)
    }
}

/// Page object for App Settings (SettingsView — appearance, analytics, etc.).
struct AppSettingsScreen {
    let app: XCUIApplication

    var appearanceSetting: XCUIElement {
        app.buttons[AID.appAppearanceSetting]
    }

    var analyticsToggle: XCUIElement {
        app.switches[AID.appAnalyticsToggle]
    }

    var isDisplayed: Bool {
        appearanceSetting.waitForExistence(timeout: 5)
    }

    @discardableResult
    func tapAppearanceMode(_ mode: String) -> Self {
        let modeButton = app.buttons[AID.appearanceMode(mode)]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        modeButton.tap()
        return self
    }
}
