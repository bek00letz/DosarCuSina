import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The same binder on two devices has the same ids, and iCloud brings both devices' records: two
/// copies of each. They become one, the same one on every device, with everything that pointed
/// at either (`RecordsMeet`).
@MainActor
@Suite("Records that share an id")
struct RecordsMeetTests {
    /// Copy names that sort as written.
    private static let low = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let high = UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000002")!

    /// One device's copy of a small household: a car with a deadline, a visit done by a firm with
    /// a part and its invoice (one page), and a reading.
    private struct Copy {
        let car: Asset, rca: Obligation, visit: HistoryEntry, part: ServiceItem, km: MeasurementLog
        let invoice: DosarCuSina.Attachment, page: AttachmentPage, firm: Provider

        var all: [any UndoableRecord] { [car, rca, visit, part, km, invoice, page, firm] }

        /// Ids every device shares.
        struct IDs {
            let car = UUID(), rca = UUID(), visit = UUID(), part = UUID(), km = UUID(), invoice = UUID(), firm = UUID()
        }

        static func make(_ ids: IDs, carName: String, in context: ModelContext) -> Copy {
            let car = Asset(id: ids.car, name: carName, templateKey: BuiltInTemplates.Key.vehicle)
            let rca = Obligation(id: ids.rca, title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-07-15"))
            let visit = HistoryEntry(id: ids.visit, kind: .repair, title: "Plăcuțe de frână", occurredAt: noon("2026-10-01"))
            let part = ServiceItem(id: ids.part, name: "Plăcuțe față")
            let km = MeasurementLog(id: ids.km, kind: .custom, name: "Kilometraj", value: 120_000)
            let invoice = DosarCuSina.Attachment(id: ids.invoice, fileName: "factura.pdf", contentType: "com.adobe.pdf", data: nil, kind: .invoice)
            let page = AttachmentPage(index: 0, imageData: Data([1, 2, 3]))
            let firm = Provider(id: ids.firm, name: "Service Exemplu SRL", trades: [.mechanic])
            for record in [car, rca, visit, part, km, invoice, page, firm] as [any PersistentModel] { context.insert(record) }
            rca.asset = car
            visit.asset = car
            visit.obligation = rca
            visit.providers = [firm]
            part.entry = visit
            part.supplier = firm
            km.asset = car
            invoice.asset = car
            invoice.historyEntry = visit
            invoice.provider = firm
            page.attachment = invoice
            firm.assets = [car]
            return Copy(car: car, rca: rca, visit: visit, part: part, km: km, invoice: invoice, page: page, firm: firm)
        }

        func name(_ copyID: UUID) {
            for record in all { record.copyID = copyID }
        }
    }

    private func count<M: PersistentModel>(_ type: M.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<M>())
    }

