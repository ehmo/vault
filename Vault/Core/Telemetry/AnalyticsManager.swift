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
        SentryManager.shared.start()
        TelemetryManager.shared.start()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.key)
        if enabled {
            SentryManager.shared.start()
            TelemetryManager.shared.start()
        } else {
            SentryManager.shared.stop()
            TelemetryManager.shared.stop()
        }
    }
}
