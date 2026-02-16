import Foundation
import EmbraceIO

// File-scoped sensitive keywords to avoid actor isolation issues in Swift 6
private let SensitiveKeywords: [String] = [
    "key", "pattern", "phrase", "salt", "password", "secret", "token"
]

/// Status codes matching the former Sentry SpanStatus values used by call sites.
enum SpanStatus {
    case ok
    case internalError
    case invalidArgument
    case notFound
}

/// Lightweight wrapper around an Embrace span that preserves the existing
/// `.setTag(value:key:)` and `.finish(status:)` call-site API.
///
/// Uses closures to capture the underlying span — the concrete OTel Span type
/// is inferred by the compiler at capture time and never appears in a stored
/// property, avoiding the need to import OpenTelemetryApi directly.
///
/// SAFETY: `@unchecked Sendable` — the underlying Embrace span is thread-safe.
final class SpanHandle: @unchecked Sendable {
    private let _setTag: @Sendable (_ value: String, _ key: String) -> Void
    private let _finish: @Sendable (_ status: SpanStatus) -> Void
    fileprivate let _createChild: @Sendable (_ name: String, _ desc: String) -> SpanHandle

    fileprivate init(
        setTag: @escaping @Sendable (_ value: String, _ key: String) -> Void,
        finish: @escaping @Sendable (_ status: SpanStatus) -> Void,
        createChild: @escaping @Sendable (_ name: String, _ desc: String) -> SpanHandle
    ) {
        self._setTag = setTag
        self._finish = finish
        self._createChild = createChild
    }

    func setTag(value: String, key: String) { _setTag(value, key) }
    func finish(status: SpanStatus = .ok) { _finish(status) }

    static var noop: SpanHandle {
        SpanHandle(
            setTag: { _, _ in },
            finish: { _ in },
            createChild: { _, _ in .noop }
        )
    }
}

/// Telemetry wrapper around the Embrace SDK.
///
/// Drop-in replacement for the former SentryManager. All public method
/// signatures are unchanged so consumer files need only a find-replace
/// of the class name.
///
/// SAFETY: `@unchecked Sendable` because `isStarted` is only mutated from
/// `@MainActor` `start()`/`stop()`. All other methods use thread-safe
/// Embrace SDK APIs.
final class EmbraceManager: @unchecked Sendable {
    static let shared = EmbraceManager()
    private var isStarted = false
    private init() {}

    // MARK: - Start / Stop

    @MainActor
    func start() {
        guard !self.isStarted else { return }
        self.isStarted = true
        Task.detached(priority: .utility) {
            do {
                try Embrace
                    .setup(options: Embrace.Options(
                        appId: "ehz4q"
                    ))
                    .start()
            } catch {
                print("[EmbraceManager] Setup failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func stop() {
        guard self.isStarted else { return }
        // Embrace has no close/stop API — it runs for the app's lifetime.
        self.isStarted = false
    }

    // MARK: - Convenience: Transactions & Spans

    /// Creates a root span (transaction). Closures capture the concrete Embrace
    /// Span type by inference — no OTel type names needed in stored properties.
    nonisolated func startTransaction(name: String, operation: String) -> SpanHandle {
        guard let span = Embrace.client?.buildSpan(name: name).startSpan() else {
            return .noop
        }
        span.setAttribute(key: "operation", value: operation)

        return SpanHandle(
            setTag: { value, key in
                if EmbraceManager.containsSensitive(key) || EmbraceManager.containsSensitive(value) {
                    span.setAttribute(key: key, value: "[REDACTED]")
                } else {
                    span.setAttribute(key: key, value: value)
                }
            },
            finish: { status in
                switch status {
                case .ok:
                    span.end()
                case .internalError, .invalidArgument, .notFound:
                    span.end(errorCode: .failure)
                }
            },
            createChild: { childName, description in
                guard let childSpan = Embrace.client?.buildSpan(name: childName)
                    .setParent(span)
                    .startSpan() else { return .noop }
                childSpan.setAttribute(key: "description", value: description)
                return SpanHandle(
                    setTag: { value, key in
                        if EmbraceManager.containsSensitive(key) || EmbraceManager.containsSensitive(value) {
                            childSpan.setAttribute(key: key, value: "[REDACTED]")
                        } else {
                            childSpan.setAttribute(key: key, value: value)
                        }
                    },
                    finish: { status in
                        switch status {
                        case .ok:
                            childSpan.end()
                        case .internalError, .invalidArgument, .notFound:
                            childSpan.end(errorCode: .failure)
                        }
                    },
                    createChild: { _, _ in .noop }
                )
            }
        )
    }

    nonisolated func startSpan(parent: SpanHandle, operation: String, description: String) -> SpanHandle {
        parent._createChild(operation, description)
    }

    // MARK: - Convenience: Errors

    func captureError(_ error: Error) {
        let span = Embrace.client?.buildSpan(name: "error.captured").startSpan()
        span?.setAttribute(key: "error.type", value: String(describing: type(of: error)))
        span?.setAttribute(key: "error.message", value: error.localizedDescription)
        span?.end(errorCode: .failure)
    }

    // MARK: - Convenience: Breadcrumbs

    func addBreadcrumb(category: String, message: String? = nil, data: [String: Any]? = nil) {
        let text: String
        if let message, !message.isEmpty {
            text = "\(category): \(message)"
        } else {
            text = category
        }
        let scrubbed = Self.containsSensitive(text) ? "[REDACTED]" : text
        let properties = Self.scrubProperties(data) ?? [:]
        Embrace.client?.add(event: .breadcrumb(scrubbed, properties: properties))
    }

    // MARK: - Scrubbing

    @inline(__always) static func containsSensitive(_ value: String) -> Bool {
        let lower = value.lowercased()
        return SensitiveKeywords.contains { lower.contains($0) }
    }

    private static func scrubProperties(_ data: [String: Any]?) -> [String: String]? {
        guard let data else { return nil }
        var result = [String: String]()
        for (key, value) in data {
            let strValue = String(describing: value)
            if containsSensitive(key) || containsSensitive(strValue) {
                result[key] = "[REDACTED]"
            } else {
                result[key] = strValue
            }
        }
        return result
    }
}
