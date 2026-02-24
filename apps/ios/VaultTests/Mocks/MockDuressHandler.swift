import Foundation
@testable import Vault

/// Mock DuressHandler for testing. Tracks calls without destroying real data.
actor MockDuressHandler: DuressHandlerProtocol {
    var duressFingerprint: String?
    var triggerDuressCallCount = 0
    var nuclearWipeCallCount = 0
    var lastTriggerKey: Data?

    func setAsDuressVault(key: Data) async throws {
        duressFingerprint = String(key.hashValue)
    }

    func isDuressKey(_ key: Data) -> Bool {
        guard let stored = duressFingerprint else { return false }
        return stored == String(key.hashValue)
    }

    func clearDuressVault() {
        duressFingerprint = nil
    }

    var hasDuressVault: Bool {
        duressFingerprint != nil
    }

    func triggerDuress(preservingKey duressKey: Data) async {
        triggerDuressCallCount += 1
        lastTriggerKey = duressKey
    }

    func performNuclearWipe(secure _: Bool) async {
        nuclearWipeCallCount += 1
        duressFingerprint = nil
    }
}
