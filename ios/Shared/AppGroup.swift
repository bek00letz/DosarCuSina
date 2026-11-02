import Foundation

/// The App Group the app, its widgets and its share extension use to hand
/// things to each other. Only small files live here: the widget snapshot,
/// items waiting in the share inbox and completions tapped on a widget.
/// The household database stays in the app's own container.
///
/// This file is compiled into every target, so it uses Foundation only.
public enum AppGroup {
    public static let identifier = "group.com.ar.dosarcusina.shared"

    /// The shared container, or nil when the entitlement is missing (unsigned builds).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Posted as a Darwin notification (it crosses processes) when the share
    /// extension puts something in the inbox, so an open app picks it up at once.
    public static let inboxDidChangeNotification = "com.ar.dosarcusina.inboxDidChange"

    /// Tells the other processes of the app that the inbox changed.
    public static func postInboxDidChange() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(inboxDidChangeNotification as CFString), nil, nil, true)
    }
}
