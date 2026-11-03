import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import DosarCuSina

@Suite("Readiness checks")
struct ReadinessTests {
    let calendar = Calendar.bucharest

    private func trip(_ plan: TripPlan, _ assets: [ReadinessAsset]) -> [ReadinessItem] {
        ReadinessEngine.check(.trip(plan), assets: assets, calendar: calendar)
    }

    // MARK: Trip: people

    @Test("I didn't check my passport when I booked the trip")
    func passportNeedsItsTravelCutoffAfterANonEUTrip() {
        let ana = ReadinessAsset.member("Ana")
        let passport = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2027-03-01", holder: ana)
        let assets = [ana, passport]
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .outsideEU, in: assets), assets)
        let check = items[id: "trip.passport.\(ana.id)"]
        #expect(items.first?.status == .problem, "Problems come first")
        #expect(check?.status == .problem)
        #expect(check?.action == .open(.asset(passport.id)))

        let renewed = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2031-03-01", holder: ana)
        let ok = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .outsideEU, in: [ana, renewed]), [ana, renewed])
        #expect(ok[id: "trip.passport.\(ana.id)"]?.status == .ok)
    }

    @Test func outsideTheEUAnIDCardIsNotEnough() {
        let ana = ReadinessAsset.member("Ana")
        let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: ana)
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .outsideEU, in: [ana, card]), [ana, card])
        let passport = items[id: "trip.passport.\(ana.id)"]
        #expect(passport?.status == .missing)
        #expect(passport?.action == .addPersonalDocument(holderID: ana.id), "A missing document is added for the person, photo first")
        #expect(items[id: "trip.identity.\(ana.id)"] == nil)
        #expect(items[id: "trip.ehic.\(ana.id)"] == nil, "The European health card is for the EU")
    }

    @Test func anIDCardIsEnoughInsideTheEU() {
        let ana = ReadinessAsset.member("Ana")
        let assets = [
            ana,
            ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2029-01-01", holder: ana),
            ReadinessAsset.personalDocument(DocumentType.passport, expires: "2027-02-01", holder: ana),
            ReadinessAsset.personalDocument(DocumentType.euHealthCard, expires: "2026-12-31", holder: ana),
        ]
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, in: assets), assets)
        #expect(items[id: "trip.identity.\(ana.id)"]?.status == .ok)
        #expect(items[id: "trip.identity.\(ana.id)"]?.title == DocumentType.label(for: DocumentType.idCard))
        #expect(items[id: "trip.passport.\(ana.id)"] == nil, "Inside the EU the passport's cut-off doesn't matter")
        #expect(items[id: "trip.ehic.\(ana.id)"]?.status == .warning, "The health card ends mid-trip")
    }

    @Test func anExpiredIDCardInsideTheEU() {
        let ana = ReadinessAsset.member("Ana")
        let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2026-12-30", holder: ana)
        let alone = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, in: [ana, card]), [ana, card])
        #expect(alone[id: "trip.identity.\(ana.id)"]?.status == .problem, "It ends before the trip does")

        // A passport valid until its printed expiry stands in for it inside the EU, even within its cut-off.
        let passport = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2027-02-01", holder: ana)
        let withPassport = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, in: [ana, card, passport]), [ana, card, passport])
        let identity = withPassport[id: "trip.identity.\(ana.id)"]
        #expect(identity?.status == .ok)
        #expect(identity?.title == DocumentType.label(for: DocumentType.passport))
        #expect(identity?.action == .open(.asset(passport.id)))
    }

    @Test func onlyThePeopleGoingAreChecked() {
        let ana = ReadinessAsset.member("Ana")
        let ion = ReadinessAsset.member("Ion")
        let assets = [
            ana, ion,
            ReadinessAsset.personalDocument(DocumentType.passport, expires: "2031-01-01", holder: ana),
            ReadinessAsset.personalDocument(DocumentType.passport, expires: "2027-01-10", holder: ion),
        ]
        var plan = TripPlan.everyone(start: "2026-12-20", end: "2027-01-05", region: .outsideEU, in: assets)
        plan.travellers = [.member(ana.id)]
        let result = ReadinessEngine.checklist(.trip(plan), assets: assets, calendar: calendar)
        #expect(result.groups.map(\.title) == ["Ana"])
        #expect(result.isAllReady)

        plan.travellers = [.member(ana.id), .member(ion.id)]
        let both = ReadinessEngine.checklist(.trip(plan), assets: assets, calendar: calendar)
        #expect(both.groups.map(\.title) == ["Ana", "Ion"])
        #expect(both.items[id: "trip.passport.\(ion.id)"]?.status == .problem, "Ion's passport isn't Ana's")
        #expect(both.attentionCount == 1)
    }

    @Test func documentsFiledUnderNoOneTravelTogether() {
        let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2029-01-01")
        let candidates = ReadinessEngine.tripCandidates(in: [card])
        #expect(candidates.travellers.map(\.traveller) == [.unfiled])
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, in: [card]), [card])
        #expect(items[id: "trip.identity.unfiled"]?.status == .ok)
    }

    @Test func aTripFromAMembersPageStartsWithThem() {
        let ana = ReadinessAsset.member("Ana")
        let ion = ReadinessAsset.member("Ion")
        let fromAna = ReadinessEngine.defaultTrip(start: CalendarDay("2027-07-12"), end: CalendarDay("2027-07-20"), holderID: ana.id, assets: [ana, ion])
        #expect(fromAna.travellers == [.member(ana.id)])
        #expect(fromAna.vehicles.isEmpty && fromAna.pets.isEmpty)
        let fromUpcoming = ReadinessEngine.defaultTrip(start: CalendarDay("2027-07-12"), end: CalendarDay("2027-07-20"), holderID: nil, assets: [ana, ion])
        #expect(fromUpcoming.travellers == [.member(ana.id), .member(ion.id)])
    }

    // MARK: Trip: the car and the pet

    @Test func drivingChecksTheCar() {
        let ana = ReadinessAsset.member("Ana")
        let licence = ReadinessAsset.personalDocument(DocumentType.drivingLicence, expires: "2030-01-01", holder: ana)
        let car = ReadinessAsset.car(dues: [
            BuiltInBlueprints.vehicleRCA: "2026-12-30",
            BuiltInBlueprints.vehicleITP: "2027-06-01",
            BuiltInBlueprints.vehicleVignette: "2026-12-25",
        ])
        let assets = [ana, licence, car, ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: ana)]
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, driving: true, in: assets), assets)
        #expect(items[id: "vehicle.rca.\(car.id)"]?.status == .problem, "RCA ends during the trip")
        #expect(items[id: "trip.greenCard.\(car.id)"]?.status == .problem, "The green card comes with the RCA")
        #expect(items[id: "vehicle.itp.\(car.id)"]?.status == .ok)
        #expect(items[id: "vehicle.vignette.\(car.id)"]?.status == .warning, "Valid to the border, not for the way back")
        #expect(items[id: "trip.licence.\(car.id)"]?.status == .ok)
        #expect(items.map(\.status) == items.map(\.status).sorted())
    }

    @Test func aMissingRCAIsAddedFromTheChecklist() {
        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleITP: "2027-06-01", BuiltInBlueprints.vehicleVignette: "2026-12-01"])
        let plan = TripPlan.everyone(start: "2026-12-20", end: "2027-01-05", region: .outsideEU, driving: true, in: [car])
        let items = trip(plan, [car])
        let rca = items[id: "vehicle.rca.\(car.id)"]
        #expect(rca?.status == .missing)
        #expect(rca?.action == .addDeadline(assetID: car.id, blueprintKey: BuiltInBlueprints.vehicleRCA))
        #expect(items[id: "trip.greenCard.\(car.id)"]?.status == .missing)
        #expect(items[id: "vehicle.vignette.\(car.id)"]?.status == .problem, "Expired before leaving")
        #expect(items[id: "trip.licence.\(car.id)"]?.status == .missing)
    }

    @Test func aValidRCABringsTheGreenCard() {
        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleRCA: "2027-06-01"])
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .outsideEU, driving: true, in: [car]), [car])
        #expect(items[id: "trip.greenCard.\(car.id)"]?.status == .ok)
    }

    @Test func petsNeedTheirPassportAndARabiesVaccineInTime() {
        var petValues = FieldValues()
        petValues[PetFields.passport] = .text("RO-000000")
        let cat = ReadinessAsset(name: "PawPaw", templateKey: BuiltInTemplates.Key.pet, values: petValues, obligations: [
            BuiltInBlueprints.petRabies: ReadinessObligation(due: CalendarDay("2027-12-10"), lastDone: CalendarDay("2026-12-10")),
        ])
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, withPet: true, in: [cat]), [cat])
        #expect(items[id: "trip.rabies.\(cat.id)"]?.status == .problem, "Vaccinated only 10 days before leaving")
        #expect(items[id: "trip.petPassport.\(cat.id)"]?.status == .ok)
        #expect(items[id: "trip.petTiter.\(cat.id)"] == nil)

        let outside = trip(.everyone(start: "2027-02-20", end: "2027-03-05", region: .outsideEU, withPet: true, in: [cat]), [cat])
        #expect(outside[id: "trip.rabies.\(cat.id)"]?.status == .ok)
        #expect(outside[id: "trip.petTiter.\(cat.id)"]?.status == .reminder)

        let noPet = trip(.everyone(start: "2027-02-20", end: "2027-03-05", region: .outsideEU, in: [cat]), [cat])
        #expect(noPet.isEmpty, "A pet that stays home isn't checked")
    }

    @Test("The due day is the last valid day")
    func theDueDayIsTheLastValidDay() {
        #expect(DueDayValidity.isValid(due: CalendarDay("2027-01-05"), on: CalendarDay("2027-01-05")))
        #expect(!DueDayValidity.isValid(due: CalendarDay("2027-01-05"), on: CalendarDay("2027-01-06")))
        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleRCA: "2027-01-05"])
        let items = trip(.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, driving: true, in: [car]), [car])
        #expect(items[id: "vehicle.rca.\(car.id)"]?.status == .ok, "An RCA valid until the day of return covers the trip")
    }

    // MARK: Claim

    @Test("Where's the policy number for a claim?")
    func claimShowsTheFollowedPolicysNumberAndPhone() {
        var values = FieldValues()
        values[VehicleFields.claimsPhone] = .text("0700000001")
        var car = ReadinessAsset.car(values: values, dues: [BuiltInBlueprints.vehicleRCA: "2027-01-01"], documentKinds: [.policy])
        car.obligations[BuiltInBlueprints.vehicleRCA]?.reference = "POL-000001"
        let result = ReadinessEngine.checklist(.insuranceClaim(assetId: car.id), assets: [car], today: CalendarDay("2026-11-03"), calendar: calendar)
        #expect(result.policy?.blueprintKey == BuiltInBlueprints.vehicleRCA)
        #expect(result.policy?.policyNumber == "POL-000001", "The RCA reference stands in for a missing policy field")
        #expect(result.policy?.claimsPhone == "0700000001")
        #expect(result.groups.first { $0.id == "claim.policy" }?.items.allSatisfy { $0.status == .ok } == true)
        #expect(result.groups.contains { $0.id == "claim.photos" })
        #expect(result.items[id: "claim.photo.otherDriver"]?.status == .reminder, "A car's claim asks for the other driver's papers")
    }

    @Test func aCASCOClaimShowsCASCOsFactsAndTheChoice() {
        var values = FieldValues()
        values[VehicleFields.policyNumber] = .text("RCA-000001")
        values[VehicleFields.claimsPhone] = .text("0700000001")
        values[VehicleFields.cascoPolicyNumber] = .text("CASCO-000001")
        values[VehicleFields.cascoClaimsPhone] = .text("0700000002")
        let car = ReadinessAsset.car(values: values, dues: [BuiltInBlueprints.vehicleRCA: "2027-01-01", BuiltInBlueprints.vehicleCASCO: "2027-01-01"])
        let rca = ReadinessEngine.checklist(.insuranceClaim(assetId: car.id), assets: [car], today: CalendarDay("2026-11-03"), calendar: calendar)
        #expect(rca.policyOptions.map(\.blueprintKey) == [BuiltInBlueprints.vehicleRCA, BuiltInBlueprints.vehicleCASCO])
        #expect(rca.policy?.policyNumber == "RCA-000001")

        let casco = ReadinessEngine.checklist(.insuranceClaim(assetId: car.id, blueprintKey: BuiltInBlueprints.vehicleCASCO), assets: [car],
                                              today: CalendarDay("2026-11-03"), calendar: calendar)
        #expect(casco.policy?.policyNumber == "CASCO-000001")
        #expect(casco.policy?.claimsPhone == "0700000002")
        #expect(casco.policy?.whenToUse != rca.policy?.whenToUse)
    }

    @Test func aClaimWithoutTheNumberOrOnAnExpiredPolicySaysSo() {
        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleRCA: "2026-10-01"])
        let result = ReadinessEngine.checklist(.insuranceClaim(assetId: car.id), assets: [car], today: CalendarDay("2026-11-03"), calendar: calendar)
        #expect(result.items[id: "claim.policyNumber"]?.status == .missing)
        #expect(result.items[id: "claim.policyNumber"]?.action == .editSection(assetID: car.id))
        #expect(result.items[id: "claim.phone"]?.status == .missing)
        #expect(result.items[id: "claim.validity"]?.status == .problem)
        #expect(result.items[id: "claim.policyDocument"]?.action == .addDocument(assetID: car.id), "The policy is added photo first")
    }

    @Test func aHomeClaimGoesToPADOrTheOptionalPolicy() {
        var values = FieldValues()
        values[HomeFields.policyNumber] = .text("PAD-000001")
        values[HomeFields.optionalPolicyNumber] = .text("FAC-000001")
        values[HomeFields.optionalClaimsPhone] = .text("0700000003")
        let home = ReadinessAsset(name: "Apartament", templateKey: BuiltInTemplates.Key.home, values: values, facts: ReadinessFacts.of(BuiltInTemplates.home))
        let pad = ReadinessEngine.checklist(.insuranceClaim(assetId: home.id, blueprintKey: BuiltInBlueprints.homePAD), assets: [home], calendar: calendar)
        let optional = ReadinessEngine.checklist(.insuranceClaim(assetId: home.id, blueprintKey: BuiltInBlueprints.homeInsurance), assets: [home], calendar: calendar)
        #expect(pad.policy?.policyNumber == "PAD-000001")
        #expect(pad.policy?.claimsPhone == nil, "PAD never borrows the optional policy's phone")
        #expect(optional.policy?.policyNumber == "FAC-000001")
        #expect(optional.policy?.claimsPhone == "0700000003")
        #expect(pad.policy?.whenToUse != optional.policy?.whenToUse)
        #expect(pad.items[id: "claim.photo.rooms"] != nil, "A home's claim asks for the rooms, not the cars")
        #expect(pad.items[id: "claim.photo.cars"] == nil)
    }

    @Test("A claim on each policy shows that policy's own facts", arguments: BuiltInTemplates.all.flatMap { template in
        template.blueprints.filter { $0.facts != nil }.map { (template.key, $0.key) }
    })
    func eachPolicysClaimShowsItsOwnFacts(templateKey: String, blueprintKey: String) throws {
        let template = try #require(BuiltInTemplates.definition(for: templateKey))
        let facts = try #require(template.blueprints.first { $0.key == blueprintKey }?.facts)
        // Every policy of the category has its own made-up values; only this one's may show.
        var values = FieldValues()
        for blueprint in template.blueprints {
            for (role, field) in blueprint.facts?.fields ?? [] where values[field] == nil {
                values[field] = .text("\(blueprint.key) \(role.rawValue)")
            }
        }
        let asset = ReadinessAsset(name: "Exemplu", templateKey: templateKey, values: values, facts: ReadinessFacts.of(template))
        let result = ReadinessEngine.checklist(.insuranceClaim(assetId: asset.id, blueprintKey: blueprintKey), assets: [asset], calendar: calendar)
        let expectedNumber = facts.policyNumber.flatMap { values[$0]?.textValue }
        let expectedPhone = facts.claimsPhone.flatMap { values[$0]?.textValue }
        #expect(result.policy?.policyNumber == expectedNumber)
        #expect(result.policy?.claimsPhone == expectedPhone)

        // The deadline page reads the same facts.
        let page = DeadlineFacts.of(blueprintKey: blueprintKey, in: template, values: values, reference: nil)
        #expect(page.policyNumber == expectedNumber)
        #expect(page.claimsPhone == expectedPhone)
        #expect(page.insurer == facts.insurer.flatMap { values[$0]?.textValue })
        #expect(result.policy?.insurer == page.insurer)
    }

    @Test func aCASCODeadlineNeverShowsTheRCAPolicy() {
        var values = FieldValues()
        values[VehicleFields.policyNumber] = .text("RCA-000001")
        values[VehicleFields.claimsPhone] = .text("0210000001")
        let casco = DeadlineFacts.of(blueprintKey: BuiltInBlueprints.vehicleCASCO, in: BuiltInTemplates.vehicle, values: values, reference: nil)
        #expect(casco.policyNumber == nil)
        #expect(casco.claimsPhone == nil)
        let itp = DeadlineFacts.of(blueprintKey: BuiltInBlueprints.vehicleITP, in: BuiltInTemplates.vehicle, values: values, reference: nil)
        #expect(itp == DeadlineFacts(), "A deadline with no facts shows none")
    }

    // MARK: Sale

    @Test func sellingACarAsksForTheIdentityTheHistoryAndAValidITP() {
        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleITP: "2026-10-01", BuiltInBlueprints.vehicleRCA: "2027-03-01"])
        let result = ReadinessEngine.checklist(.sellingVehicle(assetId: car.id), assets: [car], today: CalendarDay("2026-11-03"), calendar: calendar)
        let items = result.items
        #expect(items[id: "sale.\(VehicleFields.vin)"]?.status == .missing)
        #expect(items[id: "sale.\(VehicleFields.civ)"]?.action == .editSection(assetID: car.id))
        #expect(items[id: "sale.history"]?.status == .warning)
        #expect(items[id: "sale.itp"]?.status == .problem, "The buyer can't register it without a valid ITP")
        #expect(items[id: "sale.rca"]?.status == .ok)
        #expect(items[id: "sale.invoices"]?.action == .addDocument(assetID: car.id))
        #expect(result.groups.map(\.id) == ["sale.buyer", "sale.money", "sale.after"])
    }

    @Test func afterTheSaleThePoliciesAreCancelledAndWhatIsOwedIsPaid() {
        let tax = ReadinessObligation(due: CalendarDay("2026-09-30"), title: "Impozit auto", kind: .tax, amount: Money(120, currency: "RON"))
        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleRCA: "2027-03-01", BuiltInBlueprints.vehicleCASCO: "2027-03-01"], other: [tax])
        let items = ReadinessEngine.check(.sellingVehicle(assetId: car.id), assets: [car], today: CalendarDay("2026-11-03"), calendar: calendar)
        let rca = car.obligations[BuiltInBlueprints.vehicleRCA]!
        let casco = car.obligations[BuiltInBlueprints.vehicleCASCO]!
        #expect(items[id: "sale.after.cancel.\(rca.id)"]?.action == .open(.obligation(rca.id)))
        #expect(items[id: "sale.after.cancel.\(casco.id)"] != nil)
        let owed = items[id: "sale.owed.\(tax.id)"]
        #expect(owed?.status == .problem)
        #expect(owed?.detail.contains("120") == true)
    }

    // MARK: Where situations live

    @Test func situationsLiveWhereTheyBelong() throws {
        #expect(ReadinessSituation.offered(by: BuiltInTemplates.vehicle) == [.sale, .claim])
        #expect(ReadinessSituation.offered(by: BuiltInTemplates.home) == [.claim])
        #expect(ReadinessSituation.offered(by: BuiltInTemplates.member) == [.trip])
        #expect(ReadinessSituation.offered(by: BuiltInTemplates.documents).isEmpty)
        #expect(ReadinessSituation.offered(by: BuiltInTemplates.other).isEmpty)
        #expect(ReadinessSituation.allCases.filter(\.isHouseholdWide) == [.trip], "Urmează offers the trip")
        let id = UUID()
        #expect(ReadinessSituation.sale.route(for: id) == .readiness(.sale(assetID: id)))
        #expect(ReadinessSituation.sale.route(for: nil) == nil, "A sale needs its car")
        #expect(ReadinessSituation.trip.route(for: nil) == .readiness(.trip(holderID: nil)))
    }

    @Test func aChecklistOverALockedCategoryReadsAsSensitive() {
        let ana = ReadinessAsset.member("Ana")
        let passport = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2031-01-01", holder: ana, isSensitive: true)
        let car = ReadinessAsset.car()
        #expect(ReadinessEngine.readsSensitive(.trip(holderID: nil), assets: [ana, passport, car]))
        #expect(!ReadinessEngine.readsSensitive(.trip(holderID: nil), assets: [ana, car]))
        #expect(!ReadinessEngine.readsSensitive(.sale(assetID: car.id), assets: [ana, passport, car]), "A sale reads only its car")
        var locked = car
        locked.isSensitive = true
        #expect(ReadinessEngine.readsSensitive(.claim(assetID: car.id), assets: [locked]))
    }

    // MARK: The kept trip

    @Test func aTripIsKeptUntilItIsOver() throws {
        let suite = "readiness.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        nonisolated(unsafe) let unsafeDefaults = defaults
        let store = TripPlanStore(defaults: { unsafeDefaults })
        let plan = TripPlan(start: CalendarDay("2027-07-12"), end: CalendarDay("2027-07-20"), region: .europeanUnion, destination: "Grecia",
                            travellers: [.member(UUID()), .unfiled])
        store.save(plan)
        #expect(store.load(today: CalendarDay("2027-07-01")) == plan)
        #expect(store.load(today: CalendarDay("2027-07-20")) == plan, "Kept through the last day")
        #expect(store.load(today: CalendarDay("2027-07-21")) == nil, "Forgotten once it is over")
        #expect(store.load(today: CalendarDay("2027-07-01")) == nil, "and not brought back")
    }

    // MARK: The binder

    @MainActor
    @Test func readsTheBinder() throws {
        let context = try makeContext()
        try ExampleDataService(context: context, calendar: calendar, now: { noon("2026-11-02") }).loadExamples()
        let assets = try ReadinessAsset.fetchAll(in: context, calendar: calendar)
        let car = try #require(assets.first { $0.templateKey == BuiltInTemplates.Key.vehicle })
        #expect(car.obligations[BuiltInBlueprints.vehicleRCA] != nil)
        #expect(car.historyCount >= 2)
        let me = try #require(assets.first { $0.role == .holder })
        #expect(assets.contains { $0.role == .personalDocument && $0.parentId == me.id }, "Documents know their holder")
        #expect(assets.contains { $0.role == .personalDocument && $0.isSensitive }, "Acte asks for Face ID by default")
        let plan = TripPlan.everyone(start: "2027-01-10", end: "2027-01-20", region: .outsideEU, in: assets)
        let items = ReadinessEngine.check(.trip(plan), assets: assets, calendar: calendar)
        #expect(items[id: "trip.passport.\(me.id)"]?.status == .problem, "The example passport is past its travel cut-off on return")
    }
}

