import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Units are known by stable keys. Every label written so far reads as its key, backups
/// write keys and read both, and stored labels are rewritten to keys once, by themselves.
@MainActor
@Suite("Units as keys")
struct MeasurementUnitTests {
    /// Every spelling an earlier version stored, and the unit it is.
    nonisolated static let earlierLabels: [(label: String, unit: MeasurementUnit)] = [
        ("km", .kilometres), ("KM", .kilometres),
        ("h", .engineHours),
        ("kWh", .kilowattHours), ("kwh", .kilowattHours),
        ("m³", .cubicMetres), ("mc", .cubicMetres), ("m3", .cubicMetres), ("MC", .cubicMetres),
        ("Gcal", .gigacalories),
        ("kg", .kilograms),
        ("mg/dL", .milligramsPerDecilitre),
        ("mmHg", .millimetresOfMercury),
        ("dpt", .dioptres),
        ("cm³", .cubicCentimetres),
        ("CP", .horsepower),
        ("m²", .squareMetres),
        ("luni", .months),
        ("cafele", .shots),
        (" km ", .kilometres),
    ]

    @Test(arguments: earlierLabels.map(\.label))
    func everyLabelWrittenSoFarReadsAsItsKey(_ label: String) throws {
        let expected = try #require(Self.earlierLabels.first { $0.label == label }?.unit)
        #expect(MeasurementUnit(label) == expected)
        #expect(MeasurementUnit.storedKey(for: label) == expected.key)
        #expect(expected.isCatalog)
    }

    @Test func everyCatalogUnitReadsBackFromItsKeyAndItsLabel() {
        for unit in MeasurementUnit.catalog {
            #expect(MeasurementUnit(unit.key) == unit, "\(unit.key)")
            #expect(MeasurementUnit(unit.label) == unit, "\(unit.label)")
        }
        #expect(Set(MeasurementUnit.catalog.map(\.key)).count == MeasurementUnit.catalog.count, "Keys are unique")
    }

    @Test func labelsAreWhatPeopleRead() {
        #expect(MeasurementUnit.cubicMetres.label == "m³")
        #expect(MeasurementUnit.kilowattHours.label == "kWh")
        #expect(MeasurementUnit.gigacalories.label == "Gcal")
        #expect(MeasurementUnit.months.label == "luni")
        #expect(MeasurementUnit.shots.label == "cafele")
        #expect(MeasurementUnit.written(45_724, in: .kilometres) == "45.724 km")
        #expect(MeasurementUnit.written(12.5, in: .cubicMetres) == "12,5 m³")
        #expect(MeasurementUnit.written(3, in: nil) == "3")
    }

    @Test func aUnitOfThePersonsOwnStaysAsWritten() throws {
        let own = try #require(MeasurementUnit("ore motor"))
        #expect(own.key == "ore motor")
        #expect(own.label == "ore motor")
        #expect(!own.isCatalog)
        #expect(MeasurementUnit("") == nil)
        #expect(MeasurementUnit("   ") == nil)
        #expect(MeasurementUnit(nil) == nil)
        #expect(MeasurementUnit.storedKey(for: "") == "")
    }

    // MARK: Stored forms

