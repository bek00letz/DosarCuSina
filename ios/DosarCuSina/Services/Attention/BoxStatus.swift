import Foundation

/// The one line under a box on the Dosar grid: "Totul e în regulă", or the
/// single most pressing obligation in that box with how far it is.
public struct BoxStatus: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case allGood
        case pending(AttentionEntry)
    }

    public var state: State

    /// The obligation shown, if any.
    public var entry: AttentionEntry? {
        if case .pending(let entry) = state { return entry }
        return nil
    }

    /// Whether the line should look like a problem (overdue past grace, or due today).
    public var isAlarming: Bool { entry?.urgency.isAlarming ?? false }

    /// The status of a box from the obligations it holds, ranked exactly as the
    /// Urmează tab ranks them. Only what is inside its attention window counts;
    /// anything further out is "all good" for now.
    public static func make(_ obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .current) -> BoxStatus {
        let digest = AttentionModel.digest(obligations, now: now, calendar: calendar, limits: .init(maxNow: 1, soonWindowDays: 0))
        if let top = digest.now.first { return BoxStatus(state: .pending(top)) }
        return BoxStatus(state: .allGood)
    }

    /// The box of one asset: its own obligations and those of the assets filed under it.
    public static func make(forAsset id: UUID, descendants: Set<UUID> = [], in obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .current) -> BoxStatus {
        let ids = descendants.union([id])
        return make(obligations.filter { $0.assetId.map(ids.contains) ?? false }, now: now, calendar: calendar)
    }

    /// The line to show. In a section behind a lock the obligation's title is
    /// replaced, so the line never reveals what is inside.
    public func line(isSensitive: Bool) -> String {
        guard let entry else { return String(localized: "Totul e în regulă", comment: "Box status when nothing needs attention") }
        let title = isSensitive ? String(localized: "O scadență", comment: "Box status title in a locked section") : entry.obligation.title
        let days = abs(entry.daysRemaining)
        switch entry.urgency {
        case .overdue:
            return String(localized: "\(title) · depășit de \(DayCount.phrase(days))", comment: "Box status: overdue by N days")
        case .withinGrace:
            return String(localized: "\(title) · întârziat \(DayCount.phrase(days))", comment: "Box status: late, but within accepted grace")
        case .today:
            return String(localized: "\(title) · azi", comment: "Box status: due today")
        case .soon, .upcoming, .later:
            if entry.daysRemaining == 1 { return String(localized: "\(title) · mâine", comment: "Box status: due tomorrow") }
            return String(localized: "\(title) · în \(DayCount.phrase(days))", comment: "Box status: due in N days")
        }
    }
}

/// "1 zi", "5 zile", "20 de zile". The forms live in the String Catalog as
/// plural variations (Romanian one / few / other), like every other count in
/// the app, so there is one way to write plurals.
public enum DayCount {
    public static func phrase(_ count: Int) -> String {
        let n = abs(count)
        return String(localized: "\(n) zile", comment: "A number of days, with Romanian plural forms: 1 zi, 2 zile, 20 de zile.")
    }
}
