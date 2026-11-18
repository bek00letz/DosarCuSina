// path: ios/DosarCuSina/Services/Reminders/ExampleReminders.swift
// „Ai o scadență mâine” in a comment doesn't count, nor an obligation in English.
enum ExampleReminders {
    static func title() -> String { String(localized: "Ai un termen mâine", comment: "Generic reminder title for an obligation.") }
    static let host = "obligation"
}
