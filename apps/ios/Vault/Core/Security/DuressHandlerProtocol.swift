import Foundation

/// Protocol abstracting DuressHandler for testability.
/// Covers the public API surface used by AppState and ContentView.
/// All methods are async because DuressHandler is an actor.
protocol DuressHandlerProtocol: Actor {
    func setAsDuressVault(key: Data) async throws
    func isDuressKey(_ key: Data) -> Bool
    func clearDuressVault()
    var hasDuressVault: Bool { get }
    func triggerDuress(preservingKey duressKey: Data) async
    func performNuclearWipe(secure: Bool) async
}

extension DuressHandler: DuressHandlerProtocol {}
