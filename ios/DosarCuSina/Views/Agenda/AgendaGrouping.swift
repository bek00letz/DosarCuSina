import Foundation

/// How the Agenda groups people: by what they do, or by what they look after.
enum AgendaGrouping: String, CaseIterable, Hashable, Sendable {
    case trade
    case section

    var title: String {
        switch self {
        case .trade: String(localized: "După meserie", comment: "Agenda grouping option.")
        case .section: String(localized: "După secțiune", comment: "Agenda grouping option.")
        }
    }
}

/// A group of providers under one heading.
struct AgendaGroup: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var providerIDs: [UUID]
}

/// Pure grouping for the Agenda, so the order rules are tested.
enum AgendaGroups {
    struct Person: Hashable, Sendable {
        var id: UUID
        var name: String
        /// `ProviderTrade` raw values or free text.
        var trades: [String]
        /// Names of the sections they look after or worked on.
        var sections: [String]
        var wouldCallAgain: Bool?
        var rating: Double?
    }

    static let otherID = "other"

    static func make(_ people: [Person], by grouping: AgendaGrouping) -> [AgendaGroup] {
        switch grouping {
        case .trade: byTrade(people)
        case .section: bySection(people)
        }
    }

    /// Everyone under each of their trades, known trades in the catalog's order,
    /// then trades typed by hand, then people with no trade under "Altceva".
    static func byTrade(_ people: [Person]) -> [AgendaGroup] {
        var buckets: [String: [Person]] = [:]
        for person in people {
            let trades = person.trades.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != ProviderTrade.other.rawValue }
            if trades.isEmpty {
                buckets[otherID, default: []].append(person)
            }
            for trade in Set(trades) { buckets[trade, default: []].append(person) }
        }
        let known = ProviderTrade.allCases.map(\.rawValue)
        let keys = buckets.keys.sorted { lhs, rhs in
            let l = known.firstIndex(of: lhs), r = known.firstIndex(of: rhs)
            switch (lhs == otherID, rhs == otherID) {
            case (true, _): return false
            case (_, true): return true
            default: break
            }
            switch (l, r) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
        return keys.map { key in
            let title = key == otherID ? ProviderTrade.other.title : (ProviderTrade(rawValue: key)?.title ?? key)
            return AgendaGroup(id: "trade.\(key)", title: title, providerIDs: sorted(buckets[key] ?? []).map(\.id))
        }
    }

    /// Everyone under each section they look after, alphabetically, then people
    /// not tied to any section.
    static func bySection(_ people: [Person]) -> [AgendaGroup] {
        var buckets: [String: [Person]] = [:]
        var loose: [Person] = []
        for person in people {
            let sections = Set(person.sections.filter { !$0.isEmpty })
            if sections.isEmpty { loose.append(person) }
            for section in sections { buckets[section, default: []].append(person) }
        }
        var groups = buckets.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { AgendaGroup(id: "section.\($0)", title: $0, providerIDs: sorted(buckets[$0] ?? []).map(\.id)) }
        if !loose.isEmpty {
            groups.append(AgendaGroup(id: "section.\(otherID)", title: String(localized: "Fără secțiune", comment: "Agenda group of people not tied to a section."), providerIDs: sorted(loose).map(\.id)))
        }
        return groups
    }

    /// Best first: would call again, then rating, then name.
    static func sorted(_ people: [Person]) -> [Person] {
        people.sorted { lhs, rhs in
            let l = (lhs.wouldCallAgain == true, lhs.rating ?? 0), r = (rhs.wouldCallAgain == true, rhs.rating ?? 0)
            if l.0 != r.0 { return l.0 }
            if l.1 != r.1 { return l.1 > r.1 }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
