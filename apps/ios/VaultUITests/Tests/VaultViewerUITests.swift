import XCTest

/// Tests for the vault file grid and empty state.
final class VaultViewerUITests: BaseUITest {
    override var additionalLaunchArguments: [String] {
        ["-MAESTRO_CLEAR_VAULT"]
    }

    func test_emptyVault_showsEmptyState() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        // Check for empty state indicators — the text or the button
        let firstFilesBtn = vault.firstFilesButton
        let addFilesText = app.staticTexts["Add your files"]
        let protectText = app.staticTexts["Protect Your First Files"]

        let foundEmpty = firstFilesBtn.waitForExistence(timeout: 10)
            || addFilesText.waitForExistence(timeout: 3)
            || protectText.waitForExistence(timeout: 3)
            || vault.emptyStateContainer.waitForExistence(timeout: 3)
        XCTAssertTrue(foundEmpty, "Empty vault should show empty state")
    }
}

/// Tests that require seeded files in the vault.
final class VaultViewerSeededUITests: BaseUITest {
    override var seedFiles: Bool { true }
    override var additionalLaunchArguments: [String] {
        ["-MAESTRO_CLEAR_VAULT"]
    }

    func test_populatedVault_showsFiles() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        // With seeded files, the select button should be visible
        XCTAssertTrue(
            vault.selectButton.waitForExistence(timeout: 10),
            "Populated vault should show select button"
        )
    }

    /// Skipped: SwiftUI LazyVGrid items with .onTapGesture don't expose as
    /// tappable images/cells in XCUITest. Needs accessibility identifier on grid items.
    func SKIP_test_fileViewer_openAndDismiss() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)

        // Wait for files to load
        XCTAssertTrue(vault.selectButton.waitForExistence(timeout: 10))

        // Tap the first file to open viewer
        vault.tapFirstFile()

        let doneButton = app.buttons[AID.viewerDone]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "Viewer should show Done button")

        // Dismiss the viewer
        doneButton.tap()

        // Vault should be visible again
        XCTAssertTrue(vault.settingsButton.waitForExistence(timeout: 5))
    }

    func test_editMode_selectAndDelete() {
        let vault = VaultScreen(app: app)
        XCTAssertTrue(vault.isDisplayed)
        XCTAssertTrue(vault.selectButton.waitForExistence(timeout: 10))

        // Enter edit mode
        vault.tapSelect()

        // Select all
        XCTAssertTrue(vault.selectAllButton.waitForExistence(timeout: 5))
        vault.tapSelectAll()

        // Delete
        XCTAssertTrue(vault.deleteButton.waitForExistence(timeout: 5))
        vault.tapDelete()

        // Confirm deletion in alert
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let buttons = alert.buttons
            if buttons.count > 1 {
                buttons.element(boundBy: buttons.count - 1).tap()
            } else {
                buttons.firstMatch.tap()
            }
        }

        // After deletion, empty state should appear
        let addFilesText = app.staticTexts["Add your files"]
        let protectText = app.staticTexts["Protect Your First Files"]
        let foundEmpty = vault.firstFilesButton.waitForExistence(timeout: 15)
            || addFilesText.waitForExistence(timeout: 3)
            || protectText.waitForExistence(timeout: 3)
        XCTAssertTrue(foundEmpty, "Vault should show empty state after deleting all files")
    }
}
