import Foundation

extension Locale {
    /// The locale used for numbers, dates and money: the user's locale when it
    /// is Romanian, otherwise Romanian formatting so amounts read as on bills.
    public static var dosarDefault: Locale {
        let current = Locale.current
        return current.language.languageCode?.identifier == "ro" ? current : Locale(identifier: "ro_RO")
    }
}
