import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A backup carries every stored property of every record, and a backup brought in merges
/// every kind of record by one rule: the copy that changed later. The lists of properties
/// come from the models themselves (`storedProperties`), so a property added later can't be
/// forgotten by the archive without these failing.
@MainActor
@Suite("One merge rule, every stored property")
struct ArchiveMergeTests {
    let calendar = Calendar.bucharest

    // MARK: A household with every stored property set

    /// One record or more of every type, with every stored property set to something other
    /// than a new record's, so a property the archive forgets can't pass by being a default.
    @MainActor
    struct Household {
        let container: ModelContainer
        let context: ModelContext
        let boats: CategoryTemplate
        let boat: Asset
        let engine: Asset
        let service: Obligation
        let repair: HistoryEntry
        let impeller: ServiceItem
        let hours: MeasurementLog
        let firm: Provider
        let invoice: DosarCuSina.Attachment
        let oldInvoice: DosarCuSina.Attachment

        /// Long enough ago that no import takes it for a time later than now.
        static let then = noon("2025-06-01")

        static func make(calendar: Calendar) throws -> Household {
            let container = try makeInMemoryContainer()
            let context = ModelContext(container)
            try TemplateStore(context: context).installBuiltIns()
            let then = Self.then

            let boats = CategoryTemplate(definition: TemplateDefinition(
                key: "custom.\(UUID().uuidString.lowercased())", name: "Bărci", summary: "Ambarcațiuni de agrement",
                symbol: "sailboat.fill", tint: .teal, heroStyle: .vehicle, isOnHomeByDefault: false, isSensitiveByDefault: true,
                sections: [FieldSection(key: "boat.main", title: "Barcă", fields: [
                    FieldDefinition(key: "boat.registration", label: "Înmatriculare", type: .text, role: .identifier, isEssential: true),
                    FieldDefinition(key: "boat.hours", label: "Ore motor", type: .metric, role: .heroMetric, unit: .engineHours),
                ])],
                blueprints: [ObligationBlueprint(key: "boat.engine", title: "Service motor", kind: .maintenance,
                                                 recurrence: .metric(every: 100, unit: .engineHours, fallback: .years(1)))],
                components: [ComponentDefinition(key: "engine.impeller", name: "Rotor pompă", group: "Motor")],
                pockets: [.upcoming, .history, .keyFacts],
                behavior: CategoryBehavior(box: .wholeCategory, listing: .byWarranty, offerTitle: "Barcă"),
                version: 0
            ), isBuiltIn: false, homeOrder: 40)
            context.insert(boats)

            let boat = Asset(name: "Barca de pe lac", templateKey: boats.key,
                             values: FieldValues(["boat.registration": .text("RO-EXEMPLU-01"), "boat.hours": .number(210)]),
                             notes: "La ponton din aprilie.", isExample: true)
            boat.symbolOverride = "ferry.fill"
            boat.tintOverrideRaw = TemplateTint.mint.rawValue
            boat.photoData = Data([0xFF, 0xD8, 0xFF, 0x01])
            boat.customFacts = [CustomFact(label: "Loc în port", value: "Ponton 3, locul 12", isSensitive: true)]
            let engine = Asset(name: "Motor exemplu", templateKey: BuiltInTemplates.Key.other)
            context.insert(boat)
            context.insert(engine)
            engine.parent = boat

            let service = Obligation(title: "Service motor", kind: .legal, dueDay: CalendarDay("2025-09-01"),
                                     recurrence: .metric(every: 100, unit: .engineHours, fallback: .years(1)),
                                     reminders: ReminderProfile(leadDays: [60, 14, 0], consequence: .financial, graceDays: 5,
                                                                followUpAfterLapse: true, travelMarginDays: 30),
                                     estimatedCost: Money(Decimal(350), currency: "EUR"))
            service.notes = "Cu filtrul de combustibil."
            service.blueprintKey = "boat.engine"
            service.dueMetric = 300
            service.remindersCustomized = true
            service.reminderMinuteOfDay = 540
            service.provider = "Service nautic exemplu"
            service.reference = "POL-000002"
            service.statusRaw = ObligationStatus.paused.rawValue
            service.snoozedUntil = CalendarDay("2025-08-20")
            service.isExample = true
            // What a newer build wrote in its reminders, beside what this one reads.
            service.keptReminders = try JSONDecoder().decode(KeptObject<ReminderProfile>.self, from: Data(
                #"{"consequence":"financial","followUpAfterLapse":true,"graceDays":5,"leadDays":[60,14,0],"quietHours":{"from":22,"to":7},"travelMarginDays":30}"#.utf8
            ))
            context.insert(service)
            service.asset = boat

            let firm = Provider(name: "Service nautic exemplu")
            firm.trades = [ProviderTrade.mechanic.rawValue, "boatyard"]
            firm.phone = "0700 000 000"
            firm.email = "nume@exemplu.ro"
            firm.address = "Str. Exemplului 1, București"
            firm.notes = "Lucrează doar vara."
            firm.manualRating = 4
            firm.wouldCallAgain = true
            firm.taxID = "12345678"
            firm.isExample = true
            context.insert(firm)
            firm.assets = [boat]

            let repair = HistoryEntry(kind: .repair, title: "Rotor pompă nou", occurredAt: noon("2025-05-20"))
            repair.metricReading = 205
            repair.totalCost = Money(Decimal(string: "560.5")!, currency: "EUR")
            repair.note = "Garanție un an."
            repair.reference = "EXM 0000001"
            repair.rating = 4
            repair.cycleDueDay = CalendarDay("2025-05-01")
            repair.nextDueDay = CalendarDay("2025-09-01")
            repair.previousStatusRaw = ObligationStatus.active.rawValue
            repair.previousDueMetric = 200
            repair.isExample = true
            context.insert(repair)
            repair.asset = boat
            repair.obligation = service
            repair.providers = [firm]

            let impeller = ServiceItem(name: "Rotor pompă apă", componentKey: "engine.impeller")
            impeller.group = "Motor"
            impeller.partBrandOrCode = "Exemplu 47-12345"
            impeller.partSerialNumber = "SN-0001"
            impeller.costAmount = 300
            impeller.laborCostAmount = 200
            impeller.partsCostAmount = 100
            impeller.currency = "EUR"
            impeller.batchOrTicket = "LOT-01"
            impeller.locationDetail = "Babord"
            impeller.daysInService = 3
            impeller.warrantyMonths = 12
            impeller.notes = "Original."
            impeller.isExample = true
            context.insert(impeller)
            impeller.entry = repair
            impeller.supplier = firm

            let hours = MeasurementLog(kind: .engineHours, name: "Ore motor", value: 210, recordedAt: noon("2025-05-20"))
            hours.secondaryValue = 1
            hours.unitPriceAmount = Decimal(string: "1.5")
            hours.unitPriceCurrency = "EUR"
            hours.isSelfRead = false
            hours.referenceMin = 0
            hours.referenceMax = 5_000
            hours.source = "Ceasul de bord"
            hours.notes = "Citit la ponton."
            hours.isExample = true
            hours.startsCounter = true
            context.insert(hours)
            hours.asset = boat

            let oldInvoice = DosarCuSina.Attachment(id: UUID(), fileName: "factura-veche.pdf", contentType: "com.adobe.pdf",
                                                    data: Data("%PDF-1.7 veche".utf8), kind: .invoice)
            oldInvoice.isArchived = true
            let invoice = DosarCuSina.Attachment(id: UUID(), fileName: "factura.pdf", contentType: "com.adobe.pdf",
                                                 data: Data("%PDF-1.7 nouă".utf8), kind: .invoice)
            invoice.title = "Factură rotor"
            invoice.thumbnailData = Data([9, 9])
            invoice.byteCount = 42
            invoice.extractedText = "Factura nr. EXM 0000001, total 560,50 EUR"
            invoice.documentDay = CalendarDay("2025-05-20")
            invoice.validUntil = CalendarDay("2026-05-20")
            invoice.framing = DocumentFraming(pages: [PageFraming(quarterTurns: 1), PageFraming(prefersWholePhoto: true)])
            invoice.createdAt = noon("2025-05-21")
            invoice.isExample = true
            context.insert(oldInvoice)
            context.insert(invoice)
            for (index, bytes) in [Data([1, 2, 3]), Data([4, 5])].enumerated() {
                let page = AttachmentPage(index: index, imageData: bytes)
                context.insert(page)
                page.attachment = invoice
            }
            invoice.asset = boat
            invoice.obligation = service
            invoice.historyEntry = repair
            invoice.serviceItem = impeller
            invoice.measurement = hours
            invoice.provider = firm
            oldInvoice.asset = boat
            oldInvoice.supersededBy = invoice

            // Every change time and creation time set, long enough ago.
            for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) {
                template.createdAt = then
                template.updatedAt = then
            }
            for record in [boat, engine] as [Asset] { record.createdAt = then; record.updatedAt = then }
            service.createdAt = then
            service.updatedAt = then
            firm.createdAt = then
            firm.updatedAt = then
            repair.updatedAt = then
            impeller.updatedAt = then
            hours.updatedAt = then
            invoice.updatedAt = then
            oldInvoice.updatedAt = then
            oldInvoice.createdAt = noon("2025-01-10")
            try context.save()
            return Household(container: container, context: context, boats: boats, boat: boat, engine: engine, service: service,
                             repair: repair, impeller: impeller, hours: hours, firm: firm, invoice: invoice, oldInvoice: oldInvoice)
        }
    }

    // MARK: Every stored property travels

    @Test("Export, import into an empty phone, and every stored property of every record is as it was")
    func everyStoredPropertyTravels() throws {
        let household = try Household.make(calendar: calendar)
        let source = try Self.store(household.context)

        // The household really sets every property that travels, so none passes as a default.
        for (type, records) in source {
            let blank = try #require(Self.blankStates[type], "\(type) has a blank record")
            let local = DossierV3.stayOnThePhone[type] ?? []
            for name in blank.values.keys where !local.contains(name) {
                #expect(records.values.contains { $0.values[name] != blank.values[name] },
                        "\(type).\(name) is set in the test household to something a new record doesn't have")
            }
        }

        let data = try DossierArchiveService(container: household.container, calendar: calendar).exportData(exportedAt: noon("2025-06-02"))
        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: calendar).importArchive(data, mode: .replace)

        let differences = Self.differences(source, try Self.store(ModelContext(target)))
        #expect(differences.isEmpty, "Different after the trip: \(differences)")
    }

    @Test func whatStaysOnThePhoneNamesRealProperties() {
        for (type, names) in DossierV3.stayOnThePhone {
            let known = Set(Self.blankStates[type]?.values.keys.map { $0 } ?? [])
            #expect(names.isSubset(of: known), "\(type) has \(names.subtracting(known))")
        }
    }

    // MARK: Merging every kind of record

    @Test("Each kind of record changed on the other phone comes in; changed here, it stays")
    func everyKindOfRecordMergesByTheSameRule() throws {
        let other = try Household.make(calendar: calendar)
        let otherService = DossierArchiveService(container: other.container, calendar: calendar)
        let here = try makeInMemoryContainer()
        let hereService = DossierArchiveService(container: here, calendar: calendar)
        try hereService.importArchive(try otherService.exportData(), mode: .replace)
        #expect(Self.differences(try Self.store(other.context), try Self.store(ModelContext(here))).isEmpty)

        // On the other phone, one record of every kind changes, a document by a page of its own.
        other.boats.name = "Bărci și caiace"
        other.boat.notes = "Iernează în hangar."
        other.service.notes = "Și anodul."
        other.repair.note = "Garanție doi ani."
        other.impeller.notes = "Schimbat sub garanție."
        other.hours.notes = "Citit la hangar."
        other.firm.notes = "Lucrează și iarna."
        other.invoice.title = "Factură rotor, corectată"
        let page = AttachmentPage(index: 0, imageData: Data([7, 7]))
        other.context.insert(page)
        page.attachment = other.oldInvoice
        try UnitOfWork.save(other.context)
        let changed: [any ChangeTimed] = [other.boats, other.boat, other.service, other.repair, other.impeller, other.hours,
                                          other.firm, other.invoice, other.oldInvoice]
        for record in changed {
            #expect(record.updatedAt > Household.then, "\(record.recordKey) has a new change time")
        }
        #expect(other.engine.updatedAt == Household.then, "A section nothing changed in keeps its time")

        let archive = try otherService.exportData()
        let result = try hereService.importArchive(archive, mode: .merge)
        #expect(result.updated == changed.count)
        #expect(result.inserted == 0)
        let merged = Self.differences(try Self.store(other.context), try Self.store(ModelContext(here)))
        #expect(merged.isEmpty, "After the merge: \(merged)")

        // Here, the same records change again, later: the other phone's older copies don't win.
        let context = ModelContext(here)
        func find<M: UndoableRecord>(_ record: M) throws -> M { try #require(M.find(record.recordKey, in: context)) }
        try find(other.boats).name = "Bărcile noastre"
        try find(other.boat).notes = "Vândută."
        try find(other.service).notes = "Gata."
        try find(other.repair).note = "Fără garanție."
        try find(other.impeller).notes = "Returnat."
        try find(other.hours).notes = "Corectat."
        try find(other.firm).notes = "Închis."
        try find(other.invoice).title = "Factură rotor, a noastră"
        for page in try find(other.oldInvoice).pages ?? [] { context.delete(page) }
        try UnitOfWork.save(context)
        let ours = try Self.store(context)

        let again = try hereService.importArchive(archive, mode: .merge)
        #expect(again.updated == 0)
        #expect(Self.differences(ours, try Self.store(ModelContext(here))).isEmpty, "What changed here stays")
    }

    @Test("A backup that carries no change time for history, readings and documents never overwrites a change here")
    func anOlderBackupKeepsWhatChangedHere() throws {
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        let fixture = try Fixtures.archive("dosar-v3/household")
        try service.importArchive(fixture, mode: .replace)
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<HistoryEntry>())
        let withoutTime = try #require(entries.first { $0.title == "Frâne față" })
        #expect(withoutTime.updatedAt == ChangeTime.unknown, "An entry the archive carries no time for has none")
        let withTime = try #require(entries.first { $0.title == "ITP" })
        #expect(withTime.updatedAt == MachineText.moment("2026-03-01T07:45:00Z"))

        withoutTime.note = "Plăcuțe originale."
        withTime.note = "Corectat."
        let reading = try #require(try context.fetch(FetchDescriptor<MeasurementLog>()).first { $0.value == 210 })
        reading.notes = "Citit din nou."
        try UnitOfWork.save(context)

        let result = try service.importArchive(fixture, mode: .merge)
        #expect(result.updated == 0)
        let after = ModelContext(container)
        let notes = Set(try after.fetch(FetchDescriptor<HistoryEntry>()).compactMap(\.note))
        #expect(notes.isSuperset(of: ["Plăcuțe originale.", "Corectat."]))
        #expect(try after.fetch(FetchDescriptor<MeasurementLog>()).contains { $0.notes == "Citit din nou." })
    }

    @Test func theRuleIsTheSameForEveryRecord() {
        let earlier = noon("2026-01-01")
        let later = noon("2026-02-01")
        #expect(ArchiveMerge.outcome(archive: later, here: nil) == .insert)
        #expect(ArchiveMerge.outcome(archive: later, here: earlier) == .update)
        #expect(ArchiveMerge.outcome(archive: earlier, here: later) == .keepHere)
        #expect(ArchiveMerge.outcome(archive: later, here: later) == .keepHere, "On a tie the phone's own copy stays")
        #expect(ArchiveMerge.outcome(archive: ChangeTime.unknown, here: ChangeTime.unknown) == .keepHere)
        #expect(ArchiveMerge.outcome(archive: earlier, here: ChangeTime.unknown) == .update, "Any change is newer than an unknown time")
    }

    // MARK: Helpers

    /// Every record of every type, by the key it is known by in any store: its id, a
    /// category's key, a page's document and place.
    static func store(_ context: ModelContext) throws -> [String: [String: RecordState]] {
        let fresh = ModelContext(context.container)
        var all: [String: [String: RecordState]] = [:]
        for (name, type) in UndoableRecords.types {
            let found: [RecordState] = try states(of: type, in: fresh)
            var byKey: [String: RecordState] = [:]
            for state in found where byKey[key(of: state)] == nil { byKey[key(of: state)] = state }
            all[name] = byKey
        }
        return all
    }

    private static func states<M: UndoableRecord>(of type: M.Type, in context: ModelContext) throws -> [RecordState] {
        try context.fetch(FetchDescriptor<M>()).map { RecordState.capture($0) }
    }

    private static func key(of state: RecordState) -> String {
        guard state.ref.type == "AttachmentPage" else { return state.ref.key }
        guard case .one(let document)? = state.values["attachment"], case .attribute(let index)? = state.values["index"] else { return state.ref.key }
        return "\(document?.key ?? "-")#\(index)"
    }

    /// A new, empty record of every type, as it would be made.
    static var blankStates: [String: RecordState] {
        var states: [String: RecordState] = [:]
        for (name, type) in UndoableRecords.types {
            let state: RecordState = blank(type)
            states[name] = state
        }
        return states
    }

    private static func blank<M: UndoableRecord>(_ type: M.Type) -> RecordState {
        RecordState.capture(M.blank())
    }

    /// The records and properties that differ, but for what never leaves a phone. Times are
    /// compared to the second, as archives write them; JSON is compared as JSON.
    static func differences(_ a: [String: [String: RecordState]], _ b: [String: [String: RecordState]]) -> [String] {
        var found: [String] = []
        for type in Set(a.keys).union(b.keys).sorted() {
            let left = a[type] ?? [:]
            let right = b[type] ?? [:]
            let local = DossierV3.stayOnThePhone[type] ?? []
            for key in Set(left.keys).union(right.keys).sorted() {
                guard let l = left[key], let r = right[key] else {
                    found.append("\(type) \(key) is only on one side")
                    continue
                }
                for name in Set(l.values.keys).union(r.values.keys).sorted() where !local.contains(name) {
                    if type == "Attachment", name == "pages" {
                        if l.values[name]?.refs.count != r.values[name]?.refs.count { found.append("\(type) \(key).pages") }
                        continue
                    }
                    if !same(l.values[name], r.values[name]) { found.append("\(type) \(key).\(name)") }
                }
            }
        }
        return found
    }

    private static func same(_ a: StoredValue?, _ b: StoredValue?) -> Bool {
        guard case .attribute(let x)? = a, case .attribute(let y)? = b else { return a == b }
        if let dx = x.base as? Date, let dy = y.base as? Date {
            return dx.timeIntervalSinceReferenceDate.rounded(.down) == dy.timeIntervalSinceReferenceDate.rounded(.down)
        }
        if let dx = x.base as? Data, let dy = y.base as? Data,
           let jx = try? JSONDecoder().decode(JSONValue.self, from: dx), let jy = try? JSONDecoder().decode(JSONValue.self, from: dy) {
            return jx == jy
        }
        return x == y
    }
}
