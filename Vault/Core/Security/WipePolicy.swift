import Foundation

enum WipePolicyThreshold: Int, CaseIterable, Codable {
    case disabled = 0
    case fiveAttempts = 5
    case tenAttempts = 10
    case twentyAttempts = 20

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .fiveAttempts: return "5 attempts"
        case .tenAttempts: return "10 attempts"
        case .twentyAttempts: return "20 attempts"
        }
    }
}

final class WipePolicy {
    static let shared = WipePolicy()

    private let userDefaults = UserDefaults.standard
    private let thresholdKey = "wipePolicy.threshold"
    private let secureEnclave = SecureEnclaveManager.shared
    private let storage = VaultStorage.shared

    private init() {}

    // MARK: - Configuration

    var threshold: WipePolicyThreshold {
        get {
            let raw = userDefaults.integer(forKey: thresholdKey)
            return WipePolicyThreshold(rawValue: raw) ?? .tenAttempts
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: thresholdKey)
        }
    }

    // MARK: - Attempt Tracking

    var currentAttempts: Int {
        secureEnclave.getWipeCounter()
    }

    func recordFailedAttempt() async -> WipeAction {
        secureEnclave.incrementWipeCounter()
        let attempts = currentAttempts

        // Check if threshold reached
        if threshold != .disabled && attempts >= threshold.rawValue {
            await performWipe()
            return .wiped
        }

        // Calculate delay
        let delay = calculateDelay(for: attempts)
        return .delayed(seconds: delay)
    }

    func recordSuccessfulAttempt() {
        secureEnclave.resetWipeCounter()
    }

    // MARK: - Progressive Delay

    private func calculateDelay(for attemptCount: Int) -> TimeInterval {
        // Progressive delays: 0, 1, 2, 4, 8, 16, 30, 30, 30...
        switch attemptCount {
        case 0...1: return 0
        case 2: return 1
        case 3: return 2
        case 4: return 4
        case 5: return 8
        case 6: return 16
        default: return 30
        }
    }

    // MARK: - Wipe Execution

    func performWipe() async {
        // 1. Destroy all keychain data
        secureEnclave.performNuclearWipe()

        // 2. Overwrite all vault data with random bytes
        storage.destroyAllVaultData()

        // 3. Clear UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleId)
        }
    }

    enum WipeAction {
        case none
        case delayed(seconds: TimeInterval)
        case wiped
    }
}
