import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

private func field(_ key: CaptureFieldKey, _ value: CaptureValue, confidence: Double = 0.9) -> CaptureField {
    CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CaptureDay(year: parts[0], month: parts[1], day: parts[2])!)
}

/// A capture result routed the way the engine routes it.
private func capture(_ kind: CaptureDocumentKind, _ fields: [CaptureField]) -> CaptureResult {
    let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.9, fields: fields)
    return CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], document: nil, notices: [])
}

/// An ENGIE gas bill. Placeholder codes and addresses only.
private func gasBill(clc: String = "DEG0000000000001", issued: String = "2026-10-05", due: String = "2026-11-20",
                     supplyAddress: String? = nil, directDebit: String? = nil) -> CaptureResult {
    var fields = [
        field(.provider, .text("ENGIE Romania S.A.")),
        field(.serviceKind, .text(ServiceKind.gas)),
        field(.clientCode, .text("1000000000")),
        field(.clcCode, .text(clc)),
        field(.invoiceNumber, .text("EX 000000001")),
        field(.issueDate, day(issued)),
        field(.dueDate, day(due)),
        field(.total, .money(CaptureMoney(amount: Decimal(string: "245.30")!, currencyCode: "RON"))),
    ]
    if let supplyAddress { fields.append(field(.supplyAddress, .text(supplyAddress))) }
    if let directDebit { fields.append(field(.directDebit, .text(directDebit))) }
    return capture(.utilityInvoice, fields)
}

/// Where a bill is supplied and whether the bank pays it: the address read off the bill
/// and matched against the homes, "debit direct" read and offered (never switched on by
/// itself), and the bill reminder following the setting.
@Suite("Bills: the supply address and direct debit")
@MainActor
struct BillPlaceAndDirectDebitTests {

    private let today = "2026-11-02"

    // MARK: Addresses (pure)

    private func agreement(_ a: String, _ b: String) throws -> PostalAddress.Agreement {
        let left = try #require(PostalAddress(a), "\(a) reads as an address")
        let right = try #require(PostalAddress(b), "\(b) reads as an address")
        return left.agreement(with: right)
    }

    @Test func anAddressIsReadPartByPart() throws {
        let address = try #require(PostalAddress("Str. Exemplului nr. 1, bl. A1, sc. B, et. 3, ap. 12, Sector 3, București"))
        #expect(address.street == ["exemplului"])
        #expect(address.streetType == "strada")
        #expect(address.number == "1")
        #expect(address.block == "a1")
        #expect(address.staircase == "b")
        #expect(address.apartment == "12")
        #expect(address.sector == "3")
        #expect(address.locality == ["bucuresti"])

        let village = try #require(PostalAddress("Sat Exemplu nr. 12, Com. Exemplu, Jud. Exemplu"))
        #expect(village.street.isEmpty)
        #expect(village.number == "12")
        #expect(village.county == ["exemplu"])

        #expect(PostalAddress("Cod client 1000000000") == nil, "A code is not an address")
        #expect(PostalAddress("1234") == nil)
        #expect(PostalAddress("Index citit la locul de consum") == nil)
    }

