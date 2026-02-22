import XCTest
@testable import Vault

final class OnboardingStepTests: XCTestCase {

    // MARK: - Case Count

    func testAllCasesCountIsSix() {
        XCTAssertEqual(OnboardingStep.allCases.count, 6)
    }

    // MARK: - Ordering

    func testCaseOrderMatchesExpectedFlow() {
        let expected: [OnboardingStep] = [.welcome, .permissions, .analytics, .paywall, .thankYou, .rating]
        XCTAssertEqual(OnboardingStep.allCases, expected)
    }

    // MARK: - next()

    func testNextFromWelcomeReturnsPermissions() {
        XCTAssertEqual(OnboardingStep.welcome.next(), .permissions)
    }

    func testNextFromPermissionsReturnsAnalytics() {
        XCTAssertEqual(OnboardingStep.permissions.next(), .analytics)
    }

    func testNextFromAnalyticsReturnsPaywall() {
        XCTAssertEqual(OnboardingStep.analytics.next(), .paywall)
    }

    func testNextFromPaywallReturnsThankYou() {
        XCTAssertEqual(OnboardingStep.paywall.next(), .thankYou)
    }

    func testNextFromThankYouReturnsRating() {
        XCTAssertEqual(OnboardingStep.thankYou.next(), .rating)
    }

    func testNextFromRatingReturnsNil() {
        XCTAssertNil(OnboardingStep.rating.next())
    }

    // MARK: - previous()

    func testPreviousFromWelcomeReturnsNil() {
        XCTAssertNil(OnboardingStep.welcome.previous())
    }

    func testPreviousFromPermissionsReturnsWelcome() {
        XCTAssertEqual(OnboardingStep.permissions.previous(), .welcome)
    }

    func testPreviousFromThankYouReturnsPaywall() {
        XCTAssertEqual(OnboardingStep.thankYou.previous(), .paywall)
    }

    func testPreviousFromRatingReturnsThankYou() {
        XCTAssertEqual(OnboardingStep.rating.previous(), .thankYou)
    }

    // MARK: - progressFraction

    func testProgressFractionForFirstStep() {
        let fraction = OnboardingStep.welcome.progressFraction
        XCTAssertEqual(fraction, 1.0 / 6.0, accuracy: 0.001)
    }

    func testProgressFractionForLastStep() {
        let fraction = OnboardingStep.rating.progressFraction
        XCTAssertEqual(fraction, 1.0, accuracy: 0.001)
    }

    func testProgressFractionIncreases() {
        let fractions = OnboardingStep.allCases.map(\.progressFraction)
        for i in 1..<fractions.count {
            XCTAssertGreaterThan(fractions[i], fractions[i - 1],
                                 "Fraction at index \(i) should be greater than \(i - 1)")
        }
    }
}
