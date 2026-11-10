import Combine
import SwiftUI

extension View {
    /// Writes and counts everything under this view the app's way: `Locale.dosarDefault`
    /// and `Calendar.dosar`, whatever the phone's region and calendar, so a date picker shows
    /// Gregorian days and a screen that reads `\.calendar` counts the days `CalendarDay` does.
    /// Set once at each root the app draws (the app's window, the lock's window); the
    /// calendar is made again when the phone's time zone changes.
    public func dosarLocaleAndCalendar() -> some View {
        modifier(DosarLocaleAndCalendar())
    }
}

private struct DosarLocaleAndCalendar: ViewModifier {
    @State private var calendar = Calendar.dosar
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.locale, .dosarDefault)
            .environment(\.calendar, calendar)
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: DispatchQueue.main)) { _ in
                follow()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { follow() }
            }
    }

    /// The calendar again, in the time zone the phone is in now.
    private func follow() {
        let fresh = Calendar.dosar
        if fresh != calendar { calendar = fresh }
    }
}