@MainActor
@Suite("Readiness screens")
struct ReadinessScreenTests {
    @Test func everyChecklistHasARouteAndALink() throws {
        let id = UUID()
        let routes: [ReadinessRoute] = [.trip(holderID: nil), .trip(holderID: id), .sale(assetID: id), .claim(assetID: id)]
        for route in routes {
            let url = DeepLink.url(for: .readiness(route))
            #expect(try #require(DeepLink.route(from: url)) == .readiness(route))
        }
        #expect(DeepLink.route(from: URL(string: "dosarcusina://ready/sale")!) == nil, "A sale names its car")
        #expect(DeepLink.route(from: URL(string: "dosarcusina://ready/party")!) == nil)
    }

    @Test func checklistsOpenOverWhatTheyBelongTo() {
        let id = UUID()
        #expect(ShellRouting.plan(for: .readiness(.trip(holderID: nil))) == ShellRoutePlan(tab: .upcoming, path: [.readiness(.trip(holderID: nil))]))
        #expect(ShellRouting.plan(for: .readiness(.trip(holderID: id))) == ShellRoutePlan(tab: .dosar, path: [.asset(id), .readiness(.trip(holderID: id))]))
        #expect(ShellRouting.plan(for: .readiness(.sale(assetID: id))) == ShellRoutePlan(tab: .dosar, path: [.asset(id), .readiness(.sale(assetID: id))]))
        #expect(ShellRouting.plan(for: .readiness(.claim(assetID: id))) == ShellRoutePlan(tab: .dosar, path: [.asset(id), .readiness(.claim(assetID: id))]))
    }

