import SwiftUI
import UIKit
import Combine
import OSLog

/// Manages automatic vault locking after 5 minutes of inactivity.
/// Respects video playback, active operations, and touch events to avoid
/// locking during active use.
@MainActor
final class InactivityLockManager: ObservableObject {
    static let shared = InactivityLockManager()

    private let logger = Logger(subsystem: "app.vaultaire.ios", category: "InactivityLockManager")

    /// Time interval before auto-lock (5 minutes)
    let lockTimeout: TimeInterval

    /// Timer for tracking inactivity
    private var inactivityTimer: Timer?

    /// Timestamp of last user activity
    var lastActivityTime: Date = Date()

    /// Whether video is currently playing
    @Published private(set) var isVideoPlaying = false

    /// Whether the vault should auto-lock (set by app state)
    private(set) var shouldAutoLock = false

    /// Callback to lock the vault
    private var lockCallback: (() -> Void)?

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Closures that report whether an active operation is in progress.
    /// When any returns true, the auto-lock timer resets instead of firing.
    private var activeOperationChecks: [() -> Bool] = []

    private convenience init() {
        self.init(lockTimeout: 300)
    }

    /// Internal init for testing with configurable timeout.
    init(lockTimeout: TimeInterval = 300) {
        self.lockTimeout = lockTimeout
        setupNotifications()
    }

    // MARK: - Public API

    /// Starts monitoring for inactivity. Call when vault is unlocked.
    func startMonitoring(lockCallback: @escaping () -> Void) {
        self.lockCallback = lockCallback
        self.shouldAutoLock = true
        self.lastActivityTime = Date()

        logger.debug("Started inactivity monitoring")

        // Start the timer
        startTimer()
    }

    /// Stops monitoring. Call when vault is locked.
    func stopMonitoring() {
        shouldAutoLock = false
        lockCallback = nil
        inactivityTimer?.invalidate()
        inactivityTimer = nil

        logger.debug("Stopped inactivity monitoring")
    }

    /// Call this when user performs any activity (tap, scroll, etc.)
    func userDidInteract() {
        guard shouldAutoLock else { return }

        lastActivityTime = Date()
    }

    /// Register a closure that returns true when an active operation should suppress auto-lock.
    func registerActiveOperationCheck(_ check: @escaping () -> Bool) {
        activeOperationChecks.append(check)
    }

    /// Call this when video playback starts
    func videoPlaybackStarted() {
        isVideoPlaying = true
        logger.debug("Video playback started, pausing auto-lock")
    }

    /// Call this when video playback stops/pauses
    func videoPlaybackStopped() {
        isVideoPlaying = false
        lastActivityTime = Date() // Reset timer when video stops
        logger.debug("Video playback stopped, resuming auto-lock timer")
    }

    // MARK: - Private

    private func setupNotifications() {
        // App going to background - stop monitoring
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logger.debug("App entered background, stopping inactivity monitoring")
                self?.inactivityTimer?.invalidate()
            }
            .store(in: &cancellables)

        // App coming to foreground - restart monitoring if needed
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.shouldAutoLock else { return }
                self.logger.debug("App entering foreground, restarting inactivity monitoring")
                self.lastActivityTime = Date() // Reset on foreground
                self.startTimer()
            }
            .store(in: &cancellables)

        // Screen locked - stop monitoring
        NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logger.debug("Screen locked, stopping inactivity monitoring")
                self?.inactivityTimer?.invalidate()
            }
            .store(in: &cancellables)

        // Screen unlocked - restart monitoring
        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.shouldAutoLock else { return }
                self.logger.debug("Screen unlocked, restarting inactivity monitoring")
                self.lastActivityTime = Date() // Reset on unlock
                self.startTimer()
            }
            .store(in: &cancellables)
    }

    private func startTimer() {
        inactivityTimer?.invalidate()

        // Check every 10 seconds
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInactivity()
            }
        }
    }

    /// Whether any registered active operation is currently in progress.
    private var isActiveOperationInProgress: Bool {
        activeOperationChecks.contains { $0() }
    }

    func checkInactivity() {
        guard shouldAutoLock else { return }

        // Don't lock if video is playing
        if isVideoPlaying {
            logger.debug("Video is playing, skipping inactivity check")
            return
        }

        // Don't lock if an active operation is in progress
        if isActiveOperationInProgress {
            logger.debug("Active operation in progress, resetting inactivity timer")
            lastActivityTime = Date()
            return
        }

        // Don't lock if screen is off (device is locked)
        if UIApplication.shared.applicationState == .background {
            logger.debug("App is in background, skipping inactivity check")
            return
        }

        let elapsed = Date().timeIntervalSince(lastActivityTime)
        let remaining = lockTimeout - elapsed

        logger.debug("Inactivity check: elapsed=\(elapsed)s, remaining=\(remaining)s")

        if elapsed >= lockTimeout {
            logger.info("Inactivity timeout reached (5 minutes), locking vault")
            lockCallback?()
            stopMonitoring()
        }
    }
}

// MARK: - Passive Touch Recognizer

/// A gesture recognizer that observes all touches without consuming them.
/// Installed on the key window to reliably detect user interaction regardless
/// of SwiftUI gesture conflicts with buttons, lists, and scroll views.
/// UIGestureRecognizer is @MainActor, so touchesBegan runs on the main actor.
class PassthroughTouchRecognizer: UIGestureRecognizer {
    override func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
        state = .failed // Never consume the touch
        InactivityLockManager.shared.userDidInteract()
    }
}

// MARK: - Video Player Integration

/// Environment key for video playback state
private struct VideoPlaybackStateKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isVideoPlaying: Bool {
        get { self[VideoPlaybackStateKey.self] }
        set { self[VideoPlaybackStateKey.self] = newValue }
    }
}

/// View modifier to report video playback state to InactivityLockManager
struct VideoPlaybackReporter: ViewModifier {
    let isPlaying: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    InactivityLockManager.shared.videoPlaybackStarted()
                } else {
                    InactivityLockManager.shared.videoPlaybackStopped()
                }
            }
            .onDisappear {
                // Ensure we report stopped when view disappears
                InactivityLockManager.shared.videoPlaybackStopped()
            }
    }
}

extension View {
    /// Reports video playback state to the inactivity lock manager
    func reportVideoPlayback(isPlaying: Bool) -> some View {
        self.modifier(VideoPlaybackReporter(isPlaying: isPlaying))
    }
}
