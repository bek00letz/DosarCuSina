import Foundation
import Testing
@testable import DosarCuSina

/// Values printed in pieces, a series and a number, read by one rule (`CompositeValue`,
/// `LabelledLayout.composite`) into one value, whatever the layout and whoever read them.
/// Every value is a placeholder.
@Suite("Values printed in parts")
struct CompositeValueTests {

    static let policy = "RO/00/X00/XX 123456789"
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    // MARK: A policy's series and number

    @Test("A policy's series and number, in every layout, are one value", arguments: [
        "Seria și numărul: RO/00/X00/XX 123456789",
        "Seria și numărul poliței: RO/00/X00/XX 123456789",
        "CONTRACT DE ASIGURARE DE RĂSPUNDERE CIVILĂ AUTO RCA Seria RO/00/X00/XX nr. 123456789",
        "Polița seria RO/00/X00/XX nr. 123456789",
        "Seria: RO / 00 / X00 / XX Nr.: 123456789",
        "Seria RO/00/X00/XX\nNr. 123456789",
        "Seria\nRO/00/X00/XX\nNr. 123456789",
        "Serie: RO/00/X00/XX\nNumăr: 123456789",
        // The green card: one header over the value, the series and the number on lines of their own.
        "Codul ţării / Codul asigurătorului / Numărul\nCountry code / Insurer's code / Number\nRO/00/X00/XX\n123456789",
        "Codul țării / Codul asigurătorului / Numărul\nRO/00/X00/XX\n123456789",
    ])
    func policyLayouts(text: String) {
        #expect(RomanianFieldExtractor.policyNumber(in: CaptureText(text))?.value == Self.policy, "\(text)")
    }

    @Test("Columns: the series beside its label, the number on the row below")
    func policyColumns() throws {
        let page = [
            Card.line("Seria", 0.05, 0.10, 0.08),
            Card.line("RO/00/X00/XX", 0.16, 0.10, 0.22),
            Card.line("Nr.", 0.05, 0.14, 0.05),
            Card.line("123456789", 0.16, 0.14, 0.18),
        ]
        let fragments = CaptureText(pages: [page])
        #expect(RomanianFieldExtractor.policyNumber(in: fragments)?.value == Self.policy)
        #expect(RomanianFieldExtractor.policyNumber(in: fragments.joiningRows())?.value == Self.policy)
    }

    @Test("Side by side: the number in its own fragment on the series' row")
    func policySideBySide() {
        let page = [
            Card.line("Seria RO/00/X00/XX", 0.05, 0.10, 0.30),
            Card.line("Nr. 123456789", 0.40, 0.10, 0.22),
        ]
        #expect(RomanianFieldExtractor.policyNumber(in: CaptureText(pages: [page]))?.value == Self.policy)
    }

    @Test("Another field's number is never the policy's", arguments: [
        "Seria RO/00/X00/XX\nNr. înmatriculare B 123 ABC",
        "Seria RO/00/X00/XX\nNr. înmatriculare 1234567",
        "Seria RO/00/X00/XX\nNr. contract 123456789",
        "Nr. contract: 123456789",
        "Nr. identificare - Serie CIV / J123456",
        "Serie șasiu WVWZZZAUZJW000000",
        "Nr. rate 1 Valoare rate R1: 1234.56 Lei",
    ])
    func policyNearMisses(text: String) {
        #expect(RomanianFieldExtractor.policyNumber(in: CaptureText(text)) == nil, "\(text)")
    }

    @Test("A label word is never a part, and a number alone is kept as one")
    func labelWords() {
        #expect(CompositeValue.policy.parts(in: "NR. 123456789") == .init(series: nil, number: "123456789"))
        #expect(CompositeValue.policy.parts(in: "SERIA NR") == nil)
        #expect(RomanianFieldExtractor.policyNumber(in: CaptureText("Nr. poliță: 123456789"))?.value == "123456789")
        #expect(RomanianFieldExtractor.policyNumber(in: CaptureText("Nr. poliță: 123456789"))?.quality == .numberOnly)
        // A series ending in digits never takes the number's first ones.
        #expect(CompositeValue.policy.normalized("RO/00/X/000000000") == "RO/00/X/000000000")
    }

