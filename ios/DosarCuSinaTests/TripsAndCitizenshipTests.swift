import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// „Pleci din țară” for every household: several trips kept at once, each until it is over;
/// the documents each traveller needs following their citizenship, declared once as data
/// (`TravelRules`); the citizenship read from a person's documents and kept on them; and the
/// residence permit as a personal document. Placeholder people, numbers and codes only.
@Suite("Trips and citizenship")
@MainActor
struct TripsAndCitizenshipTests {
    let calendar = Calendar.bucharest

    private func trip(_ plan: TripPlan, _ assets: [ReadinessAsset]) -> [ReadinessItem] {
        ReadinessEngine.check(.trip(plan), assets: assets, calendar: calendar)
    }

    private func store() throws -> (TripPlanStore, UserDefaults, String) {
        let suite = "trips.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        nonisolated(unsafe) let unsafeDefaults = defaults
        return (TripPlanStore(defaults: { unsafeDefaults }), defaults, suite)
    }

    // MARK: Several trips

    @Test("Several trips are kept, the soonest first, each until it is over")
    func severalTripsAreKept() throws {
        let (store, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ana = UUID(), ion = UUID()
        let summer = TripPlan(start: CalendarDay("2027-07-12"), end: CalendarDay("2027-07-20"), region: .europeanUnion, destination: "Grecia",
                              travellers: [.member(ana), .member(ion)])
        let weekend = TripPlan(start: CalendarDay("2027-05-01"), end: CalendarDay("2027-05-03"), region: .outsideEU, destination: "Serbia",
                               travellers: [.member(ion)])
        store.save(summer)
        store.save(weekend)
        #expect(store.load(today: CalendarDay("2027-04-01")).map(\.id) == [weekend.id, summer.id], "The soonest first")

        var changed = summer
        changed.destination = "Italia"
        store.save(changed)
        #expect(store.load(today: CalendarDay("2027-04-01")).map(\.destination) == ["Serbia", "Italia"], "A change keeps its place, never a second copy")

        #expect(store.load(today: CalendarDay("2027-05-04")).map(\.id) == [summer.id], "A trip that is over drops away by itself")
        store.remove(summer.id)
        #expect(store.load(today: CalendarDay("2027-05-04")).isEmpty)
    }

    @Test("The one trip an earlier version kept is brought across")
    func theSingleTripIsBroughtAcross() throws {
        let (store, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ana = UUID()
        let written = #"{"start":"2027-07-12","end":"2027-07-20","region":"europeanUnion","destination":"Grecia","travellers":[{"member":{"_0":"\#(ana.uuidString)"}}],"vehicles":[],"pets":[]}"#
        defaults.set(Data(written.utf8), forKey: TripPlanStore.singleTripKey)

        let first = store.load(today: CalendarDay("2027-07-01"))
        #expect(first.map(\.destination) == ["Grecia"])
        #expect(first.first?.travellers == [.member(ana)])
        #expect(defaults.data(forKey: TripPlanStore.singleTripKey) == nil, "Moved, not copied")
        #expect(store.load(today: CalendarDay("2027-07-01")) == first, "and it keeps its id from then on")
    }

    // MARK: The rules, by citizenship

    @Test("Every citizenship's rules are declared for both regions, and none names a country")
    func rulesAreDeclaredForEveryGroup() {
        for group in Citizenship.Group.allCases {
            for region in TripPlan.Region.allCases {
                #expect(TravelRules.table[group]?[region] != nil, "\(group) \(region)")
            }
        }
        #expect(TravelRules.requirements(for: .freeMovement, in: .europeanUnion).map(\.accepted) == [[DocumentType.idCard, DocumentType.passport]])
        #expect(TravelRules.requirements(for: .thirdCountry, in: .europeanUnion).map(\.need) == [.passport, .residencePermit])
        #expect(TravelRules.requirements(for: .thirdCountry, in: .outsideEU).map(\.need) == [.passport, .residencePermit])
        for group in Citizenship.Group.allCases {
            let outside = TravelRules.requirements(for: group, in: .outsideEU)
            #expect(outside.contains { $0.need == .passport && $0.countsTravelCutoff }, "Everyone needs a passport outside the EU")
        }
        #expect(TravelRules.requirements(for: .unknown, in: .europeanUnion).isEmpty, "Nothing is assumed before the citizenship is known")
    }

    @Test("Inside the EU an EU citizen needs an identity card or a passport, either one")
    func eitherDocumentInsideTheEU() {
        let ana = ReadinessAsset.member("Ana")
        let none = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana]), [ana])
        let identity = none[id: "trip.identity.\(ana.id)"]
        #expect(identity?.status == .missing)
        #expect(identity?.title == "Carte de identitate sau pașaport", "Neither is demanded over the other")
        #expect(identity?.action == .addPersonalDocument(holderID: ana.id))

