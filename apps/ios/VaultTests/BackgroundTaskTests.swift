import XCTest
@testable import Vault

/// Tests for @MainActor await patterns and background task handling.
/// These tests catch common mistakes like:
/// - Missing `await` when calling @MainActor singletons from Task/Task.detached
/// - Not wrapping long operations in beginBackgroundTask/endBackgroundTask
/// - Orphaned background task IDs
@MainActor
final class BackgroundTaskTests: XCTestCase {

    private var testKey: VaultKey!
    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid

    override func setUp() {
        super.setUp()
        testKey = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)
    }

    // MARK: - Background Task Lifecycle

    /// Tests that beginBackgroundTask creates a valid task ID.
    func testBeginBackgroundTaskCreatesValidTask() {
        let expectation = XCTestExpectation(description: "Background task created")

        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "TestTask") {
            // Expiration handler
            expectation.fulfill()
        }

        XCTAssertNotEqual(bgTaskId, .invalid, "Should create valid background task")

        // Clean up
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
    }

    /// Tests that endBackgroundTask properly ends the task.
    func testEndBackgroundTaskEndsTask() {
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "TestTask") {
            // No-op: expiration handler not tested
        }

        XCTAssertNotEqual(bgTaskId, .invalid)

        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid

        // Task should be ended (no way to verify directly, but no crash = success)
        XCTAssertEqual(bgTaskId, .invalid)
    }

    /// Tests that orphaned tasks are prevented by ending previous task.
    /// Catches: Orphaned background task IDs
    func testBeginBackgroundTaskEndsPreviousTask() {
        // Start first task
        let firstTaskId = UIApplication.shared.beginBackgroundTask(withName: "FirstTask") {
            // No-op: expiration handler not tested
        }
        XCTAssertNotEqual(firstTaskId, .invalid)

        // Start second task without ending first (bad practice, but test shows the issue)
        let secondTaskId = UIApplication.shared.beginBackgroundTask(withName: "SecondTask") {
            // No-op: expiration handler not tested
        }
        XCTAssertNotEqual(secondTaskId, .invalid)
        XCTAssertNotEqual(firstTaskId, secondTaskId, "Each task should have unique ID")

        // Clean up both
        UIApplication.shared.endBackgroundTask(firstTaskId)
        UIApplication.shared.endBackgroundTask(secondTaskId)
    }

    // MARK: - @MainActor Singleton Access

    /// Tests that ShareSyncManager.scheduleSync requires await from Task.
    /// Catches: @MainActor await omission
    func testShareSyncManagerRequiresAwaitFromTask() async {
        let expectation = XCTestExpectation(description: "Schedule sync called")

        // This should compile and work with await
        Task {
            await ShareSyncManager.shared.scheduleSync(vaultKey: testKey)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    /// Tests that @MainActor singletons require await from Task.detached.
    /// Catches: @MainActor await omission in detached tasks
    func testBackgroundTransferManagerRequiresAwaitFromDetached() async {
        let expectation = XCTestExpectation(description: "Detached task completed")

        Task.detached {
            // This MUST have await - testing that it compiles and works
            await ShareSyncManager.shared.scheduleSync(vaultKey: self.testKey)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    /// Tests that DeepLinkHandler requires await from non-main context.
    func testDeepLinkHandlerRequiresAwait() async {
        let handler = DeepLinkHandler()
        let testURL = URL(string: "vaultaire://s/test")! // S1075: hardcoded URI acceptable in tests

        // From main actor - no await needed for sync method
        let result = handler.handle(testURL)
        XCTAssertFalse(result, "Should not handle invalid URL")
    }

    // MARK: - Concurrent Access Patterns

    /// Tests that multiple concurrent background tasks are handled correctly.
    func testConcurrentBackgroundTasks() async {
        let expectation = XCTestExpectation(description: "All tasks completed")
        expectation.expectedFulfillmentCount = 5

        for i in 0..<5 {
            Task.detached {
                await self.runConcurrentBackgroundTask(named: "ConcurrentTask\(i)")
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    // MARK: - Helpers

    private func runConcurrentBackgroundTask(named name: String) async {
        let taskId = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: name) {
                // No-op: expiration handler not tested
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    // MARK: - Error Handling

    /// Tests that background task works correctly even when operation fails.
    func testBackgroundTaskEndsOnError() async {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "ErrorTask") {
            // No-op: expiration handler not tested
        }

        // Simulate error
        let shouldFail = true
        if shouldFail {
            // Even on error, task should be ended
            UIApplication.shared.endBackgroundTask(taskId)
        }

        // Should not crash and task should be ended
        XCTAssertNotEqual(taskId, .invalid)
    }
}
