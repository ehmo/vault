import XCTest

/// Page object for the onboarding flow (Welcome → Permissions → Analytics → Paywall → ThankYou → PatternSetup).
struct OnboardingScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var welcomeContinueButton: XCUIElement {
        app.buttons[AID.welcomeContinue]
    }

    var permissionsContinueButton: XCUIElement {
        app.buttons[AID.permissionsContinue]
    }

    var analyticsEnableButton: XCUIElement {
        app.buttons[AID.analyticsEnable]
    }

    var analyticsDeclineButton: XCUIElement {
        app.buttons[AID.analyticsDecline]
    }

    var paywallSkipButton: XCUIElement {
        app.buttons[AID.paywallSkip]
    }

    var thankYouContinueButton: XCUIElement {
        app.buttons[AID.thankyouContinue]
    }

    var patternGrid: XCUIElement {
        app.otherElements[AID.patternGrid]
    }

    var recoverySavedButton: XCUIElement {
        app.buttons[AID.recoverySaved]
    }

    var patternClearButton: XCUIElement {
        app.buttons[AID.patternClear]
    }

    var patternStartOverButton: XCUIElement {
        app.buttons[AID.patternStartOver]
    }

    var backButton: XCUIElement {
        app.buttons[AID.onboardingBack]
    }

    // MARK: - Actions

    /// Complete the full onboarding happy path through to vault unlock.
    @discardableResult
    func completeHappyPath() -> VaultScreen {
        tapWelcomeContinue()
        tapPermissionsContinue()
        tapAnalyticsDecline()
        skipPaywall()
        tapThankYouContinue()
        drawPattern()
        confirmPattern()
        tapRecoverySaved()
        return VaultScreen(app: app)
    }

    @discardableResult
    func tapWelcomeContinue() -> Self {
        XCTAssertTrue(welcomeContinueButton.waitForExistence(timeout: 5))
        welcomeContinueButton.tap()
        return self
    }

    @discardableResult
    func tapPermissionsContinue() -> Self {
        XCTAssertTrue(permissionsContinueButton.waitForExistence(timeout: 5))
        permissionsContinueButton.tap()
        return self
    }

    @discardableResult
    func tapAnalyticsDecline() -> Self {
        XCTAssertTrue(analyticsDeclineButton.waitForExistence(timeout: 5))
        analyticsDeclineButton.tap()
        return self
    }

    @discardableResult
    func skipPaywall() -> Self {
        XCTAssertTrue(paywallSkipButton.waitForExistence(timeout: 5))
        paywallSkipButton.tap()
        return self
    }

    @discardableResult
    func tapThankYouContinue() -> Self {
        XCTAssertTrue(thankYouContinueButton.waitForExistence(timeout: 5))
        thankYouContinueButton.tap()
        return self
    }

    /// Draw a horizontal pattern across the top row of the 5×5 grid (4+ dots).
    /// The grid dots are evenly distributed. We drag from the first dot to the last.
    @discardableResult
    func drawPattern() -> Self {
        XCTAssertTrue(patternGrid.waitForExistence(timeout: 5))
        let grid = patternGrid
        // Drag across the top row: (0.1, 0.1) -> (0.9, 0.1)
        // This should cross 5 dots on the 5×5 grid
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        let end = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1))
        start.press(forDuration: 0.1, thenDragTo: end)
        return self
    }

    /// Confirm the pattern (draw it again).
    @discardableResult
    func confirmPattern() -> Self {
        // Wait for the confirm step to appear
        sleep(2)
        XCTAssertTrue(patternGrid.waitForExistence(timeout: 5))
        let grid = patternGrid
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        let end = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1))
        start.press(forDuration: 0.1, thenDragTo: end)
        return self
    }

    @discardableResult
    func tapRecoverySaved() -> Self {
        XCTAssertTrue(recoverySavedButton.waitForExistence(timeout: 10))
        recoverySavedButton.tap()
        return self
    }
}
