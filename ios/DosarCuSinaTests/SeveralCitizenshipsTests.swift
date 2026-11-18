import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A person can have several citizenships, all kept on them, and the trip check goes by the
/// most favourable for each trip, with that citizenship's documents; the travel rules as data
/// (`TravelRules`): the Schengen area, Moldova and the Western Balkans, an identity card
/// without a chip or the simple one, the residence card; a day already passed said as passed;
/// a rabies booster on time. Placeholder people, numbers and codes only.
@Suite("Several citizenships and the travel rules")
@MainActor
struct SeveralCitizenshipsTests {
    let calendar = Calendar.bucharest
    static let today = "2026-11-18"

    private func trip(_ plan: TripPlan, _ assets: [ReadinessAsset], today: String = Self.today) -> [ReadinessItem] {
        ReadinessEngine.check(.trip(plan), assets: assets, today: CalendarDay(today), calendar: calendar)
    }

    /// A household member who keeps these citizenships, as this version keeps them: a list.
    private func person(_ name: String, _ codes: [String]) -> ReadinessAsset {
        var values = FieldValues()
        values[MemberFields.citizenship] = .choices(codes.map(Citizenship.key))
        return ReadinessAsset(name: name, templateKey: BuiltInTemplates.Key.member, role: .holder, values: values)
    }

    private func document(_ type: String, expires: String, holder: ReadinessAsset, nationality: String? = nil, variant: String? = nil) -> ReadinessAsset {
        var document = ReadinessAsset.personalDocument(type, expires: expires, holder: holder, nationality: nationality)
        if let variant { document.values[DocumentType.variantFieldKey] = .text(variant) }
        return document
    }

    // MARK: Keeping several