    @Test("Two copies of every kind of record become one, with every link, whichever copy stays", arguments: [false, true])
    func everyKindOfRecordWithOneIDBecomesOne(theOtherDevicesCopyStays: Bool) throws {
        let context = try makeContext()
        let ids = Copy.IDs()
        // This device's copy, then the other device's, newer: the car was renamed there.
        let mine = Copy.make(ids, carName: "VW Golf 2018", in: context)
        let theirs = Copy.make(ids, carName: "VW Golf 2018 alb", in: context)
        mine.name(theOtherDevicesCopyStays ? Self.high : Self.low)
        theirs.name(theOtherDevicesCopyStays ? Self.low : Self.high)
        // Something only the other device has: a later visit by the same firm, on its copy of the car.
        let later = HistoryEntry(kind: .maintenance, title: "Revizie", occurredAt: noon("2026-11-01"))
        context.insert(later)
        later.asset = theirs.car
        later.providers = [theirs.firm]
        try context.save()
        for (records, time) in [(mine.all, noon("2026-10-01")), (theirs.all, noon("2026-10-02"))] {
            for case let record as any ChangeTimed in records { record.updatedAt = time }
        }
        try context.save()

        #expect(try RecordsMeet.join(in: context))

        #expect(try count(Asset.self, in: context) == 1)
        #expect(try count(Obligation.self, in: context) == 1)
        #expect(try count(HistoryEntry.self, in: context) == 2, "The visit once, and the later one")
        #expect(try count(ServiceItem.self, in: context) == 1)
        #expect(try count(MeasurementLog.self, in: context) == 1)
        #expect(try count(DosarCuSina.Attachment.self, in: context) == 1)
        #expect(try count(AttachmentPage.self, in: context) == 1, "The document's pages are the newer copy's, once")
        #expect(try count(Provider.self, in: context) == 1)

        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        #expect(car.copyID == Self.low, "The copy with the smallest name stays, on every device")
        #expect(car.name == "VW Golf 2018 alb", "With the newer copy's values")
        #expect(car.updatedAt == noon("2026-10-02"), "And its change time: no new one is given")
        let rca = try #require(car.obligations?.first)
        let visit = try #require(car.history?.first { $0.id == ids.visit })
        let firm = try #require(try context.fetch(FetchDescriptor<Provider>()).first)
        let invoice = try #require(car.attachments?.first)
        #expect(car.history?.count == 2)
        #expect(car.measurements?.count == 1)
        #expect(visit.obligation === rca)
        #expect(visit.items?.count == 1)
        #expect(visit.items?.first?.supplier === firm)
        #expect(visit.providers?.map(\.id) == [firm.id])
        #expect(invoice.historyEntry === visit)
        #expect(invoice.provider === firm)
        #expect(invoice.pages?.count == 1)
        #expect(firm.assets?.map(\.id) == [car.id])
        let laterNow = try #require(car.history?.first { $0.id == later.id })
        #expect(laterNow.providers?.first === firm, "What pointed at the copy that went points at the one that stays")

        #expect(try !RecordsMeet.join(in: context), "Once joined, nothing more to do")
    }

    @Test("Two devices joining at once keep the same copy, even when one hasn't seen the other's change yet")
    func twoDevicesDecideTheSame() throws {
        let id = UUID()
        func device(seesTheEdit: Bool, insertsTheirsFirst: Bool) throws -> ModelContext {
            let context = try makeContext()
            let first = Provider(id: id, name: "Service Exemplu SRL", trades: [.mechanic])
            let second = Provider(id: id, name: "Service Exemplu SRL", trades: [.mechanic])
            let (named, other) = insertsTheirsFirst ? (second, first) : (first, second)
            context.insert(other)
            context.insert(named)
            named.copyID = Self.high
            other.copyID = Self.low
            try context.save()
            named.updatedAt = noon("2026-10-01")
            other.updatedAt = noon("2026-10-01")
            if seesTheEdit {
                named.phone = "0721 000 000"
                named.updatedAt = noon("2026-10-05")
            }
            try context.save()
            return context
        }
        let phone = try device(seesTheEdit: true, insertsTheirsFirst: false)
        let pad = try device(seesTheEdit: false, insertsTheirsFirst: true)
        try RecordsMeet.join(in: phone)
        try RecordsMeet.join(in: pad)

        let onPhone = try phone.fetch(FetchDescriptor<Provider>())
        let onPad = try pad.fetch(FetchDescriptor<Provider>())
        #expect(onPhone.count == 1 && onPad.count == 1)
        #expect(onPhone.map(\.copyID) == [Self.low] && onPad.map(\.copyID) == [Self.low], "Both keep the same copy, so neither deletes the other's")
        #expect(onPhone.map(\.id) == [id] && onPad.map(\.id) == [id])
        #expect(onPhone.first?.phone == "0721 000 000", "The newer copy's detail is kept where it was seen, and syncs from there")
    }

