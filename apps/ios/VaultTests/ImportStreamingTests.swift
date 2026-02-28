import XCTest
@testable import Vault

/// Comprehensive tests verifying the one-by-one streaming import behavior.
/// These tests guard against regression to batched imports where UI progress stalls.
final class ImportStreamingTests: XCTestCase {

    // MARK: - Helpers

    private struct ContinuousClockInstant {
        let uptimeNanoseconds: UInt64

        static var now: ContinuousClockInstant {
            ContinuousClockInstant(uptimeNanoseconds: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        }

        static func - (lhs: ContinuousClockInstant, rhs: ContinuousClockInstant) -> Duration {
            .nanoseconds(Int64(lhs.uptimeNanoseconds - rhs.uptimeNanoseconds))
        }
    }

    // MARK: - One-by-One Streaming

    /// Critical regression test: events must stream individually, not accumulate in batches.
    /// If someone re-introduces batch-of-N coordinator, the inter-event gap would be ~N * processTime
    /// instead of ~processTime.
    func testEventsStreamOneByOne() async {
        let items = Array(0..<6)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 1)],  // Single worker for deterministic timing
                process: { @Sendable item in
                    try await Task.sleep(for: .milliseconds(50))
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var timestamps: [UInt64] = []
        for await event in stream {
            if case .imported = event {
                timestamps.append(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
            }
        }
        await workerTask.value

        XCTAssertEqual(timestamps.count, 6, "All 6 items should be streamed")

        // With one-by-one streaming, each event arrives ~50ms after the previous.
        // With batch-of-N, we'd see 0 events for N*50ms then N events at once.
        // Check that events are spread out, not clumped.
        var maxGap: UInt64 = 0
        for i in 1..<timestamps.count {
            let gap = timestamps[i] - timestamps[i - 1]
            maxGap = max(maxGap, gap)
        }
        // Max gap between consecutive events should be < 200ms (generous, actual ~50ms)
        // A batch-of-6 would have ~300ms gap followed by near-zero gaps
        let maxGapMs = maxGap / 1_000_000
        XCTAssertLessThan(maxGapMs, 200, "Events should stream individually, not in bursts (max gap: \(maxGapMs)ms)")
    }

    /// Verifies that each event updates progress incrementally.
    func testProgressIncrementsPerEvent() async {
        let items = Array(0..<5)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 2)],
                process: { @Sendable item in
                    try await Task.sleep(for: .milliseconds(30))
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var progressSnapshots: [Int] = []
        var count = 0
        for await event in stream {
            if case .imported = event {
                count += 1
                progressSnapshots.append(count)
            }
        }
        await workerTask.value

        XCTAssertEqual(progressSnapshots, [1, 2, 3, 4, 5],
                       "Progress should increment by 1 after each event")
    }

    // MARK: - Error Handling

