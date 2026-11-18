import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What a subscription is, declared once per service (`ServiceKind.Service`): the codes its
/// papers are identified by (read, shown and asked only for that service), the group it is
/// listed under in Abonamente, and a telecom contract or its EU summary read well. Every value
/// is a placeholder.
@Suite("Subscriptions by service")
@MainActor
struct SubscriptionsByServiceTests {

    static let referenceDate = Date(timeIntervalSince1970: 1_793_577_600)

    // MARK: The declaration

    @Test func everyServiceDeclaresItsGroupAndCodes() {
        let groups = Dictionary(grouping: ServiceKind.services, by: \.group).mapValues { $0.map(\.key) }
        #expect(groups[.utilities] == [ServiceKind.gas, ServiceKind.electricity, ServiceKind.water, ServiceKind.heating, ServiceKind.sanitation])
        #expect(groups[.internetAndPhone] == [ServiceKind.internetTV, ServiceKind.mobile])
        #expect(groups[.transport] == [ServiceKind.transport])
        #expect(groups[.appsAndStreaming] == [ServiceKind.streaming])
        #expect(groups[.other] == [ServiceKind.other])
        #expect(SubscriptionGroup.allCases.map(\.label) == ["Utilități", "Internet și telefon", "Transport", "Aplicații și streaming", "Altele"])

        #expect(ServiceKind.codes(of: ServiceKind.electricity).contains(.pod))
        #expect(ServiceKind.codes(of: ServiceKind.gas).contains(.clc))
        #expect(ServiceKind.codes(of: ServiceKind.water).contains(.placeCode))
        for service in [ServiceKind.internetTV, ServiceKind.mobile] {
            let codes = ServiceKind.codes(of: service)
            #expect([SubscriptionCode.clientCode, .contractNumber, .account].allSatisfy(codes.contains))
            #expect(!codes.contains { $0.family == .consumptionPoint }, "Never a POD or a CLC for \(service)")
        }
        #expect(ServiceKind.codes(of: nil) == [.clientCode, .contractNumber], "Before the service is chosen: what any contract has")
        #expect(ServiceKind.isTiedToHome(ServiceKind.heating) && ServiceKind.isTiedToHome(ServiceKind.sanitation))
        #expect(!ServiceKind.sendsRegularBills(ServiceKind.streaming))
        #expect(ServiceKind.meterKind(for: ServiceKind.water) == .coldWater)
    }

    @Test func theEditFormShowsOnlyTheServicesCodes() {
        let definition = BuiltInTemplates.subscription
        func shown(for service: String?) -> Set<String> {
            var values = FieldValues()
            values[SubscriptionFields.service] = service.map(FieldValue.text)
            return Set(SubscriptionCode.allCases.map(\.fieldKey).filter { definition.field($0)?.applies(to: values) == true })
        }
        #expect(shown(for: ServiceKind.internetTV) == [SubscriptionFields.clientCode, SubscriptionFields.contractNumber, SubscriptionFields.account])
        #expect(shown(for: ServiceKind.mobile).contains(SubscriptionFields.phoneNumber))
        #expect(shown(for: ServiceKind.electricity) == [SubscriptionFields.pod, SubscriptionFields.clientCode, SubscriptionFields.contractNumber])
        #expect(shown(for: ServiceKind.water).contains(SubscriptionFields.placeCode))
        #expect(shown(for: ServiceKind.streaming).isEmpty)
        #expect(shown(for: nil) == [SubscriptionFields.clientCode, SubscriptionFields.contractNumber])
        for code in SubscriptionCode.allCases {
            #expect(definition.field(code.fieldKey)?.label == code.label, "One name for \(code)")
        }
    }

