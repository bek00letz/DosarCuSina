import Foundation
import Observation
import SwiftUI

/// Finds the words of a text that match a query the way `SearchIndex` matches:
/// each query word as the start of a word, ignoring case and diacritics, so
/// "polita" highlights "Poliță".
enum SearchHighlighter {
    /// Ranges in `text` to highlight for `query`.
    static func ranges(in text: String, query: String) -> [Range<String.Index>] {
        let tokens = SearchText.tokens(query)
        guard !tokens.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                index = text.index(after: index)
            }
            let word = String(text[start..<index])
            let normalized = SearchText.normalize(word)
            if let token = tokens.filter({ normalized.hasPrefix($0) }).max(by: { $0.count < $1.count }) {
                // Highlight as many characters as the token covers in the original word.
                let end = prefixEnd(of: word, matching: token.count, in: text, from: start)
                result.append(start..<end)
            }
        }
        return result
    }

    /// The index after the first `count` letters or digits of the word at `start`.
    private static func prefixEnd(of word: String, matching count: Int, in text: String, from start: String.Index) -> String.Index {
        var end = start
        var taken = 0
        while end < text.endIndex, taken < count, text[end].isLetter || text[end].isNumber {
            taken += 1
            end = text.index(after: end)
        }
        return end
    }

    /// `text` with the matching words in bold and the accent color.
    static func attributed(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges(in: text, query: query) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            attributed[lower..<upper].foregroundColor = DS.Palette.accent
        }
        return attributed
    }
}

/// The last few searches, kept on this device only, newest first. They remember only
/// what search may keep: a search that found anything in a locked section, or holds
/// a CNP-shaped number, a card number or a sealed value, is never kept, and one an
/// earlier version kept is let go when the list is read (`SearchPrivacy.mayRemember`).
@MainActor
@Observable
final class RecentSearches {
    static let shared = RecentSearches()
    nonisolated static let limit = 8
    private static let key = "search.recent"

    private(set) var items: [String]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        items = stored.filter { SearchPrivacy.mayRemember($0) }
        if items != stored { defaults.set(items, forKey: Self.key) }
    }

    /// Remembers a query, moving it to the top if it was there already, unless
    /// what it found must not be remembered.
    func add(_ query: String, results: [SearchResult]) {
        guard SearchPrivacy.mayRemember(query, results: results) else { return }
        items = Self.adding(query, to: items)
        defaults.set(items, forKey: Self.key)
    }

    func remove(_ query: String) {
        items.removeAll { $0 == query }
        defaults.set(items, forKey: Self.key)
    }

    func clear() {
        items = []
        defaults.removeObject(forKey: Self.key)
    }

    /// Pure: the list after adding `query`. Same query in another case or without
    /// diacritics counts as the same search.
    nonisolated static func adding(_ query: String, to items: [String], limit: Int = RecentSearches.limit) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let key = SearchText.normalize(trimmed)
        return Array(([trimmed] + items.filter { SearchText.normalize($0) != key }).prefix(limit))
    }
}

extension SearchResultKind {
    /// Group headings for results, in the order they are shown.
    static let displayOrder: [SearchResultKind] = [.asset, .obligation, .document, .historyEntry, .component, .provider]

    var groupTitle: String {
        switch self {
        case .asset: String(localized: "Secțiuni", comment: "Search group: assets.")
        case .obligation: String(localized: "Termene", comment: "Search group: obligations.")
        case .document: String(localized: "Documente", comment: "Search group: documents.")
        case .historyEntry: String(localized: "Istoric", comment: "Search group: history entries.")
        case .component: String(localized: "Piese și lucrări", comment: "Search group: components.")
        case .provider: String(localized: "Oameni", comment: "Search group: providers.")
        }
    }

    var systemImage: String {
        switch self {
        case .asset: "square.grid.2x2"
        case .obligation: "clock"
        case .document: "doc.text"
        case .historyEntry: "wrench.and.screwdriver"
        case .component: "gearshape.2"
        case .provider: "person"
        }
    }
}

/// Search results grouped by kind, in display order.
struct SearchGroup: Identifiable {
    var kind: SearchResultKind
    var results: [SearchResult]
    var id: SearchResultKind { kind }
}

enum SearchGroups {
    static func make(_ results: [SearchResult]) -> [SearchGroup] {
        SearchResultKind.displayOrder.compactMap { kind in
            let matching = results.filter { $0.document.kind == kind }
            return matching.isEmpty ? nil : SearchGroup(kind: kind, results: matching)
        }
    }
}