    @Test func theSamePlaceWrittenManyWays() throws {
        #expect(try agreement("STRADA EXEMPLULUI NR.1 BL.A1 SC.B AP.12 SECTOR 3 BUCUREȘTI",
                              "Str. Exemplului 1, bl. A 1, sc. b, ap. 12, sect. 3, Bucuresti") == .same, "Case, dots, spacing, diacritics")
        #expect(try agreement("Str. Ștefan cel Mare nr. 5", "Strada Stefan cel Mare nr. 5") == .same, "Ș and S, Str. and Strada")
        #expect(try agreement("B-dul Exemplului nr. 2", "Bulevardul Exemplului 2") == .same, "B-dul and Bulevardul, with or without nr.")
        #expect(try agreement("Str. Gh. Exemplu nr. 3", "Str. Gheorghe Exemplu nr. 3") == .same, "An abbreviated first name")
        #expect(try agreement("Str. Exemplului nr. 01", "Str. Exemplului nr. 1") == .same)
        #expect(try agreement("Str. Exemplului nr. 12A", "Str. Exemplului nr. 12 A") == .same)
        #expect(try agreement("Str. Exemplului nr. 1, București", "Str. Exemplului nr. 1") == .same, "A town on one side only is still the place")
    }

    @Test func twoHomesOnTheSameStreetAreTwoPlaces() throws {
        #expect(try agreement("Str. Exemplului nr. 1", "Str. Exemplului nr. 5") == .different)
        #expect(try agreement("Str. Exemplului nr. 1, Brașov", "Str. Exemplului nr. 1, Cluj-Napoca") == .different, "Another town")
        #expect(try agreement("Str. Exemplului nr. 1, Sector 3", "Str. Exemplului nr. 1, Sector 4") == .different, "Another sector")
        #expect(try agreement("Str. Exemplului nr. 1", "Str. Alta nr. 1") == .different, "Another street")
    }

    @Test func theSameBlockWithDifferentApartments() throws {
        #expect(try agreement("Str. Exemplului nr. 1, bl. A1, ap. 12", "Str. Exemplului nr. 1, bl. A1, ap. 14") == .different)
        #expect(try agreement("Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12", "Str. Exemplului nr. 1, bl. A1, sc. C, ap. 12") == .different,
                "The same flat number in another staircase")
        #expect(try agreement("Str. Exemplului nr. 1, bl. A1, ap. 12", "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12") == .same,
                "The staircase left out on one side: the same flat")
        #expect(try agreement("Str. Exemplului nr. 1, bl. A1", "Str. Exemplului nr. 1, bl. A1, ap. 12") == .likely,
                "Which flat isn't said on one side")
    }

    @Test func whatOnlyNearlyAgreesIsLikelyNotSure() throws {
        #expect(try agreement("Str. Exemplu nr. 3", "Str. Exemplului nr. 3") == .likely, "The street's name with another ending")
        #expect(try agreement("Strada Exemplului", "Strada Exemplului nr. 3") == .likely, "No number on one side")
        #expect(try agreement("Calea Exemplului nr. 3", "Strada Exemplului nr. 3") == .likely, "Another kind of street, same name")
        #expect(try agreement("Sat Exemplu nr. 12, Com. Exemplu", "Sat Exemplu nr. 12") == .likely, "A village, by its number")
    }

    // MARK: Which home (pure)

    private typealias Home = SubscriptionMatcher.Home
    private typealias Reading = SubscriptionMatcher.Reading

    private func gasReading(_ address: String?, clc: String? = nil) -> Reading {
        Reading(provider: "ENGIE Romania S.A.", service: ServiceKind.gas, codes: clc.map { [.clc: $0] } ?? [:], isBill: true, supplyAddress: address)
    }

    @Test func theSupplyAddressPicksTheHomeWhenNoCodeDoes() {
        let one = UUID(), five = UUID()
        let homes = [Home(id: one, values: FieldValues(), address: "Str. Exemplului nr. 1, București"),
                     Home(id: five, values: FieldValues(), address: "Str. Exemplului nr. 5, București")]
        let placement = SubscriptionMatcher.place(gasReading("Strada Exemplului 5, Sector 3, Bucuresti"), subscriptions: [], homes: homes)
        #expect(placement == SubscriptionMatcher.Placement(.newUnder(home: five)), "Two homes on one street: the number decides, nothing to check")
        #expect(SubscriptionMatcher.match(gasReading(nil), subscriptions: [], homes: homes) == .undecided, "No address, no code: the person picks, as before")
        #expect(SubscriptionMatcher.match(gasReading("Str. Exemplului nr. 9"), subscriptions: [], homes: homes) == .undecided, "Neither home")
    }

    @Test func aFlatInTheSameBlockIsFoundByItsApartment() {
        let twelve = UUID(), fourteen = UUID()
        let homes = [Home(id: twelve, values: FieldValues(), address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12"),
                     Home(id: fourteen, values: FieldValues(), address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 14")]
        #expect(SubscriptionMatcher.place(gasReading("Str. Exemplului nr. 1, bl. A1, ap. 14"), subscriptions: [], homes: homes)
            == SubscriptionMatcher.Placement(.newUnder(home: fourteen)))
        #expect(SubscriptionMatcher.match(gasReading("Str. Exemplului nr. 1, bl. A1"), subscriptions: [], homes: homes) == .undecided,
                "The bill doesn't say which flat: both are likely, the person picks")
    }

    @Test func aPartialMatchIsSuggestedWithACheck() {
        let flat = UUID(), other = UUID()
        let homes = [Home(id: flat, values: FieldValues(), address: "Str. Exemplului nr. 5, ap. 12"),
                     Home(id: other, values: FieldValues(), address: "Str. Alta nr. 2")]
        let partial = SubscriptionMatcher.place(gasReading("Str. Exemplului nr. 5"), subscriptions: [], homes: homes)
        #expect(partial == SubscriptionMatcher.Placement(.newUnder(home: flat), check: .addressPartlyAgrees))

        // One home is the same place and another only likely: the same one, with a check.
        let near = UUID()
        let crowded = homes + [Home(id: near, values: FieldValues(), address: "Str. Exemplului nr. 5")]
        let pick = SubscriptionMatcher.place(gasReading("Str. Exemplului nr. 5, ap. 12"), subscriptions: [], homes: crowded)
        #expect(pick == SubscriptionMatcher.Placement(.newUnder(home: flat), check: .addressPartlyAgrees))
    }

    @Test func theOnlyHomeAtAnotherAddressIsKeptButChecked() {
        let only = UUID()
        let homes = [Home(id: only, values: FieldValues(), address: "Str. Exemplului nr. 1")]
        #expect(SubscriptionMatcher.place(gasReading("Str. Alta nr. 7"), subscriptions: [], homes: homes)
            == SubscriptionMatcher.Placement(.newUnder(home: only), check: .addressDiffers))
        #expect(SubscriptionMatcher.place(gasReading("Str. Exemplului nr. 1"), subscriptions: [], homes: homes)
            == SubscriptionMatcher.Placement(.newUnder(home: only)), "The same address: nothing to check")
        #expect(SubscriptionMatcher.place(gasReading(nil), subscriptions: [], homes: [Home(id: only, values: FieldValues())])
            == SubscriptionMatcher.Placement(.newUnder(home: only)), "Nothing to compare: as before")
    }

    @Test func codesStillComeFirst() {
        let one = UUID(), five = UUID()
        var coded = FieldValues()
        coded[HomeFields.clc] = .text("DEG0000000000001")
        let homes = [Home(id: one, values: coded, address: "Str. Exemplului nr. 1"),
                     Home(id: five, values: FieldValues(), address: "Str. Exemplului nr. 5")]
        #expect(SubscriptionMatcher.place(gasReading("Str. Exemplului nr. 5", clc: "DEG0000000000001"), subscriptions: [], homes: homes)
            == SubscriptionMatcher.Placement(.newUnder(home: one)), "The home's own CLC outranks the address")
    }

    @Test func theProviderDecidesInsideTheHomeTheAddressFound() {
        let one = UUID(), five = UUID(), gasOne = UUID(), gasFive = UUID()
        func gas(_ id: UUID, under home: UUID) -> SubscriptionMatcher.Subscription {
            var values = FieldValues()
            values[SubscriptionFields.provider] = .text("ENGIE Romania S.A.")
            values[SubscriptionFields.service] = .text(ServiceKind.gas)
            return .init(id: id, parentID: home, values: values)
        }
        let homes = [Home(id: one, values: FieldValues(), address: "Str. Exemplului nr. 1"),
                     Home(id: five, values: FieldValues(), address: "Str. Exemplului nr. 5")]
        #expect(SubscriptionMatcher.match(gasReading("Str. Exemplului nr. 5"), subscriptions: [gas(gasOne, under: one), gas(gasFive, under: five)], homes: homes)
            == .existing(gasFive))
    }

    // MARK: Reading the supply address

    @Test("Supply address wordings", arguments: [
        "Adresa locului de consum: Str. Exemplului nr. 5, bl. A1, ap. 12",
        "Adresa loc de consum: Str. Exemplului nr. 5, bl. A1, ap. 12",
        "Loc consum: Str. Exemplului nr. 5, bl. A1, ap. 12",
        "Adresa de livrare: Str. Exemplului nr. 5, bl. A1, ap. 12",
        "Adresa punctului de consum: Str. Exemplului nr. 5, bl. A1, ap. 12",
        "Adresa de instalare: Str. Exemplului nr. 5, bl. A1, ap. 12",
        "Loc de consum\nAdresa: Str. Exemplului nr. 5, bl. A1, ap. 12",
    ])
    func supplyAddressWordings(text: String) throws {
        let read = try #require(ContractReader.supplyAddress(in: CaptureText(text)))
        #expect(read.value == .text("Str. Exemplului nr. 5, bl. A1, ap. 12"))
    }

    @Test func theBillingAddressIsNeverTheSupplyAddress() throws {
        let both = """
        Adresa de facturare: Str. Alta nr. 9, Brașov
        Cod loc de consum (CLC): DEG0000000000001
        Adresa locului de consum: Str. Exemplului nr. 5
        Sector 3, București
        """
        let read = try #require(ContractReader.supplyAddress(in: CaptureText(both)))
        #expect(read.value == .text("Str. Exemplului nr. 5, Sector 3, București"), "The town on the next line belongs to it")

        let billingOnly = """
        Adresa de corespondență: Str. Alta nr. 9, Brașov
        Domiciliu: Str. Alta nr. 9
        Cod loc de consum: DEG0000000000001
        """
        #expect(ContractReader.supplyAddress(in: CaptureText(billingOnly)) == nil, "Never the payer's address, never a code")

        // Two homes: the billing address names one, the supply address the other.
        let nine = UUID(), five = UUID()
        let homes = [Home(id: nine, values: FieldValues(), address: "Str. Alta nr. 9, Brașov"),
                     Home(id: five, values: FieldValues(), address: "Str. Exemplului nr. 5, București")]
        let address = read.value.text
        #expect(SubscriptionMatcher.match(gasReading(address), subscriptions: [], homes: homes) == .newUnder(home: five))
    }

    @Test func aBillIsReadWithItsSupplyAddressAndDirectDebit() {
        let bill = """
        ENGIE Romania S.A.
        FACTURĂ FISCALĂ seria EX nr. 000000001
        Gaze naturale
        Cod client: 1000000000
        Cod loc de consum (CLC): DEG0000000000001
        Adresa de facturare: Str. Alta nr. 9, Brașov
        Adresa locului de consum: Str. Exemplului nr. 5, bl. A1, ap. 12
        Data facturii: 05.10.2026
        Data scadenței: 25.10.2026
        Total de plată: 245,30 lei
        Factura se achită prin debit direct.
        """
        let analysis = CaptureAnalyzer().analyze(text: bill, referenceDate: ContractCaptureTests.referenceDate)
        #expect(analysis.kind == .utilityInvoice)
        #expect(analysis.fields.first { $0.key == .supplyAddress }?.value == .text("Str. Exemplului nr. 5, bl. A1, ap. 12"))
        #expect(analysis.fields.first { $0.key == .directDebit }?.value == .text("Factura se achită prin debit direct."))
        #expect(CaptureDocumentKind.utilityInvoice.allows(.directDebit))
        #expect(!CaptureDocumentKind.rcaPolicy.allows(.supplyAddress), "Only bills and contracts carry them")
    }

    // MARK: Reading direct debit

    @Test("Direct debit, as bills say it", arguments: [
        "Factura se achită prin debit direct.",
        "Factura se va plăti prin debit direct la data scadenței.",
        "Suma de plată va fi încasată prin debit direct.",
        "Plata se face prin debit direct.",
        "Modalitate de plată: Debit direct",
        "Mod de plată: debitare directă",
        "Debit direct: activ",
        "Debitare directă: activă",
        "Domiciliere: DA",
        "Factura este domiciliată",
        "Suma va fi debitată din contul dumneavoastră la scadență.",
        "Mandat de debitare directă nr. EX-000001",
    ])
    func directDebitWordings(line: String) {
        #expect(ContractReader.statesDirectDebit(line))
        #expect(ContractReader.directDebit(in: CaptureText(line)) != nil)
    }

    @Test("Near misses: a no, an offer or a choice in a list", arguments: [
        "Nu aveți debit direct activ.",
        "Debit direct: inactiv",
        "Debit direct: nu",
        "Activează debitul direct și plătești mai simplu.",
        "Plătește prin debit direct din aplicație.",
        "Poți plăti prin debit direct sau online.",
        "Modalități de plată: debit direct, card, numerar",
        "Ai debit direct activ? Verifică în aplicație.",
        "Înscrie-te la debit direct: www.exemplu.ro",
        "Fără debit direct, factura se plătește până la scadență.",
        "Debit direct",
    ])
    func directDebitNearMisses(line: String) {
        #expect(!ContractReader.statesDirectDebit(line))
        #expect(ContractReader.directDebit(in: CaptureText(line)) == nil)
    }

    @Test func aHeadingAloneSaysItUnlessAnOfferIsBesideIt() {
        let status = "Total de plată: 245,30 lei\nPlata prin debit direct\nData scadenței: 25.10.2026"
        #expect(ContractReader.directDebit(in: CaptureText(status))?.value == .text("Plata prin debit direct"))
        let advert = "Plata prin debit direct\nActivează-l din aplicația Exemplu, în doi pași."
        #expect(ContractReader.directDebit(in: CaptureText(advert)) == nil)
        let list = "Modalități de plată:\nPlata prin debit direct\nPlata online"
        #expect(ContractReader.directDebit(in: CaptureText(list)) == nil, "One choice in a list of ways to pay")
        let split = "Factura se va achita prin debit\ndirect la data scadenței."
        #expect(ContractReader.directDebit(in: CaptureText(split)) != nil, "A sentence broken across two lines")
    }

    @Test func theAIProvidersAnswersFollowTheSameRules() throws {
        let json = #"{"documentKind":"utilityInvoice","supplyAddress":"Str. Exemplului nr. 5, bl. A1, ap. 12","directDebit":"Activează debitul direct"}"#
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let fields = CloudAnswerMapper.fields(from: answer, schema: CloudSchema(kind: .utilityInvoice), recognizedText: "",
                                              today: ContractCaptureTests.today, resolver: CatalogComponentResolver())
        #expect(fields.first { $0.key == .supplyAddress }?.value == .text("Str. Exemplului nr. 5, bl. A1, ap. 12"))
        #expect(!fields.contains { $0.key == .directDebit }, "An offer is never read as paid by direct debit")

        let stated = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"documentKind":"utilityInvoice","directDebit":"Factura se achită prin debit direct","supplyAddress":"Cod client 1000000000"}"#.utf8))
        let kept = CloudAnswerMapper.fields(from: stated, schema: CloudSchema(kind: .utilityInvoice), recognizedText: "",
                                            today: ContractCaptureTests.today, resolver: CatalogComponentResolver())
        #expect(kept.contains { $0.key == .directDebit })
        #expect(!kept.contains { $0.key == .supplyAddress }, "A code is not an address")
        #expect(CloudSchema(kind: .utilityInvoice).fields.contains { $0.key == .supplyAddress && $0.description.contains("billing") })
    }

    // MARK: The review and filing

    private func filer(_ context: ModelContext, on iso: String? = nil) -> CaptureFiler {
        let date = noon(iso ?? today)
        return CaptureFiler(context: context, calendar: .bucharest, now: { date })
    }

    private func home(_ name: String, _ context: ModelContext, address: String?) throws -> Asset {
        var values = FieldValues()
        if let address { values[HomeFields.address] = .text(address) }
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        return try AssetActions(context: context).create(name: name, template: template, values: values)
    }

    private func assets(_ context: ModelContext) throws -> [Asset] {
        try context.fetch(FetchDescriptor<Asset>())
    }

    private func review(_ result: CaptureResult, _ context: ModelContext) throws -> CaptureReview {
        CaptureReview(result: result, assets: try assets(context), context: context)
    }

    @Test func theReviewPutsTheBillInTheHomeAtItsAddress() throws {
        let context = try makeContext()
        _ = try home("Casa Pipera", context, address: "Str. Exemplului nr. 1, București")
        let five = try home("Apartament", context, address: "Str. Exemplului nr. 5, bl. A1, ap. 12, București")

        let sure = try review(gasBill(supplyAddress: "Str. Exemplului nr. 5, bl. A1, ap. 12"), context)
        #expect(sure.destination == .asset(five.id))
        #expect(sure.placeCheck == nil)

        var partial = try review(gasBill(supplyAddress: "Str. Exemplului nr. 5"), context)
        #expect(partial.destination == .asset(five.id), "Suggested")
        #expect(partial.placeCheck == .addressPartlyAgrees, "Marked Verifică")
        partial.choosePlace(.asset(five.id))
        #expect(partial.placeCheck == nil, "The person chose it: nothing left to check")

        let none = try review(gasBill(supplyAddress: "Str. Alta nr. 9"), context)
        #expect(none.destination == .none, "Neither home: the person picks, as before")
    }

    @Test func aHomeTakesTheAddressItsBillIsSuppliedAt() async throws {
        let context = try makeContext()
        // A new home made from the bill.
        var first = try review(gasBill(supplyAddress: "Str. Exemplului nr. 5, București"), context)
        first.destination = .newAsset(templateKey: BuiltInTemplates.Key.home)
        first.newAssetName = "Casa nouă"
        let made = try #require(try await filer(context).save(first).asset?.parent)
        #expect(made.value(HomeFields.address) == .text("Str. Exemplului nr. 5, București"))

        // A home without an address gets it; one with an address keeps its own.
        let context2 = try makeContext()
        let bare = try home("Casa", context2, address: nil)
        _ = try await filer(context2).save(try review(gasBill(supplyAddress: "Str. Exemplului nr. 5"), context2))
        #expect(bare.value(HomeFields.address) == .text("Str. Exemplului nr. 5"))

        let context3 = try makeContext()
        let written = try home("Casa", context3, address: "Strada Exemplului 5")
        _ = try await filer(context3).save(try review(gasBill(supplyAddress: "Str. Exemplului nr. 5, Sector 3"), context3))
        #expect(written.value(HomeFields.address) == .text("Strada Exemplului 5"), "The person's own wording stays")
    }

    @Test func directDebitOnTheBillIsOfferedAndNeverSwitchedOnByItself() async throws {
        let context = try makeContext()
        _ = try home("Casa", context, address: nil)
        let statement = "Factura se achită prin debit direct."
        let offered = try review(gasBill(directDebit: statement), context)
        #expect(offered.directDebitStatement(assets: try assets(context)) == statement)
        #expect(!offered.turnsOnDirectDebit, "Off until the person turns it on")
        #expect(filer(context).touchesReminders(offered), "Until then, the bill still reminds")

        let kept = try await filer(context).save(offered)
        let gas = try #require(kept.asset)
        #expect(!SubscriptionFields.paysByDirectDebit(gas.values), "Not switched on silently")
        #expect(gas.activeObligations.contains { $0.blueprintKey == SubscriptionFields.billBlueprint })
    }

    @Test func confirmingDirectDebitTurnsItOnAndSetsNoReminder() async throws {
        let context = try makeContext()
        _ = try home("Casa", context, address: nil)
        // The first bill made a reminder.
        let first = try await filer(context).save(try review(gasBill(), context))
        let gas = try #require(first.asset)
        let reminder = try #require(first.obligation)

        var next = try review(gasBill(issued: "2026-11-05", due: "2026-12-20", directDebit: "Plata se face prin debit direct."), context)
        #expect(next.destination == .asset(gas.id))
        next.turnsOnDirectDebit = true
        #expect(next.paysByDirectDebit(assets: try assets(context)))
        #expect(!filer(context, on: "2026-11-06").touchesReminders(next))
        let templates = try TemplateStore(context: context).templatesByKey()
        #expect(CaptureReminderPreview.text(for: next, templates: templates, assets: try assets(context), calendar: .bucharest, today: CalendarDay("2026-11-06"))?
            .contains("debit direct") == true)

        _ = try await filer(context, on: "2026-11-06").save(next)
        #expect(SubscriptionFields.paysByDirectDebit(gas.values))
        #expect(reminder.status == .paused, "The reminder already made pauses")
        #expect(gas.activeObligations.isEmpty, "And no new one")
        #expect((gas.history ?? []).filter { $0.kind == .payment }.count == 2, "Both bills are logged")

        // A subscription that already pays this way isn't offered it again.
        let again = try review(gasBill(issued: "2026-12-05", due: "2027-01-20", directDebit: "Plata se face prin debit direct."), context)
        #expect(again.directDebitStatement(assets: try assets(context)) == nil)
    }

    // MARK: The reminder follows the setting

    private func setDirectDebit(_ isOn: Bool, on subscription: Asset, _ context: ModelContext, on iso: String) throws -> AssetActions.EditOutcome {
        var values = subscription.values
        values[SubscriptionFields.directDebit] = .bool(isOn)
        let date = noon(iso)
        return try AssetActions(context: context, calendar: .bucharest, now: { date }).update(subscription, name: subscription.name, values: values, notes: subscription.notes)
    }

    @Test func turningOnDirectDebitPausesTheBillReminderAndAnuleazaBringsItBack() async throws {
        let context = try makeContext()
        _ = try home("Casa", context, address: nil)
        let first = try await filer(context).save(try review(gasBill(), context))
        let gas = try #require(first.asset)
        let reminder = try #require(first.obligation)

        let outcome = try setDirectDebit(true, on: gas, context, on: today)
        #expect(outcome.billReminder?.value == .paused)
        #expect(reminder.status == .paused)
        #expect(gas.activeObligations.isEmpty)

        try #require(outcome.billReminder).receipt.undo()
        #expect(reminder.status == .active, "Anulează: the reminder is back")
        #expect(!SubscriptionFields.paysByDirectDebit(gas.values), "And the setting with it, as one step")

        // A change that doesn't touch direct debit says nothing.
        var values = gas.values
        values[SubscriptionFields.clientCode] = .text("1000000009")
        let other = try AssetActions(context: context).update(gas, name: gas.name, values: values, notes: nil)
        #expect(other.billReminder == nil)
    }

    @Test func turningItOffBringsBackABillStillToPayAndTheNextBillTakesUpAnOlderOne() async throws {
        let context = try makeContext()
        _ = try home("Casa", context, address: nil)
        let first = try await filer(context).save(try review(gasBill(due: "2026-11-20"), context))
        let gas = try #require(first.asset)
        let reminder = try #require(first.obligation)

        _ = try setDirectDebit(true, on: gas, context, on: "2026-11-02")
        let back = try setDirectDebit(false, on: gas, context, on: "2026-11-10")
        #expect(back.billReminder?.value == .resumed, "Its day hasn't passed: it reminds again")
        #expect(reminder.status == .active)

        _ = try setDirectDebit(true, on: gas, context, on: "2026-11-12")
        let late = try setDirectDebit(false, on: gas, context, on: "2026-11-25")
        #expect(late.billReminder == nil, "Its day passed: nothing to bring back now")
        #expect(reminder.status == .paused)

        // The next bill takes the paused reminder up again, on its own day: never a second one.
        let next = try await filer(context, on: "2026-12-06").save(try review(gasBill(issued: "2026-12-05", due: "2026-12-20"), context))
        #expect(next.obligation?.id == reminder.id)
        #expect(reminder.status == .active)
        #expect(reminder.dueDay(in: .bucharest) == CalendarDay("2026-12-20"))
        #expect((gas.obligations ?? []).filter { $0.blueprintKey == SubscriptionFields.billBlueprint }.count == 1)
    }

    @Test func theMissingBillNoteStillWorksWithDirectDebit() async throws {
        let context = try makeContext()
        _ = try home("Casa", context, address: nil)
        var bill = try review(gasBill(issued: "2026-09-05", due: "2026-09-25", directDebit: "Factura se achită prin debit direct."), context)
        bill.turnsOnDirectDebit = true
        let gas = try #require(try await filer(context, on: "2026-09-06").save(bill).asset)
        #expect(SubscriptionFields.paysByDirectDebit(gas.values))

        let notes = AttentionModel.missingBills(try BillWatchSnapshot.fetchAll(in: context, calendar: .bucharest), now: noon(today), calendar: .bucharest)
        #expect(notes.map(\.assetId) == [gas.id], "The bank pays it, but a bill that hasn't come is still worth knowing")
    }
}
