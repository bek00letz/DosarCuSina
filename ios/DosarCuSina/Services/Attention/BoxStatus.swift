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

    /// Whether the obligation shown counts on the app's badge (overdue past grace, or due today).
    public var isAlarming: Bool { entry?.urgency.isAlarming ?? false }

    /// The tone the line is drawn in, from the urgency every other surface uses.
    public var urgencyTone: UrgencyTone { entry?.urgency.tone ?? .calm }

    /// The status of a box from the obligations it holds, ranked exactly as the
    /// Urmează tab ranks them. Only what is inside its attention window counts;
    /// anything further out is "all good" for now.
    public static func make(_ obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .current) -> BoxStatus {
        let digest = AttentionModel.digest(obligations, now: now, calendar: calendar, limits: .init(maxNow: 1))
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
    public func line(isSensitive: Bool, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let entry else { return String(localized: "Totul e în regulă", comment: "Box status when nothing needs attention") }
        let title = isSensitive ? String(localized: "O scadență", comment: "Box status title in a locked section") : entry.obligation.title
        let when = WhenWording.phrase(entry.urgency, daysRemaining: entry.daysRemaining, from: now, calendar: calendar)
        return String(localized: "\(title) · \(when)", comment: "Box status: the obligation, then when it is due, e.g. 'ITP · în 5 zile'.")
    }
}
