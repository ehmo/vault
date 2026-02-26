import Foundation
import TelemetryDeck

final class TelemetryManager: @unchecked Sendable {
    static let shared = TelemetryManager()
    private var isInitialized = false
    private init() {
        // No-op: singleton
    }

    func start() {
        guard !isInitialized else { return }
        let config = TelemetryDeck.Config(appID: "598A62FB-72B8-4FB9-AB7E-069859E25FD9")
        TelemetryDeck.initialize(config: config)
        isInitialized = true
    }

    func stop() {
        // TelemetryDeck doesn't expose a shutdown method;
        // guard on isInitialized prevents new signals after toggle-off.
        isInitialized = false
    }

    func signal(_ name: String, parameters: [String: String] = [:]) {
        guard isInitialized else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }
}
