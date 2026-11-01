import Foundation
import Observation

/// Settings that belong to this device, not to the household data: when to
/// remind, whether Face ID is used at all, whether onboarding was seen.
/// Household-wide choices (which categories are sensitive) live on `CategoryTemplate`.
@MainActor
@Observable
public final class AppPreferences {
    public static let shared = AppPreferences()

    /// Posted after any preference changes, so side effects can be recomputed.
    public nonisolated static let didChangeNotification = Notification.Name("DosarCuSina.preferencesDidChange")

    public nonisolated static let defaultReminderMinuteOfDay = 9 * 60

    private enum Key {
        static let reminderMinuteOfDay = "preferences.reminderMinuteOfDay"
        static let biometricLockEnabled = "preferences.biometricLockEnabled"
        static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Minutes after midnight for reminders, unless an obligation sets its own. Default 09:00.
    public var reminderMinuteOfDay: Int {
        didSet { store(reminderMinuteOfDay, Key.reminderMinuteOfDay) }
    }

    /// Master switch for Face ID on sensitive categories. Default on.
    public var biometricLockEnabled: Bool {
        didSet { store(biometricLockEnabled, Key.biometricLockEnabled) }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { store(hasCompletedOnboarding, Key.hasCompletedOnboarding) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let minute = defaults.object(forKey: Key.reminderMinuteOfDay) as? Int
        self.reminderMinuteOfDay = minute.map { min(max($0, 0), 24 * 60 - 1) } ?? Self.defaultReminderMinuteOfDay
        self.biometricLockEnabled = defaults.object(forKey: Key.biometricLockEnabled) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
