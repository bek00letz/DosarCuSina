import Foundation
import SwiftData

/// A confirmed line item to add to a history entry. Capture produces drafts the
/// person reviews; only confirmed values reach the engine.
public struct LineItemDraft {
    public var name: String
    /// A catalog key; when nil it is worked out from `name` and the template's components.
    public var componentKey: String?
    public var group: String?
    public var partBrandOrCode: String?
    public var partSerialNumber: String?
    public var cost: Money?
    public var laborCost: Money?
    public var partsCost: Money?
    public var warrantyMonths: Int?
    public var daysInService: Int?
    public var locationDetail: String?
    public var batchOrTicket: String?
    public var notes: String?
    public var supplier: Provider?

    public init(
        name: String,
        componentKey: String? = nil,
        group: String? = nil,
        partBrandOrCode: String? = nil,
        partSerialNumber: String? = nil,
        cost: Money? = nil,
        laborCost: Money? = nil,
        partsCost: Money? = nil,
        warrantyMonths: Int? = nil,
        daysInService: Int? = nil,
        locationDetail: String? = nil,
        batchOrTicket: String? = nil,
        notes: String? = nil,
        supplier: Provider? = nil
    ) {
        self.name = name
        self.componentKey = componentKey
        self.group = group
        self.partBrandOrCode = partBrandOrCode
        self.partSerialNumber = partSerialNumber
        self.cost = cost
        self.laborCost = laborCost
        self.partsCost = partsCost
        self.warrantyMonths = warrantyMonths
        self.daysInService = daysInService
        self.locationDetail = locationDetail
        self.batchOrTicket = batchOrTicket
        self.notes = notes
        self.supplier = supplier
    }
}

