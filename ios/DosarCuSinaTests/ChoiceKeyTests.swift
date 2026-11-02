import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Choice keys")
struct ChoiceKeyTests {
    private var fuel: FieldDefinition { BuiltInTemplates.vehicle.field("vehicle.fuel")! }

    @Test func valuesStoreKeysAndShowLabels() {
        #expect(fuel.options?.map(\.key) == [FuelType.petrol, FuelType.diesel, FuelType.hybrid, FuelType.plugInHybrid, FuelType.electric, FuelType.lpg])
        #expect(FieldFormatter.display(.text(FuelType.diesel), field: fuel) == "Motorină")
        #expect(FieldFormatter.display(.text("Ceva nou"), field: fuel) == "Ceva nou", "Unknown values show as written")
    }

    @Test("Legacy display text maps to its key", arguments: [
        ("Motorină", FuelType.diesel), ("motorina", FuelType.diesel), ("Diesel", FuelType.diesel),
        ("Benzină", FuelType.petrol), ("PHEV", FuelType.plugInHybrid), (FuelType.lpg, FuelType.lpg),
    ])
    func legacyTextMapsToKeys(text: String, key: String) {
        #expect(fuel.choiceKey(for: text) == key)
    }

    @Test func signsKeepBloodTypesApart() throws {
        let field = try #require(BuiltInTemplates.health.field("health.bloodType"))
        #expect(field.choiceKey(for: "A II+") == "bloodType.aPositive")
        #expect(field.choiceKey(for: "A II-") == "bloodType.aNegative")
        #expect(field.choiceKey(for: "0 I−") == "bloodType.0Negative")
        #expect(field.choiceKey(for: "O+") == "bloodType.0Positive")
    }

    @Test func normalizingRewritesOnlyChoiceFields() {
        var values = FieldValues()
        values["vehicle.fuel"] = .text("Motorină")
        values["vehicle.usage"] = .text("Ridesharing sau taxi")
        values["vehicle.make"] = .text("Motorină")
        values["vehicle.model"] = .text("Golf")
        let normalized = values.normalizingChoices(for: BuiltInTemplates.vehicle)
        #expect(normalized["vehicle.fuel"] == .text(FuelType.diesel))
        #expect(normalized["vehicle.usage"] == .text(VehicleUse.commercial))
        #expect(normalized["vehicle.make"] == .text("Motorină"), "Free text fields are left alone")
        #expect(normalized.normalizingChoices(for: BuiltInTemplates.vehicle) == normalized, "Normalizing twice changes nothing")
    }

    @Test func optionsRoundTripAndOldDefinitionsStillDecode() throws {
        let field = FieldDefinition(key: "boat.type", label: "Tip", type: .choice, options: [ChoiceOption(key: "boat.sail", label: "Velier", aliases: ["Sailboat"])])
        let decoded = try JSONDecoder().decode(FieldDefinition.self, from: JSONEncoder().encode(field))
        #expect(decoded == field)

        let old = #"{"key": "boat.type", "label": "Tip", "type": "choice", "options": ["Velier", "Barcă cu motor"]}"#
        let legacy = try JSONDecoder().decode(FieldDefinition.self, from: Data(old.utf8))
        #expect(legacy.options?.map(\.key) == ["Velier", "Barcă cu motor"])
        #expect(legacy.label(forChoice: "Velier") == "Velier")
    }

    @Test func rulesReadKeysAndLegacyText() {
        var values = FieldValues()
        values["vehicle.year"] = .number(2022)
        values["vehicle.usage"] = .text(VehicleUse.commercial)
        #expect(RecurrenceEngine.itpInterval(values: values, on: CalendarDay("2026-05-20")) == .months(6))
        values["vehicle.usage"] = .text("Ridesharing sau taxi")
        #expect(RecurrenceEngine.itpInterval(values: values, on: CalendarDay("2026-05-20")) == .months(6))
    }
}

@MainActor
@Suite("Choice keys in storage and archives")
struct ChoiceStorageTests {
    @Test func storedDisplayTextIsMigratedAtLaunch() throws {
        let context = try makeContext()
        var values = FieldValues()
        values["vehicle.fuel"] = .text("Benzină")
        let car = Asset(name: "Mașina", templateKey: BuiltInTemplates.Key.vehicle, values: values)
        context.insert(car)
        try context.save()
        #expect(try ChoiceMigration.migrateStoredValues(in: context) == 1)
        #expect(car.value("vehicle.fuel") == .text(FuelType.petrol))
        #expect(try ChoiceMigration.migrateStoredValues(in: context) == 0)
    }

    @Test func creatingAnAssetStoresKeys() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.pet))
        var values = FieldValues()
        values["pet.species"] = .text("Pisică")
        let cat = try AssetActions(context: context).create(name: "Pisica", template: template, values: values)
        #expect(cat.value("pet.species") == .text(PetSpecies.cat))
    }

    @Test func archivesWriteKeysAndImportLegacyText() throws {
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: .bucharest)
        try service.importArchive(try Fixtures.archive("dosar-v3/household"), mode: .replace)
        let car = try #require(try ModelContext(container).fetch(FetchDescriptor<Asset>()).first { $0.name == "VW Golf" })
        #expect(car.value("vehicle.fuel") == .text(FuelType.diesel))

        let exported = try service.exportData(exportedAt: noon("2026-11-02"))
        let assets = try #require(try DosarZipEngine.unpackArchive(exported).first { $0.path == DossierV3.Path.assets })
        let json = String(decoding: assets.data, as: UTF8.self)
        #expect(json.contains("\"fuel.diesel\""))
        #expect(!json.contains("Motorină"))

        // v2 backups stored the Romanian label.
        let legacy = try makeInMemoryContainer()
        try DossierArchiveService(container: legacy, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v2/ios-export"), mode: .replace)
        let logan = try #require(try ModelContext(legacy).fetch(FetchDescriptor<Asset>()).first { $0.name == "Dacia Logan" })
        #expect(logan.value("vehicle.fuel") == .text(FuelType.diesel))
    }
}
