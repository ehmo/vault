import Foundation

final class AnalyticsManager {
    static let shared = AnalyticsManager()
    private init() {}

    private static let key = "analyticsEnabled"

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.key)
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        Task.detached(priority: .utility) {
            await EmbraceManager.shared.start()
            TelemetryManager.shared.start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.key)
        if enabled {
            // Run all SDK initialization off the main thread to avoid blocking
            // UI during the analytics → paywall transition.
            Task.detached(priority: .utility) {
                await EmbraceManager.shared.start()
                TelemetryManager.shared.start()
            }
        } else {
            Task { @MainActor in
                EmbraceManager.shared.stop()
                TelemetryManager.shared.stop()
            }
        }
    }
}

