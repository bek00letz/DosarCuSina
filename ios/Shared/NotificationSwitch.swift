import Foundation

/// „Notificări” in Settings: whether this device sends the app's notifications at all, its
/// reminders, the app badge and the share's notice („Am primit 2 acte”). It is this device's
/// choice, like the permission iOS keeps for each device, so it never travels with the binder or
/// a backup. On unless the person turned it off. iOS's own permission stays as it is either way.
///
/// Kept in one place, the App Group's defaults, because the share extension reads it too, for its
/// notice (`InboxNotice.announce`). The app reads and writes it only through
/// `AppPreferences.notificationsOn`, and only `SideEffectsCoordinator` acts on it.
public enum NotificationSwitch {
    static let key = "preferences.notificationsOn"

    /// Where it is kept: the App Group's defaults (this process's own where the group is missing,
    /// an unsigned build).
    public static var store: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    /// Whether this device sends notifications. On when nothing was chosen yet.
    public static func isOn(in defaults: UserDefaults = NotificationSwitch.store) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// Keeps the person's choice.
    public static func set(_ isOn: Bool, in defaults: UserDefaults = NotificationSwitch.store) {
        defaults.set(isOn, forKey: key)
    }
}
