import Foundation

/// What is said about Settings' „Notificări” switch (`AppPreferences.notificationsOn`): under it
/// in Settings, and where reminders are set up while it is off (`ReminderPermissionNotice`).
enum NotificationSwitchWording {
    /// Under the switch: what it does now.
    static func footnote(isOn: Bool) -> String {
        isOn
            ? String(localized: "Pe acest telefon îți amintesc la timp de termene.", comment: "Under Settings' „Notificări” switch, on.")
            : String(localized: "Oprite pe acest telefon. Termenele rămân în Urmează.", comment: "Under Settings' „Notificări” switch, off: no reminders, no badge, no notices.")
    }

    /// Where reminders are set up, while the switch is off.
    static var offTitle: String {
        String(localized: "Notificările sunt oprite", comment: "Notice where reminders are set up: notifications are off, on the phone or in the app's Settings.")
    }

    static var offMessage: String {
        String(localized: "Le-ai oprit din Setări, pe acest telefon. Termenele rămân oricum aici, în Urmează.",
               comment: "Notice where reminders are set up while the app's „Notificări” switch is off.")
    }

    /// Its button: turns the switch back on, right there.
    static var turnOn: String {
        String(localized: "Pornește-le", comment: "Button on the notice: turns the app's „Notificări” switch back on.")
    }
}
