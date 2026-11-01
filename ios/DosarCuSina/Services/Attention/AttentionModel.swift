import Foundation

/// How close an obligation is, in words a screen can show.
public enum AttentionUrgency: String, Sendable, Comparable {
    case overdue
    case today
    case soon
    case upcoming
    case later

    private var order: Int {
        switch self {
        case .overdue: return 0
        case .today: return 1
        case .soon: return 2
        case .upcoming: return 3
        case .later: return 4
        }
    }

    public static func < (lhs: AttentionUrgency, rhs: AttentionUrgency) -> Bool { lhs.order < rhs.order }
}

/// One ranked obligation.
public struct AttentionEntry: Hashable, Sendable, Identifiable {
    public var obligation: ObligationSnapshot
    /// Whole days until due; negative when overdue.
    public var daysRemaining: Int
    public var urgency: AttentionUrgency
    /// Higher needs attention sooner. Only meaningful for ordering.
    public var score: Int

    public var id: UUID { obligation.id }
}

/// Upcoming obligations of one asset, collapsed under it.
public struct AttentionAssetGroup: Hashable, Sendable, Identifiable {
    public var assetId: UUID?
    public var assetName: String
    public var symbol: String
    public var tint: TemplateTint
    /// Soonest first.
    public var entries: [AttentionEntry]

    public var id: String { assetId?.uuidString ?? "unassigned" }
    public var nextDay: CalendarDay? { entries.first?.obligation.dueDay }
}

/// Everything beyond the "soon" window, summarized instead of listed.
public struct AttentionLaterSummary: Hashable, Sendable {
    public var count: Int
    public var nextDay: CalendarDay?
    public var estimatedCost: MoneyTotals

    public static let empty = AttentionLaterSummary(count: 0, nextDay: nil, estimatedCost: MoneyTotals())
}

/// What deserves attention now, shaped so the Radar stays short however much is tracked:
/// a few items in `now`, the rest of the near future grouped per asset in `soon`,
/// and everything further out as counts in `later`.
public struct AttentionDigest: Hashable, Sendable {
    public var now: [AttentionEntry]
    public var soon: [AttentionAssetGroup]
    public var later: AttentionLaterSummary
    /// Items that qualified for `now` but were moved into `soon` because of the cap.
    public var overflowCount: Int
    /// Snoozed and paused items, not shown.
    public var hiddenCount: Int
    /// Overdue plus due today, for badges and widgets.
    public var needsActionCount: Int

    public var isAllClear: Bool { now.isEmpty && needsActionCount == 0 }
}

/// Ranks obligations by consequence, then by how soon, then by cost.
public enum AttentionModel {
    public struct Limits: Hashable, Sendable {
        /// Most items shown as "needs you now".
        public var maxNow: Int
        /// Days ahead that count as "soon" and get listed per asset.
        public var soonWindowDays: Int

        public init(maxNow: Int = 5, soonWindowDays: Int = 30) {
            self.maxNow = maxNow
            self.soonWindowDays = soonWindowDays
        }

        public static let standard = Limits()
    }

    public static func digest(
        _ obligations: [ObligationSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current,
        limits: Limits = .standard
    ) -> AttentionDigest {
        let today = CalendarDay(now, calendar: calendar)
        var hidden = 0
        var nowCandidates: [AttentionEntry] = []
        var soonEntries: [AttentionEntry] = []
        var later = AttentionLaterSummary.empty
        var needsAction = 0

        for obligation in obligations {
            switch obligation.status {
            case .done, .archived:
                continue
            case .paused:
                hidden += 1
                continue
            case .active:
                break
            }
            if let snoozedUntil = obligation.snoozedUntil, snoozedUntil > now {
                hidden += 1
                continue
            }
            let days = today.days(to: obligation.dueDay, calendar: calendar)
            let entry = AttentionEntry(
                obligation: obligation,
                daysRemaining: days,
                urgency: urgency(daysRemaining: days, kind: obligation.kind),
                score: score(daysRemaining: days, obligation: obligation)
            )
            if days <= 0 { needsAction += 1 }
            if days <= obligation.kind.attentionLeadDays {
                nowCandidates.append(entry)
            } else if days <= limits.soonWindowDays {
                soonEntries.append(entry)
            } else {
                later.count += 1
                later.nextDay = min(later.nextDay ?? obligation.dueDay, obligation.dueDay)
                if let cost = obligation.estimatedCost { later.estimatedCost.add(cost) }
            }
        }

        nowCandidates.sort(by: rank)
        let nowEntries = Array(nowCandidates.prefix(limits.maxNow))
        let overflow = Array(nowCandidates.dropFirst(limits.maxNow))
        soonEntries.append(contentsOf: overflow)

        let groups = Dictionary(grouping: soonEntries) { $0.obligation.assetId }
            .map { assetId, entries -> AttentionAssetGroup in
                let sorted = entries.sorted { lhs, rhs in
                    lhs.obligation.dueDay != rhs.obligation.dueDay ? lhs.obligation.dueDay < rhs.obligation.dueDay : rank(lhs, rhs)
                }
                let first = sorted[0].obligation
                return AttentionAssetGroup(
                    assetId: assetId,
                    assetName: first.assetName ?? String(localized: "Fără activ", comment: "Group for obligations not tied to an asset"),
                    symbol: first.symbol,
                    tint: first.tint,
                    entries: sorted
                )
            }
            .sorted { lhs, rhs in
                if lhs.nextDay != rhs.nextDay { return (lhs.nextDay ?? today) < (rhs.nextDay ?? today) }
                return lhs.assetName.localizedStandardCompare(rhs.assetName) == .orderedAscending
            }

        return AttentionDigest(
            now: nowEntries,
            soon: groups,
            later: later,
            overflowCount: overflow.count,
            hiddenCount: hidden,
            needsActionCount: needsAction
        )
    }

    public static func urgency(daysRemaining days: Int, kind: ObligationKind) -> AttentionUrgency {
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days <= kind.attentionLeadDays { return .soon }
        if days <= 30 { return .upcoming }
        return .later
    }

    /// Consequence carries the most weight, closeness can lift an item by up to
    /// three consequence steps (an overdue tax beats an ITP due in two weeks,
    /// but an overdue chore never beats a legal deadline), and cost breaks ties.
    static func score(daysRemaining days: Int, obligation: ObligationSnapshot) -> Int {
        let consequence = obligation.kind.consequenceWeight * 10
        let closeness: Int
        if days < 0 {
            closeness = 300 + min(-days, 30)
        } else {
            let lead = max(obligation.kind.attentionLeadDays, 1)
            closeness = max(0, (lead - min(days, lead)) * 280 / lead)
        }
        let cost = obligation.estimatedCost.map { NSDecimalNumber(decimal: $0.amount).doubleValue } ?? 0
        let costNudge = cost > 0 ? min(Int(log10(cost + 1) * 3), 9) : 0
        return consequence + closeness + costNudge
    }

    private static func rank(_ lhs: AttentionEntry, _ rhs: AttentionEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.obligation.dueDay != rhs.obligation.dueDay { return lhs.obligation.dueDay < rhs.obligation.dueDay }
        return lhs.obligation.title.localizedStandardCompare(rhs.obligation.title) == .orderedAscending
    }
}
