import XCTest
@testable import Vault

@MainActor
final class InactivityLockManagerTests: XCTestCase {

    private var manager: InactivityLockManager!
    private var lockCallCount: Int = 0

    override func setUp() {
        super.setUp()
        lockCallCount = 0
        // Use a short timeout for fast tests
        manager = InactivityLockManager(lockTimeout: 2.0)
    }

    override func tearDown() {
        manager.stopMonitoring()
        manager = nil
        super.tearDown()
    }

    // MARK: - Monitoring Lifecycle

    func testStartMonitoring_enablesAutoLock() {
        XCTAssertFalse(manager.shouldAutoLock)

        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        XCTAssertTrue(manager.shouldAutoLock)
    }

    func testStopMonitoring_disablesAutoLock() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        XCTAssertTrue(manager.shouldAutoLock)

        manager.stopMonitoring()

        XCTAssertFalse(manager.shouldAutoLock)
    }

    // MARK: - Inactivity Check Logic

    func testCheckInactivity_doesNotLockBeforeTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        // lastActivityTime is set to now during startMonitoring
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 0, "Should not lock before timeout")
    }

    func testCheckInactivity_locksAfterTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        // Simulate inactivity by setting lastActivityTime in the past
        manager.lastActivityTime = Date().addingTimeInterval(-3.0) // 3s > 2s timeout

        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 1, "Should lock after timeout")
    }

    func testCheckInactivity_stopsMonitoringAfterLock() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-3.0)

        manager.checkInactivity()

        XCTAssertFalse(manager.shouldAutoLock, "Should stop monitoring after lock")
    }

    // MARK: - Activity Resets Timer

    func testUserDidInteract_resetsTimer() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0) // Way past timeout

        // User interacts — should reset
        manager.userDidInteract()

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock after activity reset")
    }

    func testUserDidInteract_ignoredWhenNotMonitoring() {
        // Don't start monitoring
        let beforeDate = manager.lastActivityTime

        // Small sleep to ensure Date() advances
        Thread.sleep(forTimeInterval: 0.01)

        manager.userDidInteract()

        // lastActivityTime should not be updated when not monitoring
        XCTAssertEqual(manager.lastActivityTime.timeIntervalSince1970,
                       beforeDate.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - Video Playback Suppression

    func testVideoPlayback_suppressesLock() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0) // Past timeout

        manager.videoPlaybackStarted()
        XCTAssertTrue(manager.isVideoPlaying)

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock during video playback")
    }

    func testVideoPlaybackStopped_resumesTimer() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.videoPlaybackStarted()

        manager.videoPlaybackStopped()

        XCTAssertFalse(manager.isVideoPlaying)
        // Should have reset lastActivityTime to now
        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0, "lastActivityTime should be reset to now")
    }

    func testVideoPlaybackStopped_allowsLockAfterTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.videoPlaybackStarted()
        manager.videoPlaybackStopped()

        // Simulate timeout after video stops
        manager.lastActivityTime = Date().addingTimeInterval(-3.0)
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 1, "Should lock after video stops + timeout")
    }

    // MARK: - Multiple Interactions

    func testMultipleRapidInteractions_dontAccumulate() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        // Simulate many rapid interactions
        for _ in 0..<100 {
            manager.userDidInteract()
        }

        // Should not have locked
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0)

        // Timer should be near-now
        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0)
    }

    // MARK: - Lock Timeout Configuration

    func testDefaultTimeout_is300Seconds() {
        let defaultManager = InactivityLockManager()
        XCTAssertEqual(defaultManager.lockTimeout, 300)
        defaultManager.stopMonitoring()
    }

    func testCustomTimeout_isUsed() {
        let customManager = InactivityLockManager(lockTimeout: 60)
        XCTAssertEqual(customManager.lockTimeout, 60)

        var locked = false
        customManager.startMonitoring { locked = true }

        // 30s ago — should not lock (timeout = 60)
        customManager.lastActivityTime = Date().addingTimeInterval(-30)
        customManager.checkInactivity()
        XCTAssertFalse(locked)

        // 70s ago — should lock
        customManager.lastActivityTime = Date().addingTimeInterval(-70)
        customManager.checkInactivity()
        XCTAssertTrue(locked)

        customManager.stopMonitoring()
    }

    // MARK: - Edge Cases

    func testCheckInactivity_ignoredWhenNotMonitoring() {
        // Don't start monitoring
        manager.lastActivityTime = Date().addingTimeInterval(-999)
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 0, "Should not lock when not monitoring")
    }

    func testDoubleStop_isSafe() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.stopMonitoring()
        manager.stopMonitoring() // Should not crash
        XCTAssertFalse(manager.shouldAutoLock)
    }

    func testStartMonitoring_resetsLastActivity() {
        // Set old activity time
        manager.lastActivityTime = Date().addingTimeInterval(-999)

        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0, "startMonitoring should reset lastActivityTime")
    }
}