    @Test("Two different whole values are kept for a look")
    func conflicting() {
        let found = RomanianFieldExtractor.policyNumber(in: CaptureText("Seria RO/00/X00/XX nr. 123456789\nSeria RO/00/X00/XX nr. 987654321"))
        #expect(found?.value == Self.policy)
        #expect(found?.quality == .conflicting)
        #expect((found?.quality.confidence ?? 1) < CaptureField.checkThreshold)
    }

    // MARK: The owner's policy, both pages

    @Test("The owner's policy: either page gives the one policy number", arguments: [RCAPages.certificate, RCAPages.contract, RCAPages.certificate + "\n" + RCAPages.contract])
    func ownersPolicy(text: String) {
        let analysis = CaptureAnalyzer().analyze(text: text, referenceDate: today, as: .rcaPolicy)
        let number = analysis.fields.first { $0.key == .policyNumber }
        #expect(number?.value.text == Self.policy)
        #expect(number?.needsCheck == false)
        #expect(!analysis.fields.contains { $0.key == .documentNumber })
    }

    // MARK: Identity card, talon, invoices, contracts

    @Test("The identity card's series and number, inline or in fragments", arguments: [
        "SERIA XT NR 123456", "SERIA XT, NR 123456", "Seria XT nr. 123456", "SERIA XT NR. 123456", "SERIA XT\nNR 123456",
    ])
    func identityCard(text: String) {
        let layout = LabelledLayout(text: CaptureText(text), labels: IdentityTemplates.identityCard.labelTable)
        #expect(layout.composite(.identityCard, for: .field(.documentNumber))?.value == "XT123456", "\(text)")
    }

    @Test("The identity card's parts in separate fragments on one row")
    func identityCardFragments() {
        let page = [Card.line("SERIA XT", 0.55, 0.12, 0.15, 0.03), Card.line("NR 123456", 0.72, 0.12, 0.15, 0.03)]
        let fields = IdentityDocumentReader.read(CaptureText(pages: [page]), template: IdentityTemplates.identityCard, today: CalendarDay(today))
        #expect(fields.first { $0.key == .documentNumber }?.value.text == "XT123456")
        #expect(CompositeValue.identityCard.parts(in: "XT") == .init(series: "XT", number: nil), "A series alone waits for its number")
    }

    @Test("A talon's CIV series and number", arguments: ["Seria CIV: J123456", "Serie CIV J 123456", "C.I.V. J 123456"])
    func vehicleCard(text: String) {
        #expect(RomanianFieldExtractor.civNumber(in: CaptureText(text))?.value == "J123456", "\(text)")
    }

    @Test("An invoice's series and number", arguments: [
        ("FACTURĂ FISCALĂ seria AUT nr. 004512", "AUT 004512"),
        ("Factura seria EXM nr. 0012345", "EXM 0012345"),
        ("Seria: EXM\nNr.: 0012345", "EXM 0012345"),
        ("Nr. factură: XYZ-2026-0001", "XYZ-2026-0001"),
        ("Seria contor: ABC 12345678\nFactura seria EXM nr. 0012345", "EXM 0012345"),
    ])
    func invoice(text: String, expected: String) {
        #expect(RomanianFieldExtractor.invoiceNumber(in: CaptureText(text))?.value == expected, "\(text)")
    }

    @Test("A meter's series is never the invoice's")
    func invoiceNearMiss() {
        #expect(RomanianFieldExtractor.invoiceNumber(in: CaptureText("Seria contor: ABC 12345678\nNr. client 123456")) == nil)
    }

    @Test("A contract's number by the same rule, kept as one code", arguments: [
        ("Nr. contract: 12345/2026", "12345/2026"),
        ("Contract nr.\n12345/2026", "12345/2026"),
        ("Nr. contract de furnizare: EX-000123 din 01.03.2026", "EX-000123"),
    ])
    func contract(text: String, expected: String) {
        let fields = ContractReader.identifierFields(in: CaptureText(text))
        #expect(fields.first { $0.key == .contractNumber }?.value.text == expected, "\(text)")
    }

    // MARK: Readers that disagree

