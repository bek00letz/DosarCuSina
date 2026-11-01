import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Readiness checks")
struct ReadinessTests {
    let calendar = Calendar.bucharest

    private func document(_ type: String, expires: String) -> ReadinessAsset {
        var values = FieldValues()
        values["document.type"] = .text(type)
        values["document.expiry"] = .date(CalendarDay(expires))
        return ReadinessAsset(name: type, templateKey: BuiltInTemplates.Key.documents, values: values)
    }

    @Test("I didn't check my passport when I booked the trip")
    func passportNeedsSixMonthsAfterANonEUTrip() {
        let passport = document(DocumentType.passport, expires: "2027-03-01")
        let items = ReadinessEngine.check(
            .tripAbroad(start: CalendarDay("2026-12-20"), end: CalendarDay("2027-01-05"), region: .outsideEU, driving: false, withPet: false),
            assets: [passport], calendar: calendar
        )
        #expect(items.first?.status == .problem, "Problems come first")
        #expect(items.first?.title == DocumentType.passport)

        let renewed = document(DocumentType.passport, expires: "2031-03-01")
        let ok = ReadinessEngine.check(
            .tripAbroad(start: CalendarDay("2026-12-20"), end: CalendarDay("2027-01-05"), region: .outsideEU, driving: false, withPet: false),
            assets: [renewed], calendar: calendar
        )
        #expect(ok.first { $0.id.hasPrefix("trip.passport") }?.status == .ok)
    }

    @Test func anIDCardIsEnoughInsideTheEU() {
        let items = ReadinessEngine.check(
            .tripAbroad(start: CalendarDay("2026-12-20"), end: CalendarDay("2027-01-05"), region: .europeanUnion, driving: false, withPet: false),
            assets: [document(DocumentType.idCard, expires: "2029-01-01"), document(DocumentType.euHealthCard, expires: "2026-12-31")],
            calendar: calendar
        )
        #expect(items.first { $0.id == "trip.identity" }?.status == .ok)
        #expect(items.first { $0.id == "trip.ehic" }?.status == .warning, "The health card ends mid-trip")
    }

    @Test func drivingChecksTheCarAndPetsNeedTheirRabiesVaccineInTime() {
        let car = ReadinessAsset(name: "VW Golf", templateKey: BuiltInTemplates.Key.vehicle, obligations: [
            "vehicle.rca": ReadinessObligation(due: CalendarDay("2026-12-30")),
            "vehicle.itp": ReadinessObligation(due: CalendarDay("2027-06-01")),
        ])
        var petValues = FieldValues()
        petValues["pet.passport"] = .text("RO-000000")
        let cat = ReadinessAsset(name: "Pisica", templateKey: BuiltInTemplates.Key.pet, values: petValues, obligations: [
            "pet.rabies": ReadinessObligation(due: CalendarDay("2027-12-10"), lastDone: CalendarDay("2026-12-10")),
        ])
        let items = ReadinessEngine.check(
            .tripAbroad(start: CalendarDay("2026-12-20"), end: CalendarDay("2027-01-05"), region: .europeanUnion, driving: true, withPet: true),
            assets: [car, cat, document(DocumentType.idCard, expires: "2030-01-01")], calendar: calendar
        )
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byId["vehicle.rca.\(car.id)"]?.status == .problem, "RCA ends during the trip")
        #expect(byId["vehicle.itp.\(car.id)"]?.status == .ok)
        #expect(byId["vehicle.vignette.\(car.id)"]?.status == .missing)
        #expect(byId["trip.rabies.\(cat.id)"]?.status == .problem, "Vaccinated only 10 days before leaving")
        #expect(byId["trip.petPassport.\(cat.id)"]?.status == .ok)
        #expect(items.map(\.status) == items.map(\.status).sorted())
    }

    @Test("Where's the policy number for a claim?")
    func claimNeedsPolicyNumberPhoneAndPolicy() {
        var values = FieldValues()
        values["vehicle.claimsPhone"] = .text("+40210000000")
        let car = ReadinessAsset(name: "VW Golf", templateKey: BuiltInTemplates.Key.vehicle, values: values, obligations: [
            "vehicle.rca": ReadinessObligation(due: CalendarDay("2027-01-01"), reference: "POL-000001"),
        ], documentKinds: [.policy])
        let items = ReadinessEngine.check(.insuranceClaim(assetId: car.id), assets: [car], calendar: calendar)
        #expect(items.allSatisfy { $0.status == .ok })
        #expect(items.first { $0.id == "claim.policyNumber" }?.detail == "POL-000001", "The RCA reference stands in for a missing policy field")
    }

    @Test func sellingACarAsksForTheIdentityAndTheHistory() {
        let car = ReadinessAsset(name: "VW Golf", templateKey: BuiltInTemplates.Key.vehicle)
        let items = ReadinessEngine.check(.sellingVehicle(assetId: car.id), assets: [car], calendar: calendar)
        #expect(items.contains { $0.id == "sale.vehicle.vin" && $0.status == .missing })
        #expect(items.contains { $0.id == "sale.history" && $0.status == .warning })
    }

    @MainActor
    @Test func readsTheBinder() throws {
        let context = try makeContext()
        try ExampleDataService(context: context, calendar: calendar, now: { noon("2026-11-02") }).loadExamples()
        let assets = try ReadinessAsset.fetchAll(in: context, calendar: calendar)
        let car = try #require(assets.first { $0.templateKey == BuiltInTemplates.Key.vehicle })
        #expect(car.obligations["vehicle.rca"] != nil)
        #expect(car.historyCount >= 2)
        let items = ReadinessEngine.check(
            .tripAbroad(start: CalendarDay("2027-01-10"), end: CalendarDay("2027-01-20"), region: .outsideEU, driving: false, withPet: false),
            assets: assets, calendar: calendar
        )
        #expect(items.first?.status == .problem, "The example passport expires within 6 months of return")
    }
}
