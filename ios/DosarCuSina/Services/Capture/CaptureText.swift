import Foundation

/// Recognized text prepared for pattern matching.
///
/// Every line is kept twice: as read (for showing the source to the user) and
/// folded (lowercased, diacritics removed, cedillas and commas unified), so
/// "Poliță", "POLITA" and "polița" all match `polita`.
///
/// Text that came from recognition also keeps where each line sits on its page,
/// so labels can be matched to the values in their column. Pasted text and a
/// PDF's text layer have no positions, and every reader falls back to line order.
public struct CaptureText: Sendable {
    public let original: [String]
    public let folded: [String]
    /// Where each line sits on its page; nil when the text has no positions.
    public let boxes: [TextBox?]
    /// The page each line is on, from 0.
    public let pages: [Int]

    public init(_ text: String) {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
        self.init(pages: [lines.map { RecognizedLine($0) }])
    }

    /// Recognized pages, each in reading order.
    public init(pages: [[RecognizedLine]]) {
        var original: [String] = [], boxes: [TextBox?] = [], numbers: [Int] = []
        for (number, page) in pages.enumerated() {
            for line in page {
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                original.append(trimmed)
                boxes.append(line.box)
                numbers.append(number)
            }
        }
        self.original = original
        self.folded = original.map(Self.fold)
        self.boxes = boxes
        self.pages = numbers
    }

    /// Whether any line knows where it sits on its page.
    public var hasPositions: Bool { boxes.contains { $0 != nil } }

    /// The same text with each row's fragments joined left to right, for readers that
    /// work line by line ("Plăcuțe frână față" and "320,00" on one row are one line).
    /// Expects lines in reading order; text without positions is returned as is.
    func joiningRows() -> CaptureText {
        guard hasPositions else { return self }
        var pagesOut: [[RecognizedLine]] = []
        var current: RecognizedLine?
        var anchor: TextBox?
        var page = -1
        func flush() {
            if let line = current { pagesOut[pagesOut.count - 1].append(line) }
            current = nil
            anchor = nil
        }
        for index in original.indices {
            if pages[index] != page {
                flush()
                while pagesOut.count <= pages[index] { pagesOut.append([]) }
                page = pages[index]
            }
            let line = RecognizedLine(original[index], box: boxes[index])
            if let box = line.box, let rowAnchor = anchor, let joined = current, rowAnchor.isOnSameRow(as: box) {
                current = RecognizedLine(joined.text + " " + line.text, box: joined.box.map { $0.union(box) } ?? box)
            } else {
                flush()
                current = line
                anchor = line.box
            }
        }
        flush()
        return CaptureText(pages: pagesOut)
    }

    /// Lowercases, strips diacritics (ș/ş → s, ț/ţ → t, ă/â → a, î → i) and unifies spaces.
    public static func fold(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ro_RO"))
            .lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    public var joinedFolded: String { folded.joined(separator: "\n") }
    public var joinedOriginal: String { original.joined(separator: "\n") }

    /// Indexes of lines whose folded text contains any of the labels.
    func lines(containing labels: [String]) -> [Int] {
        folded.indices.filter { index in labels.contains { folded[index].contains($0) } }
    }

    /// True when any label appears anywhere.
    func contains(any labels: [String]) -> Bool {
        labels.contains { joinedFolded.contains($0) }
    }
}

// MARK: - Regular expressions

/// Small wrapper over `NSRegularExpression` that returns capture groups as strings.
enum TextPattern {
    struct Match {
        let groups: [String?]
        let range: Range<String.Index>
        subscript(_ index: Int) -> String? { index < groups.count ? groups[index] : nil }
    }

    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [Match] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            assertionFailure("Invalid pattern: \(pattern)")
            return []
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { result in
            guard let whole = Range(result.range, in: text) else { return nil }
            let groups = (0..<result.numberOfRanges).map { index -> String? in
                guard let range = Range(result.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
            return Match(groups: groups, range: whole)
        }
    }

    static func first(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> Match? {
        matches(pattern, in: text, caseInsensitive: caseInsensitive).first
    }
}