    private func size<V: View>(of view: V, width: CGFloat, typeSize: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, typeSize))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private var row: some View {
        DSReadinessRow(
            status: .problem,
            title: Text(verbatim: "Pașaport"),
            detail: Text(verbatim: "Bun de călătorit doar până pe 3 iunie 2027. Fă-ți altul înainte de plecare."),
            actionTitle: Text(verbatim: "Adaugă")
        ) {}
    }

    @Test(arguments: HitTargetTests.sizes)
    func aReadinessRowIsATargetAndNeverRunsOffTheScreen(typeSize: DynamicTypeSize) {
        let measured = size(of: row, width: 320, typeSize: typeSize)
        #expect(measured.height >= DS.Control.minimumHitTarget)
        #expect(measured.width <= 320.5)
    }

    @Test func theReasonWrapsInsteadOfBeingCut() {
        let large = size(of: row, width: 320, typeSize: .large)
        let huge = size(of: row, width: 320, typeSize: .accessibility5)
        #expect(huge.height > large.height * 2, "The whole reason is there at the largest size")
    }

    @Test func outcomesAreDrawnFromTheEngine() {
        #expect(DSStatus(readiness: .problem) == .overdue)
        #expect(DSStatus(readiness: .warning) == .soon)
        #expect(DSStatus(readiness: .ok) == .done)
        #expect(DSStatus(readiness: .missing) == nil)
        #expect(Set(ReadinessStatus.allCases.map(\.systemImage)).count == ReadinessStatus.allCases.count, "Every outcome has its own shape")
    }
}
