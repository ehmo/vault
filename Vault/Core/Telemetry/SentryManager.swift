import Foundation
import Sentry

// File-scoped sensitive keywords to avoid actor isolation issues in Swift 6
private let SentrySensitiveKeywords: [String] = [
    "key", "pattern", "phrase", "salt", "password", "secret", "token"
]

/// Telemetry wrapper around the Sentry SDK.
///
/// Convenience methods call thread-safe Sentry SDK APIs directly.
/// `start()` and `stop()` must be called from the main actor.
///
/// SAFETY: `@unchecked Sendable` because `isStarted` is only mutated from
/// `@MainActor` `start()`/`stop()`. All other methods use thread-safe
/// Sentry SDK APIs (startTransaction, capture, addBreadcrumb, Span.startChild).
final class SentryManager: @unchecked Sendable {
    static let shared = SentryManager()
    private var isStarted = false
    private init() {}

    // MARK: - Start / Stop

    @MainActor
    func start() {
        guard !self.isStarted else { return }
        self.isStarted = true
        SentrySDK.start { options in
            options.dsn = "https://5c2cd9ddb6a7514efdb3903e09d76e59@o4510751132745728.ingest.us.sentry.io/4510798192181248"

            // Privacy: never send PII, screenshots, or view hierarchy
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Performance
            options.enableAutoPerformanceTracing = true
            options.enableNetworkTracking = true
            options.enableFileIOTracing = true
            options.enableUIViewControllerTracing = false // SwiftUI app
            options.tracesSampleRate = 1.0

            // Scrub before sending events (scrubEvent is a pure static function)
            options.beforeSend = { event in
                Self.scrubEvent(event)
            }

            options.debug = false
        }
    }

    @MainActor
    func stop() {
        guard self.isStarted else { return }
        SentrySDK.close()
        self.isStarted = false
    }

    // MARK: - Scrubbing

    private static func scrubEvent(_ event: Event) -> Event? {
        // Scrub breadcrumbs
        event.breadcrumbs = event.breadcrumbs?.map { scrubBreadcrumb($0) }

        // Scrub tags ([String: String])
        if let tags = event.tags {
            event.tags = scrubStringDictionary(tags)
        }

        // Scrub extra ([String: Any])
        if let extra = event.extra {
            event.extra = scrubDictionary(extra)
        }

        return event
    }

    private static func scrubBreadcrumb(_ crumb: Breadcrumb) -> Breadcrumb {
        if let data = crumb.data {
            crumb.data = scrubDictionary(data)
        }
        if let message = crumb.message, containsSensitive(message) {
            crumb.message = "[REDACTED]"
        }
        return crumb
    }

    private static func scrubStringDictionary(_ dict: [String: String]) -> [String: String] {
        var result = [String: String]()
        for (key, value) in dict {
            if containsSensitive(key) || containsSensitive(value) {
                result[key] = "[REDACTED]"
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func scrubDictionary(_ dict: [String: Any]) -> [String: Any] {
        var result = [String: Any]()
        for (key, value) in dict {
            if containsSensitive(key) {
                result[key] = "[REDACTED]"
            } else if let str = value as? String, containsSensitive(str) {
                result[key] = "[REDACTED]"
            } else {
                result[key] = value
            }
        }
        return result
    }

    @inline(__always) private static func containsSensitive(_ value: String) -> Bool {
        let lower = value.lowercased()
        return SentrySensitiveKeywords.contains { lower.contains($0) }
    }

    // MARK: - Convenience: Transactions & Spans
    // Sentry SDK APIs below are all thread-safe — no main-thread dispatch needed.

    func startTransaction(name: String, operation: String) -> Span {
        SentrySDK.startTransaction(name: name, operation: operation)
    }

    func startSpan(parent: Span, operation: String, description: String) -> Span {
        parent.startChild(operation: operation, description: description)
    }

    // MARK: - Convenience: Errors

    func captureError(_ error: Error) {
        _ = SentrySDK.capture(error: error)
    }

    // MARK: - Convenience: Breadcrumbs

    func addBreadcrumb(category: String, message: String? = nil, data: [String: Any]? = nil, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }
}