    @Test("The citizenships are read from a list, or from the one key an earlier version kept")
    func citizenshipsAreAList() {
        var values = FieldValues()
        #expect(Citizenship.kept(in: values).isEmpty)
        values[MemberFields.citizenship] = .text(Citizenship.key("MD"))
        #expect(Citizenship.kept(in: values) == [Citizenship.key("MD")], "An earlier version's single value")
        values[MemberFields.citizenship] = .choices([Citizenship.romania, Citizenship.key("MD"), Citizenship.romania])
        #expect(Set(Citizenship.kept(in: values)) == [Citizenship.romania, Citizenship.key("MD")])
        #expect(Citizenship.kept(in: values).count == 2, "Each once")

        let kept = Citizenship.keeping([Citizenship.romania, Citizenship.key("MD")], in: FieldValues())
        #expect(kept?[MemberFields.citizenship]?.choicesValue?.count == 2)
        #expect(Citizenship.keeping([Citizenship.key("MD"), Citizenship.romania], in: kept ?? FieldValues()) == nil,
                "The same citizenships in another order are the same list")
    }

    @Test("The single citizenship an earlier version kept becomes a list by itself")
    func theSingleValueMovesIntoAList() throws {
        let context = try makeContext()
        let ion = Asset(name: "Ion Exemplu", templateKey: BuiltInTemplates.Key.member,
                        values: FieldValues([MemberFields.citizenship: .text(Citizenship.key("MD"))]))
        context.insert(ion)
        try ChoiceKeysStep().migrate(in: context)
        #expect(ion.values[MemberFields.citizenship] == .choices([Citizenship.key("MD")]), "Only how it is stored changes")
    }

    @Test("A second citizenship the documents show is offered once, and kept only with the owner's OK")
    func theRepairAddsTheSecondCitizenship() throws {
        let context = try makeContext()
        let ion = Asset(name: "Ion Exemplu", templateKey: BuiltInTemplates.Key.member,
                        values: FieldValues([MemberFields.citizenship: .text(Citizenship.key("MD"))]))
        context.insert(ion)
        let card = Asset(name: "Carte de identitate", templateKey: BuiltInTemplates.Key.documents,
                         values: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.idCard), DocumentFields.nationality: .text("ROU")]))
        context.insert(card)
        card.parent = ion
        let repairs = DataRepairs(context: context, calendar: .bucharest,
                                  ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "citizenships-\(UUID().uuidString)")!))

        let found = try repairs.detect().filter { $0.step == .citizenships }
        #expect(found.count == 1)
        #expect(found.first?.message.contains("România") == true)
        #expect(Citizenship.kept(in: ion.values) == [Citizenship.key("MD")], "Nothing is added before the owner says so")
        try repairs.apply(found)
        #expect(Set(Citizenship.kept(in: ion.values)) == [Citizenship.key("MD"), Citizenship.romania])
        #expect(try repairs.detect().filter { $0.step == .citizenships }.isEmpty, "Found once")
        #expect(!DataRepairs.step(.citizenships).isSuggestion)
    }

    // MARK: The most favourable citizenship

    @Test("A Romanian and Moldovan citizen goes into the EU on the Romanian card, never asked for a residence permit")
    func dualCitizenTravelsAsAnEUCitizen() {
        let ion = person("Ion", ["MD", "RO"])
        let moldovan = document(DocumentType.passport, expires: "2031-01-01", holder: ion, nationality: "MDA")
        let romanian = document(DocumentType.idCard, expires: "2030-01-01", holder: ion, nationality: "ROU")
        let assets = [ion, moldovan, romanian]
        let items = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: assets), assets)
        let identity = items[id: "trip.identity.\(ion.id)"]
        #expect(identity?.status == .ok)
        #expect(identity?.action == .open(.asset(romanian.id)), "The Romanian card")
        #expect(items[id: "trip.residencePermit.\(ion.id)"] == nil, "He can always come back in")
        #expect(items[id: "trip.passport.\(ion.id)"] == nil)
    }

    @Test("With only the Moldovan passport, a dual citizen is asked for a Romanian document, not a residence permit")
    func theOtherCountrysPassportStandsForItsOwnCitizenship() {
        let ion = person("Ion", ["MD", "RO"])
        let moldovan = document(DocumentType.passport, expires: "2031-01-01", holder: ion, nationality: "MDA")
        let items = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ion, moldovan]), [ion, moldovan])
        #expect(items[id: "trip.identity.\(ion.id)"]?.status == .missing, "A Moldovan passport isn't a Romanian citizen's document")
        #expect(items[id: "trip.residencePermit.\(ion.id)"] == nil, "Never told he can't come back in")
    }

    @Test("A Moldovan passport filed first doesn't make a dual citizen a citizen of a country outside the EU")
    func filingInAnyOrderKeepsBoth() async throws {
        let context = try makeContext()
        let memberTemplate = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.member))
        let ion = try AssetActions(context: context).create(name: "Ion Exemplu", template: memberTemplate, values: FieldValues())
        let filer = CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        _ = try await filer.save(CaptureReview(result: passport(nationality: "MDA", number: "X1234567"), assets: [ion], context: context))
        _ = try await filer.save(CaptureReview(result: passport(nationality: "ROU", number: "051234567"), assets: [ion], context: context))
        #expect(Set(Citizenship.kept(in: ion.values)) == [Citizenship.key("MD"), Citizenship.romania])

        let assets = try ReadinessAsset.fetchAll(in: context, calendar: .bucharest)
        let items = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: assets), assets)
        #expect(items[id: "trip.identity.\(ion.id)"]?.status == .ok)
        #expect(items[id: "trip.residencePermit.\(ion.id)"] == nil)
    }

    private func passport(nationality: String, number: String) -> CaptureResult {
        func field(_ key: CaptureFieldKey, _ value: CaptureValue) -> CaptureField {
            CaptureField(key: key, value: value, confidence: 0.95, sourceText: nil, tier: .deterministic)
        }
        let fields = [
            field(.surname, .text("EXEMPLU")),
            field(.givenNames, .text("ION")),
            field(.holderName, .text("ION EXEMPLU")),
            field(.nationality, .text(nationality)),
            field(.documentNumber, .text(number)),
            field(.expiryDate, .day(CalendarDay("2031-04-06"))),
        ]
        let routing = CaptureRouter.route(kind: .passport, kindConfidence: 0.95, fields: fields)
        return CaptureResult(kind: .passport, kindConfidence: 0.95, fields: fields, suggestions: routing.suggestions,
                             reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: [])
    }

    // MARK: Where they go

    @Test("Switzerland, Norway, Iceland and Liechtenstein are in the EU's region, where an identity card is enough")
    func theSchengenAreaIsOneRegion() {
        let region = TripPlan.Region.europeanUnion
        for name in ["Elveția", "Norvegia", "Islanda", "Liechtenstein"] {
            #expect(region.summary.contains(name), "\(name) is named where it belongs")
        }
        #expect(region.title.contains("Schengen"))
        #expect(TravelRules.requirements(forCitizenship: Citizenship.romania, in: region) == [TravelRules.identityOrPassport])
        #expect(TravelRules.requirements(forCitizenship: Citizenship.key("CH"), in: region) == [TravelRules.identityOrPassport])
    }

    @Test("In Moldova and the Western Balkans a Romanian identity card is enough, still valid three months after the trip")
    func moldovaTakesARomanianCard() {
        let ana = person("Ana", ["RO"])
        let lasting = document(DocumentType.idCard, expires: "2027-12-01", holder: ana)
        let plan = TripPlan.everyone(start: "2027-07-12", end: "2027-07-20", region: .moldovaAndWesternBalkans, in: [ana, lasting])
        let ok = trip(plan, [ana, lasting])
        #expect(ok[id: "trip.identity.\(ana.id)"]?.status == .ok)
        #expect(ok[id: "trip.passport.\(ana.id)"] == nil, "No passport asked of a Romanian citizen")

        let short = document(DocumentType.idCard, expires: "2027-09-01", holder: ana)
        let ending = trip(plan, [ana, short])[id: "trip.identity.\(ana.id)"]
        #expect(ending?.status == .problem, "Valid at return, but not three months after")
        #expect(ending?.detail.contains("3 luni") == true)

        #expect(TravelRules.requirements(forCitizenship: Citizenship.key("DE"), in: .moldovaAndWesternBalkans).map(\.need) == [.passport],
                "Another EU citizen's card isn't assumed")
        #expect(TravelRules.requirements(forCitizenship: Citizenship.key("MD"), in: .moldovaAndWesternBalkans).map(\.need) == [.passport, .residencePermit])
        #expect(TravelRules.requirements(forCitizenship: nil, in: .moldovaAndWesternBalkans).map(\.need) == [.passport])
        #expect(TravelRules.identityCards.keys.allSatisfy { $0 != .europeanUnion && $0 != .outsideEU })
    }

    @Test("A dual citizen goes to Moldova on the Romanian card")
    func dualCitizenInMoldova() {
        let ion = person("Ion", ["MD", "RO"])
        let card = document(DocumentType.idCard, expires: "2030-01-01", holder: ion, nationality: "ROU")
        let items = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .moldovaAndWesternBalkans, in: [ion, card]), [ion, card])
        #expect(items[id: "trip.identity.\(ion.id)"]?.status == .ok)
        #expect(items[id: "trip.residencePermit.\(ion.id)"] == nil)
    }

    // MARK: Kinds of identity card

    @Test("The simple identity card is no travel document; a passport beside it is")
    func theSimpleCardIsNoTravelDocument() {
        let ana = person("Ana", ["RO"])
        let simple = document(DocumentType.idCard, expires: "2035-01-01", holder: ana, variant: DocumentType.Variant.idCardSimple)
        let alone = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, simple]), [ana, simple])[id: "trip.identity.\(ana.id)"]
        #expect(alone?.status == .problem)
        #expect(alone?.detail == TravelWording.notATravelDocument)

        let passport = document(DocumentType.passport, expires: "2030-01-01", holder: ana)
        #expect(trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, simple, passport]),
                     [ana, simple, passport])[id: "trip.identity.\(ana.id)"]?.status == .ok)
        #expect(DocumentType.documentName(type: DocumentType.idCard, variant: DocumentType.Variant.idCardSimple) == "Carte de identitate simplă")
    }

    @Test("An identity card without a chip is good for travel until 2 August 2031 at the latest")
    func theCardWithoutAChipHasAnEnd() {
        let ana = person("Ana", ["RO"])
        let old = document(DocumentType.idCard, expires: "2034-03-01", holder: ana, variant: DocumentType.Variant.idCardWithoutChip)
        let before = trip(.everyone(start: "2031-07-25", end: "2031-08-02", region: .europeanUnion, in: [ana, old]), [ana, old])
        #expect(before[id: "trip.identity.\(ana.id)"]?.status == .ok)
        let after = trip(.everyone(start: "2031-07-25", end: "2031-08-03", region: .europeanUnion, in: [ana, old]), [ana, old])[id: "trip.identity.\(ana.id)"]
        #expect(after?.status == .problem)
        #expect(after?.detail.contains("Fără cip") == true)
        #expect(after?.detail.contains("2 august 2031") == true)
    }

    @Test("A family member's residence card and a British citizen's residence document count as the residence permit")
    func residenceCardsCount() {
        for variant in [DocumentType.Variant.residenceCard, DocumentType.Variant.withdrawalAgreement] {
            let sam = person("Sam", ["GB"])
            let passport = document(DocumentType.passport, expires: "2031-01-01", holder: sam)
            let card = document(DocumentType.residencePermit, expires: "2030-01-01", holder: sam, variant: variant)
            let items = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [sam, passport, card]), [sam, passport, card])
            #expect(items[id: "trip.residencePermit.\(sam.id)"]?.status == .ok, "\(variant)")
            #expect(DocumentType.variants(of: DocumentType.residencePermit).contains { $0.key == variant })
        }
        #expect(DocumentType.documentName(type: DocumentType.residencePermit, variant: DocumentType.Variant.residenceCard) == "Carte de rezidență")
    }

    // MARK: A day already passed

    @Test("A document that has already expired is said as expired, never in the future tense")
    func expiredIsSaidAsPast() {
        let ana = person("Ana", ["RO"])
        let expired = document(DocumentType.idCard, expires: "2026-05-01", holder: ana)
        let item = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, expired]), [ana, expired])[id: "trip.identity.\(ana.id)"]
        #expect(item?.detail.hasPrefix("A expirat pe 1 mai 2026.") == true)

        let ending = document(DocumentType.idCard, expires: "2027-07-15", holder: ana)
        #expect(trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, ending]), [ana, ending])[id: "trip.identity.\(ana.id)"]?
            .detail.hasPrefix("Expiră pe 15 iulie 2027") == true)

        let passport = document(DocumentType.passport, expires: "2026-10-01", holder: ana)
        #expect(trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .outsideEU, in: [ana, passport]), [ana, passport])[id: "trip.passport.\(ana.id)"]?
            .detail.hasPrefix("A expirat pe") == true)

        let car = ReadinessAsset.car(dues: [BuiltInBlueprints.vehicleRCA: "2026-09-01", BuiltInBlueprints.vehicleITP: "2026-10-01"])
        let carItems = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, driving: true, in: [car]), [car])
        #expect(carItems[id: "\(BuiltInBlueprints.vehicleRCA).\(car.id)"]?.detail.hasPrefix("A expirat pe") == true)
        #expect(carItems[id: "\(BuiltInBlueprints.vehicleITP).\(car.id)"]?.detail.hasPrefix("A expirat pe") == true)
        #expect(carItems[id: "trip.greenCard.\(car.id)"]?.detail.contains("care a expirat") == true)
        for item in carItems + trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, expired]), [ana, expired]) {
            #expect(!(item.detail.hasPrefix("Expiră pe") && item.detail.contains("2026")), "\(item.id): \(item.detail)")
        }
    }

    // MARK: A pet's rabies vaccine

    private func cat(lastDone: String, lastCycleDue: String?) -> ReadinessAsset {
        var values = FieldValues()
        values[PetFields.passport] = .text("RO-000000")
        return ReadinessAsset(name: "PawPaw", templateKey: BuiltInTemplates.Key.pet, values: values, obligations: [
            BuiltInBlueprints.petRabies: ReadinessObligation(due: CalendarDay("2027-12-10"), lastDone: CalendarDay(lastDone),
                                                             lastCycleDue: lastCycleDue.map { CalendarDay($0) }),
        ])
    }

    @Test("A rabies booster given before the one before ran out counts at once, even days before the trip")
    func aBoosterOnTimeCountsAtOnce() {
        let plan = { (pet: ReadinessAsset) in TripPlan.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, withPet: true, in: [pet]) }
        let booster = cat(lastDone: "2026-12-10", lastCycleDue: "2026-12-15")
        #expect(trip(plan(booster), [booster])[id: "trip.rabies.\(booster.id)"]?.status == .ok)
        let lapsed = cat(lastDone: "2026-12-10", lastCycleDue: "2026-11-30")
        #expect(trip(plan(lapsed), [lapsed])[id: "trip.rabies.\(lapsed.id)"]?.status == .problem, "After a lapse it waits its 21 days")
        let unknown = cat(lastDone: "2026-12-10", lastCycleDue: nil)
        #expect(trip(plan(unknown), [unknown])[id: "trip.rabies.\(unknown.id)"]?.status == .warning, "Not known: the passport says")
        let early = cat(lastDone: "2026-11-01", lastCycleDue: nil)
        #expect(trip(plan(early), [early])[id: "trip.rabies.\(early.id)"]?.status == .ok, "More than 21 days before: fine either way")
    }

    @Test("The citizenships repair is a new step at the end")
    func theRepairComesLast() {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        #expect(ids.last == .citizenships)
        #expect(DataRepairStepID.citizenships.rawValue == "citizenships")
    }
}