    @Test("A copy from before version 13 is named only by the device that made it, and joins once every copy is named")
    func copiesFromBeforeWaitForTheirDevice() throws {
        let folder = URL.temporaryDirectory.appending(path: "meet-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        let context = container.mainContext
        let id = UUID()

        // Made here before version 13: no name.
        let mine = Asset(id: id, name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(mine)
        mine.copyID = nil
        try context.save()
        // The other device's copy, brought by iCloud, not named there yet.
        let fromICloud = ModelContext(container)
        fromICloud.author = "NSCloudKitMirroringDelegate.import"
        let theirs = Asset(id: id, name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        fromICloud.insert(theirs)
        theirs.copyID = nil
        try fromICloud.save()

        try RecordsMeet.join(in: PersistenceController.context(in: container))
        let copies = try PersistenceController.context(in: container).fetch(FetchDescriptor<Asset>())
        #expect(copies.count == 2, "It waits for the other device to name its copy")
        #expect(copies.first { $0.persistentModelID == mine.persistentModelID }?.copyID != nil, "This device names its own")
        #expect(copies.first { $0.persistentModelID == theirs.persistentModelID }?.copyID == nil, "Never the other device's")

        // The other device names its copy, and that arrives.
        let arrived = try #require(try fromICloud.fetch(FetchDescriptor<Asset>()).first { $0.persistentModelID == theirs.persistentModelID })
        arrived.copyID = UUID()
        try fromICloud.save()
        try RecordsMeet.join(in: PersistenceController.context(in: container))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Asset>()) == 1)
    }

    @Test("Launch never stops on two copies of a firm, and keeps one")
    func launchKeepsGoingWithCopies() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let id = UUID()
        for _ in 0..<2 { context.insert(Provider(id: id, name: "Service Exemplu SRL", trades: [.mechanic])) }
        try context.save()

        // The repair list on its own, before any join: one firm by its id, nothing to offer.
        #expect(try CaptureRepairs(context: context).duplicateProviderCandidates().isEmpty)

        let failed = LaunchData.prepare(in: context, today: CalendarDay("2026-11-11"),
                                        repairs: DataRepairCenter(ledger: DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "meet-\(UUID().uuidString)")))))
        #expect(failed.isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Provider>()) == 1)
    }

    @Test("Two copies of a built-in category become one with the person's newer choices", arguments: [false, true])
    func builtInCopiesKeepThePersonsChoices(theirsStays: Bool) throws {
        let context = try makeContext()
        let key = BuiltInTemplates.Key.vehicle
        let mine = try #require(try TemplateStore(context: context).template(forKey: key))
        let definition = try #require(BuiltInTemplates.definition(for: key))
        let theirs = CategoryTemplate(definition: definition, isBuiltIn: true, homeOrder: 9)
        context.insert(theirs)
        theirs.isOnHome = false
        mine.copyID = theirsStays ? Self.high : Self.low
        theirs.copyID = theirsStays ? Self.low : Self.high
        try context.save()
        mine.updatedAt = ChangeTime.unknown
        theirs.updatedAt = noon("2026-04-01")
        try context.save()

        try RecordsMeet.join(in: context)
        let copies = try context.fetch(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == key }))
        let kept = try #require(copies.first)
        #expect(copies.count == 1)
        #expect(kept.copyID == Self.low)
        #expect(kept.homeOrder == 9, "The person's newer place")
        #expect(!kept.isOnHome)
        #expect(kept.builtInVersion == definition.version)
    }

    // MARK: Built-in categories between two versions

    @Test("Two app versions never write each other's built-in categories back and forth")
    func twoCatalogVersionsDontFight() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let newer = BuiltInTemplates.all.map { definition -> TemplateDefinition in
            var definition = definition
            definition.version += 1
            if definition.key == BuiltInTemplates.Key.vehicle { definition.name = "Vehicule" }
            return definition
        }
        // The other device runs a newer version; its categories arrive.
        #expect(try store.installBuiltIns(catalog: newer))
        for _ in 0..<3 {
            #expect(try !store.installBuiltIns(), "This version's older catalog leaves the newer one's categories as they are")
            #expect(try !store.installBuiltIns(catalog: newer), "And the newer one has nothing left to do")
        }
        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        #expect(vehicle.name == "Vehicule", "The newer catalog's definition stays")
        #expect(vehicle.builtInVersion == TemplateDefinition.builtInCatalogVersion + 1)
        #expect(try store.all().filter(\.isBuiltIn).allSatisfy { $0.builtInVersion == TemplateDefinition.builtInCatalogVersion + 1 })
    }

    @Test("Only the person's choices of a built-in category count as its change")
    func builtInChoicesStillCount() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        try store.setOnHome(vehicle, false)
        #expect(try !store.installBuiltIns(), "The same catalog writes nothing over the person's choice")
        #expect(!vehicle.isOnHome)
    }
}
