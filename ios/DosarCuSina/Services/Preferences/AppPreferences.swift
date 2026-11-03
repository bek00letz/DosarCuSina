import Foundation
import Observation

/// Settings that belong to this device, not to the household data: when to
/// remind, whether the whole app is locked, whether onboarding was seen.
/// Which sections are locked is household data and lives on `CategoryTemplate.isSensitive`;
/// the two locks are independent.
@MainActor
@Observable
public final class AppPreferences {
    public static let shared = AppPreferences()

    /// Posted after any preference changes, so side effects can be recomputed.
    public nonisolated static let didChangeNotification = Notification.Name("DosarCuSina.preferencesDidChange")

    public nonisolated static let defaultReminderMinuteOfDay = 9 * 60

    private enum Key {
        static let reminderMinuteOfDay = "preferences.reminderMinuteOfDay"
        static let appLockEnabled = "preferences.appLockEnabled"
        static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
        static let showsInSpotlight = "preferences.showsInSpotlight"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Minutes after midnight for reminders, unless an obligation sets its own. Default 09:00.
    public var reminderMinuteOfDay: Int {
        didSet { store(reminderMinuteOfDay, Key.reminderMinuteOfDay) }
    }

    /// Ask for Face ID (or the passcode) to open the app at all. Default off.
    /// Section locks work the same whether this is on or off.
    public var appLockEnabled: Bool {
        didSet { store(appLockEnabled, Key.appLockEnabled) }
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let minute = defaults.object(forKey: Key.reminderMinuteOfDay) as? Int
        self.reminderMinuteOfDay = minute.map { min(max($0, 0), 24 * 60 - 1) } ?? Self.defaultReminderMinuteOfDay
        self.appLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.showsInSpotlight = defaults.object(forKey: Key.showsInSpotlight) as? Bool ?? true
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
