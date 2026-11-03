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

    @Test func versionThreeIsANewShape() {
        let three = Self.fingerprint(DosarSchemaV3.models)
        #expect(three["Provider"] != Self.versionTwo["Provider"])
        #expect(three["CategoryTemplate"] != Self.versionTwo["CategoryTemplate"])
        #expect(three["Attachment"] != Self.versionTwo["Attachment"])
        #expect(three["Asset"] == Self.versionTwo["Asset"], "Only what version 3 adds changes")
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
            car.valuesData = StoredJSON.encode(["vehicle.plate": FieldValue.text("B-123-ABC")] as FieldValues)
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
        let policy = try #require(try context.fetch(FetchDescriptor<Attachment>()).first)
        #expect(policy.validUntil == nil)
        #expect(policy.asset?.id == car.id)

        // The new attributes are kept.
        firm.taxID = "12345678"
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Provider>()).first?.taxID == "12345678")
    }
}
