import Foundation

/// Text written for machines, not people: ISO days and hex digests. ASCII digits,
/// zero-padded, never localized, so stored values, archives and fingerprints read the
/// same on every phone. The one place such text is written; what people read goes
/// through `DosarFormat`, `Money` and `RomanianNumber` instead.
public enum MachineText {
    /// `padded(7, to: 2)` is "07"; a longer number is kept whole.
    public static func padded(_ number: Int, to width: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    /// An ISO 8601 calendar date: `2031-03-12`.
    public static func isoDay(year: Int, month: Int, day: Int) -> String {
        "\(padded(year, to: 4))-\(isoMonthDay(month: month, day: day))"
    }

    /// A month and day as ISO writes them inside a date: `03-12`.
    public static func isoMonthDay(month: Int, day: Int) -> String {
        "\(padded(month, to: 2))-\(padded(day, to: 2))"
    }

    /// Bytes as lowercase hex, two digits each: a digest's fingerprint.
    public static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        var text = ""
        for byte in bytes {
            text.append(hexDigits[Int(byte >> 4)])
            text.append(hexDigits[Int(byte & 0x0F)])
        }
        return text
    }

    private static let hexDigits = Array("0123456789abcdef")
}
