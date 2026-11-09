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

    /// Logs one record (a repair, a purchase, a bill) in the section's history, with its line
    /// items and the counter reading it read, in one save. A lower counter asks before
    /// anything is written (`LowerReadingQuestion`, answered with `lowerReading`).
    ///
    /// `replacing` is the entry the same document logged when it was filed before (a bill
    /// filed again): that entry takes these values instead of a second one being added, and
    /// moves to `asset` if the document did. Never a completion, which belongs to its deadline.
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
        lowerReading: LowerReadingAnswer? = nil,
        replacing earlier: HistoryEntry? = nil
    ) throws -> HistoryEntry {
        // Every question first, before anything is written (`StepQuestion`).
        let isExample = try ExampleOwnership.requireReal(asset, creatingExample: asExample)
        let date = occurredAt ?? now()
        let earlier = Self.replaceable(earlier)
        let reading = plannedReading(metricReading, on: asset, at: date, replacing: earlier)
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        return try UnitOfWork.perform(in: context) {
            let entry = entryToWrite(replacing: earlier, kind: kind, title: title, on: date, in: asset)
            entry.metricReading = metricReading
            entry.totalCost = totalCost
            entry.note = note
            entry.rating = rating.map { min(max($0, 1), 5) }
            entry.isExample = isExample
            entry.providers = providers
            HouseholdMutations.addItems(items, to: entry, in: context)
            if let reading {
                try HouseholdMutations.recordReading(reading, answer: lowerReading, isExample: isExample, in: context)
            }
            try save()
            return entry
        }
    }

    /// The reading a record or a visit logs with its counter (`metricReading`, the odometer):
    /// in the section's hero unit, on its day. Asked about before the step's unit opens, by
    /// the action and by a flow that files a visit inside a larger step (`CaptureFiler`).
    /// `replacing`'s own reading doesn't count against it: the step takes it away first.
    func plannedReading(_ value: Double?, on asset: Asset, at date: Date, source: ReadingSource = .person,
                        replacing earlier: HistoryEntry? = nil) -> PlannedReading? {
        guard let value else { return nil }
        let template = (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil
        let unit = template.flatMap { HouseholdMutations.heroMetricUnit(template: $0.definition) }
        let earlier = Self.replaceable(earlier)
        return PlannedReading(value, on: asset, at: date, source: source, unit: unit) { log in
            earlier.map { HouseholdMutations.isReading(log, recordedBy: $0) } ?? false
        }
    }

    /// An entry a document logged that filing it again may take over: never a completion.
    private static func replaceable(_ entry: HistoryEntry?) -> HistoryEntry? {
        entry.flatMap { $0.isDeleted || $0.isCompletion ? nil : $0 }
    }

    /// A new entry in `asset`'s history, or `earlier` cleared to be written again: its line
    /// items and the reading it recorded go, and it moves to `asset` and `date`.
    private func entryToWrite(replacing earlier: HistoryEntry?, kind: HistoryKind, title: String, on date: Date, in asset: Asset) -> HistoryEntry {
        guard let entry = earlier else {
            let entry = HistoryEntry(kind: kind, title: title, occurredAt: date)
            context.insert(entry)
            entry.asset = asset
            return entry
        }
        HouseholdMutations.removeReading(recordedBy: entry, in: context)
        for item in entry.items ?? [] { context.delete(item) }
        entry.items = []
        entry.kind = kind
        entry.title = title
        entry.occurredAt = date
        entry.asset = asset
        return entry
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
    /// The receipt takes it all back ("Anulează vizita"). A lower odometer asks before
    /// anything is written (`LowerReadingQuestion`, answered with `lowerReading`).
    ///
    /// `replacing` is the visit the same invoice was filed with before: it takes these
    /// values, line items and reading instead of a second visit being added.
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
        lowerReading: LowerReadingAnswer? = nil,
        replacing earlier: HistoryEntry? = nil
    ) throws -> Undoable<HistoryEntry> {
        // Every question first, before anything is written (`StepQuestion`).
        let isExample = try ExampleOwnership.requireReal(asset)
        let date = occurredAt ?? now()
        let earlier = Self.replaceable(earlier)
        let reading = plannedReading(odometer, on: asset, at: date, source: odometerSource, replacing: earlier)
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        return try UnitOfWork.performUndoable(in: context) {
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
            let entry = entryToWrite(replacing: earlier, kind: kind, title: title ?? Self.visitTitle(for: items), on: date, in: asset)
            entry.metricReading = odometer
            entry.totalCost = totalCost
            entry.rating = rating.map { min(max($0, 1), 5) }
            entry.isExample = isExample
            entry.providers = provider.map { [$0] } ?? []
            HouseholdMutations.addItems(items, to: entry, in: context)
            if let reading {
                try HouseholdMutations.recordReading(reading, answer: lowerReading, isExample: isExample, in: context)
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

    /// Deletes a record from Istoric, as `HistoryDeletion` describes: its line items and the
    /// reading it recorded go with it, the documents filed with it stay in the binder, and
    /// a completion moves its deadline back only when it's the latest one. This is for an
    /// older record; the step just taken is undone with its receipt.
    public func delete(_ entry: HistoryEntry) throws {
        let effect = HistoryDeletion(of: entry)
        try UnitOfWork.perform(in: context) {
            if let reopened = effect.reopensCycle, let obligation = entry.obligation {
                obligation.dueDate = reopened
                obligation.dueMetric = entry.previousDueMetric
                if obligation.status == .done {
                    obligation.status = entry.previousStatusRaw.flatMap(ObligationStatus.init(rawValue:)) ?? .active
                }
                obligation.updatedAt = now()
            }
            if effect.removedReading != nil { HouseholdMutations.removeReading(recordedBy: entry, in: context) }
            for attachment in entry.attachments ?? [] { attachment.historyEntry = nil }
            context.delete(entry)
            try save()
        }
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
