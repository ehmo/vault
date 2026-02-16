import Foundation
import EmbraceIO
import os

// File-scoped sensitive keywords to avoid actor isolation issues in Swift 6
private let sensitiveKeywords: [String] = [
    "key", "pattern", "phrase", "salt", "password", "secret", "token"
]
private let telemetryLogger = Logger(subsystem: "app.vaultaire.ios", category: "Embrace")

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
    private let setTagHandler: (_ value: String, _ key: String) -> Void
    private let finishHandler: (_ status: SpanStatus) -> Void
    fileprivate let createChildHandler: (_ name: String, _ desc: String) -> SpanHandle

    fileprivate init(
        setTag: @escaping (_ value: String, _ key: String) -> Void,
        finish: @escaping (_ status: SpanStatus) -> Void,
        createChild: @escaping (_ name: String, _ desc: String) -> SpanHandle
    ) {
        self.setTagHandler = setTag
        self.finishHandler = finish
        self.createChildHandler = createChild
    }

    func setTag(value: String, key: String) { setTagHandler(value, key) }
    func finish(status: SpanStatus = .ok) { finishHandler(status) }

    static var noop: SpanHandle {
        SpanHandle(
            setTag: { _, _ in
                // No-op: stub span ignores tags
            },
            finish: { _ in
                // No-op: stub span ignores finish
            },
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
    /// Tracks user intent (analytics enabled/disabled).
    private var isStarted = false
    /// Once Embrace SDK is initialized it cannot be re-initialized. This
    /// prevents a double-setup crash when the user toggles analytics off then on.
    private var hasSetup = false
    private init() { /* No-op */ }

    // MARK: - Start / Stop

    @MainActor
    func start() {
        guard !self.isStarted else { return }
        self.isStarted = true
        guard !self.hasSetup else {
            emitStartupHealthSignal(trigger: "re_enable")
            return
        }
        do {
            // Embrace enforces queue preconditions during setup; run on MainActor.
            try Embrace
                .setup(options: Embrace.Options(
                    appId: "ehz4q"
                ))
                .start()
            self.hasSetup = true
            emitStartupHealthSignal(trigger: "initial_start")
        } catch {
            self.isStarted = false
            self.hasSetup = false
            telemetryLogger.error("[EmbraceManager] Setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func stop() {
        guard self.isStarted else { return }
        // Embrace has no close/stop API — it runs for the app's lifetime.
        // We only clear the intent flag; hasSetup stays true to prevent
        // double-initialization if the user re-enables analytics.
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
        parent.createChildHandler(operation, description)
    }

    // MARK: - Convenience: Errors

    func captureError(_ error: Error, context: [String: Any]? = nil) {
        let nsError = error as NSError
        var attributes: [String: String] = [
            "error.type": String(describing: type(of: error)),
            "error.domain": nsError.domain,
            "error.code": String(nsError.code)
        ]
        if let context = Self.scrubProperties(context) {
            for (key, value) in context {
                attributes["context.\(key)"] = value
            }
        }

        if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            !failureReason.isEmpty
        {
            attributes["error.failure_reason"] = Self.containsSensitive(failureReason) ? "[REDACTED]" : failureReason
        }

        let scrubbedLocalizedDescription = Self.containsSensitive(error.localizedDescription)
            ? "[REDACTED]"
            : error.localizedDescription
        attributes["error.localized_description"] = scrubbedLocalizedDescription

        Embrace.client?.log(
            "handled_exception",
            severity: .error,
            type: .exception,
            attributes: attributes,
            stackTraceBehavior: .main
        )

        let span = Embrace.client?.buildSpan(name: "error.captured").startSpan()
        span?.setAttribute(key: "error.type", value: String(describing: type(of: error)))
        span?.setAttribute(key: "error.message", value: scrubbedLocalizedDescription)
        span?.end(errorCode: .failure)
    }

    // MARK: - Convenience: Breadcrumbs

    func addBreadcrumb(category: String, message: String? = nil, data: [String: Any]? = nil) {
        var text: String
        if let message, !message.isEmpty {
            text = "\(category): \(message)"
        } else {
            text = category
        }
        // Embrace 6.x breadcrumbs don't support properties — fold key data into the message.
        if let data, !data.isEmpty {
            let scrubbed = Self.scrubProperties(data) ?? [:]
            let pairs = scrubbed.sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            text += " [\(pairs)]"
        }
        let final = Self.containsSensitive(text) ? "[REDACTED]" : text
        Embrace.client?.add(event: .breadcrumb(final))
    }

    // MARK: - Scrubbing

    @inline(__always) static func containsSensitive(_ value: String) -> Bool {
        let lower = value.lowercased()
        return sensitiveKeywords.contains { lower.contains($0) }
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

    private func emitStartupHealthSignal(trigger: String) {
        guard let client = Embrace.client else {
            telemetryLogger.error("[EmbraceManager] No client after start trigger=\(trigger, privacy: .public)")
            return
        }

        let lastRunState = client.lastRunEndState()
        client.log(
            "embrace_started",
            severity: .info,
            attributes: [
                "trigger": trigger,
                "sdk_state": String(client.state.rawValue),
                "sdk_enabled": String(client.isSDKEnabled),
                "last_run_end_state": String(lastRunState.rawValue)
            ],
            stackTraceBehavior: .notIncluded
        )

        if lastRunState == .crash {
            client.log(
                "previous_run_crashed",
                severity: .critical,
                type: .exception,
                attributes: [
                    "source": "lastRunEndState",
                    "sdk_state": String(client.state.rawValue)
                ],
                stackTraceBehavior: .notIncluded
            )
        }
    }
}