    @Test func aConditionThatHoldsBeforeAValueIsGivenIsKeptThroughJSON() throws {
        let condition = BlueprintCondition(field: SubscriptionFields.service, oneOf: [ServiceKind.gas], orWhenEmpty: true)
        let data = try MachineText.jsonEncoder().encode(condition)
        #expect(try MachineText.jsonDecoder().decode(BlueprintCondition.self, from: data) == condition)
        let older = try MachineText.jsonDecoder().decode(BlueprintCondition.self, from: Data(#"{"field":"a","oneOf":["b"]}"#.utf8))
        #expect(older.orWhenEmpty == false, "A condition written before reads as it did")
        let plain = String(decoding: try MachineText.jsonEncoder().encode(older), as: UTF8.self)
        #expect(!plain.contains("orWhenEmpty"), "Written only when it holds")
        #expect(condition.isMet(by: FieldValues()))
        #expect(!older.isMet(by: FieldValues()))
    }

    // MARK: Capture keeps only the service's codes

    private func field(_ key: CaptureFieldKey, _ text: String) -> CaptureField {
        CaptureField(key: key, value: .text(text), confidence: 0.7, sourceText: nil, tier: .heuristic)
    }

    @Test func aPaperKeepsOnlyItsServicesCodes() {
        let internet = SubscriptionCode.keeping([field(.serviceKind, ServiceKind.internetTV), field(.podCode, "RO005E000000001"),
                                                 field(.clientCode, "2000000000")], service: ServiceKind.internetTV)
        #expect(internet.map(\.key) == [.serviceKind, .clientCode], "An internet contract carries no POD")

        let gas = SubscriptionCode.keeping([field(.podCode, "RO002G000000001"), field(.account, "3000000000")], service: ServiceKind.gas)
        #expect(gas.map(\.key) == [.clcCode, .clientCode], "A gas paper's POD gaz is its CLC, a customer account its client code")

        let water = SubscriptionCode.keeping([field(.clcCode, "123456"), field(.placeCode, "654321")], service: ServiceKind.water)
        #expect(water.map(\.key) == [.placeCode], "Water keeps its own place code, never a CLC")
        #expect(water.first?.value == .text("654321"))

        let unknown = [field(.podCode, "RO005E000000001"), field(.clcCode, "DEG0000000001")]
        #expect(SubscriptionCode.keeping(unknown, service: nil).map(\.key) == [.podCode, .clcCode], "Unknown service: everything read stays")
    }

    @Test func theMatcherComparesOnlyTheServicesCodes() {
        let id = UUID()
        var kept = FieldValues()
        kept[SubscriptionFields.service] = .text(ServiceKind.internetTV)
        kept[SubscriptionFields.pod] = .text("RO005E000000009")
        kept[SubscriptionFields.provider] = .text("Vodafone Romania S.A.")
        let reading = SubscriptionMatcher.Reading(provider: "Vodafone Romania", service: ServiceKind.internetTV,
                                                  codes: [.pod: "RO005E000000001", .account: "3000000000"], isBill: true)
        #expect(reading.codes == [.account: "3000000000"], "A POD on an internet bill is never compared")
        let home = UUID()
        let decision = SubscriptionMatcher.match(reading, subscriptions: [.init(id: id, parentID: home, values: kept)],
                                                 homes: [.init(id: home, values: FieldValues())])
        #expect(decision == .existing(id), "A stray POD never tells two internet contracts apart")
    }

    @Test func theReviewNeverOffersACodeTheServiceDoesntHave() throws {
        let context = try makeContext()
        let read = CaptureResult(kind: .contract, kindConfidence: 0.8,
                                 fields: [CaptureField(key: .serviceKind, value: .text(ServiceKind.internetTV), confidence: 0.8, sourceText: nil, tier: .heuristic)],
                                 suggestions: [], reminder: nil, recognizedText: "", barcodes: [], document: nil, notices: [])
        let review = CaptureReview(result: read, assets: [], context: context)
        #expect(!review.addableKeys.contains(.podCode) && !review.addableKeys.contains(.clcCode) && !review.addableKeys.contains(.placeCode))
        #expect(review.addableKeys.contains(.clientCode) && review.addableKeys.contains(.account))

        let gas = CaptureResult(kind: .contract, kindConfidence: 0.8,
                                fields: [CaptureField(key: .serviceKind, value: .text(ServiceKind.gas), confidence: 0.8, sourceText: nil, tier: .heuristic)],
                                suggestions: [], reminder: nil, recognizedText: "", barcodes: [], document: nil, notices: [])
        let gasReview = CaptureReview(result: gas, assets: [], context: context)
        #expect(gasReview.addableKeys.contains(.clcCode) && !gasReview.addableKeys.contains(.podCode))
    }

    // MARK: A telecom contract and its summary

    /// The EU contract summary („Fișa de sinteză”) as providers print it: the same headings for
    /// everyone, placeholder values.
    static let summarySheet = """
    Vodafone Romania S.A.
    Str. Exemplului nr. 1, București
    Denumirea serviciului: Internet și TV Exemplu
    Fișă de sinteză
    numărul 100000001 din data 15/03/2026
    Prezenta fișă de sinteză a contractului prevede principalele elemente ale acestei oferte de servicii.
    Serviciu (servicii și echipamente)
    Internet fix prin fibră optică
    Televiziune prin cablu, 120 de canale incluse în abonament
    Preț
    • 7,50 euro/lună taxa de abonament.
    • 2,00 euro/lună taxa pentru fiecare TV Box suplimentar.
    50% reducere la taxa lunară de abonament în primele 12 luni
    Durata, reînnoirea și încetarea contractului
    Internet și TV Exemplu 24 luni 100000002
    La expirarea Perioadei minime contractuale, acesta se prelungește tacit pe perioade egale cu Perioada minimă contractuală.
    """

    static let telecomContract = """
    Vodafone Romania S.A.
    CONTRACT DE ABONAMENT pentru servicii de comunicații electronice
    Contract nr. VDF-000123 din data 15.03.2026
    Cod client: 2000000000
    Cont de facturare: 3000000000
    Adresa de instalare: Str. Exemplului nr. 5, bl. A1, ap. 12, București
    Servicii: internet fix prin fibră optică, televiziune, telefonie fixă
    Abonament lunar: 45,00 lei
    Perioada minimă: 24 de luni
    """

    private func capture(_ text: String) async throws -> CaptureResult {
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: ""),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        return try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(storeDocument: false, referenceDate: Self.referenceDate)))
    }

    @Test func aContractSummaryReadsItsProviderServicePriceAndMinimumPeriod() async throws {
        let result = try await capture(Self.summarySheet)
        #expect(result.kind == .contract)
        #expect(result.field(.provider)?.value == .text("Vodafone Romania"))
        #expect(result.field(.serviceKind)?.value == .text(ServiceKind.internetTV))
        #expect(result.field(.monthlyPrice)?.value == .money(Money(Decimal(string: "7.50")!, currency: "EUR")), "The price, never a discount")
        #expect(result.field(.minimumMonths)?.value == .number(24))
        let start = try #require(CalendarDay(printedYear: 2026, month: 3, day: 15))
        #expect(result.field(.startDate)?.value == .day(start))
        let end = try #require(CalendarDay(printedYear: 2028, month: 3, day: 15))
        #expect(result.field(.minimumPeriodEnd)?.value == .day(end))
        #expect(result.reminder?.blueprintKey == SubscriptionFields.minimumEndsBlueprint)
        #expect(result.field(.podCode) == nil && result.field(.clcCode) == nil && result.field(.placeCode) == nil)
    }

    @Test func aTelecomContractReadsItsCodesAndInstallationAddress() async throws {
        let result = try await capture(Self.telecomContract)
        #expect(result.kind == .contract)
        #expect(result.field(.serviceKind)?.value == .text(ServiceKind.internetTV))
        #expect(result.field(.contractNumber)?.value == .text("VDF-000123"))
        #expect(result.field(.clientCode)?.value == .text("2000000000"))
        #expect(result.field(.account)?.value == .text("3000000000"))
        #expect(result.field(.supplyAddress)?.value.text?.hasPrefix("Str. Exemplului nr. 5") == true)
        #expect(result.field(.monthlyPrice)?.value == .money(Money(45)))
        #expect(result.field(.startDate)?.value == .day(try #require(CalendarDay(printedYear: 2026, month: 3, day: 15))))
        #expect(result.field(.minimumPeriodEnd)?.value == .day(try #require(CalendarDay(printedYear: 2028, month: 3, day: 15))))
    }

    @Test func aWaterBillsPlaceCodeIsItsOwn() async throws {
        let bill = """
        Apa Nova București S.A.
        FACTURĂ FISCALĂ seria EX nr. 000000001
        Apă potabilă și canalizare
        Cod client: 1000000000
        Cod loc de consum: 400000001
        Data scadenței: 25.10.2026
        Total de plată: 85,30 lei
        """
        let result = try await capture(bill)
        #expect(result.field(.serviceKind)?.value == .text(ServiceKind.water))
        #expect(result.field(.placeCode)?.value == .text("400000001"))
        #expect(result.field(.clcCode) == nil, "Never a gas code on a water bill")
    }

    // MARK: Groups

    @Test func aSubscriptionIsListedUnderWhatItIsUntilThePersonMovesIt() {
        let definition = BuiltInTemplates.subscription
        var values = FieldValues()
        values[SubscriptionFields.service] = .text(ServiceKind.gas)
        let created = values.applyingRules(of: definition, previous: nil, calendar: .bucharest)
        #expect(created[SubscriptionFields.group] == .text(SubscriptionGroup.utilities.rawValue), "Kept as its own value")

        var moved = created
        moved[SubscriptionFields.group] = .text(SubscriptionGroup.other.rawValue)
        let edited = moved.applyingRules(of: definition, previous: created, calendar: .bucharest)
        #expect(SubscriptionGroup.of(edited) == .other, "The person's move stays")

        var renamed = edited
        renamed[SubscriptionFields.provider] = .text("ENGIE Romania S.A.")
        #expect(SubscriptionGroup.of(renamed.applyingRules(of: definition, previous: edited, calendar: .bucharest)) == .other)

        var mobile = edited
        mobile[SubscriptionFields.service] = .text(ServiceKind.mobile)
        #expect(SubscriptionGroup.of(mobile.applyingRules(of: definition, previous: edited, calendar: .bucharest)) == .internetAndPhone,
                "A new service is a new thing: it goes where that is listed")

        var unsaved = FieldValues()
        unsaved[SubscriptionFields.service] = .text(ServiceKind.streaming)
        #expect(SubscriptionGroup.of(unsaved) == .appsAndStreaming, "One saved before groups is listed by its service")
        #expect(SubscriptionGroup.of(FieldValues()) == .other)
    }

    @Test func theListGroupsInTheirOrderAndLeavesEmptyGroupsOut() {
        func values(_ service: String) -> FieldValues {
            var values = FieldValues()
            values[SubscriptionFields.service] = .text(service)
            return values
        }
        let items = [("Netflix", values(ServiceKind.streaming)), ("Gaz", values(ServiceKind.gas)), ("Telefon", values(ServiceKind.mobile)),
                     ("Curent", values(ServiceKind.electricity))]
        let listed = SubscriptionGroup.grouping(items) { $0.1 }
        #expect(listed.map(\.group) == [.utilities, .internetAndPhone, .appsAndStreaming])
        #expect(listed.first?.items.map(\.0) == ["Gaz", "Curent"], "In the order they came")
    }

    @Test("Abonamente's page, a home's Abonamente pocket and its full list share one listing: under the groups where the category keeps them")
    func everyListOfSubscriptionsIsGroupedOneWay() {
        func values(_ service: String) -> FieldValues {
            var values = FieldValues()
            values[SubscriptionFields.service] = .text(service)
            return values
        }
        let items = [("Apă", values(ServiceKind.water)), ("Internet", values(ServiceKind.internetTV)), ("Curent", values(ServiceKind.electricity)),
                     ("Gaz", values(ServiceKind.gas))]
        let listing = SubscriptionGroup.listing(items, in: BuiltInTemplates.subscription) { $0.1 }
        #expect(listing.map(\.group) == [.utilities, .internetAndPhone])
        #expect(listing.map { $0.items.map(\.0) } == [["Apă", "Curent", "Gaz"], ["Internet"]])

        // A pocket shows three, in the listing's order, each group named above its first row.
        let rows = SubscriptionGroup.firstRows(of: listing, limit: 3)
        #expect(rows.map(\.item.0) == ["Apă", "Curent", "Gaz"])
        #expect(rows.map(\.opens) == [.utilities, nil, nil])
        #expect(SubscriptionGroup.firstRows(of: listing, limit: 4).map(\.opens) == [.utilities, nil, nil, .internetAndPhone])
        // One group to tell apart: no heading under the pocket's own title.
        let utilities = SubscriptionGroup.listing(Array(items.prefix(1)), in: BuiltInTemplates.subscription) { $0.1 }
        #expect(SubscriptionGroup.firstRows(of: utilities, limit: 3).map(\.opens) == [nil])

        // A category that keeps no group: one list, as it came.
        var own = BuiltInTemplates.subscription
        own.sections = own.sections.map { section in
            var section = section
            section.fields.removeAll { $0.key == SubscriptionFields.group }
            return section
        }
        let plain = SubscriptionGroup.listing(items, in: own) { $0.1 }
        #expect(plain.count == 1 && plain.first?.group == nil && plain.first?.items.map(\.0) == ["Apă", "Internet", "Curent", "Gaz"])
        #expect(SubscriptionGroup.listing([(String, FieldValues)](), in: own) { $0.1 }.isEmpty)
    }

    // MARK: Weekly

    @Test func aSubscriptionCanBeWeekly() throws {
        #expect(BillingCycle.options.map(\.key).first == BillingCycle.weekly)
        #expect(BillingCycle.interval(BillingCycle.weekly) == .weeks(1))
        #expect(BillingCycle.interval("Săptămânal") == .weeks(1), "Typed text finds its key")
        #expect(BillingCycle.interval(nil) == .months(1))
        #expect(BuiltInTemplates.subscription.field(SubscriptionFields.cycle)?.options?.contains { $0.key == BillingCycle.weekly } == true)

        var values = FieldValues()
        values[SubscriptionFields.price] = .money(Money(12))
        values[SubscriptionFields.cycle] = .text(BillingCycle.weekly)
        #expect(SubscriptionMath.monthlyEquivalent(values) == Money(52), "12 lei a week is 52 lei a month")
        #expect(SubscriptionMath.monthly(Money(120), every: .years(1)) == Money(10))
        #expect(SubscriptionMath.monthly(Money(90), every: .months(3)) == Money(30))
    }

    @Test func aWeeklyBillThatHasntComeIsMissedWithinDays() throws {
        let calendar = Calendar.bucharest
        let today = CalendarDay(Self.referenceDate, calendar: calendar)
        let weeks = (1...4).map { BillRecord(day: today.adding(days: -7 * $0 - 5, calendar: calendar), amount: Money(12)) }
        let missing = try #require(BillHistory.missing(weeks, cycle: .weeks(1), today: today, calendar: calendar))
        #expect(missing.expectedDay == today.adding(days: -5, calendar: calendar))
        #expect(BillHistory.missing(weeks, cycle: .months(1), today: today, calendar: calendar) == nil, "Monthly, it is within its grace")
        #expect(BillHistory.missing([BillRecord(day: today.adding(days: -8, calendar: calendar), amount: nil)], cycle: .weeks(1), today: today,
                                    calendar: calendar) == nil, "A day late is within its grace")

        let snapshot = BillWatchSnapshot(name: "Coș de legume", provider: "Ferma Exemplu S.R.L.", service: ServiceKind.mobile, cycle: .weeks(1), bills: weeks)
        let note = try #require(AttentionModel.missingBills([snapshot], now: Self.referenceDate, calendar: calendar).first)
        #expect(note.title == "Factura de la Ferma Exemplu n-a venit săptămâna asta")
    }
}
