import Foundation
import SwiftData

/// "Explore with examples": a small household that shows every part of the app.
/// Everything it creates is tagged `isExample`, never schedules real reminders,
/// and goes away with `removeExamples()`. Data is made up; no real people,
/// plates or identifiers. The household itself is declared once, as data, in
/// `ExampleHousehold`, which the Android app loads too.
@MainActor
public struct ExampleDataService {
    public let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    public init(context: ModelContext, calendar: Calendar = .dosar, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    /// Loads the examples on a screen's behalf, the one way screens do: on a binder that syncs,
    /// the store opens again without iCloud first and the container that synced is gone before
    /// anything is written (`PersistenceController.loadingExamples`), so no example ever reaches
    /// the person's other devices; the binder waits on this phone until they go. Refused while
    /// the person's binder may still be coming down from iCloud
    /// (`PersistenceController.examplesMayLoad`).
    public static func loadExamples(from context: ModelContext) async throws {
        let persistence = PersistenceController.shared
        guard persistence.container === context.container else {
            return try ExampleDataService(context: context).loadExamples()
        }
        try await persistence.loadingExamples { container in
            try ExampleDataService(context: container.mainContext).loadExamples()
        }
    }

    public func hasExamples() throws -> Bool {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    /// Adds the example household, in one save: a failure part-way leaves no half
    /// household behind. Does nothing if examples are already there.
    public func loadExamples() throws {
        guard try !hasExamples() else { return }
        let store = TemplateStore(context: context)
        try store.installBuiltIns()
        try UnitOfWork.perform(in: context, now: now()) { try addExampleHousehold(store: store) }
    }

    /// Makes the household's steps (`ExampleHousehold.standard`) in order, each through its
    /// action, every record marked as an example. A step naming a section that wasn't made (its
    /// category isn't in the binder) is left out with it.
    private func addExampleHousehold(store: TemplateStore) throws {
        var made = Made(templates: try store.templatesByKey())
        for step in ExampleHousehold.standard.steps {
            switch step {
            case .section(let section): try make(section, in: &made)
            case .firm(let firm): try make(firm, in: &made)
            case .record(let record): try make(record, in: made)
            case .pastCompletion(let completion): try make(completion, in: made)
            case .reading(let reading): try make(reading, in: made)
            }
        }
    }

    /// What the loader has made so far, by the refs the household's steps use.
    private struct Made {
        let templates: [String: CategoryTemplate]
        var sections: [String: Asset] = [:]
        var firms: [String: Provider] = [:]
    }

    private var assets: AssetActions { AssetActions(context: context, calendar: calendar, now: now) }

    /// The moment `days` days from now, at the same time of day in the app's calendar.
    private func moment(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: now()) ?? now() }

    private func make(_ section: ExampleHousehold.Section, in made: inout Made) throws {
        guard let template = made.templates[section.category] else { return }
        let parent = section.parent.map { made.sections[$0] }
        // Filed under a section that wasn't made: left out with it.
        if case .some(.none) = parent { return }
        let today = CalendarDay(now(), calendar: calendar)
        var values = FieldValues()
        for (key, value) in section.values { values[key] = value.value(on: today, calendar: calendar) }
        let planned = assets.plannedObligations(for: template, values: values).map { planned in
            var planned = planned
            if let offset = section.firstDue[planned.blueprint.key] { planned.firstDue = today.adding(days: offset, calendar: calendar) }
            // The add flow's rule, with the example's own dates given.
            planned.isSelected = PlannedObligation.startsSelected(planned.blueprint, firstDue: planned.firstDue)
            return planned
        }
        made.sections[section.ref] = try assets.create(name: section.name, template: template, values: values,
                                                       obligations: planned, parent: parent ?? nil, isExample: true)
    }

    private func make(_ firm: ExampleHousehold.Firm, in made: inout Made) throws {
        let linked = firm.linkedTo.compactMap { made.sections[$0] }
        guard linked.count == firm.linkedTo.count else { return }
        let providers = ProviderActions(context: context, now: now)
        let provider = try providers.create(name: firm.name, trades: firm.trades, phone: firm.phone, linkedTo: linked)
        if let rating = firm.rating { try providers.setRating(provider, rating) }
        if let again = firm.wouldCallAgain { try providers.setWouldCallAgain(provider, again) }
        made.firms[firm.ref] = provider
    }

    private func make(_ record: ExampleHousehold.Record, in made: Made) throws {
        guard let section = made.sections[record.section] else { return }
        try HistoryActions(context: context, now: now).record(
            on: section, kind: record.kind, title: record.title, occurredAt: moment(record.daysFromNow),
            metricReading: record.metricReading, totalCost: record.totalCost,
            items: record.items.map { LineItemDraft(name: $0.name, partBrandOrCode: $0.partBrandOrCode, cost: $0.cost) },
            providers: record.firms.compactMap { made.firms[$0] }, rating: record.rating, asExample: true
        )
    }

    /// A completion from before the binder knew the deadline, logged without moving the deadline.
    private func make(_ completion: ExampleHousehold.PastCompletion, in made: Made) throws {
        let deadlines = made.sections[completion.section]?.obligations ?? []
        guard let obligation = deadlines.first(where: { $0.blueprintKey == completion.deadline }) else { return }
        try ObligationActions(context: context, calendar: calendar, now: now)
            .recordPastCompletion(of: obligation, on: moment(completion.daysFromNow), cost: completion.cost)
    }

    private func make(_ reading: ExampleHousehold.Reading, in made: Made) throws {
        guard let section = made.sections[reading.section] else { return }
        try assets.recordMeasurement(on: section, kind: reading.kind, name: reading.name, value: reading.value,
                                     at: moment(reading.daysFromNow), asExample: true)
    }

    /// Deletes everything created by `loadExamples()` in one save. Only examples go:
    /// anything of the person's is never touched. Returns the example sections kept
    /// because something of the person's sits in them (from before the app asked);
    /// they become the person's, so the screen can say so. Undoable: the receipt brings
    /// every example back with its links, and the kept ones become examples again.
    @discardableResult
    public func removeExamples() throws -> Undoable<[String]> {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            var kept: [String] = []
            // Each example from its top: one that holds something of the person's becomes
            // theirs with everything under it; every other example goes.
            let examples = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample }))
            for asset in examples where asset.isExample && asset.parent?.isExample != true && Self.holdsSomethingReal(asset) {
                kept.append(asset.name)
                Self.makeReal(asset)
            }
            for asset in examples where asset.isExample { RecordContents.delete(asset, in: context) }
            // Example records that don't hang off an asset.
            // People who worked on a kept section were made the person's with it.
            for provider in try context.fetch(FetchDescriptor<Provider>(predicate: #Predicate { $0.isExample })) where provider.isExample {
                context.delete(provider)
            }
            for obligation in try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.isExample })) where obligation.asset == nil {
                context.delete(obligation)
            }
            try HouseholdRules.reconcile(in: context, today: CalendarDay(now(), calendar: calendar), calendar: calendar)
            try UnitOfWork.save(context, now: now())
            return kept
        }
    }

    /// "Da" to "Păstrezi … ca al tău?": the example section and everything in it
    /// become the person's. Removing examples never touches them again.
    public func adopt(sectionID: UUID) throws {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == sectionID })
        descriptor.fetchLimit = 1
        guard let section = try context.fetch(descriptor).first else { return }
        // The whole example it sits in, so nothing of it is left to be removed with the examples.
        let root = ExampleOwnership.exampleSection(containing: section) ?? section
        try UnitOfWork.perform(in: context, now: now()) {
            Self.makeReal(root)
            try UnitOfWork.save(context, now: now())
        }
    }

    /// Whether anything in `asset`, or under it, isn't an example.
    static func holdsSomethingReal(_ asset: Asset) -> Bool {
        tree(of: asset).contains { node in
            !node.isExample
                || (node.obligations ?? []).contains { !$0.isExample }
                || (node.history ?? []).contains { !$0.isExample }
                || (node.attachments ?? []).contains { !$0.isExample }
                || (node.measurements ?? []).contains { !$0.isExample }
        }
    }

    /// Clears the example mark on `asset`, everything under it and the people who worked on it.
    static func makeReal(_ asset: Asset) {
        for node in tree(of: asset) {
            node.isExample = false
            for obligation in node.obligations ?? [] { obligation.isExample = false }
            for entry in node.history ?? [] {
                entry.isExample = false
                for item in entry.items ?? [] { item.isExample = false }
            }
            for attachment in node.attachments ?? [] { attachment.isExample = false }
            for log in node.measurements ?? [] { log.isExample = false }
            for provider in node.providers ?? [] { provider.isExample = false }
        }
    }

    /// `asset` and everything under it.
    private static func tree(of asset: Asset) -> [Asset] {
        var result: [Asset] = []
        var queue = [asset]
        var seen = Set<UUID>()
        while let node = queue.popLast() {
            guard seen.insert(node.id).inserted else { continue }
            result.append(node)
            queue += node.children ?? []
        }
        return result
    }
}
