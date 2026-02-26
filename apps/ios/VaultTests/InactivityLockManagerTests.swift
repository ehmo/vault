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

    func testStartMonitoringEnablesAutoLock() {
        XCTAssertFalse(manager.shouldAutoLock)

        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        XCTAssertTrue(manager.shouldAutoLock)
    }

    func testStopMonitoringDisablesAutoLock() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        XCTAssertTrue(manager.shouldAutoLock)

        manager.stopMonitoring()

        XCTAssertFalse(manager.shouldAutoLock)
    }

    func testStopMonitoringClearsCallback() {
        var called = false
        manager.startMonitoring { called = true }
        manager.stopMonitoring()

        // Manually force a check — callback should be nil
        manager.lastActivityTime = Date().addingTimeInterval(-999)
        manager.checkInactivity()
        XCTAssertFalse(called, "Callback should not fire after stopMonitoring")
    }

    func testStartMonitoringResetsLastActivity() {
        manager.lastActivityTime = Date().addingTimeInterval(-999)

        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0, "startMonitoring should reset lastActivityTime")
    }

    func testRestartMonitoringAfterStop() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.stopMonitoring()

        // Start again with a new callback
        var secondCallbackFired = false
        manager.startMonitoring { secondCallbackFired = true }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()

        XCTAssertTrue(secondCallbackFired, "New callback should fire after restart")
        XCTAssertEqual(lockCallCount, 0, "Original callback should not fire")
    }

    // MARK: - Inactivity Check Logic

    func testCheckInactivityDoesNotLockBeforeTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 0, "Should not lock before timeout")
    }

    func testCheckInactivityLocksAfterTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-3.0) // 3s > 2s timeout

        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 1, "Should lock after timeout")
    }

    func testCheckInactivityStopsMonitoringAfterLock() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-3.0)

        manager.checkInactivity()

        XCTAssertFalse(manager.shouldAutoLock, "Should stop monitoring after lock")
    }

    func testCheckInactivityLocksExactlyOnce() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()
        manager.checkInactivity() // Should be no-op — monitoring stopped
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 1, "Should lock exactly once")
    }

    func testCheckInactivityAtExactTimeoutBoundary() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        // Set to exactly the timeout
        manager.lastActivityTime = Date().addingTimeInterval(-2.0)

        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 1, "Should lock at exact timeout boundary")
    }

    func testCheckInactivityJustBeforeTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        // Set to just under the timeout
        manager.lastActivityTime = Date().addingTimeInterval(-1.9)

        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 0, "Should not lock just before timeout")
    }

    func testCheckInactivityIgnoredWhenNotMonitoring() {
        manager.lastActivityTime = Date().addingTimeInterval(-999)
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 0, "Should not lock when not monitoring")
    }

    // MARK: - User Activity Resets Timer

    func testUserDidInteractResetsTimer() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0) // Way past timeout

        manager.userDidInteract()

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock after activity reset")
    }

    func testUserDidInteractIgnoredWhenNotMonitoring() {
        let beforeDate = manager.lastActivityTime
        Thread.sleep(forTimeInterval: 0.01)

        manager.userDidInteract()

        XCTAssertEqual(manager.lastActivityTime.timeIntervalSince1970,
                       beforeDate.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testMultipleRapidInteractionsDontAccumulate() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        for _ in 0..<100 {
            manager.userDidInteract()
        }

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0)

        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testUserInteractionAfterPartialTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        // 1.5s into 2s timeout
        manager.lastActivityTime = Date().addingTimeInterval(-1.5)

        // User interacts — resets timer
        manager.userDidInteract()

        // Would have been past timeout from original activity time
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Interaction should fully reset the timer")
    }

    // MARK: - Video Playback Suppression

    func testVideoPlaybackSuppressesLock() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.videoPlaybackStarted()
        XCTAssertTrue(manager.isVideoPlaying)

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock during video playback")
    }

    func testVideoPlaybackDoesNotResetTimer() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        let oldTime = Date().addingTimeInterval(-10.0)
        manager.lastActivityTime = oldTime

        manager.videoPlaybackStarted()

        // Video suppresses but does NOT reset the timer (unlike active operations)
        XCTAssertEqual(manager.lastActivityTime.timeIntervalSince1970,
                       oldTime.timeIntervalSince1970,
                       accuracy: 0.001,
                       "Video playback should not reset lastActivityTime")
    }

    func testVideoPlaybackStoppedResumesTimer() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.videoPlaybackStarted()

        manager.videoPlaybackStopped()

        XCTAssertFalse(manager.isVideoPlaying)
        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0, "lastActivityTime should be reset to now")
    }

    func testVideoPlaybackStoppedAllowsLockAfterTimeout() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.videoPlaybackStarted()
        manager.videoPlaybackStopped()

        manager.lastActivityTime = Date().addingTimeInterval(-3.0)
        manager.checkInactivity()

        XCTAssertEqual(lockCallCount, 1, "Should lock after video stops + timeout")
    }

    // MARK: - Active Operation Suppression

    func testActiveOperationSuppressesLock() {
        var operationActive = true
        manager.registerActiveOperationCheck { operationActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock during active operation")
    }

    func testActiveOperationResetsTimer() {
        var operationActive = true
        manager.registerActiveOperationCheck { operationActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()

        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0, "Active operation should reset lastActivityTime")
    }

    func testLockResumesAfterOperationCompletes() {
        var operationActive = true
        manager.registerActiveOperationCheck { operationActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0)

        // Operation completes
        operationActive = false
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 1, "Should lock after operation completes + timeout")
    }

    func testMultipleActiveOperationChecks() {
        var importActive = false
        var uploadActive = false
        var backupActive = false
        manager.registerActiveOperationCheck { importActive }
        manager.registerActiveOperationCheck { uploadActive }
        manager.registerActiveOperationCheck { backupActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        // No operations — should lock
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 1, "Should lock when no operations active")

        // Restart for next test
        lockCallCount = 0
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        // Only one operation active — should suppress
        uploadActive = true
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Any single active operation should suppress lock")

        // Different operation active
        uploadActive = false
        backupActive = true
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Backup should also suppress lock")
    }

    func testActiveOperationCheckWithWeakReference() {
        // Simulate VaultViewModel being deallocated
        var viewModel: NSObject? = NSObject()
        weak var weakRef = viewModel
        manager.registerActiveOperationCheck { [weak weakRef] in
            weakRef != nil // Simulate isImporting check
        }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        // Object alive — operation "active"
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should suppress when weak ref alive")

        // Object deallocated — operation returns false
        viewModel = nil
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 1, "Should lock when weak ref is nil")
    }

    func testActiveOperationAndVideoPlaybackCombined() {
        var operationActive = true
        manager.registerActiveOperationCheck { operationActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        // Both video and operation active
        manager.videoPlaybackStarted()
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock with both suppressors")

        // Video stops but operation still active
        manager.videoPlaybackStopped()
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Operation alone should still suppress")

        // Operation stops
        operationActive = false
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 1, "Should lock when all suppressors removed")
    }

    func testActiveOperationRegisteredBeforeMonitoring() {
        var active = true
        manager.registerActiveOperationCheck { active }

        // Register before startMonitoring — should still work
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Check registered before monitoring should work")
    }

    func testActiveOperationContinuouslyResetsTimer() {
        var operationActive = true
        manager.registerActiveOperationCheck { operationActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }

        // Simulate multiple check cycles during a long operation
        for _ in 0..<10 {
            manager.lastActivityTime = Date().addingTimeInterval(-10.0)
            manager.checkInactivity()
        }

        XCTAssertEqual(lockCallCount, 0, "Should never lock during continuous active operation")
        // Timer should still be recent
        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0)
    }

    // MARK: - Suppression Priority Order

    func testSuppressionPriorityOrder() {
        // Verify the priority: video > active operation > background > timeout
        var operationActive = true
        manager.registerActiveOperationCheck { operationActive }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        // Video playing — checked first, timer NOT reset
        manager.videoPlaybackStarted()
        let beforeTime = manager.lastActivityTime
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0)
        // Video suppression should NOT reset the timer (just skip)
        XCTAssertEqual(manager.lastActivityTime.timeIntervalSince1970,
                       beforeTime.timeIntervalSince1970,
                       accuracy: 0.001,
                       "Video suppression should not reset timer")

        // Stop video — now active operation should catch it and RESET timer
        manager.videoPlaybackStopped()
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0)
        let elapsed = Date().timeIntervalSince(manager.lastActivityTime)
        XCTAssertLessThan(elapsed, 1.0, "Active operation should reset timer")
    }

    // MARK: - Lock Timeout Configuration

    func testDefaultTimeoutIs300Seconds() {
        let defaultManager = InactivityLockManager()
        XCTAssertEqual(defaultManager.lockTimeout, 300)
        defaultManager.stopMonitoring()
    }

    func testCustomTimeoutIsUsed() {
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

    func testVeryShortTimeout() {
        let shortManager = InactivityLockManager(lockTimeout: 0.001)
        var locked = false
        shortManager.startMonitoring { locked = true }

        Thread.sleep(forTimeInterval: 0.01)
        shortManager.checkInactivity()

        XCTAssertTrue(locked, "Very short timeout should trigger lock almost immediately")
        shortManager.stopMonitoring()
    }

    // MARK: - Edge Cases

    func testDoubleStopIsSafe() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.stopMonitoring()
        manager.stopMonitoring() // Should not crash
        XCTAssertFalse(manager.shouldAutoLock)
    }

    func testDoubleStartReplacesCallback() {
        var firstCalled = false
        var secondCalled = false
        manager.startMonitoring { firstCalled = true }
        manager.startMonitoring { secondCalled = true }

        manager.lastActivityTime = Date().addingTimeInterval(-10.0)
        manager.checkInactivity()

        XCTAssertFalse(firstCalled, "First callback should be replaced")
        XCTAssertTrue(secondCalled, "Second callback should be used")
    }

    func testVideoStateResetOnStop() {
        manager.videoPlaybackStarted()
        XCTAssertTrue(manager.isVideoPlaying)

        // Stopping monitoring should NOT clear video state —
        // video state is independent of monitoring
        manager.stopMonitoring()
        XCTAssertTrue(manager.isVideoPlaying, "Video state is independent of monitoring")

        // But lock check ignores it because shouldAutoLock is false
        manager.lastActivityTime = Date().addingTimeInterval(-999)
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Should not lock when not monitoring even with old timer")
    }

    func testInteractionDuringVideoPlayback() {
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.videoPlaybackStarted()
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        // User interacts while video plays
        manager.userDidInteract()

        // Stop video — timer should be fresh from interaction
        manager.videoPlaybackStopped()
        manager.checkInactivity()
        XCTAssertEqual(lockCallCount, 0, "Timer should be fresh after interaction during video")
    }

    func testOperationCheckNotCalledWhenNotMonitoring() {
        var checkCallCount = 0
        manager.registerActiveOperationCheck {
            checkCallCount += 1
            return true
        }

        // Not monitoring — check should not be evaluated
        manager.checkInactivity()
        XCTAssertEqual(checkCallCount, 0, "Operation check should not run when not monitoring")
    }

    func testOperationCheckNotCalledWhenVideoPlaying() {
        var checkCallCount = 0
        manager.registerActiveOperationCheck {
            checkCallCount += 1
            return true
        }
        manager.startMonitoring { [weak self] in self?.lockCallCount += 1 }
        manager.videoPlaybackStarted()
        manager.lastActivityTime = Date().addingTimeInterval(-10.0)

        manager.checkInactivity()
        XCTAssertEqual(checkCallCount, 0, "Operation check should not run during video playback")
    }
}
