import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A frozen schema version must keep exactly the shape its stores have on people's
/// phones, or a migration can't recognise them. These pin each frozen version, and
/// prove a store written by the version before opens with everything in it.
@MainActor
struct SchemaMigrationTests {
    /// Each entity's version hash, as Core Data computes it, base64.
    static func fingerprint(_ models: [any PersistentModel.Type]) -> [String: String] {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else { return [:] }
        return model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }

    /// Version 2 as it shipped, read from the shipped models before version 3 existed.
    static let versionTwo: [String: String] = [
        "Asset": "58a6RIU1oRUxD3p2eFaJmRdPZEPsiXxOu/r0Cdbm4z0=",
        "Attachment": "zD/yZCgadMdd5p994OVXoj/NyBuzEO45epzaa4J6Wb8=",
        "AttachmentPage": "JuCkdlh81AVcycaJFrC8aBf8R7nkEg6kKyfUIOP9QdI=",
        "CategoryTemplate": "YVKd3GclUkHBd4xpJ54GbQx35yrBKhoQoEg89e2ScZo=",
        "HistoryEntry": "PuXnfDrnwWK/La9Ngj9fOIPjAGMOxeYuOxGRZz3Tz5o=",
        "MeasurementLog": "mIGxZoQpHOMXhYrVjhP+5Mo5Qa9Gh9Y4Dzk9+PZ4hwc=",
        "Obligation": "Xum2PE0uCd+kj/oD/bGcZ/ZZOPlFS2+2EGGSQUHwpL0=",
        "Provider": "Wau7/mbwtsfNfdHqO47ak8Kxm2f/2Y0i9Loq3oOPy4c=",
        "ServiceItem": "oLmMn8P7Qhm9kwaqXLTT6ppsedzdzLP99yAFaoqtgCw=",
    ]

