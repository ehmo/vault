import Foundation

final class AnalyticsManager: @unchecked Sendable {
    static let shared = AnalyticsManager()
    private init() {
        // No-op: singleton
    }

    private static let key = "analyticsEnabled"

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.key)
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            EmbraceManager.shared.start()
        }
        DispatchQueue.global(qos: .utility).async {
            TelemetryManager.shared.start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.key)
        if enabled {
            DispatchQueue.main.async {
                EmbraceManager.shared.start()
            }
            DispatchQueue.global(qos: .utility).async {
                TelemetryManager.shared.start()
            }
        } else {
            DispatchQueue.main.async {
                EmbraceManager.shared.stop()
            }
            TelemetryManager.shared.stop()
        }
    }
}