    @Test("Readers agree on a value written differently, or a part of it, and join two parts")
    func agreement() {
        func field(_ value: String, _ tier: CaptureTier, key: CaptureFieldKey = .policyNumber) -> CaptureField {
            CaptureField(key: key, value: .text(value), confidence: 0.7, tier: tier)
        }
        let whole = field(Self.policy, .heuristic)
        #expect(ReadingArbiter.agreedValue(whole, field("RO/00/X00/XX NR. 123456789", .cloudModel)) == .text(Self.policy))
        #expect(ReadingArbiter.agreedValue(field("123456789", .heuristic), field(Self.policy, .onDeviceModel)) == .text(Self.policy),
                "A part never beats the whole, whoever read it")
        #expect(ReadingArbiter.agreedValue(field("RO/00/X00/XX", .cloudModel), field("123456789", .heuristic)) == .text(Self.policy))
        #expect(ReadingArbiter.agreedValue(whole, field("RO/00/X00/XX 987654321", .cloudModel)) == nil)
        #expect(ReadingArbiter.agreedValue(field("XT 123456", .cloudModel, key: .documentNumber), field("XT123456", .heuristic, key: .documentNumber)) != nil)

        let merged = FieldMerger.merge([field("123456789", .heuristic)], with: [field(Self.policy, .onDeviceModel)])
        #expect(merged.map(\.value) == [.text(Self.policy)])
    }

    @Test("The owner's case: the series in one field and the number in another become one policy number")
    func strayDocumentNumber() {
        let read = [
            CaptureField(key: .documentNumber, value: .text("123456789"), confidence: 0.8, tier: .cloudModel),
            CaptureField(key: .policyNumber, value: .text("RO/00/X00/XX"), confidence: 0.8, tier: .cloudModel),
        ]
        let reconciled = CompositeValue.reconcile(read, kind: .rcaPolicy)
        #expect(reconciled.map(\.key) == [.policyNumber])
        #expect(reconciled.first?.value == .text(Self.policy))
        #expect(!CaptureDocumentKind.rcaPolicy.allows(.documentNumber))
        #expect(!CaptureDocumentKind.insurancePolicy.allows(.documentNumber))
        #expect(CaptureDocumentKind.identityCard.allows(.documentNumber))
        #expect(CaptureDocumentKind.other.allows(.documentNumber))
        // On a document whose own number is the document number, nothing moves.
        #expect(CompositeValue.reconcile(read, kind: .other).map(\.key) == [.documentNumber, .policyNumber])
    }

    @Test("The owner's case, end to end: the AI splits the parts, the review shows one value")
    @MainActor
    func ownersCaseEndToEnd() async throws {
        let answer = #"{"documentKind":"rcaPolicy","provider":"Exemplu Asigurări S.A.","policyNumber":"RO/00/X00/XX","documentNumber":"123456789","licensePlate":"B 123 ABC","startDate":"2026-11-01","expiryDate":"2027-10-31","total":null}"#
        let read = try await ReadingArbiterTests.read(RCAPages.certificate, answer: answer)
        let number = try #require(read.field(.policyNumber))
        #expect(number.value == .text(Self.policy))
        #expect(!number.needsCheck, "The phone and the AI agree")
        #expect(read.field(.documentNumber) == nil, "No second \"Serie și număr\" beside it")
    }
}

/// The owner's RCA policy, both pages, as their text layer reads them, with placeholder values.
enum RCAPages {
    /// Page 1, the insurance certificate (green card), as its text layer reads it.
    static let certificate = """
    CARTE VERDE / CERTIFICAT INTERNAȚIONAL DE ASIGURARE AUTO
    Codul ţării / Codul asigurătorului / Numărul
    Country code / Insurer's code / Number
    RO/00/X00/XX
    123456789
    5. Nr. înmatriculare/înregistrare, (sau în lipsă) nr. de identificare
    Registration No. (or if none) chassis or engine No.
    B 123 ABC
    6. Categoria vehiculului
    A
    7. Marca vehiculului
    VW
    """

    /// Page 2, the contract.
    static let contract = """
    CONTRACT DE ASIGURARE DE RĂSPUNDERE CIVILĂ AUTO RCA Seria RO/00/X00/XX nr. 123456789
    Asigurător: Exemplu Asigurări S.A.
    C.U.I. / C.N.P. Proprietar: 1800101990006 Nr. înmatriculare/înregistrare: B 123 ABC
    Nr. identificare - Serie CIV /
    Valabilitate Contract de la 01-11-2026 până la 31-10-2027 Contract emis în data de 31-10-2026 / 10:00:00
    Prima de asigurare 1234.56 LEI, Clasă Bonus-Malus: B6
    Tarif de decontare directă - LEI
    Nr. rate 1 Valoare rate R1: 1234.56 Lei; Date scadente R1: 01-11-2026.
    Limita de despăgubire pentru vătămări corporale și decese: 6.070.000 Lei
    """
}
