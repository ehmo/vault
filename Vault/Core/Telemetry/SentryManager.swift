import Foundation
import Sentry

final class SentryManager {
    static let shared = SentryManager()
    private var isStarted = false
    private init() {}

    // MARK: - Sensitive Keywords

    private static let sensitiveKeywords: [String] = [
        "key", "pattern", "phrase", "salt", "password", "secret", "token"
    ]

    // MARK: - Start / Stop

    func start() {
        guard !isStarted else { return }
        isStarted = true
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

            // Scrub before sending events
            options.beforeSend = { event in
                Self.scrubEvent(event)
            }

            #if DEBUG
            options.debug = true
            #endif
        }
    }

    func stop() {
        guard isStarted else { return }
        SentrySDK.close()
        isStarted = false
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

    private static func containsSensitive(_ value: String) -> Bool {
        let lower = value.lowercased()
        return sensitiveKeywords.contains { lower.contains($0) }
    }

    // MARK: - Convenience: Transactions & Spans

    func startTransaction(name: String, operation: String) -> Span {
        SentrySDK.startTransaction(name: name, operation: operation)
    }

    func startSpan(parent: Span, operation: String, description: String) -> Span {
        parent.startChild(operation: operation, description: description)
    }

    // MARK: - Convenience: Errors

    func captureError(_ error: Error) {
        SentrySDK.capture(error: error)
    }

    // MARK: - Convenience: Breadcrumbs

    func addBreadcrumb(category: String, message: String? = nil, data: [String: Any]? = nil, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }
}
