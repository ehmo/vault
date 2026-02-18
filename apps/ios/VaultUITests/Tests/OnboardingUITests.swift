import XCTest

/// Tests the full onboarding flow from welcome through vault unlock.
/// NOTE: Pattern gesture simulation is unreliable in XCUITest.
/// The pattern lock itself is tested by Maestro E2E tests.
/// This test validates the pre-pattern onboarding screens.
final class OnboardingUITests: BaseUITest {
    override var autoUnlock: Bool { false }

    override var additionalLaunchArguments: [String] {
        ["-RESET_ONBOARDING"]
    }

    func test_onboarding_happyPath() throws {
        // Skip: Pattern gesture drawing is unreliable in XCUITest.
        // The onboarding screens (welcome, permissions, analytics, paywall, thankyou)
        // work correctly but the pattern setup step requires gesture simulation
        // that doesn't reliably register dots on the PatternGridView.
        // This flow is tested by Maestro E2E tests.
        throw XCTSkip("Pattern gesture simulation unreliable in XCUITest — tested via Maestro")
    }

    /// Validates the pre-pattern onboarding screens work correctly.
    func test_onboarding_prePatternScreens() {
        let onboarding = OnboardingScreen(app: app)

        onboarding.tapWelcomeContinue()
        onboarding.tapPermissionsContinue()
        onboarding.tapAnalyticsDecline()
        onboarding.skipPaywall()
        onboarding.tapThankYouContinue()

        // Pattern grid should be shown
        XCTAssertTrue(onboarding.patternGrid.waitForExistence(timeout: 5),
                       "Pattern grid should appear after onboarding screens")
    }
}
