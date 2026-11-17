import Foundation

/// What a change to a deadline does, as far as its category's lock is concerned: the one rule
/// every way in reads (Urmează, the deadline's page, the reminder's buttons, the widget's „Gata”,
/// Siri and Shortcuts, through `IntentEngine.perform` and `BiometricVaultManager.confirmClosing`).
///
/// For a category behind Face ID, closing a deadline („Am rezolvat”, „Gata”) asks for Face ID or
/// the passcode first, wherever it starts; snoozing („Amână”) asks nothing, even from the Lock
/// Screen, since it only moves a reminder and shows nothing of the section. A surface that can't
/// ask (a widget, in the background) doesn't close such a deadline: it leaves it for the app.
public enum DeadlineChange: Sendable, Equatable {
    /// „Am rezolvat”, „Gata”: the cycle closes.
    case close
    /// „Amână”: the reminder comes back later; nothing else changes.
    case snooze

    /// Whether this change asks for Face ID or the passcode before it is made, for a deadline
    /// whose category is (`true`) or isn't locked on this device.
    public func asksFaceID(inLockedCategory isLocked: Bool) -> Bool {
        switch self {
        case .close: isLocked
        case .snooze: false
        }
    }
}
