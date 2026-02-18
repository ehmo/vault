import XCTest

/// Shared base class for all Vaultaire UI tests.
/// Configures the app with test launch arguments and captures screenshots on failure.
class BaseUITest: XCTestCase {
    var app: XCUIApplication!

    /// Override in subclasses to customize launch arguments.
    var additionalLaunchArguments: [String] { [] }

    /// When true, `-MAESTRO_TEST` is passed so the app auto-unlocks.
    /// Override to `false` for tests that exercise the pattern lock itself.
    var autoUnlock: Bool { true }

    /// When true, `-MAESTRO_SEED_FILES` is passed to populate the vault.
    var seedFiles: Bool { false }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-XCUITEST_MODE"]

        if autoUnlock {
            app.launchArguments += ["-MAESTRO_TEST"]
        }
        if seedFiles {
            app.launchArguments += ["-MAESTRO_SEED_FILES"]
        }

        app.launchArguments += additionalLaunchArguments
        app.launch()
    }

    override func tearDown() {
        super.tearDown()
        app = nil
    }

    override func record(_ issue: XCTIssue) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Failure-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        super.record(issue)
    }
}