    @Test func theFrozenVersionTwoKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV2.models) == Self.versionTwo)
    }

    /// Version 3 as it shipped: version 2 with a firm's tax ID, a category's behaviour and a
    /// paper's last valid day. Every entity but deadlines is pinned again by version 4 below,
    /// which was made from the shipped models.
    static let versionThree: [String: String] = [
        "Asset": "58a6RIU1oRUxD3p2eFaJmRdPZEPsiXxOu/r0Cdbm4z0=",
        "Attachment": "djPOkwOcI2y3EekaK6X63Ktf1r+QFW98LFYaEkrkrwE=",
        "AttachmentPage": "JuCkdlh81AVcycaJFrC8aBf8R7nkEg6kKyfUIOP9QdI=",
        "CategoryTemplate": "6ISuox65O5PR9u6cYpQ9MKBEqdCrUMgGOFTuEMpsZhg=",
        "HistoryEntry": "PuXnfDrnwWK/La9Ngj9fOIPjAGMOxeYuOxGRZz3Tz5o=",
        "MeasurementLog": "mIGxZoQpHOMXhYrVjhP+5Mo5Qa9Gh9Y4Dzk9+PZ4hwc=",
        "Obligation": "Xum2PE0uCd+kj/oD/bGcZ/ZZOPlFS2+2EGGSQUHwpL0=",
        "Provider": "q0DxoXrt4EWS6yXxmvgMH5Z2iOyuc8aZ5QoFphvUZw4=",
        "ServiceItem": "oLmMn8P7Qhm9kwaqXLTT6ppsedzdzLP99yAFaoqtgCw=",
    ]

    @Test func versionThreeIsANewShape() {
        let three = Self.fingerprint(DosarSchemaV3.models)
        #expect(three["Provider"] != Self.versionTwo["Provider"])
        #expect(three["CategoryTemplate"] != Self.versionTwo["CategoryTemplate"])
        #expect(three["Attachment"] != Self.versionTwo["Attachment"])
        #expect(three["Asset"] == Self.versionTwo["Asset"], "Only what version 3 adds changes")
    }

    @Test func theFrozenVersionThreeKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV3.models) == Self.versionThree)
        #expect(Self.versionThree["Obligation"] == Self.versionTwo["Obligation"], "Version 3 didn't change deadlines")
    }

    @Test func versionFourChangesOnlyDeadlines() {
        let four = Self.fingerprint(DosarSchemaV4.models)
        for (entity, hash) in Self.versionThree where entity != "Obligation" {
            #expect(four[entity] == hash, "\(entity) is as version 3 shipped it")
        }
        #expect(four["Obligation"] != Self.versionThree["Obligation"], "A deadline keeps its travel margin")
    }

    /// Version 4 as it shipped: version 3 with a deadline's travel margin.
    static let versionFour: [String: String] = versionThree.merging(["Obligation": "u0tiMcTlS/moad/uiA4LliY6jt452A0rMNTLoP3U33Y="]) { $1 }

    @Test func theFrozenVersionFourKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV4.models) == Self.versionFour)
    }

    @Test func versionFiveChangesOnlyDeadlines() {
        let five = Self.fingerprint(DosarSchemaV5.models)
        for (entity, hash) in Self.versionFour where entity != "Obligation" {
            #expect(five[entity] == hash, "\(entity) is as version 4 shipped it")
        }
        #expect(five["Obligation"] != Self.versionFour["Obligation"], "A deadline knows whether the person set its reminders")
    }

    /// Version 5 as it shipped: version 4 with whether the person set a deadline's reminders.
    static let versionFive: [String: String] = versionFour.merging(["Obligation": "g6w9CXVyhDkfgNfidSWvzsICUSR70fTqF3h1Z55p2Y8="]) { $1 }

    @Test func theFrozenVersionFiveKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV5.models) == Self.versionFive)
    }

    @Test func versionSixChangesOnlyDocuments() {
        let six = Self.fingerprint(DosarSchemaV6.models)
        for (entity, hash) in Self.versionFive where entity != "Attachment" {
            #expect(six[entity] == hash, "\(entity) is as version 5 shipped it")
        }
        #expect(six["Attachment"] != Self.versionFive["Attachment"], "A document keeps how its pages are shown")
    }

    /// Version 6 as it shipped: version 5 with how a document's pages are shown. Its frozen
    /// copy is pinned against the shapes version 7 kept: every entity but history entries.
    @Test func theFrozenVersionSixKeepsTheShapeItShippedWith() {
        let six = Self.fingerprint(DosarSchemaV6.models)
        let seven = Self.fingerprint(DosarSchemaV7.models)
        for (entity, hash) in Self.versionFive where entity != "Attachment" {
            #expect(six[entity] == hash, "\(entity) is as version 5 shipped it")
        }
        #expect(six["Attachment"] == seven["Attachment"], "Documents are as version 6 shipped them, which version 7 doesn't change")
        #expect(six["Attachment"] != Self.versionFive["Attachment"])
    }

    @Test func versionSevenChangesOnlyHistoryEntries() {
        let six = Self.fingerprint(DosarSchemaV6.models)
        let seven = Self.fingerprint(DosarSchemaV7.models)
        for (entity, hash) in six where entity != "HistoryEntry" {
            #expect(seven[entity] == hash, "\(entity) is as version 6 shipped it")
        }
        #expect(seven["HistoryEntry"] != six["HistoryEntry"], "A history entry keeps the number of the paper it records")
    }

    /// Version 7 as it shipped: version 6 with the number of the paper a history entry records.
    /// Its frozen copy is pinned against the shapes version 8 kept, and against version 6.
    @Test func theFrozenVersionSevenKeepsTheShapeItShippedWith() {
        let six = Self.fingerprint(DosarSchemaV6.models)
        let seven = Self.fingerprint(DosarSchemaV7.models)
        let eight = Self.fingerprint(DosarSchemaV8.models)
        for (entity, hash) in six where entity != "HistoryEntry" {
            #expect(seven[entity] == hash, "\(entity) is as version 6 shipped it")
        }
        for entity in ["Asset", "Obligation", "Provider", "CategoryTemplate", "AttachmentPage"] {
            #expect(seven[entity] == eight[entity], "\(entity) is as version 7 shipped it, which version 8 doesn't change")
        }
    }

    @Test func versionEightChangesOnlyTheRecordsThatHadNoChangeTime() {
        let seven = Self.fingerprint(DosarSchemaV7.models)
        let eight = Self.fingerprint(DosarSchemaV8.models)
        let timed = ["HistoryEntry", "ServiceItem", "MeasurementLog", "Attachment"]
        for (entity, hash) in seven where !timed.contains(entity) {
            #expect(eight[entity] == hash, "\(entity) is as version 7 shipped it")
        }
        for entity in timed {
            #expect(eight[entity] != seven[entity], "\(entity) keeps when it last changed")
        }
    }

    /// Version 8 as it shipped: version 7 with when a history entry, a line item, a reading and a
    /// document last changed. Read from the shipped models before version 9 existed.
    static let versionEight: [String: String] = [
        "Asset": "58a6RIU1oRUxD3p2eFaJmRdPZEPsiXxOu/r0Cdbm4z0=",
        "Attachment": "FY6Xa9w0aZgrdVuZZ4Y8RkikrPlj8MzyQjry3mG/DKA=",
        "AttachmentPage": "JuCkdlh81AVcycaJFrC8aBf8R7nkEg6kKyfUIOP9QdI=",
        "CategoryTemplate": "6ISuox65O5PR9u6cYpQ9MKBEqdCrUMgGOFTuEMpsZhg=",
        "HistoryEntry": "Kx+fLucvnb738u9jqhxEF+NxO2XpOiOgkernU2TgaMY=",
        "MeasurementLog": "c3fbetMFbEImm5eJIAPCuPBb5ry9+3bxFEh7tukqqaI=",
        "Obligation": "g6w9CXVyhDkfgNfidSWvzsICUSR70fTqF3h1Z55p2Y8=",
        "Provider": "q0DxoXrt4EWS6yXxmvgMH5Z2iOyuc8aZ5QoFphvUZw4=",
        "ServiceItem": "/BS5EFz6yHYk8QrzcDMNIkzvKNBhcNj0uS85aNIkTYQ=",
    ]

    @Test func theFrozenVersionEightKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV8.models) == Self.versionEight)
    }

    @Test func versionNineChangesOnlyTheRecordsThatKeepDays() {
        let nine = Self.fingerprint(DosarSchemaV9.models)
        let dated = ["Obligation", "HistoryEntry", "Attachment"]
        for (entity, hash) in Self.versionEight where !dated.contains(entity) {
            #expect(nine[entity] == hash, "\(entity) is as version 8 shipped it")
        }
        for entity in dated {
            #expect(nine[entity] != Self.versionEight[entity], "\(entity) keeps its days as days")
        }
    }

    /// Version 9 as it shipped: version 8 with every day kept as a day. Read from the frozen
    /// copy, made attribute for attribute from the shipped models before version 10 existed.
    static let versionNine: [String: String] = [
        "Asset": "58a6RIU1oRUxD3p2eFaJmRdPZEPsiXxOu/r0Cdbm4z0=",
        "Attachment": "89VNT6c3kLZ2ln2eDDvEWTbUdyQoFFMW4MhlJ2BWJ/0=",
        "AttachmentPage": "JuCkdlh81AVcycaJFrC8aBf8R7nkEg6kKyfUIOP9QdI=",
        "CategoryTemplate": "6ISuox65O5PR9u6cYpQ9MKBEqdCrUMgGOFTuEMpsZhg=",
        "HistoryEntry": "+Wd2vBQ9N6+tlE+Wrs12/HrGTSYy2WDlakIuecNsemc=",
        "MeasurementLog": "c3fbetMFbEImm5eJIAPCuPBb5ry9+3bxFEh7tukqqaI=",
        "Obligation": "ph3/Wvtsy9PkxKjnORg2H6dF4B7jl8Regw8b2alJBQg=",
        "Provider": "q0DxoXrt4EWS6yXxmvgMH5Z2iOyuc8aZ5QoFphvUZw4=",
        "ServiceItem": "/BS5EFz6yHYk8QrzcDMNIkzvKNBhcNj0uS85aNIkTYQ=",
    ]

    @Test func theFrozenVersionNineKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV9.models) == Self.versionNine)
    }

    @Test func versionTenChangesOnlyReadings() {
        let ten = Self.fingerprint(DosarSchemaV10.models)
        for (entity, hash) in Self.versionNine where entity != "MeasurementLog" {
            #expect(ten[entity] == hash, "\(entity) is as version 9 shipped it")
        }
        #expect(ten["MeasurementLog"] != Self.versionNine["MeasurementLog"], "A reading says whether it starts a new counter")
    }

    @Test func aStoreFromVersionNineOpensWithItsReadingsAsOneCounter() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v9.store")
        let edited = noon("2026-10-01")

        // Written by version 9: a car with two readings, the second lower (an old meter), and a deadline.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV9.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV9.Asset(name: "VW Golf 2018", templateKey: "vehicle")
            let before = DosarSchemaV9.MeasurementLog(name: "", value: 145_000)
            before.kindRaw = MeasurementKind.odometer.rawValue
            before.unit = MeasurementUnit.kilometres.key
            before.recordedAt = noon("2026-03-01")
            before.updatedAt = edited
            let after = DosarSchemaV9.MeasurementLog(name: "", value: 1_200)
            after.kindRaw = MeasurementKind.odometer.rawValue
            after.unit = MeasurementUnit.kilometres.key
            after.recordedAt = noon("2026-06-01")
            after.updatedAt = edited
            let itp = DosarSchemaV9.Obligation(title: "ITP")
            itp.dueDayISO = "2027-03-01"
            for model in [car, before, after, itp] as [any PersistentModel] { context.insert(model) }
            before.asset = car
            after.asset = car
            itp.asset = car
            try context.save()
        }

        // Opened by this version: every reading as it was, one counter, nothing guessed.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        let readings = (car.measurements ?? []).sorted { $0.recordedAt < $1.recordedAt }
        #expect(readings.map(\.value) == [145_000, 1_200])
        #expect(readings.allSatisfy { !$0.startsCounter }, "An old store has one counter")
        #expect(readings.allSatisfy { $0.updatedAt == edited }, "An upgrade isn't a change")
        #expect(HouseholdMutations.readingSeries(of: car, unit: .kilometres).counters.count == 1)
        #expect(try context.fetch(FetchDescriptor<Obligation>()).first?.dueDay == CalendarDay("2027-03-01"))

        // A new counter from now on is kept.
        readings[1].startsCounter = true
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let kept = try reopened.fetch(FetchDescriptor<MeasurementLog>()).sorted { $0.recordedAt < $1.recordedAt }
        #expect(kept.map(\.startsCounter) == [false, true])
    }

    /// Version 10 as it shipped: version 9 with whether a reading starts a new counter. Its frozen
    /// copy is pinned against version 9 for everything but readings, and against version 11 for
    /// everything but the deadline, which version 11 changes.
    @Test func theFrozenVersionTenKeepsTheShapeItShippedWith() {
        let ten = Self.fingerprint(DosarSchemaV10.models)
        let eleven = Self.fingerprint(DosarSchemaV11.models)
        for (entity, hash) in Self.versionNine where entity != "MeasurementLog" && entity != "Obligation" {
            #expect(ten[entity] == hash, "\(entity) is as version 9 shipped it, which version 10 doesn't change")
        }
        #expect(ten["Obligation"] == Self.versionNine["Obligation"], "Version 10 doesn't change deadlines")
        #expect(ten["MeasurementLog"] == eleven["MeasurementLog"], "A reading is as version 10 shipped it, which version 11 doesn't change")
        #expect(ten.count == eleven.count)
    }

    @Test func versionElevenChangesOnlyDeadlines() {
        let ten = Self.fingerprint(DosarSchemaV10.models)
        let eleven = Self.fingerprint(DosarSchemaV11.models)
        for (entity, hash) in ten where entity != "Obligation" {
            #expect(eleven[entity] == hash, "\(entity) is as version 10 shipped it")
        }
        #expect(eleven["Obligation"] != ten["Obligation"], "A deadline keeps since when its cycle is known")
    }

    @Test func aStoreFromVersionTenOpensWithItsDeadlinesKnownSinceTheirChangeTime() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v10.store")
        let edited = noon("2026-10-01")

        // Written by version 10: a car's RCA, due and snoozed, with its completion, and a reading
        // that starts a new counter.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV10.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV10.Asset(name: "VW Golf 2018", templateKey: "vehicle")
            let rca = DosarSchemaV10.Obligation(title: "RCA")
            rca.dueDayISO = "2027-07-15"
            rca.snoozedUntilISO = "2027-07-01"
            rca.reminderLeadDays = [30, 7]
            rca.updatedAt = edited
            let paid = DosarSchemaV10.HistoryEntry(title: "RCA")
            paid.cycleDueDayISO = "2026-07-15"
            paid.nextDueDayISO = "2027-07-15"
            let reading = DosarSchemaV10.MeasurementLog(name: "", value: 1_200)
            reading.startsCounter = true
            for model in [car, rca, paid, reading] as [any PersistentModel] { context.insert(model) }
            rca.asset = car
            paid.asset = car
            paid.obligation = rca
            reading.asset = car
            try context.save()
        }

        // Opened by this version: everything as it was; no moment is known yet, so the deadline
        // reads as known since its change time, as reminders counted before.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let rca = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(rca.dueDay == CalendarDay("2027-07-15"))
        #expect(rca.snoozedUntil == CalendarDay("2027-07-01"))
        #expect(rca.reminderLeadDays == [30, 7])
        #expect(rca.updatedAt == edited, "An upgrade isn't a change")
        #expect(rca.cycleKnownAt == nil)
        #expect(rca.cycleKnownSince == edited)
        #expect(rca.historyEntries?.first?.cycleDueDay == CalendarDay("2026-07-15"))
        #expect(try context.fetch(FetchDescriptor<MeasurementLog>()).first?.startsCounter == true)
        #expect(try ObligationSnapshot.fetchAll(in: context).first?.cycleKnownSince == edited)

        // A new due day from now on gives it its own, kept.
        let moved = noon("2026-11-05")
        rca.dueDay = CalendarDay("2027-08-01")
        try UnitOfWork.save(context, now: moved)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Obligation>()).first?.cycleKnownAt == moved)
    }

    /// Version 11 as it shipped: version 10 with since when a deadline's cycle is known. Its frozen
    /// copy is pinned against version 10 for everything but deadlines, and against version 12 for
    /// everything but deadlines and categories, which version 12 changes.
    @Test func theFrozenVersionElevenKeepsTheShapeItShippedWith() {
        let ten = Self.fingerprint(DosarSchemaV10.models)
        let eleven = Self.fingerprint(DosarSchemaV11.models)
        let twelve = Self.fingerprint(DosarSchemaV12.models)
        for (entity, hash) in ten where entity != "Obligation" {
            #expect(eleven[entity] == hash, "\(entity) is as version 10 shipped it, which version 11 doesn't change")
            if entity != "CategoryTemplate" {
                #expect(twelve[entity] == hash, "\(entity) is as version 11 shipped it, which version 12 doesn't change")
            }
        }
        #expect(eleven["Obligation"] != ten["Obligation"])
        #expect(eleven.count == twelve.count)
    }

    @Test func versionTwelveChangesOnlyDeadlinesAndCategories() {
        let eleven = Self.fingerprint(DosarSchemaV11.models)
        let twelve = Self.fingerprint(DosarSchemaV12.models)
        for (entity, hash) in eleven where entity != "Obligation" && entity != "CategoryTemplate" {
            #expect(twelve[entity] == hash, "\(entity) is as version 11 shipped it")
        }
        #expect(twelve["Obligation"] != eleven["Obligation"], "A deadline keeps what a newer build wrote in its reminders")
        #expect(twelve["CategoryTemplate"] != eleven["CategoryTemplate"], "A category's lock left the store")
    }

    @Test func aStoreFromVersionElevenKeepsEveryLockOnThisDevice() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v11.store")

        // Written by version 11: Acte opened by the person, a car category locked, a notebook of one's own locked.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV11.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let documents = DosarSchemaV11.CategoryTemplate(key: BuiltInTemplates.Key.documents)
            documents.isBuiltIn = true
            documents.isSensitive = false
            let vehicles = DosarSchemaV11.CategoryTemplate(key: BuiltInTemplates.Key.vehicle)
            vehicles.isBuiltIn = true
            vehicles.isSensitive = true
            let notebook = DosarSchemaV11.CategoryTemplate(key: "custom.0b6c6f43-0000-4000-8000-00000000c0de")
            notebook.isSensitive = true
            for model in [documents, vehicles, notebook] as [any PersistentModel] { context.insert(model) }
            try context.save()
        }

        // Opened by this version: every lock as it was, now this device's own.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let templates = Dictionary(uniqueKeysWithValues: try ModelContext(container).fetch(FetchDescriptor<CategoryTemplate>()).map { ($0.key, $0) })
        #expect(templates[BuiltInTemplates.Key.documents]?.isSensitive == false, "A lock the person opened stays open")
        #expect(templates[BuiltInTemplates.Key.vehicle]?.isSensitive == true)
        #expect(templates["custom.0b6c6f43-0000-4000-8000-00000000c0de"]?.isSensitive == true)
        #expect(FileManager.default.fileExists(atPath: SectionLocks.file(forStoreAt: url).path(percentEncoded: false)), "Kept beside the store")
    }

    @Test func aStoreFromVersionElevenOpensWithItsRemindersAsTheyWere() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v11.store")
        let edited = noon("2026-10-01")
        let known = noon("2026-10-02")

        // Written by version 11: a car's RCA with reminders of its own and since when its cycle is known.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV11.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV11.Asset(name: "VW Golf 2018", templateKey: "vehicle")
            let rca = DosarSchemaV11.Obligation(title: "RCA")
            rca.dueDayISO = "2027-07-15"
            rca.reminderLeadDays = [30, 7]
            rca.consequenceRaw = "legal"
            rca.graceDays = 3
            rca.remindersCustomized = true
            rca.updatedAt = edited
            rca.cycleKnownAt = known
            for model in [car, rca] as [any PersistentModel] { context.insert(model) }
            rca.asset = car
            try context.save()
        }

        // Opened by this version: everything as it was, nothing kept beside the reminders yet.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let rca = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(rca.reminders == ReminderProfile(leadDays: [30, 7], consequence: .legal, graceDays: 3, followUpAfterLapse: false))
        #expect(rca.remindersCustomized)
        #expect(rca.remindersData == nil)
        #expect(!rca.keptReminders.keepsMore)
        #expect(rca.updatedAt == edited, "An upgrade isn't a change")
        #expect(rca.cycleKnownAt == known)

        // What a newer build wrote in them is kept from now on.
        rca.keptReminders = try JSONDecoder().decode(KeptObject<ReminderProfile>.self, from: Data(
            #"{"consequence":"legal","followUpAfterLapse":false,"graceDays":3,"leadDays":[30,7],"quietHours":{"from":22,"to":7}}"#.utf8
        ))
        try UnitOfWork.save(context)
        let reopened = try #require(try ModelContext(try PersistenceController.makeContainer(storeURL: url)).fetch(FetchDescriptor<Obligation>()).first)
        #expect(reopened.keptReminders.keepsMore)
        #expect(reopened.reminders.leadDays == [30, 7])
    }

    /// The days a version 8 store keeps, written as version 8 wrote them in `calendar`'s time
    /// zone: noon of the day, a snooze's end at the start of its day.
    private struct EightDays {
        static let due = CalendarDay("2026-07-15")
        static let snooze = CalendarDay("2026-07-01")
        static let cycle = CalendarDay("2025-07-15")
        static let next = CalendarDay("2026-07-15")
        static let issued = CalendarDay("2025-07-10")
        static let valid = CalendarDay("2026-07-14")
    }

    /// Writes a version 8 store with a deadline (due and snoozed), its completion and its policy.
    private func writeVersionEight(at url: URL, in calendar: Calendar, edited: Date) throws {
        let schema = Schema(versionedSchema: DosarSchemaV8.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let car = DosarSchemaV8.Asset(name: "VW Golf 2018", templateKey: "vehicle")
        let rca = DosarSchemaV8.Obligation(title: "RCA")
        rca.dueDate = EightDays.due.noonDate(in: calendar)
        rca.snoozedUntil = EightDays.snooze.startDate(in: calendar)
        rca.updatedAt = edited
        let paid = DosarSchemaV8.HistoryEntry(title: "RCA")
        paid.cycleDueDate = EightDays.cycle.noonDate(in: calendar)
        paid.nextDueDate = EightDays.next.noonDate(in: calendar)
        paid.updatedAt = edited
        let policy = DosarSchemaV8.Attachment(fileName: "polita.pdf")
        policy.documentDate = EightDays.issued.noonDate(in: calendar)
        policy.validUntil = EightDays.valid.noonDate(in: calendar)
        policy.updatedAt = edited
        let note = DosarSchemaV8.HistoryEntry(title: "Spălat")
        for model in [car, rca, paid, policy, note] as [any PersistentModel] { context.insert(model) }
        rca.asset = car
        paid.asset = car
        paid.obligation = rca
        policy.asset = car
        policy.obligation = rca
        note.asset = car
        try context.save()
    }

    private func expectTheSameDays(in context: ModelContext, edited: Date, _ comment: Comment? = nil) throws {
        let rca = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(rca.title == "RCA")
        #expect(rca.dueDay == EightDays.due, comment)
        #expect(rca.snoozedUntil == EightDays.snooze, comment)
        #expect(rca.updatedAt == edited, "An upgrade isn't a change")
        let paid = try #require(rca.historyEntries?.first)
        #expect(paid.cycleDueDay == EightDays.cycle, comment)
        #expect(paid.nextDueDay == EightDays.next, comment)
        #expect(paid.isCompletion)
        #expect(paid.updatedAt == edited)
        let policy = try #require(rca.attachments?.first)
        #expect(policy.documentDay == EightDays.issued, comment)
        #expect(policy.validUntil == EightDays.valid, comment)
        #expect(policy.updatedAt == edited)
        let note = try #require(try context.fetch(FetchDescriptor<HistoryEntry>()).first { $0.title == "Spălat" })
        #expect(note.cycleDueDay == nil && note.nextDueDay == nil && !note.isCompletion, "A visit stays a visit")
    }

    @Test func aStoreFromVersionEightOpensWithEveryDayTheSameDay() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v8.store")
        let edited = noon("2026-10-01")

        // Written by version 8 on this phone, in its time zone.
        try writeVersionEight(at: url, in: .dosar, edited: edited)

        // Opened by this version: every day as it was, kept as a day.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        try expectTheSameDays(in: context, edited: edited)
        let rca = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(rca.dueDayISO == "2026-07-15")
        #expect(rca.snoozedUntilISO == "2026-07-01")

        // A day changed from now on is kept as a day.
        rca.dueDay = CalendarDay("2027-07-15")
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Obligation>()).first?.dueDay == CalendarDay("2027-07-15"))
    }

    /// A phone anywhere from twelve hours behind to fourteen ahead upgrades with every day the
    /// same day it was written on there.
    @Test(arguments: ["Etc/GMT+12", "Pacific/Pago_Pago", "America/Los_Angeles", "UTC", "Europe/Bucharest", "Asia/Kolkata", "Asia/Tokyo", "Pacific/Auckland", "Pacific/Kiritimati"])
    func aStoreFromVersionEightKeepsItsDaysInTheTimeZoneItWasWrittenIn(zone: String) throws {
        let calendar = Calendar.dosar(in: try #require(TimeZone(identifier: zone)))
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v8.store")
        let edited = noon("2026-10-01")
        try writeVersionEight(at: url, in: calendar, edited: edited)

        let container = try DayMigration.$calendar.withValue(calendar) { try PersistenceController.makeContainer(storeURL: url) }
        try expectTheSameDays(in: ModelContext(container), edited: edited, "Written and upgraded in \(zone)")
    }

    /// The time zone isn't stored, so the upgrade reads the moments where the phone is then:
    /// a phone that moved up to eleven hours away since keeps every day.
    @Test(arguments: [("Europe/Bucharest", "Asia/Tokyo"), ("Europe/Bucharest", "America/New_York"), ("Asia/Tokyo", "Europe/London"), ("America/Los_Angeles", "Asia/Dubai")])
    func aStoreFromVersionEightKeepsItsDaysAfterTheMoveToAnotherTimeZone(written: String, upgraded: String) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v8.store")
        let edited = noon("2026-10-01")
        try writeVersionEight(at: url, in: .dosar(in: try #require(TimeZone(identifier: written))), edited: edited)

        let there = Calendar.dosar(in: try #require(TimeZone(identifier: upgraded)))
        let container = try DayMigration.$calendar.withValue(there) { try PersistenceController.makeContainer(storeURL: url) }
        try expectTheSameDays(in: ModelContext(container), edited: edited, "Written in \(written), upgraded in \(upgraded)")
    }

    @Test func aStoreFromVersionSevenOpensWithItsRecordsAndNoKnownChangeTime() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v7.store")
        let edited = noon("2026-10-01")

        // Written by version 7: a visit with a line item and its invoice, and a reading.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV7.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV7.Asset(name: "VW Golf 2018", templateKey: "vehicle")
            car.updatedAt = edited
            let visit = DosarSchemaV7.HistoryEntry(title: "Revizie")
            visit.reference = "EXM 0000001"
            let filter = DosarSchemaV7.ServiceItem(name: "Filtru ulei")
            let reading = DosarSchemaV7.MeasurementLog(name: "", value: 142_500)
            let invoice = DosarSchemaV7.Attachment(fileName: "factura.pdf")
            let page = DosarSchemaV7.AttachmentPage(index: 0)
            page.imageData = Data([1, 2, 3])
            for model in [car, visit, filter, reading, invoice, page] as [any PersistentModel] { context.insert(model) }
            visit.asset = car
            filter.entry = visit
            reading.asset = car
            invoice.historyEntry = visit
            page.attachment = invoice
            try context.save()
        }

        // Opened by this version: everything as it was, with a change time older than any change.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let visit = try #require(try context.fetch(FetchDescriptor<HistoryEntry>()).first)
        #expect(visit.reference == "EXM 0000001")
        #expect(visit.updatedAt == ChangeTime.unknown)
        let filter = try #require(visit.items?.first)
        #expect(filter.name == "Filtru ulei")
        #expect(filter.updatedAt == ChangeTime.unknown)
        let reading = try #require(try context.fetch(FetchDescriptor<MeasurementLog>()).first)
        #expect(reading.value == 142_500)
        #expect(reading.updatedAt == ChangeTime.unknown)
        let invoice = try #require(visit.attachments?.first)
        #expect(invoice.orderedPages.first?.imageData == Data([1, 2, 3]))
        #expect(invoice.updatedAt == ChangeTime.unknown)
        #expect(try context.fetch(FetchDescriptor<Asset>()).first?.updatedAt == edited, "A section keeps the time it had")

        // A change from now on is newer, and kept.
        visit.note = "Cu filtrul de aer."
        try UnitOfWork.save(context)
        #expect(visit.updatedAt > ChangeTime.unknown)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<HistoryEntry>()).first?.updatedAt == visit.updatedAt)
    }

    @Test func aStoreFromVersionSixOpensWithItsBills() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v6.store")

        // Written by version 6: a gas bill in its subscription's history, its number in the note.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV6.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let gas = DosarSchemaV6.Asset(name: "Gaz – ENGIE Romania S.A.", templateKey: "subscription")
            let bill = DosarSchemaV6.HistoryEntry(title: "Factură ENGIE Romania S.A.")
            bill.kindRaw = HistoryKind.payment.rawValue
            bill.note = "Factura nr. EXM 0000001"
            bill.totalCostAmount = 245
            bill.totalCostCurrency = "RON"
            let photo = DosarSchemaV6.Attachment(fileName: "Factură.heic")
            photo.framingData = Data("{}".utf8)
            context.insert(gas)
            context.insert(bill)
            context.insert(photo)
            bill.asset = gas
            photo.historyEntry = bill
            photo.asset = gas
            try context.save()
        }

        // Opened by this version: the bill is there as it was, with no number of its own yet.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let bill = try #require(try context.fetch(FetchDescriptor<HistoryEntry>()).first)
        #expect(bill.title == "Factură ENGIE Romania S.A.")
        #expect(bill.note == "Factura nr. EXM 0000001")
        #expect(bill.totalCost == Money(245))
        #expect(bill.reference == nil)
        #expect(bill.attachments?.first?.framingData == Data("{}".utf8))
        #expect(bill.asset?.name == "Gaz – ENGIE Romania S.A.")

        // The new attribute is kept.
        bill.reference = "EXM 0000001"
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<HistoryEntry>()).first?.reference == "EXM 0000001")
    }

    @Test func aStoreFromVersionFiveOpensWithItsDocuments() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v5.store")
        let page = Data([0xFF, 0xD8, 0xFF, 0xD9])

        // Written by version 5: an identity card's photo, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV5.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let card = DosarSchemaV5.Asset(name: "Carte de identitate", templateKey: "documents")
            let photo = DosarSchemaV5.Attachment(fileName: "Carte de identitate.heic")
            photo.title = "Carte de identitate"
            let front = DosarSchemaV5.AttachmentPage(index: 0)
            front.imageData = page
            let reminder = DosarSchemaV5.Obligation(title: "Reînnoire")
            reminder.remindersCustomized = true
            context.insert(card)
            context.insert(photo)
            context.insert(front)
            context.insert(reminder)
            photo.asset = card
            front.attachment = photo
            reminder.asset = card
            try context.save()
        }

        // Opened by this version: the photo is kept as taken and shown whole, as before.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let photo = try #require(try context.fetch(FetchDescriptor<DosarCuSina.Attachment>()).first)
        #expect(photo.title == "Carte de identitate")
        #expect(photo.orderedPages.first?.imageData == page)
        #expect(photo.framingData == nil)
        #expect(photo.framing.isPlain)
        #expect(try context.fetch(FetchDescriptor<Obligation>()).first?.remindersCustomized == true)

        // The new attribute is kept.
        photo.framing = DocumentFraming(pages: [PageFraming(quarterTurns: 1)])
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<DosarCuSina.Attachment>()).first?.framing[page: 0].shownQuarterTurns == 1)
    }

    @Test func aStoreFromVersionFourOpensWithItsDeadlines() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v4.store")
        let deadlineID = UUID()

        // Written by version 4: a passport's deadline with its cut-off, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV4.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let passport = DosarSchemaV4.Asset(name: "Pașaport", templateKey: "documents")
            passport.valuesData = StoredJSON.encode(FieldValues([DocumentType.typeFieldKey: .text(DocumentType.passport)]))
            let renewal = DosarSchemaV4.Obligation(title: "Reînnoire")
            renewal.id = deadlineID
            renewal.blueprintKey = BuiltInBlueprints.documentRenew
            renewal.kindRaw = ObligationKind.renewal.rawValue
            renewal.reminderLeadDays = [90, 0]
            renewal.consequenceRaw = Consequence.legal.rawValue
            renewal.followUpAfterLapse = true
            renewal.travelMarginDays = 180
            context.insert(passport)
            context.insert(renewal)
            renewal.asset = passport
            try context.save()
        }

        // Opened by this version: everything kept, and the reminders aren't marked as the person's.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let renewal = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(renewal.id == deadlineID)
        #expect(renewal.asset?.name == "Pașaport")
        #expect(renewal.reminders == ReminderProfile(leadDays: [90, 0], consequence: .legal, followUpAfterLapse: true, travelMarginDays: 180))
        #expect(!renewal.remindersCustomized)

        // The new attribute is kept.
        renewal.remindersCustomized = true
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Obligation>()).first?.remindersCustomized == true)
    }

    @Test func aStoreFromVersionThreeOpensWithItsDeadlines() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v3.store")
        let deadlineID = UUID()

        // Written by version 3: a passport's deadline, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let passport = DosarSchemaV3.Asset(name: "Pașaport", templateKey: "documents")
            passport.valuesData = StoredJSON.encode(FieldValues([DocumentType.typeFieldKey: .text(DocumentType.passport)]))
            let renewal = DosarSchemaV3.Obligation(title: "Reînnoire")
            renewal.id = deadlineID
            renewal.blueprintKey = BuiltInBlueprints.documentRenew
            renewal.kindRaw = ObligationKind.renewal.rawValue
            renewal.reminderLeadDays = [180, 60]
            renewal.consequenceRaw = Consequence.legal.rawValue
            renewal.followUpAfterLapse = true
            context.insert(passport)
            context.insert(renewal)
            renewal.asset = passport
            try context.save()
        }

        // Opened by this version: everything kept, no travel margin until the repair list adds it.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let renewal = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(renewal.id == deadlineID)
        #expect(renewal.asset?.name == "Pașaport")
        #expect(renewal.reminders == ReminderProfile(leadDays: [180, 60], consequence: .legal, followUpAfterLapse: true))
        #expect(renewal.travelMarginDays == 0)

        // The new attribute is kept.
        renewal.travelMarginDays = 180
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Obligation>()).first?.reminders.travelMarginDays == 180)
    }

    @Test func aStoreFromVersionTwoOpensWithEverythingInIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v2.store")

        // Written by version 2, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV2.Asset(name: "VW Golf 2018", templateKey: "vehicle")
            car.valuesData = StoredJSON.encode(FieldValues(["vehicle.plate": .text("B-123-ABC")]))
            let firm = DosarSchemaV2.Provider(name: "ENGIE Romania S.A.")
            firm.trades = [ProviderTrade.mechanic.rawValue]
            let template = DosarSchemaV2.CategoryTemplate(key: "vehicle")
            template.name = "Mașini"
            let policy = DosarSchemaV2.Attachment(fileName: "Poliță RCA.pdf")
            context.insert(car)
            context.insert(firm)
            context.insert(template)
            context.insert(policy)
            firm.assets = [car]
            policy.asset = car
            try context.save()
        }

        // Opened by this version, through the migration plan.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        #expect(car.name == "VW Golf 2018")
        #expect(car.values["vehicle.plate"] == .text("B-123-ABC"))
        let firm = try #require(try context.fetch(FetchDescriptor<Provider>()).first)
        #expect(firm.name == "ENGIE Romania S.A.")
        #expect(firm.taxID == nil)
        #expect(firm.assets?.map(\.id) == [car.id])
        let template = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first)
        #expect(template.behavior == .standard, "A category from before version 3 behaves as standard until the built-ins are upgraded")
        let policy = try #require(try context.fetch(FetchDescriptor<DosarCuSina.Attachment>()).first)
        #expect(policy.validUntil == nil)
        #expect(policy.asset?.id == car.id)

        // The new attributes are kept.
        firm.taxID = "12345678"
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Provider>()).first?.taxID == "12345678")
    }
}
