import Foundation

/// Extends active reads into the background, then waits for the foreground if
/// the system withdraws execution time. Only idempotent reads belong here.
@MainActor
final class ReadExecutionCoordinator {
    typealias BeginExecution = (@escaping @MainActor @Sendable () -> Void) -> (() -> Void)?

    private let beginExecution: BeginExecution
    private var endExecution: (() -> Void)?
    private var executionID: UUID?
    private var active = true
    private var exhausted = false
    private var operations: [UUID: () -> Void] = [:]
    private var activities = Set<UUID>()
    private var interrupted = Set<UUID>()
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(beginExecution: @escaping BeginExecution) {
        self.beginExecution = beginExecution
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active {
            executionBecameAvailable()
        } else if endExecution == nil, !operations.isEmpty || !activities.isEmpty {
            interruptReads()
        }
    }

    func executionBecameAvailable() {
        exhausted = false
        let continuations = Array(waiting.values)
        waiting.removeAll()
        for continuation in continuations { continuation.resume() }
        if !operations.isEmpty || !activities.isEmpty { extendExecution() }
    }

    /// Keep one system grant across the gaps between individual reads in a scan.
    /// The caller must release the returned activity with defer.
    func beginActivity() -> () -> Void {
        let id = UUID()
        activities.insert(id)
        extendExecution()
        return { [weak self] in
            guard let self else { return }
            self.activities.remove(id)
            self.finishIfIdle()
        }
    }

    func read<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        while true {
            try await waitForExecution()
            try Task.checkCancellation()
            let id = UUID()
            let task = Task {
                try Task.checkCancellation()
                let value = try await operation()
                try Task.checkCancellation()
                return value
            }
            operations[id] = { task.cancel() }
            extendExecution()
            let result = await withTaskCancellationHandler {
                await task.result
            } onCancel: {
                task.cancel()
            }
            let retry = interrupted.remove(id) != nil
            operations.removeValue(forKey: id)
            finishIfIdle()
            try Task.checkCancellation()
            if retry { continue }
            return try result.get()
        }
    }

    private func waitForExecution() async throws {
        try Task.checkCancellation()
        guard !active && exhausted else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting[id] = continuation }
            }
        } onCancel: {
            Task { @MainActor in
                self.waiting.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    private func extendExecution() {
        guard executionID == nil, !exhausted else { return }
        let id = UUID()
        executionID = id
        let finish = beginExecution { [weak self] in
            guard let self, self.executionID == id else { return }
            self.interruptReads()
        }
        // Also handle a provider which expires synchronously during begin.
        guard executionID == id else { finish?(); return }
        endExecution = finish
        if finish == nil {
            executionID = nil
            if !active { interruptReads() }
        }
    }

    private func interruptReads() {
        exhausted = true
        interrupted.formUnion(operations.keys)
        for cancel in operations.values { cancel() }
        finishExecution()
    }

    private func finishExecution() {
        executionID = nil
        let finish = endExecution
        endExecution = nil
        finish?()
    }

    private func finishIfIdle() {
        if operations.isEmpty && activities.isEmpty { finishExecution() }
    }
}
