import Foundation

/// A calm note in Urmează: something worth knowing, with nothing due. It never
/// notifies, never counts on the badge and never reaches widgets.
public struct AttentionNote: Hashable, Sendable, Identifiable {
    /// The subscription it is about.
    public var assetId: UUID
    /// "Factura de la ENGIE n-a venit luna asta".
    public var title: String
    /// Where it is filed and when the last one came.
    public var detail: String
    public var expectedDay: CalendarDay

    public var id: UUID { assetId }
}

extension AttentionModel {
    /// The bills that haven't come when they usually do. Only for subscriptions billed on
    /// a rhythm (utilities and phone plans, monthly unless they say otherwise) that have
    /// had a bill before; examples never. Comfort only: oldest expected first.
    public static func missingBills(
        _ subscriptions: [BillWatchSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .dosarDefault
    ) -> [AttentionNote] {
        let today = CalendarDay(now, calendar: calendar)
        return subscriptions
            .filter { !$0.isExample && ServiceKind.sendsRegularBills($0.service) }
            .compactMap { subscription -> AttentionNote? in
                guard let missing = BillHistory.missing(subscription.bills, cycleMonths: subscription.cycleMonths, today: today, calendar: calendar) else { return nil }
                let last = DosarFormat.dayMonth(missing.lastDay, locale: locale)
                let lastLine = String(localized: "Ultima a venit pe \(last).", comment: "When a subscription's last bill came.")
                guard !subscription.isSensitive else {
                    return AttentionNote(assetId: subscription.id, title: String(localized: "O factură n-a venit încă", comment: "A missing bill, in a locked section."),
                                         detail: lastLine, expectedDay: missing.expectedDay)
                }
                let from = subscription.provider.map(SubscriptionMatcher.shortProviderName) ?? subscription.name
                let title = missing.cycleMonths == 1
                    ? String(localized: "Factura de la \(from) n-a venit luna asta", comment: "A monthly bill that hasn't come. The argument is the provider.")
                    : String(localized: "Factura de la \(from) n-a venit încă", comment: "A bill that hasn't come. The argument is the provider.")
                let place = [subscription.name, subscription.placeName].compactMap { $0 }.joined(separator: " · ")
                return AttentionNote(assetId: subscription.id, title: title, detail: place + ". " + lastLine, expectedDay: missing.expectedDay)
            }
            .sorted { $0.expectedDay < $1.expectedDay }
    }
}
