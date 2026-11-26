import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Numbers an earlier version kept a step off (its `NSDecimalNumber.doubleValue` missed the
/// nearest Double) are put back on their short number by themselves, once, with no change time:
/// a reading, a record's counter and a section's number. Every value is a placeholder.
@MainActor
@Suite("Repair: numbers kept a step off")
struct DecimalDoublesRepairTests {
    private func repairs(_ context: ModelContext) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "decimal-doubles-\(UUID().uuidString)")!))
    }

    @Test func numbersKeptAStepOffArePutBackByThemselvesOnce() throws {
        let missed = try #require(RomanianNumberTests.missedBefore.first { $0.right > 1_000 })
        let context = try makeContext()
        let gas = MeasurementUnit.cubicMetres
        let custom = try TemplateStore(context: context).createCustom(
            name: "Centrală", symbol: "flame", tint: .orange,
            sections: [FieldSection(key: "boiler", title: "Centrală", fields: [
                FieldDefinition(key: "boiler.index", label: "Index", type: .metric, role: .heroMetric, unit: gas),
                FieldDefinition(key: "boiler.year", label: "An", type: .year),
            ])],
            blueprints: []
        )
        let boiler = Asset(name: "Centrală Apartament", templateKey: custom.key,
                           values: FieldValues(["boiler.index": .number(missed.old), "boiler.year": .number(2018), "boiler.other": .number(missed.old)]))
        context.insert(boiler)
        let reading = MeasurementLog(kind: .gas, name: "", value: missed.old, unit: gas, recordedAt: try AppCalendarTests.noon("2026-03-01"))
        context.insert(reading)
        reading.asset = boiler
        let kilometres = MeasurementLog(kind: .odometer, name: "", value: 45_724, unit: .kilometres, recordedAt: try AppCalendarTests.noon("2026-03-02"))
        context.insert(kilometres)
        kilometres.asset = boiler
        let visit = HistoryEntry(kind: .maintenance, title: "Revizie", occurredAt: try AppCalendarTests.noon("2026-03-01"))
        visit.metricReading = missed.old
        context.insert(visit)
        visit.asset = boiler
        try UnitOfWork.save(context)
        let times = [boiler.updatedAt, reading.updatedAt, visit.updatedAt]

        let found = try repairs(context).detect()
        #expect(!found.contains { $0.step == .decimalDoubles }, "It never asks")
        #expect(reading.value == missed.right)
        #expect(visit.metricReading == missed.right, "The record's counter stays the reading's")
        #expect(boiler.values["boiler.index"] == .number(missed.right))
        #expect(boiler.values["boiler.year"] == .number(2018))
        #expect(boiler.values["boiler.other"] == .number(missed.old), "A value no field of the category names stays")
        #expect(kilometres.value == 45_724)
        #expect([boiler.updatedAt, reading.updatedAt, visit.updatedAt] == times, "Only how the number is stored: no change time")

        #expect(try DecimalDoublesStep().migrate(in: context) == 0, "A second run changes nothing")
    }
}
