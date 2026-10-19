import XCTest
@testable import RatingCore

@MainActor
final class ReadExecutionCoordinatorTests: XCTestCase {
    func testScanKeepsCompletedResultsAndResumesOnlyInterruptedReads() async throws {
        let runtime = ExecutionFixture()
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        let release = coordinator.beginActivity()
        defer { release() }
        let source = BackgroundReadFixture()
        let entries = (0..<8).map {
            RemoteEntry(path: "/\($0).jpg", name: "\($0).jpg", isDirectory: false, size: 1)
        }
        let scan = Task {
            try await RatingScanner.scan(entries, read: { entry in
                try await coordinator.read { try await source.read(entry.path) }
            }, update: { path, _, _ in await source.record(path) })
        }
        defer { scan.cancel() }
        try await eventually {
            let delivered = await source.delivered
            let active = await source.active
            return delivered.contains("/0.jpg") && active >= 3
        }
        coordinator.setActive(false)
        // Moving to the background alone must leave the granted reads running.
        XCTAssertEqual(runtime.ends, 0)
        runtime.expirations[0]()
        try await eventually { await source.active == 0 }
        let attemptsAtPause = await source.attempts
        try await Task.sleep(nanoseconds: 20_000_000)
        let attemptsAfterWaiting = await source.attempts
        XCTAssertEqual(attemptsAtPause, attemptsAfterWaiting, "No new reads after execution expires")
        let completedBeforeResume = await source.delivered
        XCTAssertEqual(completedBeforeResume, ["/0.jpg"])
        XCTAssertEqual(runtime.ends, 1)
        await source.allowCompletion()
        coordinator.setActive(true)
        let result = try await scan.value
        XCTAssertEqual(result.ratings.count, 8)
        XCTAssertTrue(result.failedPaths.isEmpty, "A suspension is not a failed rating")
        let attempts = await source.attempts
        XCTAssertEqual(attempts["/0.jpg"], 1, "Already delivered results remain in the current scan")
        XCTAssertTrue(attempts.values.contains(2), "Interrupted reads are retried")
        let maximum = await source.maximumActive
        XCTAssertLessThanOrEqual(maximum, 3)
        release()
        XCTAssertEqual(runtime.begins, 2)
        XCTAssertEqual(runtime.ends, 2)
    }

    func testCancellationWhilePausedDoesNotWaitForForegroundOrReadAgain() async throws {
        let runtime = ExecutionFixture()
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        let release = coordinator.beginActivity()
        defer { release() }
        coordinator.setActive(false)
        runtime.expirations[0]()
        let source = BackgroundReadFixture()
        let task = Task { try await coordinator.read { try await source.read("/0.jpg") } }
        await Task.yield()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        let attempts = await source.attempts
        XCTAssertTrue(attempts.isEmpty)
        coordinator.setActive(true)
        let stillEmpty = await source.attempts.isEmpty
        XCTAssertTrue(stillEmpty)
    }

    func testDeniedBackgroundGrantWaitsUntilForeground() async throws {
        let runtime = ExecutionFixture()
        runtime.grantsAllowed = false
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        coordinator.setActive(false)
        let source = BackgroundReadFixture()
        let task = Task { try await coordinator.read { try await source.read("/0.jpg") } }
        defer { task.cancel() }
        try await eventually { runtime.begins == 1 }
        let attempts = await source.attempts
        XCTAssertTrue(attempts.isEmpty)
        coordinator.setActive(true)
        let result = try await task.value
        XCTAssertEqual(result, 5)
        XCTAssertEqual(runtime.ends, 0)
    }

    func testCancellingAnActiveReadReleasesItsGrantWithoutRetry() async throws {
        let runtime = ExecutionFixture()
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        let source = BackgroundReadFixture()
        let task = Task { try await coordinator.read { try await source.read("/waiting.jpg") } }
        defer { task.cancel() }
        try await eventually { await source.active == 1 }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        let attempts = await source.attempts
        XCTAssertEqual(attempts["/waiting.jpg"], 1)
        XCTAssertEqual(runtime.ends, 1)
    }

    func testReadFailureIsNotRetriedAndGrantIsReleased() async throws {
        let runtime = ExecutionFixture()
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        do {
            let _: Int = try await coordinator.read { throw POSIXError(.EACCES) }
            XCTFail("Expected a read error")
        } catch let error as POSIXError { XCTAssertEqual(error.code, .EACCES) }
        XCTAssertEqual(runtime.begins, 1)
        XCTAssertEqual(runtime.ends, 1)
    }

    func testOneGrantCoversReadGapsAndOldExpirationCannotInterruptNextActivity() async throws {
        let runtime = ExecutionFixture()
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        let first = coordinator.beginActivity()
        _ = try await coordinator.read { 1 }
        _ = try await coordinator.read { 2 }
        XCTAssertEqual(runtime.begins, 1)
        XCTAssertEqual(runtime.ends, 0)
        first()
        let second = coordinator.beginActivity()
        coordinator.setActive(false)
        runtime.expirations[0]()
        let result = try await coordinator.read { 3 }
        XCTAssertEqual(result, 3)
        XCTAssertEqual(runtime.ends, 1)
        second()
        XCTAssertEqual(runtime.ends, 2)
    }

    func testLateContinuedProcessingGrantResumesInBackground() async throws {
        let runtime = ExecutionFixture()
        let coordinator = ReadExecutionCoordinator(beginExecution: runtime.begin)
        let release = coordinator.beginActivity()
        defer { release() }
        coordinator.setActive(false)
        runtime.expirations[0]()
        let source = BackgroundReadFixture()
        let task = Task { try await coordinator.read { try await source.read("/0.jpg") } }
        defer { task.cancel() }
        await Task.yield()
        let attempts = await source.attempts
        XCTAssertTrue(attempts.isEmpty)
        coordinator.executionBecameAvailable()
        let result = try await task.value
        XCTAssertEqual(result, 5)
        XCTAssertEqual(runtime.begins, 2)
    }

    private func eventually(_ predicate: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for the read lifecycle")
        throw CancellationError()
    }
}

@MainActor
private final class ExecutionFixture {
    var begins = 0
    var ends = 0
    var grantsAllowed = true
    var expirations: [@MainActor @Sendable () -> Void] = []
    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)? {
        begins += 1
        guard grantsAllowed else { return nil }
        expirations.append(expiration)
        return { self.ends += 1 }
    }
}

private actor BackgroundReadFixture {
    var attempts: [String: Int] = [:]
    var delivered: [String] = []
    var active = 0
    var maximumActive = 0
    private var canComplete = false
    func read(_ path: String) async throws -> Int {
        attempts[path, default: 0] += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if path == "/0.jpg" { return 5 }
        while !canComplete { try await Task.sleep(nanoseconds: 2_000_000) }
        return 4
    }
    func record(_ path: String) { delivered.append(path) }
    func allowCompletion() { canComplete = true }
}
