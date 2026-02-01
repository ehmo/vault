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
        Task { @MainActor in
            SentryManager.shared.start()
            TelemetryManager.shared.start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.key)
        if enabled {
            Task { @MainActor in
                SentryManager.shared.start()
                TelemetryManager.shared.start()
            }
        } else {
            Task { @MainActor in
                SentryManager.shared.stop()
                TelemetryManager.shared.stop()
            }
        }
    }
}

