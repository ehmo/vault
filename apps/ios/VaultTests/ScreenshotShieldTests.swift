import XCTest
@testable import Vault

@MainActor
final class ScreenshotShieldTests: XCTestCase {

    private var shield: ScreenshotShield!
    private var hostWindow: UIWindow!

    override func setUp() {
        super.setUp()
        shield = ScreenshotShield()

        // Create a window with a superlayer (required for reparenting).
        // Adding it to a UIWindowScene gives its layer a superlayer.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("No window scene available for testing")
            return
        }
        hostWindow = UIWindow(windowScene: scene)
        hostWindow.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        hostWindow.makeKeyAndVisible()
    }

    override func tearDown() {
        shield.reset()
        hostWindow.isHidden = true
        hostWindow = nil
        super.tearDown()
    }

    // MARK: - Secure Text Field Setup

    func testSecureFieldHasSecureTextEntry() {
        shield.activate(on: hostWindow)

        XCTAssertNotNil(shield.secureField)
        XCTAssertTrue(shield.secureField!.isSecureTextEntry)
    }

    func testSecureFieldIsNotInteractive() {
        shield.activate(on: hostWindow)

        XCTAssertFalse(shield.secureField!.isUserInteractionEnabled)
    }

    // MARK: - Field Positioning (Critical — prevents content offset bug)

    func testSecureFieldRemainsAtOrigin() {
        shield.activate(on: hostWindow)

        // The field MUST stay at origin. Centering constraints caused a bug where
        // all window content shifted to the bottom-right by half the screen size.
        let field = shield.secureField!
        XCTAssertEqual(field.frame.origin, .zero,
                       "Field must stay at origin — any offset shifts all window content")
    }

    // MARK: - Layer Reparenting

    func testWindowLayerIsInsideSecureContainer() {
        shield.activate(on: hostWindow)

        guard let field = shield.secureField else {
            XCTFail("Shield should have a secure field")
            return
        }

        // Get the secure container using the same logic as the implementation
        let secureContainer = findSecureContainer(in: field.layer)

        guard let container = secureContainer else {
            XCTFail("Shield should have a secure container sublayer")
            return
        }

        // window.layer should now be a sublayer of the secure container
        XCTAssertTrue(container.sublayers?.contains(hostWindow.layer) ?? false,
                      "Window layer must be inside the secure container for screenshot blanking")
    }

    func testFieldLayerIsInWindowSuperlayer() {
        let originalSuperlayer = hostWindow.layer.superlayer
        XCTAssertNotNil(originalSuperlayer, "Test window must have a superlayer")

        shield.activate(on: hostWindow)

        guard shield.secureField != nil else {
            XCTFail("Shield should have a secure field")
            return
        }

        // field.layer should be a direct sublayer of what was the window's superlayer
        XCTAssertEqual(shield.secureField!.layer.superlayer, originalSuperlayer,
                       "Field layer must be a sublayer of the original window superlayer")
    }

    // MARK: - masksToBounds (prevents clipping)

    func testMasksToBoundsDisabledOnFieldLayer() {
        shield.activate(on: hostWindow)

        XCTAssertFalse(shield.secureField!.layer.masksToBounds,
                       "Field layer must not clip — zero-sized layer hosts full-screen content")
    }

    func testMasksToBoundsDisabledOnSecureContainer() {
        shield.activate(on: hostWindow)

        guard let field = shield.secureField else {
            XCTFail("Secure field should exist")
            return
        }

        let secureContainer = findSecureContainer(in: field.layer)

        guard let container = secureContainer else {
            XCTFail("Secure container sublayer should exist")
            return
        }

        XCTAssertFalse(container.masksToBounds,
                       "Secure container must not clip — it hosts the full-screen window layer")
    }

    // MARK: - Idempotency

    func testActivateIsIdempotent() {
        shield.activate(on: hostWindow)
        let firstField = shield.secureField

        shield.activate(on: hostWindow)
        let secondField = shield.secureField

        XCTAssertTrue(firstField === secondField,
                      "Calling activate twice should not create a second field")
        XCTAssertTrue(shield.isActive)
    }

    // MARK: - Activation State

    func testActivateSetsIsActive() {
        XCTAssertFalse(shield.isActive)

        shield.activate(on: hostWindow)

        XCTAssertTrue(shield.isActive)
    }

    func testNotActiveBeforeActivation() {
        XCTAssertNil(shield.secureField)
        XCTAssertFalse(shield.isActive)
    }

    // MARK: - Layer Hierarchy Integrity

    func testLayerHierarchyIsCorrectOrder() {
        let originalSuperlayer = hostWindow.layer.superlayer!

        shield.activate(on: hostWindow)

        // Expected: originalSuperlayer → field.layer → secureContainer → window.layer
        let field = shield.secureField!
        XCTAssertEqual(field.layer.superlayer, originalSuperlayer)

        let secureContainer = findSecureContainer(in: field.layer)!
        XCTAssertTrue(secureContainer.sublayers?.contains(hostWindow.layer) ?? false)
        XCTAssertEqual(hostWindow.layer.superlayer, secureContainer)
    }

    // MARK: - Deactivation

    func testDeactivateRemovesField() {
        shield.activate(on: hostWindow)
        XCTAssertNotNil(shield.secureField)

        shield.deactivate()

        XCTAssertNil(shield.secureField)
        XCTAssertFalse(shield.isActive)
    }

    func testDeactivateIdempotent() {
        // Should not crash when called without prior activation
        shield.deactivate()
        XCTAssertFalse(shield.isActive)
    }

    // MARK: - Reset

    func testResetClearsState() {
        shield.activate(on: hostWindow)
        XCTAssertTrue(shield.isActive)

        shield.reset()

        XCTAssertNil(shield.secureField)
        XCTAssertFalse(shield.isActive)
    }

    // MARK: - Reactivation After Window Destruction

    func testReactivateIfNeededAfterWindowDestruction() {
        // Activate on original window
        shield.activate(on: hostWindow)
        XCTAssertTrue(shield.isActive)

        // Simulate window destruction (common in scene lifecycle changes).
        // Detach from scene so the shield detects the window is gone.
        hostWindow.isHidden = true
        hostWindow.windowScene = nil
        hostWindow = nil

        // isActive is still true — the shield hasn't been told to deactivate
        XCTAssertTrue(shield.isActive)

        // Create a new window (simulates scene reconnect)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("No window scene available")
            return
        }
        hostWindow = UIWindow(windowScene: scene)
        hostWindow.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        hostWindow.makeKeyAndVisible()

        // Try to reactivate
        shield.reactivateIfNeeded()

        // Should have reactivated on new window
        XCTAssertTrue(shield.isActive)
        XCTAssertNotNil(shield.protectedWindow)
        XCTAssertTrue(shield.protectedWindow === hostWindow)
    }

    // MARK: - Reactivation Idempotency

    func testReactivateIfNeededDoesNothingWhenWindowExists() {
        shield.activate(on: hostWindow)
        XCTAssertTrue(shield.isActive)

        // Call reactivateIfNeeded when window still exists
        shield.reactivateIfNeeded()

        // Should still be active on same window
        XCTAssertTrue(shield.isActive)
        XCTAssertTrue(shield.protectedWindow === hostWindow)
    }

    // MARK: - Helper Methods

    /// Finds the secure container using the same logic as the implementation
    private func findSecureContainer(in layer: CALayer) -> CALayer? {
        if #available(iOS 17.0, *) {
            return layer.sublayers?.last ?? layer.sublayers?.first
        } else {
            return layer.sublayers?.first ?? layer.sublayers?.last
        }
    }
}
