import Foundation
import Testing
@testable import DosarCuSina

/// Contracts as a kind of their own: told apart from bills, their codes and terms
/// read, the minimum period's end worked out and checked, and the AI provider asked
/// for the same fields. Every value is a placeholder.
@Suite("Contract capture")
struct ContractCaptureTests {

    static let referenceDate = Date(timeIntervalSince1970: 1_793_577_600)
    static let today = CaptureDay(date: referenceDate)

    static let gasContract = """
    ENGIE Romania S.A.
    CONTRACT DE FURNIZARE A GAZELOR NATURALE
    Contract nr. EX-2026-000123
    Cod client: 1000000000
    Cod loc de consum (CLC): DEG0000000000001
    Încheiat la data de 15.03.2026
    Perioada minimă: 24 de luni
    Preț lunar abonament: 12,50 lei
    Condiții generale de furnizare
    """

    static let mobileContract = """
    Orange Romania S.A.
    CONTRACT DE ABONAMENT
    Contract nr. MOB-000123
    Număr de telefon: 0700 000 000
    Data activării: 01.02.2026
    Perioada contractuală: 24 luni
    Abonament lunar: 9 EUR
    Telefonie mobilă, minute naționale nelimitate, date mobile 50 GB
    """

    static let gasBill = """
    ENGIE Romania S.A.
    FACTURĂ FISCALĂ seria EX nr. 000000001
    Gaze naturale
    Cod client: 1000000000
    Cod loc de consum (CLC): DEG0000000000001
    Contract nr. EX-2026-000123
    Data facturii: 05.10.2026
    Data scadenței: 25.10.2026
    Total de plată: 245,30 lei
    """

    private func analyze(_ text: String) -> CaptureAnalyzer.Analysis {
        CaptureAnalyzer().analyze(text: text, referenceDate: Self.referenceDate)
    }

    private func value(_ key: CaptureFieldKey, in fields: [CaptureField]) -> CaptureValue? {
        fields.first { $0.key == key }?.value
    }

    // MARK: Telling them apart

    @Test func aContractIsReadAsAContractNotABill() {
        #expect(analyze(Self.gasContract).kind == .contract)
        #expect(analyze(Self.mobileContract).kind == .contract)
        #expect(analyze("ACT ADIȚIONAL nr. 2 la contractul de abonament\nPerioada minimă: 12 luni").kind == .contract)
    }

    @Test func aBillQuotingItsContractStaysABill() {
        #expect(analyze(Self.gasBill).kind == .utilityInvoice)
    }

    // MARK: What a contract says

    @Test func aGasContractsCodesAndTerms() {
        let fields = analyze(Self.gasContract).fields
        #expect(value(.provider, in: fields) == .text("ENGIE Romania"))
        #expect(value(.contractNumber, in: fields) == .text("EX-2026-000123"))
        #expect(value(.clientCode, in: fields) == .text("1000000000"))
        #expect(value(.clcCode, in: fields) == .text("DEG0000000000001"))
        #expect(value(.serviceKind, in: fields) == .text(ServiceKind.gas), "A CLC means gas")
        #expect(value(.startDate, in: fields) == .day(CaptureDay(year: 2026, month: 3, day: 15)!))
        #expect(value(.minimumMonths, in: fields) == .number(24))
        #expect(value(.monthlyPrice, in: fields) == .money(CaptureMoney(amount: Decimal(string: "12.50")!, currencyCode: "RON")))
        #expect(value(.lineItems, in: fields) == nil)
    }

    @Test func aMobileContractsNumberAndService() {
        let fields = analyze(Self.mobileContract).fields
        #expect(value(.phoneNumber, in: fields) == .text("0700 000 000"))
        #expect(value(.serviceKind, in: fields) == .text(ServiceKind.mobile))
        #expect(value(.minimumMonths, in: fields) == .number(24))
        #expect(value(.startDate, in: fields) == .day(CaptureDay(year: 2026, month: 2, day: 1)!))
        #expect(value(.monthlyPrice, in: fields)?.money?.currencyCode == "EUR", "Never turned into lei")
    }

    @Test func aBillCarriesTheCodesThatFindItsContract() {
        let fields = analyze(Self.gasBill).fields
        #expect(value(.contractNumber, in: fields) == .text("EX-2026-000123"))
        #expect(value(.clcCode, in: fields) == .text("DEG0000000000001"))
        #expect(value(.serviceKind, in: fields) == .text(ServiceKind.gas))
    }

