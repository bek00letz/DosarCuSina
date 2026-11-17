import Foundation

/// A calm note in Urmează's "Din timp": something worth knowing, with nothing due. It never
/// notifies, never counts on the badge and never reaches widgets. Two kinds share it: a bill
/// that hasn't come (`missingBills`), and the suggestions for the binder (`suggestionNote`),
/// which are never an alert and never in the repair list.
public struct AttentionNote: Hashable, Sendable, Identifiable {
    /// Where tapping the note goes.
    public enum Opens: Hashable, Sendable {
        /// The subscription the bill belongs to.
        case section(UUID)
        /// The page of suggestions (`SuggestionsScreen`).
        case suggestions
    }

    public var opens: Opens
    /// "Factura de la ENGIE n-a venit luna asta", "O sugestie pentru dosar".
    public var title: String
    /// Where it is filed and when the last one came; what the suggestions are about.
    public var detail: String
    /// When a bill was expected; nil for what has no day (suggestions), which goes last.
    public var expectedDay: CalendarDay?

    public init(opens: Opens, title: String, detail: String, expectedDay: CalendarDay?) {
        self.opens = opens
        self.title = title
        self.detail = detail
        self.expectedDay = expectedDay
    }

    /// The section it is about, when it is about one.
    public var assetId: UUID? {
        if case .section(let id) = opens { return id }
        return nil
    }

    public var id: Opens { opens }
}

extension AttentionModel {
    /// The calm notes of "Din timp", in the order they show: the bills that haven't come, oldest
    /// expected first, then the suggestions.
    public static func calmNotes(missingBills: [AttentionNote], suggestions: AttentionNote?) -> [AttentionNote] {
        missingBills + [suggestions].compactMap { $0 }
    }

    /// One note for every suggestion waiting (`DataRepairStep.isSuggestion`): how many, and what
    /// they are about ("Ce ține de altă secțiune"), never the names of what they would move, so the
    /// note says nothing a locked section wouldn't. Nil with none. It opens the suggestions' page.
    public static func suggestionNote(count: Int, topics: [String]) -> AttentionNote? {
        guard count > 0 else { return nil }
        let title = String(localized: "\(count) sugestii pentru dosar", locale: .dosarDefault, comment: "Urmează, Din timp: how many suggestions wait for the binder, with Romanian plural forms (O sugestie pentru dosar).")
        let about = topics.formatted(.list(type: .and).locale(.dosarDefault))
        let promise = String(localized: "Nu schimb nimic fără tine.", comment: "Repair prompt: nothing changes without the owner.")
        let detail = about.isEmpty ? promise : about + ". " + promise
        return AttentionNote(opens: .suggestions, title: title, detail: detail, expectedDay: nil)
    }

    /// The bills that haven't come when they usually do. Only for subscriptions billed on
    /// a rhythm (utilities and phone plans, monthly unless they say otherwise) that have
    /// had a bill before; examples never. Comfort only: oldest expected first.
    public static func missingBills(
        _ subscriptions: [BillWatchSnapshot],
        now: Date = Date(),
        calendar: Calendar = .dosar,
        locale: Locale = .dosarDefault
    ) -> [AttentionNote] {
        let today = CalendarDay(now, calendar: calendar)
        return subscriptions
            .filter { !$0.isExample && ServiceKind.sendsRegularBills($0.service) }
            .compactMap { subscription -> (note: AttentionNote, day: CalendarDay)? in
                guard let missing = BillHistory.missing(subscription.bills, cycleMonths: subscription.cycleMonths, today: today, calendar: calendar) else { return nil }
                let last = DosarFormat.dayMonth(missing.lastDay, locale: locale)
                let lastLine = String(localized: "Ultima a venit pe \(last).", comment: "When a subscription's last bill came.")
                guard !subscription.isSensitive else {
                    return (AttentionNote(opens: .section(subscription.id), title: String(localized: "O factură n-a venit încă", comment: "A missing bill, in a locked section."),
                                          detail: lastLine, expectedDay: missing.expectedDay), missing.expectedDay)
                }
                let from = subscription.provider.map(SubscriptionMatcher.shortProviderName) ?? subscription.name
                // By how many months its bills come apart, the String Catalog's plural variations:
                // a monthly bill "n-a venit luna asta", a rarer one "n-a venit încă".
                let title = String(localized: "Factura de la \(from) n-a venit, o dată la \(missing.cycleMonths) luni",
                                   locale: .dosarDefault, comment: "A bill that hasn't come. The first argument is the provider; by how many months its bills come apart, without the number: one „Factura de la ENGIE n-a venit luna asta”, more „Factura de la ENGIE n-a venit încă”.")
                let place = [subscription.name, subscription.placeName].compactMap { $0 }.joined(separator: " · ")
                return (AttentionNote(opens: .section(subscription.id), title: title, detail: place + ". " + lastLine, expectedDay: missing.expectedDay), missing.expectedDay)
            }
            .sorted { $0.day < $1.day }
            .map(\.note)
    }
}