        let passport = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2030-01-01", holder: ana)
        let withPassport = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, passport]), [ana, passport])
        #expect(withPassport[id: "trip.identity.\(ana.id)"]?.status == .ok, "A passport alone is enough")
        #expect(withPassport[id: "trip.residencePermit.\(ana.id)"] == nil)

        // A Swiss or Norwegian citizen moves freely too.
        for code in ["CH", "NO", "DE"] {
            let other = ReadinessAsset.member("Exemplu", citizenship: Citizenship.key(code))
            let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: other)
            #expect(trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [other, card]), [other, card])[id: "trip.identity.\(other.id)"]?.status == .ok, "\(code)")
        }
    }

    @Test("A citizen of a country outside the EU needs a passport and a valid residence permit")
    func thirdCountryCitizenNeedsAPermit() {
        let ion = ReadinessAsset.member("Ion", citizenship: Citizenship.key("MD"))
        let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: ion)
        let passport = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2030-01-01", holder: ion)
        let permit = ReadinessAsset.personalDocument(DocumentType.residencePermit, expires: "2027-07-15", holder: ion)
        let assets = [ion, card, passport, permit]

        let inEU = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: assets), assets)
        #expect(inEU[id: "trip.identity.\(ion.id)"] == nil, "An identity card isn't the rule for him")
        #expect(inEU[id: "trip.passport.\(ion.id)"]?.status == .ok)
        let ending = inEU[id: "trip.residencePermit.\(ion.id)"]
        #expect(ending?.status == .problem, "The permit ends before he comes back")
        #expect(ending?.action == .open(.asset(permit.id)))

        let outside = trip(.everyone(start: "2027-07-12", end: "2027-07-14", region: .outsideEU, in: assets), assets)
        #expect(outside[id: "trip.residencePermit.\(ion.id)"]?.status == .ok, "Valid until he is back")
        #expect(outside[id: "trip.passport.\(ion.id)"]?.status == .ok)
        #expect(outside[id: "trip.visa.\(ion.id)"]?.status == .reminder, "The destination's visa rules, to look up")

        let noPermit = trip(.everyone(start: "2027-07-12", end: "2027-07-14", region: .europeanUnion, in: [ion, passport]), [ion, passport])
        #expect(noPermit[id: "trip.residencePermit.\(ion.id)"]?.status == .missing)
        #expect(noPermit[id: "trip.residencePermit.\(ion.id)"]?.title == "Permis de ședere")
        #expect(noPermit[id: "trip.residencePermit.\(ion.id)"]?.action == .addPersonalDocument(holderID: ion.id))
    }

    @Test("Outside the EU everyone is reminded of the visa rules; inside, no one")
    func visaReminderOutsideTheEU() {
        let ana = ReadinessAsset.member("Ana")
        let outside = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .outsideEU, in: [ana]), [ana])
        #expect(outside[id: "trip.visa.\(ana.id)"]?.status == .reminder)
        let inside = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana]), [ana])
        #expect(inside[id: "trip.visa.\(ana.id)"] == nil)
    }

    @Test("With no citizenship known it is asked, and Romanian is never assumed")
    func unknownCitizenshipIsAsked() {
        let ana = ReadinessAsset.member("Ana", citizenship: nil)
        let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: ana)
        let inEU = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ana, card]), [ana, card])
        let asked = inEU[id: "trip.citizenship.\(ana.id)"]
        #expect(asked?.status == .missing)
        #expect(asked?.action == .chooseCitizenship(holderID: ana.id))
        #expect(inEU[id: "trip.identity.\(ana.id)"] == nil, "The identity card isn't counted as enough before it is known")

        let outside = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .outsideEU, in: [ana, card]), [ana, card])
        #expect(outside[id: "trip.citizenship.\(ana.id)"] != nil)
        #expect(outside[id: "trip.passport.\(ana.id)"]?.status == .missing, "Everyone needs a passport outside the EU, meanwhile")

        let answered = ReadinessAsset.member("Ana")
        #expect(trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [answered]), [answered])[id: "trip.citizenship.\(answered.id)"] == nil,
                "Asked once: kept on the person, never again")
    }

    @Test("A citizenship is read from the person's documents when they have none kept")
    func citizenshipFromDocuments() {
        let ion = ReadinessAsset.member("Ion", citizenship: nil)
        let passport = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2030-01-01", holder: ion, nationality: "MDA")
        let items = trip(.everyone(start: "2027-07-12", end: "2027-07-20", region: .europeanUnion, in: [ion, passport]), [ion, passport])
        #expect(items[id: "trip.citizenship.\(ion.id)"] == nil)
        #expect(items[id: "trip.residencePermit.\(ion.id)"]?.status == .missing, "Moldova's rules, read off his passport")

        // A person with two: the free-movement one decides.
        let card = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: ion, nationality: "Română / ROU")
        #expect(ReadinessEngine.citizenship(of: .member(ion.id), in: [ion, passport, card]) == Citizenship.romania)

        // What is kept on the person wins over the documents.
        let stated = ReadinessAsset.member("Ion", citizenship: Citizenship.key("MD"))
        let romanianCard = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2030-01-01", holder: stated, nationality: "ROU")
        #expect(ReadinessEngine.citizenship(of: .member(stated.id), in: [stated, romanianCard]) == Citizenship.key("MD"))
    }

    // MARK: Countries

    @Test("A document's nationality names its country: the zone's code, a card's line, a name")
    func nationalitiesAreRead() {
        #expect(Citizenship.key(forNationality: "ROU") == Citizenship.romania)
        #expect(Citizenship.key(forNationality: "Română / ROU") == Citizenship.romania)
        #expect(Citizenship.key(forNationality: "ROMÂNĂ") == Citizenship.romania)
        #expect(Citizenship.key(forNationality: "D") == Citizenship.key("DE"), "Germany's zone prints a single letter")
        #expect(Citizenship.key(forNationality: "MDA") == Citizenship.key("MD"))
        #expect(Citizenship.key(forNationality: "RKS") == Citizenship.key("XK"))
        #expect(Citizenship.key(forNationality: "XXA") == Citizenship.stateless)
        #expect(Citizenship.key(forNationality: "Exemplu") == nil)
        #expect(Citizenship.key(forNationality: nil) == nil)

        #expect(Citizenship.group(of: Citizenship.romania) == .freeMovement)
        #expect(Citizenship.group(of: Citizenship.key("CH")) == .freeMovement)
        #expect(Citizenship.group(of: Citizenship.key("IS")) == .freeMovement)
        #expect(Citizenship.group(of: Citizenship.key("GB")) == .thirdCountry)
        #expect(Citizenship.group(of: Citizenship.key("MD")) == .thirdCountry)
        #expect(Citizenship.group(of: Citizenship.stateless) == .thirdCountry)
        #expect(Citizenship.group(of: nil) == .unknown)
    }

    @Test("The countries are stable keys by ISO code, named in Romanian, the EU's 27 among them")
    func countriesAreData() throws {
        let keys = Citizenship.options.map(\.key)
        #expect(Set(keys).count == keys.count, "One key per country")
        #expect(keys.allSatisfy { $0.hasPrefix("country.") })
        #expect(Citizenship.label(for: Citizenship.romania) == "România")
        #expect(Citizenship.freeMovement.count == 31, "27 EU states, Iceland, Liechtenstein, Norway and Switzerland")
        #expect(Citizenship.freeMovement.allSatisfy { code in Citizenship.countries.contains { $0.code == code } })
        #expect(Set(Citizenship.countries.map(\.printedCode)).count == Citizenship.countries.count)
        let field = try #require(BuiltInTemplates.member.field(MemberFields.citizenship))
        #expect(field.type == .choice)
        #expect(field.options?.map(\.key) == keys)
        #expect(field.isSensitive, "Never in search or outside the app")
    }

    // MARK: The residence permit

    @Test("The residence permit is a personal document type, with its reminders and its back")
    func residencePermitIsADocumentType() {
        #expect(DocumentType.label(for: DocumentType.residencePermit) == "Permis de ședere")
        #expect(DocumentType.options.contains { $0.key == DocumentType.residencePermit }, "Offered when adding a person's documents")
        #expect(DocumentType.keepsBackSide(DocumentType.residencePermit))
        #expect(DocumentType.travelMarginDays(for: DocumentType.residencePermit) == 0, "Good for travel until it expires")
        let renew = BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew }
        let reminders = renew?.reminders(for: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.residencePermit)]))
        #expect(reminders?.leadDays == [90, 45], "Its extension is asked for at least 30 days before it ends")
        #expect(!ObligationRequirements.list(forBlueprint: BuiltInBlueprints.documentRenew,
                                             values: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.residencePermit)])).isEmpty)
        #expect(CaptureDocumentKind.residencePermit.profile.documentType == DocumentType.residencePermit)
        #expect(CaptureDocumentKind.residencePermit.isIdentityDocument)
    }

    static let permitZone = """
    IRROURP12345672<<<<<<<<<<<<<<<
    9005204M3001318MDA<<<<<<<<<<<8
    EXEMPLU<<ION<<<<<<<<<<<<<<<<<<
    """

    static let permitFront = """
    ROMÂNIA
    PERMIS DE ȘEDERE / RESIDENCE PERMIT
    Nume / Surname
    EXEMPLU
    Prenume / Given names
    ION
    Valabil până la / Valid until
    31.01.2030
    Tipul permisului / Type of permit
    MUNCĂ
    Cetățenie / Nationality
    MDA
    """

    @Test("A residence permit's zone names it, and an identity card's stays an identity card")
    func zoneNamesThePermit() throws {
        let permit = try #require(MRZParser.parse(text: Self.permitZone, referenceDate: noon("2026-11-10")))
        #expect(permit.allChecksValid)
        #expect(permit.nationality == "MDA", "The holder's citizenship, not Romania's")
        #expect(DocumentClassifier.classify(text: CaptureText(Self.permitZone), mrz: permit).kind == .residencePermit)

        let identityCard = """
        I<UTOD231458907<<<<<<<<<<<<<<<
        7408122F1204159UTO<<<<<<<<<<<6
        ERIKSSON<<ANNA<MARIA<<<<<<<<<<
        """
        let card = try #require(MRZParser.parse(text: identityCard, referenceDate: noon("2010-01-01")))
        #expect(DocumentClassifier.classify(text: CaptureText(identityCard), mrz: card).kind == .identityCard)
    }

    @Test("A residence permit's front is read by its template: the holder, the expiry and the citizenship")
    func permitFrontIsRead() async throws {
        #expect(DocumentClassifier.classify(text: CaptureText(Self.permitFront), mrz: nil).kind == .residencePermit)
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: Self.permitFront),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(Self.permitFront), options: CaptureOptions(useOnDeviceModel: false, storeDocument: false,
                                                                                                         referenceDate: noon("2026-11-10"))))
        #expect(result.kind == .residencePermit)
        #expect(result.fields.first { $0.key == .nationality }?.value.text == "MDA")
        #expect(result.fields.first { $0.key == .expiryDate }?.value.day == CalendarDay("2030-01-31"))
    }

    // MARK: Filing keeps the citizenship on the person

    private func passport(nationality: String) -> CaptureResult {
        func field(_ key: CaptureFieldKey, _ value: CaptureValue) -> CaptureField {
            CaptureField(key: key, value: value, confidence: 0.95, sourceText: nil, tier: .deterministic)
        }
        let fields = [
            field(.surname, .text("EXEMPLU")),
            field(.givenNames, .text("ION")),
            field(.holderName, .text("ION EXEMPLU")),
            field(.nationality, .text(nationality)),
            field(.documentNumber, .text("X1234567")),
            field(.expiryDate, .day(CalendarDay("2031-04-06"))),
        ]
        let routing = CaptureRouter.route(kind: .passport, kindConfidence: 0.95, fields: fields)
        return CaptureResult(kind: .passport, kindConfidence: 0.95, fields: fields, suggestions: routing.suggestions,
                             reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: [])
    }

    @Test("Filing a passport keeps its citizenship on its holder, never over one already kept")
    func filingKeepsTheCitizenship() async throws {
        let context = try makeContext()
        let memberTemplate = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.member))
        let ion = try AssetActions(context: context).create(name: "Ion Exemplu", template: memberTemplate, values: FieldValues())
        let filer = CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") })

        let review = CaptureReview(result: passport(nationality: "MDA"), assets: [ion], context: context)
        #expect(review.destination == .asset(ion.id))
        _ = try await filer.save(review)
        #expect(ion.values[MemberFields.citizenship] == .text(Citizenship.key("MD")))

        // A second passport, another country's: the citizenship kept stays.
        _ = try await filer.save(CaptureReview(result: passport(nationality: "ROU"), assets: [ion], context: context))
        #expect(ion.values[MemberFields.citizenship] == .text(Citizenship.key("MD")), "Changed only on the person's page")
    }
}