    @Test func lengthsAreReadInMonths() {
        #expect(ContractReader.months(in: "24 de luni") == 24)
        #expect(ContractReader.months(in: "12 (douasprezece) luni") == 12)
        #expect(ContractReader.months(in: "2 ani") == 24)
        #expect(ContractReader.months(in: "500 de luni") == nil, "Not a minimum period")
        #expect(ContractReader.displayPhone("+40700000000") == "0700 000 000")
        #expect(!ContractReader.isMobileNumber("0210000000"), "A landline isn't a phone plan's number")
    }

    // MARK: End to end, with its deadline

    @Test func theEngineWorksOutTheEndOfTheMinimumPeriodAndItsReminder() async throws {
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: ""),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(Self.gasContract), options: CaptureOptions(storeDocument: false, referenceDate: Self.referenceDate)))
        #expect(result.kind == .contract)
        let end = try #require(CaptureDay(year: 2028, month: 3, day: 15))
        #expect(result.field(.minimumPeriodEnd)?.value == .day(end))
        #expect(result.reminder == CaptureReminderHint(day: end, profileKey: "minimumPeriod", leadDays: [30, 0]))
        #expect(result.suggestions.contains { $0.destination == .obligation(blueprintKey: "subscriptionMinimumEnds", templateKey: "subscriptions") })
        #expect(CaptureMapping.blueprintKey("subscriptionMinimumEnds") == SubscriptionFields.minimumEndsBlueprint)
        #expect(CaptureMapping.templateKey(for: .contract) == BuiltInTemplates.Key.subscription)
        #expect(DocumentKind(capturedKind: .contract) == .contract)
    }

    @Test func aMinimumPeriodEndingBeforeItStartsIsDropped() {
        let start = CaptureField(key: .startDate, value: .day(CaptureDay(year: 2026, month: 3, day: 15)!), confidence: 0.7, tier: .heuristic)
        let end = CaptureField(key: .minimumPeriodEnd, value: .day(CaptureDay(year: 2025, month: 3, day: 15)!), confidence: 0.6, tier: .heuristic)
        let resolved = CaptureConsistency.resolve([start, end], kind: .contract, today: Self.today)
        #expect(resolved.dropped == [.minimumPeriodEnd])
        let ancient = CaptureField(key: .startDate, value: .day(CaptureDay(year: 1950, month: 1, day: 1)!), confidence: 0.7, tier: .heuristic)
        #expect(CaptureConsistency.plausible([ancient], kind: .contract, today: Self.today).isEmpty, "No household contract started in 1950")
    }

    // MARK: The AI provider

    @Test func theProviderIsAskedForContractsAndTheirFields() {
        let schema = CloudSchema(kind: .contract)
        let names = Set(schema.fields.map(\.name))
        #expect(names.isSuperset(of: ["serviceKind", "contractNumber", "minimumMonths", "minimumPeriodEnd", "monthlyPrice", "phoneNumber"]))
        #expect(schema.json["properties"]?[CloudSchema.kindName]?["enum"]?.array?.contains(.string("contract")) == true)
        #expect(schema.fields.first { $0.key == .serviceKind }?.format == .serviceKind)
        #expect(schema.fields.first { $0.key == .minimumPeriodEnd }?.format == .date)
    }

    @Test func theProvidersAnswerIsCheckedLikeAnyOther() throws {
        let json = #"{"documentKind":"contract","serviceKind":"service.mobile","phoneNumber":"+40 700 000 000","minimumMonths":24,"minimumPeriodEnd":"2028-01-31","contractNumber":"MOB-000123","provider":"Orange Romania S.A."}"#
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let fields = CloudAnswerMapper.fields(from: answer, schema: CloudSchema(kind: .contract), recognizedText: Self.mobileContract,
                                              today: Self.today, resolver: CatalogComponentResolver())
        #expect(CloudAnswerMapper.kind(from: answer) == .contract)
        #expect(value(.serviceKind, in: fields) == .text(ServiceKind.mobile))
        #expect(value(.phoneNumber, in: fields) == .text("0700 000 000"))
        #expect(value(.minimumMonths, in: fields) == .number(24))

        let odd = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"documentKind":"contract","serviceKind":"satellite","minimumMonths":900}"#.utf8))
        let kept = CloudAnswerMapper.fields(from: odd, schema: CloudSchema(kind: .contract), recognizedText: "", today: Self.today, resolver: CatalogComponentResolver())
        #expect(kept.isEmpty, "An unknown service and an impossible length are never kept")
    }
}
