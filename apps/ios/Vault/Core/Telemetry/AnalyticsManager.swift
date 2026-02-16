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
        Task(priority: .utility) { @MainActor in
            EmbraceManager.shared.start()
            TelemetryManager.shared.start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.key)
        if enabled {
            // Embrace setup/start must run on MainActor to satisfy SDK queue
            // preconditions and ensure Embrace.client is initialized.
            Task(priority: .utility) { @MainActor in
                EmbraceManager.shared.start()
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