    @Test func fieldsAndRecurrencesReadLabelsAndWriteKeys() throws {
        let field = try JSONDecoder().decode(FieldDefinition.self, from: Data(#"{"key": "gas.index", "label": "Index", "type": "metric", "unit": "mc"}"#.utf8))
        #expect(field.unit == .cubicMetres)
        let fieldJSON = String(decoding: try #require(StoredJSON.encode(field)), as: UTF8.self)
        #expect(fieldJSON.contains(#""unit":"m3""#))

        let rule = try JSONDecoder().decode(RecurrenceRule.self, from: Data(#"{"type": "metric", "every": 100, "unit": "cafele", "fallbackEvery": 2, "fallbackUnit": "week"}"#.utf8))
        #expect(rule == .metric(every: 100, unit: .shots, fallback: .weeks(2)))
        let ruleJSON = String(decoding: try #require(StoredJSON.encode(rule)), as: UTF8.self)
        #expect(ruleJSON.contains(#""unit":"shots""#))
        #expect(ruleJSON.contains(#""fallbackUnit":"week""#), "A calendar step keeps its own unit")

        #expect(MeasurementKind.forUnit(MeasurementUnit("kWh")) == .electricity)
        #expect(NumberKind.forField(unit: MeasurementUnit("KM")) == .kilometres)
        #expect(RomanianNumber.value("12,5 mc", as: .meterIndex) == Decimal(string: "12.5"))
        #expect(RomanianNumber.value("12,5 m³", as: .meterIndex) == Decimal(string: "12.5"))
    }

    @Test func aReadingStoredWithALabelCountsWithItsKey() throws {
        let context = try makeContext()
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        for (day, value, unit) in [("2026-01-10", 45_000.0, "km"), ("2026-03-10", 46_000.0, "KM")] {
            let log = MeasurementLog(kind: .odometer, name: "", value: value, recordedAt: noon(day))
            log.unit = unit
            context.insert(log)
            log.asset = car
        }
        try context.save()
        #expect(HouseholdMutations.readingSeries(of: car, unit: .kilometres).current == 46_000)
        #expect(throws: LowerReadingQuestion.self) {
            try HouseholdMutations.recordReading(4_600, on: car, at: noon("2026-04-01"), source: .person, unit: .kilometres, in: context)
        }
    }

    // MARK: The repair

    /// Readings, a metric deadline and a category of the person's own stored labels; the
    /// step rewrites them to keys by itself, and a second run changes nothing.
    @Test func theRepairRewritesStoredLabelsToKeysOnce() throws {
        let context = try makeContext()
        let gas = MeasurementUnit.cubicMetres
        let custom = try TemplateStore(context: context).createCustom(
            name: "Centrală", symbol: "flame", tint: .orange,
            sections: [FieldSection(key: "boiler", title: "Centrală", fields: [
                FieldDefinition(key: "boiler.index", label: "Index", type: .metric, role: .heroMetric, unit: gas),
            ])],
            blueprints: [ObligationBlueprint(key: "boiler.check", title: "Verificare", kind: .maintenance,
                                             recurrence: .metric(every: 500, unit: gas, fallback: .years(1)))]
        )
        // As an earlier version stored them: labels, not keys.
        custom.sectionsData = Data(String(decoding: try #require(custom.sectionsData), as: UTF8.self).replacingOccurrences(of: #""unit":"m3""#, with: #""unit":"mc""#).utf8)
        custom.blueprintsData = Data(String(decoding: try #require(custom.blueprintsData), as: UTF8.self).replacingOccurrences(of: #""unit":"m3""#, with: #""unit":"m³""#).utf8)
        let boiler = Asset(name: "Centrală Apartament", templateKey: custom.key)
        context.insert(boiler)
        let deadline = Obligation(title: "Verificare", kind: .maintenance, dueDay: CalendarDay("2027-01-10"),
                                  recurrence: .metric(every: 500, unit: gas, fallback: .years(1)), calendar: .bucharest)
        deadline.recurrenceData = Data(#"{"every":500,"fallbackEvery":1,"fallbackUnit":"year","type":"metric","unit":"mc"}"#.utf8)
        context.insert(deadline)
        deadline.asset = boiler
        let labels = ["m³", "mc", "kWh", "cafele", ""]
        for (index, label) in labels.enumerated() {
            let log = MeasurementLog(kind: .gas, name: "", value: Double(100 + index), recordedAt: noon("2026-0\(index + 1)-01"))
            log.unit = label
            context.insert(log)
            log.asset = boiler
        }
        try context.save()

        let step = UnitKeysStep()
        let changed = try step.migrate(in: context)
        #expect(changed == labels.count - 1 + 2, "Four readings, the deadline and the category; no unit stays none")
        let units = try context.fetch(FetchDescriptor<MeasurementLog>(sortBy: [SortDescriptor(\.value)])).map(\.unit)
        #expect(units == ["m3", "m3", "kwh", "shots", ""])
        #expect(deadline.recurrence == .metric(every: 500, unit: gas, fallback: .years(1)))
        #expect(String(decoding: try #require(deadline.recurrenceData), as: UTF8.self).contains(#""unit":"m3""#))
        #expect(custom.sections.first?.fields.first?.unit == gas)
        #expect(String(decoding: try #require(custom.sectionsData), as: UTF8.self).contains(#""unit":"m3""#))
        #expect(String(decoding: try #require(custom.blueprintsData), as: UTF8.self).contains(#""unit":"m3""#))
        try context.save()

        #expect(try step.migrate(in: context) == 0, "A second run changes nothing")
        #expect(context.hasChanges == false)
    }

    @Test func theRepairRunsByItselfAndLeavesAnUnknownRecurrenceAsItWas() throws {
        let context = try makeContext()
        let deadline = Obligation(title: "Altceva", kind: .routine, dueDay: CalendarDay("2027-01-10"), calendar: .bucharest)
        let newer = Data(#"{"type":"weekdays","unit":"mc","days":[1,3]}"#.utf8)
        deadline.recurrenceData = newer
        context.insert(deadline)
        let log = MeasurementLog(kind: .electricity, name: "", value: 1_200, recordedAt: noon("2026-01-01"))
        log.unit = "kWh"
        context.insert(log)
        try context.save()

        let found = try DataRepairs(context: context, calendar: .bucharest,
                                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "units-\(UUID().uuidString)")!)).detect()
        #expect(!found.contains { $0.step == .unitKeys }, "It never asks")
        #expect(log.unit == "kwh")
        #expect(deadline.recurrenceData == newer, "A recurrence from a newer version is kept as stored")
    }

    // MARK: Backups

    /// Labels in the store go out as keys and come back as keys; a backup that still has
    /// labels reads too.
    @Test func backupsWriteKeysAndReadBoth() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let home = Asset(name: "Apartament", templateKey: BuiltInTemplates.Key.home)
        context.insert(home)
        for (index, label) in ["m³", "mc", "kWh"].enumerated() {
            let log = MeasurementLog(kind: .gas, name: "", value: Double(10 + index), recordedAt: noon("2026-0\(index + 1)-01"))
            log.unit = label
            context.insert(log)
            log.asset = home
        }
        try context.save()

        let data = try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-02"))
        let entries = Dictionary(uniqueKeysWithValues: try DosarZipEngine.unpackArchive(data).map { ($0.path, $0.data) })
        let written = String(decoding: try #require(entries[DossierV3.Path.measurements]), as: UTF8.self)
        #expect(written.contains(#""unit" : "m3""#))
        #expect(written.contains(#""unit" : "kwh""#))
        #expect(!written.contains("m³") && !written.contains(#""mc""#))

        var package = try DossierArchiveReader.read(data)
        let gas = try #require(package.measurements.firstIndex { $0.value == 10 })
        package.measurements[gas].unit = "mc"
        let target = try makeInMemoryContainer()
        _ = try DossierArchiveService(container: target, calendar: .bucharest).importPackage(package, mode: .replace)
        let units = try ModelContext(target).fetch(FetchDescriptor<MeasurementLog>(sortBy: [SortDescriptor(\.value)])).map(\.unit)
        #expect(units == ["m3", "m3", "kwh"])
    }

    @Test func theGoldenFixtureReadsItsUnitsAsKeys() throws {
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v3/household"), mode: .replace)
        let context = ModelContext(container)
        let units = Set(try context.fetch(FetchDescriptor<MeasurementLog>()).compactMap(\.measurementUnit))
        #expect(units == [.kilometres, .engineHours], "Both written as keys, km and h")
        let boats = try #require(try TemplateStore(context: context).templatesByKey()["custom.0b6c6f43-6c1e-4d1a-9c55-7d3b4f1f2a10"])
        #expect(boats.sections.first?.fields.last?.unit == .engineHours)
    }
}
