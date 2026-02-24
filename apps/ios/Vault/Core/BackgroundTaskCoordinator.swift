import BackgroundTasks
import os.log

/// Lightweight coordinator for `BGProcessingTask` registration and scheduling.
/// Reduces boilerplate across managers that share the same register / schedule / cancel pattern.
enum BackgroundTaskCoordinator {

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "BGTask")

    /// Registers a `BGProcessingTask` handler and logs the result.
    /// - Parameters:
    ///   - identifier: The task identifier (must be in Info.plist `BGTaskSchedulerPermittedIdentifiers`).
    ///   - handler: Called on the main actor when the system launches the task.
    @discardableResult
    static func register(
        identifier: String,
        handler: @escaping @MainActor (BGProcessingTask) -> Void
    ) -> Bool {
        let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handler(processingTask)
            }
        }

        if success {
            logger.info("[bg-task] Registered \(identifier, privacy: .public)")
        } else {
            logger.error("[bg-task] Failed to register \(identifier, privacy: .public)")
        }
        return success
    }

    /// Cancels any pending request for `identifier`, then submits a new one.
    static func schedule(
        identifier: String,
        earliestIn seconds: TimeInterval = 15,
        requiresNetwork: Bool = true,
        requiresPower: Bool = false
    ) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = requiresNetwork
        request.requiresExternalPower = requiresPower
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("[bg-task] Scheduled \(identifier, privacy: .public) in ~\(Int(seconds))s")
        } catch {
            logger.error("[bg-task] Failed to schedule \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancels a pending background task request.
    static func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}
