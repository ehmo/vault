import XCTest

/// Page object for the main vault view (file grid, toolbar, FAB).
struct VaultScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var settingsButton: XCUIElement {
        app.buttons[AID.vaultSettingsButton]
    }

    var lockButton: XCUIElement {
        app.buttons[AID.vaultLockButton]
    }

    var addButton: XCUIElement {
        app.buttons[AID.vaultAddButton]
    }

    var selectButton: XCUIElement {
        app.buttons[AID.vaultSelectButton]
    }

    var selectAllButton: XCUIElement {
        app.buttons[AID.vaultSelectAll]
    }

    var editDoneButton: XCUIElement {
        app.buttons[AID.vaultEditDone]
    }

    var deleteButton: XCUIElement {
        app.buttons[AID.vaultEditDelete]
    }

    var emptyStateContainer: XCUIElement {
        app.otherElements[AID.vaultEmptyStateContainer]
    }

    var firstFilesButton: XCUIElement {
        app.buttons[AID.vaultFirstFiles]
    }

    var searchField: XCUIElement {
        app.searchFields[AID.vaultSearchField]
    }

    /// Check if the vault view is displayed (settings gear visible = unlocked).
    var isDisplayed: Bool {
        settingsButton.waitForExistence(timeout: 10)
    }

    // MARK: - Actions

    @discardableResult
    func tapSettings() -> SettingsScreen {
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        // Wait for the button to be hittable (not behind loading overlay)
        settingsButton.waitForHittable(timeout: 5)
        settingsButton.tap()
        return SettingsScreen(app: app)
    }

    @discardableResult
    func tapLock() -> PatternLockScreen {
        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        lockButton.tap()
        return PatternLockScreen(app: app)
    }

    @discardableResult
    func tapAdd() -> Self {
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        return self
    }

    @discardableResult
    func tapSelect() -> Self {
        XCTAssertTrue(selectButton.waitForExistence(timeout: 5))
        selectButton.tap()
        return self
    }

    @discardableResult
    func tapSelectAll() -> Self {
        XCTAssertTrue(selectAllButton.waitForExistence(timeout: 5))
        selectAllButton.tap()
        return self
    }

    @discardableResult
    func tapDelete() -> Self {
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        return self
    }

    @discardableResult
    func tapEditDone() -> Self {
        XCTAssertTrue(editDoneButton.waitForExistence(timeout: 5))
        editDoneButton.tap()
        return self
    }

    /// Tap the first image cell in the grid.
    @discardableResult
    func tapFirstFile() -> Self {
        // LazyVGrid items may show as images or buttons
        let firstImage = app.images.firstMatch
        if firstImage.waitForExistence(timeout: 5) {
            firstImage.tap()
        } else {
            // Fallback: try cells
            let firstCell = app.cells.firstMatch
            XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
            firstCell.tap()
        }
        return self
    }
}
