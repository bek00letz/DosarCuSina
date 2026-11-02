import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Visits with many parts")
struct VisitTests {
    @Test func oneVisitRecordsEveryTickedPartInOneSave() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.odometer"] = .number(100_000)
        let car = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-01-10") }).create(name: "Mașina", template: template, values: values)
        let mechanic = try ProviderActions(context: context).create(name: "Service exemplu", trades: [.mechanic])

        let entry = try HistoryActions(context: context, now: { noon("2026-06-01") }).recordVisit(
            on: car,
            checklist: [
                .init(componentKey: "engine.oil", cost: Money(420)),
                .init(componentKey: "filters.cabin"),
                .init(componentKey: "brakes.padsFront", cost: Money(380), partBrandOrCode: "Marca"),
            ],
            totalCost: Money(1_100),
            odometer: 108_000,
            provider: mechanic,
            documents: [DocumentDraft(title: "Factură service", fileName: "factura.pdf", kind: .invoice, contentType: "com.adobe.pdf", originalData: Data([1, 2, 3]))],
            calendar: .bucharest
        )
        #expect(entry.items?.count == 3)
        #expect(Set(entry.items?.compactMap(\.componentKey) ?? []) == ["engine.oil", "filters.cabin", "brakes.padsFront"])
        #expect(entry.items?.first { $0.componentKey == "filters.cabin" }?.name == "Filtru de habitaclu", "Names come from the catalog")
        #expect(entry.title == "Revizie: 3 lucrări")
        #expect(entry.totalCost == Money(1_100))
        #expect(entry.providerNames == ["Service exemplu"])
        #expect(entry.attachments?.first?.asset?.id == car.id)
        #expect(car.value("vehicle.odometer") == .number(108_000))
        #expect(car.measurements?.contains { $0.value == 108_000 } == true)
        #expect(context.hasChanges == false, "Everything was saved together")
    }

    @Test func checklistGroupsComponentsInCatalogOrder() {
        let groups = ComponentCatalog.checklist(for: BuiltInComponents.vehicle)
        #expect(groups.first?.title == "Frâne")
        #expect(groups.flatMap(\.components).count == BuiltInComponents.vehicle.count)
        #expect(Set(groups.map(\.title)).count == groups.count)
    }
}

@Suite("Next replacement estimate")
struct NextEstimateTests {
    let calendar = Calendar.bucharest

    private var pads: [HistoryItemSnapshot] {
        [
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe", occurredAt: noon("2023-01-10"), metricReading: 60_000),
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe", occurredAt: noon("2025-01-10"), metricReading: 90_000),
        ]
    }

    @Test func oneJobIsNotAPattern() {
        #expect(MaintenanceLog.nextEstimate(of: "brakes.padsFront", in: Array(pads.prefix(1)), now: noon("2026-01-10"), calendar: calendar) == nil)
    }

    @Test func usesDistanceAndPaceWhenKnown() throws {
        let readings = [
            CadenceCalculator.TelemetryReading(date: noon("2025-07-10"), metric: 100_000),
            CadenceCalculator.TelemetryReading(date: noon("2026-01-06"), metric: 106_000),
        ]
        #expect(MaintenanceLog.monthlyRate(readings).map { ($0 - 1_000).magnitude < 5 } == true, "About 1 000 km a month")
        let estimate = try #require(MaintenanceLog.nextEstimate(of: "brakes.padsFront", in: pads, readings: readings, currentMetric: 106_000,
                                                                 now: noon("2026-01-10"), calendar: calendar))
        #expect(estimate.basis == .distance)
        #expect(estimate.metric == 120_000)
        #expect((CalendarDay("2026-01-10").days(to: estimate.day, calendar: calendar) - 420).magnitude < 10, "14 000 km at ~1 000 km a month")
    }

    @Test func fallsBackToTimeWithoutAPace() throws {
        let estimate = try #require(MaintenanceLog.nextEstimate(of: "brakes.padsFront", in: pads, now: noon("2026-01-10"), calendar: calendar))
        #expect(estimate.basis == .time)
        #expect(estimate.day == CalendarDay("2025-01-10").adding(days: 731, calendar: calendar))
        #expect(MaintenanceLog.monthlyRate([CadenceCalculator.TelemetryReading(date: noon("2026-01-01"), metric: 1)]) == nil)
    }
}
