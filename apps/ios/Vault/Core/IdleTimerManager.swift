import UIKit
import OSLog

/// Manages the idle timer to prevent screen sleep during critical operations.
/// Provides a reference-counted approach for nested operations.
final class IdleTimerManager: @unchecked Sendable {
    static let shared = IdleTimerManager()
    
    private let logger = Logger(subsystem: "app.vaultaire.ios", category: "IdleTimerManager")
    private var disableCount = 0
    private let lock = NSLock()
    
    /// Disables the idle timer (screen will stay on).
    /// Call `enable()` when the operation completes.
    func disable() {
        lock.lock()
        defer { lock.unlock() }
        
        disableCount += 1
        if disableCount == 1 {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            logger.debug("Idle timer disabled")
        }
    }
    
    /// Re-enables the idle timer (screen can sleep).
    /// Must be paired with a prior `disable()` call.
    func enable() {
        lock.lock()
        defer { lock.unlock() }
        
        guard disableCount > 0 else {
            logger.warning("IdleTimerManager enable() called without matching disable()")
            return
        }
        
        disableCount -= 1
        if disableCount == 0 {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            logger.debug("Idle timer re-enabled")
        }
    }
    
    /// Executes a closure with the idle timer disabled, automatically re-enabling afterward.
    /// - Parameter operation: The work to perform with idle timer disabled
    func withDisabled<T>(_ operation: () throws -> T) rethrows -> T {
        disable()
        defer { enable() }
        return try operation()
    }
    
    /// Executes an async closure with the idle timer disabled, automatically re-enabling afterward.
    /// - Parameter operation: The async work to perform with idle timer disabled
    func withDisabled<T>(_ operation: () async throws -> T) async rethrows -> T {
        disable()
        defer { enable() }
        return try await operation()
    }
}
