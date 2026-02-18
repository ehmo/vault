import Foundation

/// Protocol abstracting SubscriptionManager for testability.
/// Covers the public API surface used by feature-gating checks.
@MainActor
protocol SubscriptionClient {
    var isPremium: Bool { get }

    func canCreateVault(currentCount: Int) -> Bool
    func canJoinSharedVault(currentCount: Int) -> Bool
    func canAddFile(currentFileCount: Int) -> Bool
    func canCreateSharedVault() -> Bool
    func canCreateDuressVault() -> Bool
    func canSyncWithICloud() -> Bool
    func canExpandStorage() -> Bool
}

extension SubscriptionManager: SubscriptionClient {}