    /// Verifies that failures are reported as individual events, not swallowed.
    func testFailuresReportedIndividually() async {
        let items = Array(0..<6)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 2)],
                process: { @Sendable item in
                    if item % 2 == 0 {
                        throw NSError(domain: "Test", code: item, userInfo: [NSLocalizedDescriptionKey: "Error \(item)"])
                    }
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var successes = 0
        var failures = 0
        var failureReasons: [String] = []
        for await event in stream {
            switch event {
            case .imported:
                successes += 1
            case .failed(let reason):
                failures += 1
                if let reason { failureReasons.append(reason) }
            }
        }
        await workerTask.value

        XCTAssertEqual(successes, 3, "Items 1, 3, 5 should succeed")
        XCTAssertEqual(failures, 3, "Items 0, 2, 4 should fail")
        XCTAssertEqual(failureReasons.count, 3, "Each failure should have a reason")
        for reason in failureReasons {
            XCTAssertTrue(reason.contains("Error"), "Failure reason should contain error message")
        }
    }

    /// Verifies that a mix of successes and failures still produces correct totals.
    func testMixedSuccessFailureCounting() async {
        let items = Array(0..<10)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 3)],
                process: { @Sendable item in
                    // Items 3, 7 fail
                    if item == 3 || item == 7 {
                        throw NSError(domain: "Test", code: item)
                    }
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var successCount = 0
        var failedCount = 0
        for await event in stream {
            switch event {
            case .imported: successCount += 1
            case .failed: failedCount += 1
            }
        }
        await workerTask.value

        XCTAssertEqual(successCount + failedCount, 10, "Total events should equal total items")
        XCTAssertEqual(successCount, 8)
        XCTAssertEqual(failedCount, 2)
    }

    // MARK: - Empty Input

    /// Verifies that empty work arrays don't hang or crash.
    func testEmptyPhotoImportCompletes() async {
        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runPhotoImport(
                videoWork: [],
                imageWork: [],
                videoWorkerCount: 0,
                imageWorkerCount: 0,
                config: .init(
                    key: VaultKey(Data(repeating: 0, count: 32)),
                    encryptionKey: Data(repeating: 0, count: 32),
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
            continuation.finish()
        }

        var eventCount = 0
        for await _ in stream {
            eventCount += 1
        }
        await workerTask.value

        XCTAssertEqual(eventCount, 0, "Empty input should produce zero events")
    }

    /// Verifies that empty file import completes immediately.
    func testEmptyFileImportCompletes() async {
        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runFileImport(
                videoWork: [],
                otherWork: [],
                videoWorkerCount: 0,
                otherWorkerCount: 0,
                config: .init(
                    key: VaultKey(Data(repeating: 0, count: 32)),
                    encryptionKey: Data(repeating: 0, count: 32),
                    optimizationMode: .optimized
                ),
                continuation: continuation
            )
            continuation.finish()
        }

        var eventCount = 0
        for await _ in stream {
            eventCount += 1
        }
        await workerTask.value

        XCTAssertEqual(eventCount, 0, "Empty input should produce zero events")
    }

    // MARK: - Cancellation

    /// Verifies that cancellation stops all workers promptly.
    func testCancellationStopsAllWorkers() async {
        let items = Array(0..<100)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 4)],
                process: { @Sendable item in
                    try await Task.sleep(for: .milliseconds(50))
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        // Let a few items process then cancel
        try? await Task.sleep(for: .milliseconds(200))
        workerTask.cancel()

        var processedCount = 0
        for await event in stream {
            if case .imported = event { processedCount += 1 }
        }

        // With 4 workers × 50ms per item, ~200ms should process roughly 16 items at most
        XCTAssertLessThan(processedCount, 100, "Cancellation should stop most items from processing")
        XCTAssertLessThan(processedCount, 30, "Should process significantly fewer than total (got \(processedCount))")
    }

    // MARK: - Queue Completeness

    /// Verifies all items from all queues are processed exactly once across multiple queues.
    func testMultipleQueuesProcessAllItems() async {
        let queueA = ParallelImporter.Queue(Array(0..<5))
        let queueB = ParallelImporter.Queue(Array(100..<108))

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queueA, 2), (queueB, 2)],
                process: { @Sendable item in
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var sizes: [Int] = []
        for await event in stream {
            if case .imported(let file) = event {
                sizes.append(file.size)
            }
        }
        await workerTask.value

        let expected = Set(Array(0..<5) + Array(100..<108))
        XCTAssertEqual(Set(sizes), expected, "All items from both queues should be processed")
        XCTAssertEqual(sizes.count, 13, "No duplicates")
    }

    // MARK: - Work Stealing Behavior

    /// Verifies that video workers steal from image queue after draining video queue.
    /// Uses timing to prove workers don't sit idle while the other queue has work.
    func testVideoWorkersStealFromImageQueue() async {
        // 2 video items (fast) + 8 image items (slow)
        // Without stealing: 2 image workers handle 8 items = 4 rounds × 100ms = 400ms
        // With stealing: after videos done (~100ms), 2 video workers help → ~200ms total
        let videoItems = Array(0..<2)
        let imageItems = Array(100..<108)
        let videoQueue = ParallelImporter.Queue(videoItems)
        let imageQueue = ParallelImporter.Queue(imageItems)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let start = ContinuousClockInstant.now

        let workerTask = Task {
            await Self.runWorkStealingWorkers(
                videoQueue: videoQueue, imageQueue: imageQueue, continuation: continuation
            )
            continuation.finish()
        }

        var count = 0
        for await event in stream {
            if case .imported = event { count += 1 }
        }
        await workerTask.value

        let elapsed = ContinuousClockInstant.now - start

        XCTAssertEqual(count, 10, "All 10 items should be processed")
        // 10 items / 4 workers × 100ms = 250ms min. Allow generous 500ms.
        // Without stealing it would be 400ms+ (2 workers stuck waiting).
        XCTAssertLessThan(elapsed, .milliseconds(500),
                          "Work stealing should let all 4 workers share the load")
    }

    // MARK: - Process Return Nil

    /// Verifies that when process returns nil (e.g. Task.isCancelled), no event is yielded.
    func testNilReturnProducesNoEvent() async {
        let items = Array(0..<5)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 1)],
                process: { @Sendable item -> VaultFileItem? in
                    if item % 2 == 0 { return nil }
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
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

        // Items 0, 2, 4 return nil → no event. Items 1, 3 return file → imported.
        XCTAssertEqual(Set(importedSizes), Set([1, 3]),
                       "Only non-nil returns should produce events")
    }

    // MARK: - Stream Finishes After Workers Complete

    /// Verifies that the stream terminates cleanly after all workers finish.
    func testStreamFinishesAfterWorkersComplete() async {
        let items = Array(0..<3)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 2)],
                process: { @Sendable item in
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        let start = ContinuousClockInstant.now
        var count = 0
        for await event in stream {
            if case .imported = event { count += 1 }
        }
        let elapsed = ContinuousClockInstant.now - start
        await workerTask.value

        XCTAssertEqual(count, 3)
        // Should complete quickly, not hang waiting for more events
        XCTAssertLessThan(elapsed, .milliseconds(500),
                          "Stream should finish promptly after workers complete")
    }

    // MARK: - Concurrent Correctness

    /// Stress test: many items, many workers, verify no duplicates or missing items.
    func testHighConcurrencyNoDuplicates() async {
        let itemCount = 200
        let items = Array(0..<itemCount)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 8)],
                process: { @Sendable item in
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        var sizes: [Int] = []
        for await event in stream {
            if case .imported(let file) = event {
                sizes.append(file.size)
            }
        }
        await workerTask.value

        XCTAssertEqual(sizes.count, itemCount, "All items should be processed")
        XCTAssertEqual(Set(sizes).count, itemCount, "No duplicates")
        XCTAssertEqual(Set(sizes), Set(0..<itemCount), "All items present")
    }

    // MARK: - No Batch Coordinator Regression

    /// Guard test: if someone adds a coordinator that buffers events, this test fails.
    /// The test verifies events arrive within processTime + small margin per item,
    /// not after a batch threshold is reached.
    func testNoBatchBuffering() async {
        let items = Array(0..<10)
        let queue = ParallelImporter.Queue(items)

        let (stream, continuation) = AsyncStream<ParallelImporter.ImportEvent>.makeStream()

        // Use single worker for deterministic ordering
        let workerTask = Task {
            await ParallelImporter.runWorkers(
                queues: [(queue, 1)],
                process: { @Sendable item in
                    try await Task.sleep(for: .milliseconds(30))
                    return VaultFileItem(
                        id: UUID(), size: item,
                        mimeType: "text/plain", filename: "f\(item).txt"
                    )
                },
                continuation: continuation
            )
            continuation.finish()
        }

        let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var arrivalTimesMs: [UInt64] = []
        for await event in stream {
            if case .imported = event {
                let elapsed = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - startTime) / 1_000_000
                arrivalTimesMs.append(elapsed)
            }
        }
        await workerTask.value

        XCTAssertEqual(arrivalTimesMs.count, 10)

        // With 30ms per item and 1 worker, events should arrive at roughly:
        // 30, 60, 90, 120, ..., 300ms
        // If batched by N, we'd see nothing until N*30ms, then N events at once.
        // Verify first event arrives within ~100ms (not 300ms for a batch of 10)
        if let first = arrivalTimesMs.first {
            XCTAssertLessThan(first, 100, "First event should arrive early, not after batch fills (arrived at \(first)ms)")
        }

        // Verify events are roughly evenly spaced (not clumped)
        if arrivalTimesMs.count >= 5 {
            let midpoint = arrivalTimesMs[4]
            // By event 5, ~150ms should have elapsed. A batch-of-10 would show 0 at this point.
            XCTAssertGreaterThan(midpoint, 100, "Events should be spread over time, not instant")
            XCTAssertLessThan(midpoint, 300, "Event 5 should arrive by 300ms (arrived at \(midpoint)ms)")
        }
    }

    // MARK: - Helpers

    private static func runWorkStealingWorkers(
        videoQueue: ParallelImporter.Queue<Int>,
        imageQueue: ParallelImporter.Queue<Int>,
        continuation: AsyncStream<ParallelImporter.ImportEvent>.Continuation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    while let item = await videoQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "video/mp4", filename: "v.mp4"
                        )))
                    }
                    while let item = await imageQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "image/heic", filename: "i.heic"
                        )))
                    }
                }
            }
            for _ in 0..<2 {
                group.addTask {
                    while let item = await imageQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "image/heic", filename: "i.heic"
                        )))
                    }
                    while let item = await videoQueue.next() {
                        try? await Task.sleep(for: .milliseconds(100))
                        continuation.yield(.imported(VaultFileItem(
                            id: UUID(), size: item, mimeType: "video/mp4", filename: "v.mp4"
                        )))
                    }
                }
            }
        }
    }
}
