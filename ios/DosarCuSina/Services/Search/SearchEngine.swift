import Foundation

/// What a search result points at.
public enum SearchResultKind: String, Sendable, CaseIterable {
    case asset
    case obligation
    case historyEntry
    case component
    case provider
    case document
}

/// A piece of searchable text and how much a match in it counts.
public struct SearchField: Hashable, Sendable {
    public var text: String
    public var weight: Int

    public init(_ text: String?, weight: Int) {
        self.text = text ?? ""
        self.weight = weight
    }

    public enum Weight {
        public static let title = 10
        /// Identifiers, document numbers, key facts, policy numbers.
        public static let identifier = 8
        public static let label = 6
        public static let value = 4
        public static let note = 3
        /// Text read from scanned documents.
        public static let extracted = 1
    }
}

/// One thing that can be found.
public struct SearchDocument: Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: SearchResultKind
    public var title: String
    public var subtitle: String?
    public var route: AppRoute
    public var fields: [SearchField]
    /// Newer things rank slightly higher among equal matches.
    public var date: Date?
    /// From a category behind Face ID; the screen hides the snippet until unlocked.
    public var isSensitive: Bool

    public init(id: String, kind: SearchResultKind, title: String, subtitle: String?, route: AppRoute, fields: [SearchField], date: Date? = nil, isSensitive: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.route = route
        self.fields = fields
        self.date = date
        self.isSensitive = isSensitive
    }
}

public struct SearchResult: Hashable, Sendable, Identifiable {
    public var document: SearchDocument
    public var score: Int
    /// The text that matched best, for a one-line preview.
    public var snippet: String?

    public var id: String { document.id }
}

/// An in-memory index over the whole binder. Matching ignores case and
/// diacritics ("polita" finds "poliță") and treats each query word as the start
/// of a word, so Romanian endings still match. Every query word must match.
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        var document: SearchDocument
        /// Per field: its normalized words.
        var words: [[Substring]]
    }

    private let entries: [Entry]

    public init(_ documents: [SearchDocument]) {
        entries = documents.map(Self.entry)
    }

    private init(entries: [Entry]) {
        self.entries = entries
    }

    private static func entry(_ document: SearchDocument) -> Entry {
        Entry(document: document, words: document.fields.map { SearchText.normalize($0.text).split(separator: " ") })
    }

    /// The same index with some documents taken out and others put in; only the new
    /// ones are prepared again.
    public func updating(removing ids: Set<String>, adding documents: [SearchDocument]) -> SearchIndex {
        let replaced = ids.union(documents.map(\.id))
        return SearchIndex(entries: entries.filter { !replaced.contains($0.document.id) } + documents.map(Self.entry))
    }

    public var count: Int { entries.count }

    /// Every document in the index.
    public var documents: [SearchDocument] { entries.map(\.document) }

    /// A result's preview line: the field that matched best among those that add something, for
    /// every kind of result alike. A field the row already says, in its title or its subtitle (the
    /// section's name under a deadline, „VW Golf · 3 martie”), is no preview, so nothing reads
    /// twice; when every matching field is already said, there is none.
    private static func snippet(of entry: Entry, points: [Int]) -> String? {
        let shown = [entry.document.title, entry.document.subtitle ?? ""].map { SearchText.normalize($0).split(separator: " ") }
        let candidates = points.indices.filter { points[$0] > 0 }.sorted { points[$0] > points[$1] || (points[$0] == points[$1] && $0 < $1) }
        return candidates.lazy.map { (index: $0, words: entry.words[$0]) }
            .first { field in !field.words.isEmpty && !shown.contains { Self.says($0, field.words) } }
            .map { entry.document.fields[$0.index].text }
    }

    /// Whether `words` appear in `line` one after another, each whole.
    private static func says(_ line: [Substring], _ words: [Substring]) -> Bool {
        guard words.count <= line.count else { return false }
        return (0...(line.count - words.count)).contains { start in Array(line[start..<(start + words.count)]) == words }
    }

    public func search(_ query: String, limit: Int = 50, kinds: Set<SearchResultKind>? = nil) -> [SearchResult] {
        let tokens = SearchText.tokens(query)
        guard !tokens.isEmpty else { return [] }
        var results: [SearchResult] = []
        for entry in entries {
            if let kinds, !kinds.contains(entry.document.kind) { continue }
            var score = 0
            var fieldPoints = [Int](repeating: 0, count: entry.words.count)
            var matchedAll = true
            for token in tokens {
                var best = 0
                for (index, words) in entry.words.enumerated() {
                    let weight = entry.document.fields[index].weight
                    var points = 0
                    for word in words {
                        if word == token { points = max(points, weight * 3); break }
                        if word.hasPrefix(token) { points = max(points, weight * 2) }
                    }
                    fieldPoints[index] = max(fieldPoints[index], points)
                    best = max(best, points)
                }
                if best == 0 { matchedAll = false; break }
                score += best
            }
            guard matchedAll else { continue }
            results.append(SearchResult(document: entry.document, score: score, snippet: Self.snippet(of: entry, points: fieldPoints)))
        }
        return Array(results.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let l = lhs.document.date ?? .distantPast, r = rhs.document.date ?? .distantPast
            if l != r { return l > r }
            return lhs.document.title.localizedStandardCompare(rhs.document.title) == .orderedAscending
        }.prefix(limit))
    }
}
