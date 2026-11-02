import Foundation
import SwiftData

/// How a visit is worded for each kind of section: a car goes to the service,
/// a pet to the vet, a home gets a tradesperson. Driven by the template's
/// look (`HeroStyle`), so a custom category gets the neutral wording. The one
/// source for the section's "log a visit" button and the visit flow.
struct VisitWording: Equatable {
    var title: String
    var checklistTitle: String
    var providerTitle: String
    var kind: HistoryKind
    var trade: ProviderTrade

    static func forTemplate(key: String, heroStyle: HeroStyle) -> VisitWording {
        switch (key, heroStyle) {
        case (_, .vehicle), (BuiltInTemplates.Key.bike, _):
            return VisitWording(title: String(localized: "Am fost la service"), checklistTitle: String(localized: "Ce s-a făcut"),
                                providerTitle: String(localized: "Service-ul"), kind: .maintenance, trade: .mechanic)
        case (_, .pet):
            return VisitWording(title: String(localized: "Am fost la veterinar"), checklistTitle: String(localized: "Ce i s-a făcut"),
                                providerTitle: String(localized: "Veterinarul"), kind: .visit, trade: .vet)
        case (_, .home):
            return VisitWording(title: String(localized: "Am chemat un meseriaș"), checklistTitle: String(localized: "Ce a lucrat"),
                                providerTitle: String(localized: "Meseriașul"), kind: .repair, trade: .handyman)
        case (BuiltInTemplates.Key.health, _):
            return VisitWording(title: String(localized: "Am fost la medic"), checklistTitle: String(localized: "Ce s-a făcut"),
                                providerTitle: String(localized: "Medicul"), kind: .visit, trade: .doctor)
        default:
            return VisitWording(title: String(localized: "Am făcut o lucrare"), checklistTitle: String(localized: "Ce s-a făcut"),
                                providerTitle: String(localized: "Cine a lucrat"), kind: .repair, trade: .other)
        }
    }
}

/// A visit being filled in: the ticked checklist rows, anything else done,
/// the date, the counter, the total and who did it. Turns into exactly one
/// `HistoryActions.recordVisit` call.
struct VisitDraft: Equatable {
    struct Part: Equatable {
        var cost: Decimal?
        var brand: String = ""
    }

    struct Extra: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var cost: Decimal?
    }

    enum ProviderChoice: Equatable {
        case none
        case existing(UUID)
        case new(String)
    }

    var date: Date
    /// Ticked rows by component key, in the order they were ticked.
    var ticked: [String] = []
    var parts: [String: Part] = [:]
    var extras: [Extra] = []
    var odometer: Double?
    var total: Decimal?
    var currency: String = Money.defaultCurrency
    var provider: ProviderChoice = .none
    var rating: Int?
    /// The captured invoice, filed with the visit: new pages, or a copy the binder already
    /// keeps (it moves to the visit).
    var document: CapturedDocumentRef?
    var documentTitle: String?
    var documentText: String?

    init(date: Date) {
        self.date = date
    }

    var isEmpty: Bool {
        ticked.isEmpty && extras.allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty } && total == nil && document == nil
    }

    func isTicked(_ key: String) -> Bool { ticked.contains(key) }

    mutating func toggle(_ key: String) {
        if let index = ticked.firstIndex(of: key) {
            ticked.remove(at: index)
        } else {
            ticked.append(key)
        }
    }

    // MARK: To the engine

    var checklistItems: [HistoryActions.ChecklistItem] {
        ticked.map { key in
            let part = parts[key]
            let brand = part?.brand.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return HistoryActions.ChecklistItem(
                componentKey: key,
                cost: part?.cost.map { Money($0, currency: currency) },
                partBrandOrCode: brand.isEmpty ? nil : brand
            )
        }
    }

    var extraItems: [LineItemDraft] {
        extras.compactMap { extra in
            let name = extra.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return LineItemDraft(name: name, cost: extra.cost.map { Money($0, currency: currency) })
        }
    }

    /// The total written: the one typed, else nothing (the parts add up on their own).
    var totalMoney: Money? { total.map { Money($0, currency: currency) } }

    /// The sum of the parts' costs, shown as a hint under the total.
    var partsSum: Decimal? {
        let costs = ticked.compactMap { parts[$0]?.cost } + extras.compactMap(\.cost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    // MARK: From an invoice

    /// Fills the draft from a captured invoice: ticks the rows its lines match,
    /// with their costs; lines the catalog doesn't know become "Altceva" rows;
    /// labour and the total, the date and the provider's name fill in when empty.
    mutating func apply(_ result: CaptureResult, components: [ComponentDefinition], calendar: Calendar = .current) {
        let fields = Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        for line in fields[.lineItems]?.lineItems ?? [] {
            let cost = line.amount?.amount
            if let currency = line.amount?.currencyCode { self.currency = currency }
            let key = line.componentKey.flatMap { key in components.contains { $0.key == key } ? key : nil }
                ?? (line.isLabour ? nil : ComponentCatalog.match(line.description, in: components)?.key)
            if let key {
                if !isTicked(key) { ticked.append(key) }
                var part = parts[key] ?? Part()
                if let cost { part.cost = (part.cost ?? 0) + cost }
                parts[key] = part
            } else {
                let name = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !extras.contains(where: { $0.name == name }) else { continue }
                extras.append(Extra(name: name, cost: cost))
            }
        }
        if total == nil, let money = fields[.total]?.money {
            total = money.amount
            currency = money.currencyCode
        }
        if let day = (fields[.issueDate] ?? fields[.purchaseDate])?.day, let date = day.date(in: calendar) {
            self.date = CalendarDay(date, calendar: calendar).noonDate(in: calendar)
        }
        if odometer == nil, case .metric(let value, _)? = fields[.odometer] {
            odometer = NSDecimalNumber(decimal: value).doubleValue
        }
        if provider == .none, let name = fields[.provider]?.text, !name.isEmpty {
            provider = .new(name)
        }
        if let document = result.document { self.document = document }
        documentText = result.recognizedText.isEmpty ? nil : result.recognizedText
    }
}

/// What the visit changed, for the screen after saving: each part with when it
/// was last done before, so "Plăcuțe frână față" reads "azi · înainte în martie 2024".
struct VisitChange: Identifiable, Equatable {
    var id: String { componentKey }
    var componentKey: String
    var name: String
    var cost: Money?
    /// When it was done before this visit, if ever.
    var previous: Date?

    @MainActor
    static func changes(of entry: HistoryEntry, on asset: Asset) -> [VisitChange] {
        let items = HistoryItemSnapshot.items(of: asset).filter { $0.entryId != entry.id }
        return (entry.items ?? []).compactMap { item in
            guard let key = item.componentKey else { return nil }
            let previous = MaintenanceLog.lastOccurrence(of: key, in: items)?.date
            return VisitChange(componentKey: key, name: item.name, cost: item.totalCost, previous: previous)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// The counter (odometer) a visit starts with: the latest reading, moved on by
/// the usual pace since then, rounded up to the hundred. Easy to correct; it only saves a few taps.
enum OdometerEstimate {
    static func value(readings: [CadenceCalculator.TelemetryReading], fallback: Double?, now: Date) -> Double? {
        guard let latest = readings.max(by: { $0.date < $1.date }) else { return fallback }
        guard let rate = MaintenanceLog.monthlyRate(readings) else { return latest.metric }
        let days = max(0, now.timeIntervalSince(latest.date) / 86_400)
        // Rounded up, so the estimate is never below the last real reading.
        return ((latest.metric + rate * days / 30) / 100).rounded(.up) * 100
    }
}