/// Logging what happened to an asset: repairs, visits, purchases. Completing an
/// obligation goes through `ObligationActions` and lands in the same history.
@MainActor
public final class HistoryActions {
    public let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func record(
        on asset: Asset,
        kind: HistoryKind,
        title: String,
        occurredAt: Date? = nil,
        metricReading: Double? = nil,
        totalCost: Money? = nil,
        note: String? = nil,
        items: [LineItemDraft] = [],
        providers: [Provider] = [],
        rating: Int? = nil,
        asExample: Bool = false,
        lowerReading: LowerReadingAnswer? = nil
    ) throws -> HistoryEntry {
        // One step: a question about a lower reading leaves nothing half-changed.
        return try UnitOfWork.perform(in: context) {
            let isExample = try ExampleOwnership.requireReal(asset, creatingExample: asExample)
            let date = occurredAt ?? now()
            let entry = HistoryEntry(kind: kind, title: title, occurredAt: date)
            entry.metricReading = metricReading
            entry.totalCost = totalCost
            entry.note = note
            entry.rating = rating.map { min(max($0, 1), 5) }
            entry.isExample = isExample
            context.insert(entry)
            entry.asset = asset
            entry.providers = providers
            HouseholdMutations.addItems(items, to: entry, in: context)
            if let metricReading {
                let template = (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil
                let unit = template.flatMap { HouseholdMutations.heroMetricUnit(template: $0.definition) }
                try HouseholdMutations.recordReading(metricReading, on: asset, at: date, source: .person, unit: unit,
                                                     answer: lowerReading, isExample: isExample, in: context)
            }
            try save()
            return entry
        }
    }

    /// One ticked component on the visit checklist, with what it cost if known.
    public struct ChecklistItem: Sendable {
        public var componentKey: String
        public var cost: Money?
        public var partBrandOrCode: String?

        public init(componentKey: String, cost: Money? = nil, partBrandOrCode: String? = nil) {
            self.componentKey = componentKey
            self.cost = cost
            self.partBrandOrCode = partBrandOrCode
        }
    }

    /// Records one visit (a service, a repair, a check-up) with every part ticked on
    /// the checklist, all in one save: the entry, its line items, the odometer
    /// reading (also logged as a measurement), the provider and the documents.
    @discardableResult
    public func recordVisit(
        on asset: Asset,
        kind: HistoryKind = .maintenance,
        title: String? = nil,
        occurredAt: Date? = nil,
        checklist: [ChecklistItem],
        extraItems: [LineItemDraft] = [],
        totalCost: Money? = nil,
        odometer: Double? = nil,
        provider: Provider? = nil,
        documents: [DocumentDraft] = [],
        rating: Int? = nil,
        calendar: Calendar = .current,
        odometerSource: ReadingSource = .person,
        lowerReading: LowerReadingAnswer? = nil
    ) throws -> HistoryEntry {
        // One step: a question about a lower reading leaves nothing half-changed.
        return try UnitOfWork.perform(in: context) {
            let isExample = try ExampleOwnership.requireReal(asset)
            let template = (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil
            let catalog = template?.components ?? []
            let ticked = checklist.map { item in
                LineItemDraft(
                    name: catalog.first { $0.key == item.componentKey }?.name ?? item.componentKey,
                    componentKey: item.componentKey,
                    partBrandOrCode: item.partBrandOrCode,
                    cost: item.cost
                )
            }
            let items = ticked + extraItems
            let date = occurredAt ?? now()
            let entry = HistoryEntry(kind: kind, title: title ?? Self.visitTitle(for: items), occurredAt: date)
            entry.metricReading = odometer
            entry.totalCost = totalCost
            entry.rating = rating.map { min(max($0, 1), 5) }
            entry.isExample = isExample
            context.insert(entry)
            entry.asset = asset
            entry.providers = provider.map { [$0] } ?? []
            HouseholdMutations.addItems(items, to: entry, in: context)
            if let odometer {
                let unit = template.flatMap { HouseholdMutations.heroMetricUnit(template: $0.definition) }
                try HouseholdMutations.recordReading(odometer, on: asset, at: date, source: odometerSource, unit: unit,
                                                     answer: lowerReading, isExample: isExample, in: context)
            }
            for draft in documents {
                _ = AttachmentActions.insert(draft, asset: asset, obligation: nil, historyEntry: entry, provider: nil, isExample: isExample, calendar: calendar, in: context)
            }
            try save()
            return entry
        }
    }

    /// "Ulei și filtru, Plăcuțe frână față" for short visits, a plain title for long ones.
    static func visitTitle(for items: [LineItemDraft]) -> String {
        let names = items.map(\.name).filter { !$0.isEmpty }
        switch names.count {
        case 0: return String(localized: "Vizită", comment: "History entry title when nothing was listed")
        case 1...2: return names.joined(separator: ", ")
        default: return String(localized: "Revizie: \(names.count) lucrări", comment: "History entry title for a visit with many jobs")
        }
    }

    /// Adds line items to an existing entry.
    public func addItems(_ items: [LineItemDraft], to entry: HistoryEntry) throws {
        HouseholdMutations.addItems(items, to: entry, in: context)
        try save()
    }

    /// Rates the job 1–5, or clears the rating with nil. The providers' ratings follow.
    public func rate(_ entry: HistoryEntry, _ rating: Int?) throws {
        entry.rating = rating.map { min(max($0, 1), 5) }
        try save()
    }

    public func delete(_ entry: HistoryEntry) throws {
        context.delete(entry)
        try save()
    }

    private func save() throws {
        try UnitOfWork.save(context)
    }
}

extension HouseholdMutations {
    /// Inserts line items, resolving each component key from the asset's template catalog.
    static func addItems(_ drafts: [LineItemDraft], to entry: HistoryEntry, in context: ModelContext) {
        guard !drafts.isEmpty else { return }
        let template = entry.asset.flatMap { asset in (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil }
        let components = template?.components ?? []
        for draft in drafts {
            let item = ServiceItem(name: draft.name, componentKey: draft.componentKey ?? ComponentCatalog.key(for: draft.name, in: components))
            let currency = (draft.cost ?? draft.laborCost ?? draft.partsCost)?.currency ?? Money.defaultCurrency
            item.currency = currency
            item.costAmount = draft.cost?.amount
            item.laborCostAmount = draft.laborCost?.amount
            item.partsCostAmount = draft.partsCost?.amount
            item.group = draft.group ?? components.first { $0.key == item.componentKey }?.group
            item.partBrandOrCode = draft.partBrandOrCode
            item.partSerialNumber = draft.partSerialNumber
            item.warrantyMonths = draft.warrantyMonths
            item.daysInService = draft.daysInService
            item.locationDetail = draft.locationDetail
            item.batchOrTicket = draft.batchOrTicket
            item.notes = draft.notes
            item.isExample = entry.isExample
            context.insert(item)
            item.entry = entry
            item.supplier = draft.supplier
        }
    }
}
