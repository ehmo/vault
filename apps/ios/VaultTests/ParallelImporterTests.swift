import XCTest
@testable import Vault

final class ParallelImporterTests: XCTestCase {

    // MARK: - Concurrency Monitor

    /// Tracks peak concurrent operations to verify parallelism.
    private actor ConcurrencyMonitor {
        private(set) var current = 0
        private(set) var peak = 0

        func enter() {
            current += 1
            if current > peak { peak = current }
        }

        func exit() {
            current -= 1
        }
    }

    // MARK: - testRunWorkers_ExecutesConcurrently

    /// The key regression test: verifies that workers actually run in parallel.
    /// If ParallelImporter silently regresses to serial, peak would be 1 and elapsed ~900ms.
    func testRunWorkersExecutesConcurrently() async {
        let monitor = ConcurrencyMonitor()
        let items = Array(0..<9)
        let queue = ParallelImporter.Queue(items)
        let workerCount = 3

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let start = ContinuousClockInstant.now

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, workerCount)],
                process: { @Sendable item in
                    await monitor.enter()
                    try await Task.sleep(for: .milliseconds(100))
                    await monitor.exit()
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "item\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var importedCount = 0
        for await event in stream {
            if case .imported = event { importedCount += 1 }
        }
        await workerTask.value

        let elapsed = ContinuousClockInstant.now - start
        let peakConcurrency = await monitor.peak

        // With 3 workers processing 9 items of 100ms each:
        // Parallel: peak >= 3, elapsed ~300ms
        // Serial: peak == 1, elapsed ~900ms
        XCTAssertGreaterThanOrEqual(peakConcurrency, 3, "Peak concurrency should be >= 3 (was \(peakConcurrency))")
        XCTAssertEqual(importedCount, 9, "All 9 items should be imported")
        XCTAssertLessThan(elapsed, .milliseconds(500), "Parallel execution should complete in <500ms")
    }

    // MARK: - testRunWorkers_AllItemsProcessed

    /// Verifies that every work item is processed exactly once.
    func testRunWorkersAllItemsProcessed() async {
        let items = Array(0..<12)
        let queue = ParallelImporter.Queue(items)
        let workerCount = 3

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, workerCount)],
                process: { @Sendable item in
                    VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "item\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var importedSizes: [Int] = []
        for await event in stream {
            if case .imported(let file) = event {
                importedSizes.append(file.size)
            }
        }
        await workerTask.value

        XCTAssertEqual(importedSizes.count, 12, "All 12 items should be processed")
        XCTAssertEqual(Set(importedSizes), Set(0..<12), "Each item should be processed exactly once")
    }

    // MARK: - testRunWorkers_CancellationStopsProcessing

    /// Verifies that cancelling the parent task stops workers from processing remaining items.
    func testRunWorkersCancellationStopsProcessing() async {
        let items = Array(0..<50)
        let queue = ParallelImporter.Queue(items)
        let workerCount = 2

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, workerCount)],
                process: { @Sendable item in
                    try await Task.sleep(for: .milliseconds(50))
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "item\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        // Cancel after a short delay
        try? await Task.sleep(for: .milliseconds(150))
        workerTask.cancel()

        var processedCount = 0
        for await event in stream {
            if case .imported = event { processedCount += 1 }
        }

        XCTAssertLessThan(processedCount, 50, "Most items should NOT be processed after cancellation (got \(processedCount))")
    }

    // MARK: - testQueue_ThreadSafety

    /// Verifies that Queue actor safely distributes items across many concurrent consumers
    /// with no duplicates and no missed items.
    func testQueueThreadSafety() async {
        let totalItems = 100
        let consumerCount = 10
        let items = Array(0..<totalItems)
        let queue = ParallelImporter.Queue(items)

        let collector = Collector()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<consumerCount {
                group.addTask {
                    while let item = await queue.next() {
                        await collector.add(item)
                    }
                }
            }
        }

        let collected = await collector.items
        XCTAssertEqual(collected.count, totalItems, "Total dequeued should be \(totalItems)")
        XCTAssertEqual(Set(collected).count, totalItems, "No duplicates — each item dequeued exactly once")
    }

    /// Thread-safe collector for testQueue_ThreadSafety.
    private actor Collector {
        var items: [Int] = []
        func add(_ item: Int) { items.append(item) }
    }
}

/// Clock instant helper for elapsed time measurement.
private struct ContinuousClockInstant {
    let uptimeNanoseconds: UInt64

    static var now: ContinuousClockInstant {
        ContinuousClockInstant(uptimeNanoseconds: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
    }

    static func - (lhs: ContinuousClockInstant, rhs: ContinuousClockInstant) -> Duration {
        .nanoseconds(Int64(lhs.uptimeNanoseconds - rhs.uptimeNanoseconds))
    }
}
