import Foundation

/// How a category's visits read and what they are: a car goes to the service, a pet to
/// the vet, a home gets a tradesperson. Declared once per built-in in `BuiltInTemplates`
/// and kept with the category's behaviour (`CategoryBehavior.visit`); a category without
/// one, such as any of the person's own, reads as `standard`. The one source for the
/// section's "log a visit" button and the visit flow.
///
/// Part of the `.dosar` contract (`behavior.visit`). A missing or unknown value reads as
/// the standard one's.
public struct VisitWording: Hashable, Sendable, Codable {
    /// The button and the visit flow's title: "Am fost la service".
    public var title: String
    /// Above the checklist: "Ce s-a făcut".
    public var checklistTitle: String
    /// Above who did it: "Service-ul".
    public var providerTitle: String
    /// What the visit is in the history.
    public var kind: HistoryKind
    /// What a firm or person added from the visit does.
    public var trade: ProviderTrade

    public init(title: String, checklistTitle: String, providerTitle: String, kind: HistoryKind, trade: ProviderTrade) {
        self.title = title
        self.checklistTitle = checklistTitle
        self.providerTitle = providerTitle
        self.kind = kind
        self.trade = trade
    }

    /// Any category that doesn't say: a job done, by whoever did it.
    public static var standard: VisitWording {
        VisitWording(title: String(localized: "Am făcut o lucrare"), checklistTitle: String(localized: "Ce s-a făcut"),
                     providerTitle: String(localized: "Cine a lucrat"), kind: .repair, trade: .other)
    }

    private enum CodingKeys: String, CodingKey { case title, checklistTitle, providerTitle, kind, trade }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        func text(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
        }
        title = text(.title) ?? standard.title
        checklistTitle = text(.checklistTitle) ?? standard.checklistTitle
        providerTitle = text(.providerTitle) ?? standard.providerTitle
        kind = text(.kind).flatMap(HistoryKind.init(rawValue:)) ?? standard.kind
        trade = text(.trade).flatMap(ProviderTrade.init(rawValue:)) ?? standard.trade
    }
}
