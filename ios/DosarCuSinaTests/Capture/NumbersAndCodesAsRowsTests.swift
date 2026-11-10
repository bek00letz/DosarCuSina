import Foundation
import Testing
@testable import DosarCuSina

/// An invoice's and the CIV's numbers, the talon's numbered fields (B, D.1, D.3; its A, the
/// plate, is read as on any car's paper), the tax ID's labels and a company's legal forms are
/// rows of their tables, read by the shared readers as they were read when they were patterns:
/// their dots printed or left out, their words apart by any space. All names, plates and
/// numbers are placeholders.
@Suite("Numbers, numbered fields and codes are rows of their tables")
struct NumbersAndCodesAsRowsTests {
    let analyzer = CaptureAnalyzer()
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    // MARK: The tables

    @Test("Every invoice's number and the tax ID are rows of the shared table; the talon's are its own")
    func theRowsAreInTheirTables() {
        for key in [CaptureFieldKey.invoiceNumber, .providerTaxID] {
            #expect(!CaptureKindProfile.commonLabels(for: key).isEmpty, "\(key)")
        }
        for kind in [CaptureDocumentKind.utilityInvoice, .serviceInvoice, .other] {
            #expect(kind.profile.labels(for: .invoiceNumber) == CaptureKindProfile.commonLabels(for: .invoiceNumber), "\(kind)")
        }
        let talon = CaptureDocumentKind.vehicleRegistration.profile
        for key in [CaptureFieldKey.civNumber, .make, .model, .firstRegistrationDate] {
            #expect(!CaptureKindProfile.labels(for: key, in: talon.labels).isEmpty, "The talon's \(key) is its row")
        }
    }

    @Test("A value in parts is read beside the other fields' labels, never its own among them")
    func aValueInPartsKeepsItsOwnWordings() {
        let civ = CompositeLabels.table(for: CaptureKindProfile.labels(for: .civNumber, in: CaptureKindProfile.registrationLabels))
        let others = civ.filter { $0.0 == .other }.flatMap { $0.1 }.compactMap(\.words)
        #expect(!others.contains("serie civ") && !others.contains("seria civ"), "The CIV's own wordings are its value's")
        #expect(others.contains("serie sasiu"), "Another field's series stays another field's")
        let invoice = CompositeLabels.table(for: CaptureKindProfile.commonLabels(for: .invoiceNumber))
        #expect(invoice.filter { $0.0 == .other }.flatMap { $0.1 } == CompositeLabels.otherFields)
    }

    // MARK: Read as they were

    @Test("A talon's make, its number's dots printed or not", arguments: ["D.1 VW", "D1 VW", "D 1 VW", "D. 1 VW", "d.1. VW"])
    func theMake(line: String) {
        #expect(RomanianFieldExtractor.registrationFields(in: CaptureText(line))[.make]?.0 == .text("VW"), "\(line)")
    }

    @Test("A talon's model and first registration")
    func theModelAndFirstRegistration() throws {
        let fields = RomanianFieldExtractor.registrationFields(in: CaptureText("D.3 Golf\nB. 15.03.2018"))
        #expect(fields[.model]?.0 == .text("Golf"))
        let day = try #require(CalendarDay(printedYear: 2018, month: 3, day: 15))
        #expect(fields[.firstRegistrationDate]?.0 == .day(day))
    }

    @Test("A line that only starts like a numbered field is none")
    func nearMisses() {
        let fields = RomanianFieldExtractor.registrationFields(in: CaptureText("D.12 Exemplu\nBon 15.03.2018\nA B 123 ABC"))
        #expect(fields.isEmpty)
    }

    @Test("The whole talon, read with its table")
    func theTalon() throws {
        let text = "CERTIFICAT DE ÎNMATRICULARE\nA B 123 ABC\nB 15.03.2018\nD.1 VW\nD.3 Golf\nSeria CIV: J123456"
        let analysis = analyzer.analyze(text: text, referenceDate: today, as: .vehicleRegistration)
        func value(_ key: CaptureFieldKey) -> CaptureValue? { analysis.fields.first { $0.key == key }?.value }
        #expect(value(.licensePlate) == .text("B 123 ABC"))
        #expect(value(.make) == .text("VW"))
        #expect(value(.model) == .text("Golf"))
        #expect(value(.civNumber) == .text("J123456"))
        let registered = try #require(CalendarDay(printedYear: 2018, month: 3, day: 15))
        #expect(value(.firstRegistrationDate) == .day(registered))
    }

    @Test("The tax ID after any of its labels, the dots printed or not", arguments: [
        ("CUI: RO 12345674", "RO12345674"), ("C.U.I. RO12345674", "RO12345674"), ("C. U. I.: 12345674", "12345674"),
        ("CIF 12345674", "12345674"), ("C.I.F.: RO12345674", "RO12345674"), ("Cod fiscal: RO12345674", "RO12345674"),
        ("Cod  unic de înregistrare 12345674", "12345674"), ("Cod de identificare fiscală: RO 12345674", "RO12345674"),
    ])
    func theTaxID(line: String, expected: String) throws {
        let found = try #require(RomanianFieldExtractor.taxID(in: CaptureText("EXEMPLU SERVICE S.R.L.\n\(line)")), "\(line)")
        #expect(found.value == expected, "\(line)")
        #expect(found.valid)
        #expect(found.line == 1)
    }

    @Test("No tax ID label, no tax ID")
    func noTaxID() {
        #expect(RomanianFieldExtractor.taxID(in: CaptureText("EXEMPLU SERVICE S.R.L.\nTel. 0712 345 678\nCuiul 12345674")) == nil)
    }

    @Test("A company is named by its legal form, its dots printed or not", arguments: [
        ("EXEMPLU SERVICE S.R.L.", true), ("Exemplu Service SRL", true), ("Exemplu S. R. L., București", true),
        ("Exemplu Asigurări S.A.", true), ("Exemplu PFA", true), ("Exemplu I.I.", true), ("Exemplu S.C.S.", true),
        ("Ion Exemplu", false), ("Sala de așteptare", false), ("Salariu", false),
    ])
    func aCompany(line: String, names: Bool) {
        #expect(RomanianFieldExtractor.namesACompany(line) == names, "\(line)")
    }
}
