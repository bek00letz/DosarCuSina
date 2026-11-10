import BackgroundTasks
import Foundation
import UIKit

/// Keeps a long backup step the person started going when they leave the app or lock the phone,
/// with its progress shown by the system and a way to stop it there.
@MainActor
protocol BackupKeeper {
    /// Starts keeping `run` going, under `title` and `subtitle` in the system's progress. The
    /// caller ends the hold once the work is done, whatever its outcome.
    func hold(_ run: BackupRun, title: String, subtitle: String) -> any BackupHold
}

@MainActor
protocol BackupHold: AnyObject {
    /// The work ended: it succeeded, or failed or was stopped.
    func end(success: Bool)
}

/// The system's way, one hold per step:
///
/// - **Continued processing** (`BGContinuedProcessingTaskRequest`, iOS 26): asked for as the step
///   starts, while the app is on screen, under an identifier of its own that the app's Info.plist
///   allows (`identifierPrefix` and anything after it). Once the system starts it, it shows the
///   step's progress (`BackupRun.progress`) and lets the person stop it, which stops the work at its
///   next file (`BackupRun.cancel`). Asked with `.fail`, so a phone that can't start it now says so
///   at once and the step goes on with the fallback.
/// - **A background task** (`UIApplication.beginBackgroundTask`) from the start, until continued
///   processing takes over, and as the fallback where it can't (the Simulator, a busy phone): the
///   step keeps going for the short while iOS gives an app that left the screen; when that runs
///   out before the step ends, the step stops cleanly rather than be frozen half-way.
/// - **The phone locked:** the hold tells the run when protected files go and come back
///   (`BackupRun.protectedData`), so a step that needs them waits and goes on after unlocking.
@MainActor
final class SystemBackupKeeper: BackupKeeper {
    static let shared = SystemBackupKeeper()

    /// The start of every backup step's identifier; Info.plist's `BGTaskSchedulerPermittedIdentifiers`
    /// allows it with `.*` after it.
    static let identifierPrefix = "com.ar.dosarcusina.app.backup."

    func hold(_ run: BackupRun, title: String, subtitle: String) -> any BackupHold {
        SystemBackupHold(run: run, title: title, subtitle: subtitle)
    }
}

@MainActor
private final class SystemBackupHold: BackupHold {
    private let run: BackupRun
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var continued: BGContinuedProcessingTask?
    private var outcome: Bool?
    private var observers: [any NSObjectProtocol] = []

    init(run: BackupRun, title: String, subtitle: String) {
        self.run = run
        run.protectedData(isAvailable: UIApplication.shared.isProtectedDataAvailable)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [run] _ in
                run.protectedData(isAvailable: false)
            },
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [run] _ in
                run.protectedData(isAvailable: true)
            },
        ]
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: title) { [weak self] in
            MainActor.assumeIsolated { self?.backgroundTimeRanOut() }
        }
        askToContinue(title: title, subtitle: subtitle)
    }

    private func askToContinue(title: String, subtitle: String) {
        let identifier = SystemBackupKeeper.identifierPrefix + UUID().uuidString
        // Registered just before it is asked for, once: a continued task may be registered after
        // launch, and each step has an identifier of its own. The handler holds this hold until the
        // system starts the task, so it can end it however the step ended.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { self.adopt(task) }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not on this phone now (the Simulator, Background App Refresh off, a busy phone): the
            // background task already begun keeps the step going as long as iOS allows.
        }
    }

    /// The system started the continued task: it shows the run's progress and can stop it.
    private func adopt(_ task: BGTask) {
        if let outcome {
            task.setTaskCompleted(success: outcome)
            return
        }
        guard let task = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }
        continued = task
        task.progress.totalUnitCount = 1_000
        task.progress.addChild(run.progress, withPendingUnitCount: 1_000)
        task.expirationHandler = { [run] in run.cancel() }
        endBackgroundTask()
    }

    /// iOS is about to freeze the app and no continued task took over: the step stops cleanly.
    private func backgroundTimeRanOut() {
        if continued == nil { run.cancel() }
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func end(success: Bool) {
        guard outcome == nil else { return }
        outcome = success
        continued?.setTaskCompleted(success: success)
        continued = nil
        endBackgroundTask()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}
