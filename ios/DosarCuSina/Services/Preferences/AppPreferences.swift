import Foundation
import Observation

/// Settings that belong to this device, not to the household data: whether and when to
/// remind, whether the whole app is locked, whether onboarding was seen.
/// Which sections are locked is this device's choice too, kept beside the store
/// (`SectionLocks`, read through `CategoryTemplate.isSensitive`); the two locks are independent.
@MainActor
@Observable
public final class AppPreferences {
    /// The app's own: its switch for notifications is kept where the share extension reads it too.
    public static let shared = AppPreferences(groupDefaults: NotificationSwitch.store)

    /// Posted after any preference changes, so side effects can be recomputed.
    public nonisolated static let didChangeNotification = Notification.Name("DosarCuSina.preferencesDidChange")

    public nonisolated static let defaultReminderMinuteOfDay = 9 * 60

    private enum Key {
        static let reminderMinuteOfDay = "preferences.reminderMinuteOfDay"
        static let appLockEnabled = "preferences.appLockEnabled"
        static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
        static let showsInSpotlight = "preferences.showsInSpotlight"
        static let syncsWithICloud = "preferences.syncsWithICloud"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Where what the app's extensions read too is kept (`NotificationSwitch`).
    @ObservationIgnored private let groupDefaults: UserDefaults

    /// „Notificări”: this device sends its reminders, the app badge and the share's notice. Off
    /// stops them all at once; on brings them back (`SideEffectsCoordinator`, the one that acts
    /// on it). iOS's own permission is apart from it. Default on.
    public var notificationsOn: Bool {
        didSet {
            NotificationSwitch.set(notificationsOn, in: groupDefaults)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// Minutes after midnight for reminders, unless an obligation sets its own. Default 09:00.
    public var reminderMinuteOfDay: Int {
        didSet { store(reminderMinuteOfDay, Key.reminderMinuteOfDay) }
    }

    /// Ask for Face ID (or the passcode) to open the app at all. Default off.
    /// Section locks work the same whether this is on or off. Changed only through `setAppLock`.
    public private(set) var appLockEnabled: Bool {
        didSet { store(appLockEnabled, Key.appLockEnabled) }
    }

    /// Turns the app lock on or off. Turning it off takes the person's Face ID first, every time
    /// (`lowering`, from `BiometricVaultManager.confirmLowering`); without it, it throws
    /// `LockLowering.Needed` and the lock stays on.
    public func setAppLock(_ isOn: Bool, lowering: LockLowering? = nil) throws {
        if !isOn, appLockEnabled, lowering == nil { throw LockLowering.Needed() }
        appLockEnabled = isOn
    }

    public var hasCompletedOnboarding: Bool {
        didSet { store(hasCompletedOnboarding, Key.hasCompletedOnboarding) }
    }

    /// "Arată în căutarea iPhone-ului": sections, deadlines and documents from categories
    /// not behind Face ID appear in Spotlight (`SpotlightIndexer`). Default on; off deletes
    /// the app's whole index.
    public var showsInSpotlight: Bool {
        didSet { store(showsInSpotlight, Key.showsInSpotlight) }
    }

    /// "Sincronizează cu iCloud": the binder goes to the person's own private iCloud and comes
    /// back on their other devices, where the build syncs (`PersistenceController.syncIsBuiltIn`).
    /// Default on; off stops syncing and keeps everything on the phone. Read when the store opens.
    public var syncsWithICloud: Bool {
        didSet { store(syncsWithICloud, Key.syncsWithICloud) }
    }

    /// - Parameter groupDefaults: where the switch for notifications is kept; `defaults` when
    ///   nil (a test's own suite).
    public init(defaults: UserDefaults = .standard, groupDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.groupDefaults = groupDefaults ?? defaults
        self.notificationsOn = NotificationSwitch.isOn(in: groupDefaults ?? defaults)
        let minute = defaults.object(forKey: Key.reminderMinuteOfDay) as? Int
        self.reminderMinuteOfDay = minute.map(ReminderClock.clamped) ?? Self.defaultReminderMinuteOfDay
        self.appLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.showsInSpotlight = defaults.object(forKey: Key.showsInSpotlight) as? Bool ?? true
        self.syncsWithICloud = defaults.object(forKey: Key.syncsWithICloud) as? Bool ?? true
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
