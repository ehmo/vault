import XCTest
@testable import Vault

final class PatternSetupCoordinatorTests: XCTestCase {

    private let dummyKey = Data(repeating: 0xAA, count: 32)
    private let dummyPattern = [0, 1, 2, 7, 12, 17, 22]
    private let dummyGridSize = 5
    private let dummyPhrase = "alpha bravo charlie delta echo foxtrot"

    private func makeCoordinator(
        deriveKey: (([Int], Int) async throws -> Data)? = nil,
        vaultExists: ((Data) -> Bool)? = nil,
        saveIndex: ((VaultStorage.VaultIndex, Data) throws -> Void)? = nil,
        saveRecoveryPhrase: ((String, [Int], Int, Data) async throws -> Void)? = nil
    ) -> PatternSetupCoordinator {
        var coordinator = PatternSetupCoordinator()
        if let deriveKey { coordinator.deriveKey = deriveKey }
        if let vaultExists { coordinator.vaultExists = vaultExists }
        if let saveIndex { coordinator.saveIndex = saveIndex }
        if let saveRecoveryPhrase { coordinator.saveRecoveryPhrase = saveRecoveryPhrase }
        return coordinator
    }

    // MARK: - savePattern

    func testSuccessReturnsKey() async {
        let coordinator = makeCoordinator(
            deriveKey: { _, _ in self.dummyKey },
            vaultExists: { _ in false },
            saveIndex: { _, _ in },
            saveRecoveryPhrase: { _, _, _, _ in }
        )

        let result = await coordinator.savePattern(dummyPattern, gridSize: dummyGridSize, phrase: dummyPhrase)

        if case .success(let key) = result {
            XCTAssertEqual(key, dummyKey)
        } else {
            XCTFail("Expected .success, got \(result)")
        }
    }

    func testDuplicatePatternDetected() async {
        let coordinator = makeCoordinator(
            deriveKey: { _, _ in self.dummyKey },
            vaultExists: { _ in true },
            saveIndex: { _, _ in },
            saveRecoveryPhrase: { _, _, _, _ in }
        )

        let result = await coordinator.savePattern(dummyPattern, gridSize: dummyGridSize, phrase: dummyPhrase)

        if case .duplicatePattern = result {
            // Pass
        } else {
            XCTFail("Expected .duplicatePattern, got \(result)")
        }
    }

    func testKeyDerivationFailure() async {
        let coordinator = makeCoordinator(
            deriveKey: { _, _ in throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "derivation failed"]) },
            vaultExists: { _ in false },
            saveIndex: { _, _ in },
            saveRecoveryPhrase: { _, _, _, _ in }
        )

        let result = await coordinator.savePattern(dummyPattern, gridSize: dummyGridSize, phrase: dummyPhrase)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("derivation failed"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }

    func testIndexSaveFailure() async {
        let coordinator = makeCoordinator(
            deriveKey: { _, _ in self.dummyKey },
            vaultExists: { _ in false },
            saveIndex: { _, _ in throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "save failed"]) },
            saveRecoveryPhrase: { _, _, _, _ in }
        )

        let result = await coordinator.savePattern(dummyPattern, gridSize: dummyGridSize, phrase: dummyPhrase)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("save failed"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }

    func testRecoveryPhraseSaveFailure() async {
        let coordinator = makeCoordinator(
            deriveKey: { _, _ in self.dummyKey },
            vaultExists: { _ in false },
            saveIndex: { _, _ in },
            saveRecoveryPhrase: { _, _, _, _ in throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "phrase failed"]) }
        )

        let result = await coordinator.savePattern(dummyPattern, gridSize: dummyGridSize, phrase: dummyPhrase)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("phrase failed"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }

    // MARK: - saveCustomPhrase

    func testCustomPhraseSaveFailure() async {
        let coordinator = makeCoordinator(
            saveRecoveryPhrase: { _, _, _, _ in throw NSError(domain: "test", code: 4, userInfo: [NSLocalizedDescriptionKey: "custom failed"]) }
        )

        let result = await coordinator.saveCustomPhrase(dummyPhrase, pattern: dummyPattern, gridSize: dummyGridSize, key: dummyKey)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("custom failed"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }
}

final class ChangePatternFlowStateTests: XCTestCase {

    func testShowErrorClearsValidationResult() {
        var state = ChangePatternFlowState()
        let invalid = PatternValidator.shared.validate([0, 1], gridSize: 5)
        state.showValidation(invalid)

        state.showError("boom")

        XCTAssertEqual(state.errorMessage, "boom")
        XCTAssertNil(state.validationResult)
    }

    func testShowValidationClearsErrorMessage() {
        var state = ChangePatternFlowState()
        state.showError("old error")
        let invalid = PatternValidator.shared.validate([0, 1], gridSize: 5)

        state.showValidation(invalid)

        XCTAssertNil(state.errorMessage)
        XCTAssertNotNil(state.validationResult)
    }

    func testBeginProcessingIfIdleRejectsConcurrentStart() {
        var state = ChangePatternFlowState()

        XCTAssertTrue(state.beginProcessingIfIdle())
        XCTAssertFalse(state.beginProcessingIfIdle())
        XCTAssertTrue(state.isProcessing)

        state.endProcessing()
        XCTAssertFalse(state.isProcessing)
    }

    func testResetForStartOverClearsState() {
        var state = ChangePatternFlowState(
            step: .confirmNew,
            currentPattern: [0, 1, 2],
            newPattern: [3, 4, 5],
            validationResult: PatternValidator.shared.validate([0, 1], gridSize: 5),
            errorMessage: "x",
            isProcessing: true,
            newRecoveryPhrase: "phrase"
        )

        state.resetForStartOver()

        XCTAssertEqual(state.step, .verifyCurrent)
        XCTAssertTrue(state.currentPattern.isEmpty)
        XCTAssertTrue(state.newPattern.isEmpty)
        XCTAssertNil(state.validationResult)
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isProcessing)
        XCTAssertEqual(state.newRecoveryPhrase, "phrase")
    }

    func testTransitionsSetStepAndClearFeedback() {
        var state = ChangePatternFlowState()
        state.showError("old")
        state.transitionToCreate(currentPattern: [0, 1, 2, 3, 4, 5])

        XCTAssertEqual(state.step, .createNew)
        XCTAssertEqual(state.currentPattern, [0, 1, 2, 3, 4, 5])
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.validationResult)
        XCTAssertFalse(state.isProcessing)

        state.showValidation(PatternValidator.shared.validate([0, 1], gridSize: 5))
        state.transitionToConfirm(newPattern: [6, 7, 8, 9, 10, 11])

        XCTAssertEqual(state.step, .confirmNew)
        XCTAssertEqual(state.newPattern, [6, 7, 8, 9, 10, 11])
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.validationResult)
        XCTAssertFalse(state.isProcessing)
    }
}
