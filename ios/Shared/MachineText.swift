import Foundation

/// Text written for machines, not people: ISO days, moments, hex digests and the JSON the
/// app, its widgets and its share extension keep and hand each other. ASCII digits,
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

    // MARK: JSON

    /// How machine JSON is laid out. Every layout sorts its keys, so the same value always
    /// gives the same bytes.
    public enum JSONLayout: Sendable {
        /// One line: what the app, its widgets and its share extension keep and hand each
        /// other (the widget snapshot, the share inbox, a widget's completions, outside
        /// failures).
        case compact
        /// Indented, slashes left as they are: a `.dosar` archive, which people may open.
        case readable
    }

    /// The one JSON encoder for machine text: moments as ISO 8601 in UTC, to the second
    /// (`2026-11-02T08:00:00Z`), keys sorted.
    public static func jsonEncoder(_ layout: JSONLayout = .compact) -> JSONEncoder {
        let encoder = JSONEncoder()
        switch layout {
        case .compact: encoder.outputFormatting = [.sortedKeys]
        case .readable: encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The one JSON decoder for machine text. Reads every moment `jsonEncoder` writes and
    /// what earlier versions and other writers wrote: with or without fractional seconds,
    /// with any UTC offset, or a day alone (its start in UTC).
    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = moment(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp: \(raw)")
        }
        return decoder
    }

    /// A moment written as ISO 8601, as `jsonDecoder` reads it; nil when it isn't one.
    public static func moment(_ raw: String) -> Date? {
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if raw.count == 10, let day = CalendarDay(isoString: raw) {
            return day.startDate(in: CalendarDay.isoCalendar)
        }
        return nil
    }
}
