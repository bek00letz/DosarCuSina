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
    public static func make(_ obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .dosar) -> BoxStatus {
        let digest = AttentionModel.digest(obligations, now: now, calendar: calendar, limits: .init(maxNow: 1))
        if let top = digest.now.first { return BoxStatus(state: .pending(top)) }
        return BoxStatus(state: .allGood)
    }

    /// The box of one asset: its own obligations and those of the assets filed under it.
    public static func make(forAsset id: UUID, descendants: Set<UUID> = [], in obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .dosar) -> BoxStatus {
        make(forAssets: descendants.union([id]), in: obligations, now: now, calendar: calendar)
    }

    /// The box of several assets (a category's box, or its sections grouped into one), with
    /// what is filed under them in `ids` too: the most pressing of them all, which is the worst
    /// of the boxes they would have each, by the same ranking.
    public static func make(forAssets ids: Set<UUID>, in obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .dosar) -> BoxStatus {
        make(obligations.filter { $0.assetId.map(ids.contains) ?? false }, now: now, calendar: calendar)
    }

    /// The line to show. In a section behind a lock the obligation's title is
    /// replaced, so the line never reveals what is inside.
    public func line(isSensitive: Bool, now: Date = Date(), calendar: Calendar = .dosar) -> String {
        guard let entry else { return String(localized: "Totul e în regulă", comment: "Box status when nothing needs attention") }
        let title = isSensitive ? String(localized: "O scadență", comment: "Box status title in a locked section") : entry.obligation.title
        let when = WhenWording.phrase(entry.urgency, daysRemaining: entry.daysRemaining, from: now, calendar: calendar)
        return String(localized: "\(title) · \(when)", comment: "Box status: the obligation, then when it is due, e.g. 'ITP · în 5 zile'.")
    }

    /// The line of a box that holds a category's sections grouped into one: how many, then the
    /// most pressing deadline among them, "3 mașini · ITP · în 5 zile".
    public func line(counting count: Int, of noun: SectionNoun?, isSensitive: Bool, now: Date = Date(), calendar: Calendar = .dosar) -> String {
        let counted = Self.count(count, of: noun)
        guard entry != nil else {
            return String(localized: "\(counted) · totul e în regulă", comment: "Status of a box holding several sections when nothing needs attention, e.g. '3 mașini · totul e în regulă'.")
        }
        let pressing = line(isSensitive: isSensitive, now: now, calendar: calendar)
        return String(localized: "\(counted) · \(pressing)", comment: "Status of a box holding several sections: how many, then the most pressing deadline, e.g. '3 mașini · ITP · în 5 zile'.")
    }

    /// How many sections a box holds, in its category's words: "o mașină", "3 plante",
    /// "20 de secțiuni" for a category without words of its own.
    public static func count(_ count: Int, of noun: SectionNoun?) -> String {
        switch noun {
        case .car: String(localized: "\(count) mașini", comment: "How many cars a box holds.")
        case .home: String(localized: "\(count) locuințe", comment: "How many homes a box holds.")
        case .pet: String(localized: "\(count) animale", comment: "How many pets a box holds.")
        case .bike: String(localized: "\(count) biciclete", comment: "How many bikes a box holds.")
        case .plant: String(localized: "\(count) plante", comment: "How many plants a box holds.")
        case .espressoMachine: String(localized: "\(count) espressoare", comment: "How many espresso machines a box holds.")
        case nil: String(localized: "\(count) secțiuni", comment: "How many sections a box holds, for a category without words of its own.")
        }
    }
}
