import UIKit
#if !targetEnvironment(macCatalyst)
import BackgroundTasks
#endif

/// UIKit covers short transfers on all supported iPads. On iPadOS 26 and later,
/// large user-started rating scans additionally request continued processing.
@MainActor
final class ReadBackgroundRuntime {
    static let shared = ReadBackgroundRuntime()
    private var grantID: UUID?
    private var expiration: (@MainActor @Sendable () -> Void)?
    private var shortTask = UIBackgroundTaskIdentifier.invalid
    private var scanID: UUID?
    private var completed = 0
    private var total = 0
    private var finishLongTask: ((Bool) -> Void)?
    private var updateLongTask: ((Int, Int) -> Void)?
    private var cancelRequest: (() -> Void)?

    private init() {}

    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)? {
        let id = UUID()
        grantID = id
        self.expiration = expiration
        shortTask = UIApplication.shared.beginBackgroundTask(withName: "Bilder und Bewertungen laden") { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.grantID == id else { return }
                self.endShortTask()
                if self.finishLongTask == nil { self.expiration?() }
            }
        }
        guard shortTask != .invalid || finishLongTask != nil else {
            self.expiration = nil
            grantID = nil
            return nil
        }
        return { [weak self] in
            guard let self, self.grantID == id else { return }
            self.endShortTask()
            self.grantID = nil
            self.expiration = nil
        }
    }

    /// Returns callbacks tied to this exact scan, so a cancelled scan cannot
    /// finish or overwrite progress belonging to its replacement.
    func beginRatingScan(total: Int) -> (update: (Int) -> Void, finish: (Bool) -> Void) {
        finishScan(success: false)
        let id = UUID()
        scanID = id
        self.total = total
        completed = 0
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), total >= 100, UIApplication.shared.applicationState == .active {
            submitScan(id: id)
        }
        #endif
        return ({ [weak self] count in
            guard let self, self.scanID == id else { return }
            self.completed = count
            self.updateLongTask?(count, total)
        }, { [weak self] success in
            guard let self, self.scanID == id else { return }
            self.finishScan(success: success)
        })
    }

    private func finishScan(success: Bool) {
        scanID = nil
        cancelRequest?(); cancelRequest = nil
        let finish = finishLongTask
        finishLongTask = nil
        updateLongTask = nil
        finish?(success)
        if finish != nil, shortTask == .invalid, UIApplication.shared.applicationState == .background {
            expiration?()
        }
    }

    private func endShortTask() {
        guard shortTask != .invalid else { return }
        let identifier = shortTask
        shortTask = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    #if !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private func submitScan(id: UUID) {
        let identifier = "\(Bundle.main.bundleIdentifier!).rating-scan.\(id.uuidString)"
        // The plist permits the wildcard; registration and submission use the
        // same fully composed, unique identifier for this particular scan.
        guard BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main, launchHandler: { [weak self] task in
            MainActor.assumeIsolated { self?.accept(task) }
        }) else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
            title: "Bildbewertungen laden", subtitle: "0 / \(total) Bewertungen geprüft")
        // Never schedule stale filtering work for an unspecified later time.
        request.strategy = .fail
        cancelRequest = { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        Task {
            guard scanID == id else { return }
            do {
                if #available(iOS 27.0, *) { try await BGTaskScheduler.shared.submitTaskRequest(request) }
                else { try BGTaskScheduler.shared.submit(request) }
                if scanID != id { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
            } catch {
                // The UIKit grant remains available when continued processing is denied.
                if scanID == id { cancelRequest = nil }
            }
        }
    }

    @available(iOS 26.0, *)
    private func accept(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask,
              let scanID, task.identifier.hasSuffix(scanID.uuidString) else {
            task.setTaskCompleted(success: false)
            return
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.scanID == scanID else { return }
                // A system cancellation pauses this scan; it must not be
                // silently submitted again or turn pending reads into failures.
                let expire = self.expiration
                self.finishScan(success: false)
                expire?()
            }
        }
        updateLongTask = { count, total in
            task.progress.totalUnitCount = Int64(total)
            task.progress.completedUnitCount = Int64(count)
            task.updateTitle("Bildbewertungen laden", subtitle: "\(count) / \(total) Bewertungen geprüft")
        }
        finishLongTask = { success in task.setTaskCompleted(success: success) }
        updateLongTask?(completed, total)
        ReadExecutionCoordinator.shared.executionBecameAvailable()
    }
    #endif
}
