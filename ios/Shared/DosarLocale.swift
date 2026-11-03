import Foundation

extension Locale {
    /// The one locale the app and its widgets write numbers, dates and money in, whatever
    /// the phone's region or number format, so what the app writes `RomanianNumber` reads
    /// back the same. Injected once at the app's root as the environment's locale.
    public static let dosarDefault = Locale(identifier: "ro_RO")
}
