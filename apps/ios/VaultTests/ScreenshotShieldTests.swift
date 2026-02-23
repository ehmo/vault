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
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        hostWindow = UIWindow(windowScene: scene!)
        hostWindow.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        hostWindow.makeKeyAndVisible()
    }

    override func tearDown() {
        hostWindow.isHidden = true
        hostWindow = nil
        shield = nil
        super.tearDown()
    }

    // MARK: - Secure Text Field Setup

    func test_secureField_hasSecureTextEntry() {
        shield.activate(on: hostWindow)

        XCTAssertNotNil(shield.secureField)
        XCTAssertTrue(shield.secureField!.isSecureTextEntry)
    }

    func test_secureField_isNotInteractive() {
        shield.activate(on: hostWindow)

        XCTAssertFalse(shield.secureField!.isUserInteractionEnabled)
    }

    // MARK: - Field Positioning (Critical — prevents content offset bug)

    func test_secureField_remainsAtOrigin() {
        shield.activate(on: hostWindow)

        // The field MUST stay at origin. Centering constraints caused a bug where
        // all window content shifted to the bottom-right by half the screen size.
        let field = shield.secureField!
        XCTAssertEqual(field.frame.origin, .zero,
                       "Field must stay at origin — any offset shifts all window content")
    }

    // MARK: - Layer Reparenting

    func test_windowLayer_isInsideSecureContainer() {
        shield.activate(on: hostWindow)

        guard let field = shield.secureField,
              let secureContainer = field.layer.sublayers?.first else {
            XCTFail("Shield should have a secure field with a container sublayer")
            return
        }

        // window.layer should now be a sublayer of the secure container
        XCTAssertTrue(secureContainer.sublayers?.contains(hostWindow.layer) ?? false,
                      "Window layer must be inside the secure container for screenshot blanking")
    }

    func test_fieldLayer_isInWindowSuperlayer() {
        let originalSuperlayer = hostWindow.layer.superlayer
        XCTAssertNotNil(originalSuperlayer, "Test window must have a superlayer")

        shield.activate(on: hostWindow)

        guard let field = shield.secureField else {
            XCTFail("Shield should have a secure field")
            return
        }

        // field.layer should be a direct sublayer of what was the window's superlayer
        XCTAssertEqual(field.layer.superlayer, originalSuperlayer,
                       "Field layer must be a sublayer of the original window superlayer")
    }

    // MARK: - masksToBounds (prevents clipping)

    func test_masksToBounds_disabledOnFieldLayer() {
        shield.activate(on: hostWindow)

        XCTAssertFalse(shield.secureField!.layer.masksToBounds,
                       "Field layer must not clip — zero-sized layer hosts full-screen content")
    }

    func test_masksToBounds_disabledOnSecureContainer() {
        shield.activate(on: hostWindow)

        guard let secureContainer = shield.secureField?.layer.sublayers?.first else {
            XCTFail("Secure container sublayer should exist")
            return
        }

        XCTAssertFalse(secureContainer.masksToBounds,
                       "Secure container must not clip — it hosts the full-screen window layer")
    }

    // MARK: - Idempotency

    func test_activate_isIdempotent() {
        shield.activate(on: hostWindow)
        let firstField = shield.secureField

        shield.activate(on: hostWindow)
        let secondField = shield.secureField

        XCTAssertTrue(firstField === secondField,
                      "Calling activate twice should not create a second field")
        XCTAssertTrue(shield.isActive)
    }

    // MARK: - Activation State

    func test_activate_setsIsActive() {
        XCTAssertFalse(shield.isActive)

        shield.activate(on: hostWindow)

        XCTAssertTrue(shield.isActive)
    }

    func test_notActive_beforeActivation() {
        XCTAssertNil(shield.secureField)
        XCTAssertFalse(shield.isActive)
    }

    // MARK: - Layer Hierarchy Integrity

    func test_layerHierarchy_isCorrectOrder() {
        let originalSuperlayer = hostWindow.layer.superlayer!

        shield.activate(on: hostWindow)

        // Expected: originalSuperlayer → field.layer → secureContainer → window.layer
        let field = shield.secureField!
        XCTAssertEqual(field.layer.superlayer, originalSuperlayer)

        let secureContainer = field.layer.sublayers!.first!
        XCTAssertTrue(secureContainer.sublayers!.contains(hostWindow.layer))
        XCTAssertEqual(hostWindow.layer.superlayer, secureContainer)
    }
}
