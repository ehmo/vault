import Foundation

final class AnalyticsManager {
    static let shared = AnalyticsManager()
    private init() { /* No-op */ }

    private static let key = "analyticsEnabled"

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.key)
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        runOnMain {
            EmbraceManager.shared.start()
            TelemetryManager.shared.start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.key)
        runOnMain {
            if enabled {
                EmbraceManager.shared.start()
                TelemetryManager.shared.start()
            } else {
                EmbraceManager.shared.stop()
                TelemetryManager.shared.stop()
            }
        }
    }

    private func runOnMain(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    block()
                }
            }
        }
    }
}
