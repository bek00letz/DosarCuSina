import BackgroundTasks
import Foundation
import SwiftData

/// Wakes the app now and then, when iOS allows it, to apply widget taps waiting
/// in the App Group, plan the next reminders and rewrite the widget snapshot, so
/// a household with more reminders than iOS keeps (64) stays covered even when
/// the app isn't opened for weeks. It works on this phone only: no network.
///
/// iOS decides when it runs, so the planner's "open the app" reminder stays the
/// safety net.
@MainActor
enum BackgroundRefresh {
    static let identifier = "com.ar.dosarcusina.app.refresh-reminders"
    /// The earliest we ask to run again; iOS usually waits longer.
    static let interval: TimeInterval = 12 * 60 * 60

    /// Registers the handler. Must run before the app finishes launching.
    static func register(containerProvider: @escaping @MainActor () -> ModelContainer? = { PersistenceController.shared.container }) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                run(task, containerProvider: containerProvider)
            }
        }
    }

    /// Asks for the next run. Called whenever the app has planned reminders.
    static func schedule(after now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background App Refresh is off for the app, or not available here
            // (the Simulator). The "open the app" reminder still covers it.
        }
    }

    private static func run(_ task: BGTask, containerProvider: @escaping @MainActor () -> ModelContainer?) {
        schedule()
        guard let container = containerProvider() else {
            task.setTaskCompleted(success: false)
            return
        }
        let work = Task { @MainActor in
            IntentEngine.applyQueuedWidgetCompletions(in: container.mainContext)
            await SideEffectsCoordinator.shared(for: container).reconcileNow(allowPermissionPrompt: false)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
