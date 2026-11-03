import Foundation
import Testing
@testable import DosarCuSina

/// Builds recognized lines with positions, the way Vision hands them over: fragments,
/// in no particular order, normalized to the page with the origin at the top-left.
enum Card {
    static func line(_ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double = 0.025) -> RecognizedLine {
        RecognizedLine(text, box: TextBox(x: x, y: y, width: width, height: height))
    }

    /// The front of the public specimen of the electronic identity card (CEI), with its
    /// fictional data: labels stacked in two languages, values under them, in columns.
    static let electronicFront: [RecognizedLine] = [
        line("Manole", 0.60, 0.86, 0.12, 0.05),
        line("1983", 0.70, 0.50, 0.06, 0.04),
        line("ROMÂNIA", 0.33, 0.04, 0.15, 0.03),
        line("CARTE DE IDENTITATE", 0.50, 0.04, 0.30, 0.03),
        line("ROMANIA", 0.33, 0.08, 0.12, 0.03),
        line("IDENTITY CARD", 0.60, 0.08, 0.20, 0.03),
        line("Nume", 0.33, 0.15, 0.06),
        line("Surname", 0.33, 0.18, 0.10),
        line("MANOLE", 0.33, 0.21, 0.14, 0.04),
        line("Prenume", 0.33, 0.27, 0.09),
        line("Given names", 0.33, 0.30, 0.14),
        line("CORINA", 0.33, 0.33, 0.14, 0.04),
        line("IOANA", 0.33, 0.375, 0.12, 0.04),
        line("Sex", 0.33, 0.44, 0.04),
        line("Cetățenie", 0.45, 0.44, 0.11),
        line("Data nașterii", 0.62, 0.44, 0.15),
        line("Sex", 0.33, 0.47, 0.04),
        line("Nationality", 0.45, 0.47, 0.12),
        line("Date of birth", 0.62, 0.47, 0.15),
        line("F", 0.33, 0.50, 0.02, 0.04),
        line("ROU", 0.45, 0.50, 0.05, 0.04),
        line("03", 0.62, 0.50, 0.03, 0.04),
        line("07", 0.66, 0.50, 0.03, 0.04),
        line("CNP", 0.33, 0.57, 0.05),
        line("2830703460094", 0.45, 0.57, 0.22, 0.035),
        line("PIN", 0.33, 0.60, 0.04),
        line("Nr. document", 0.33, 0.66, 0.14),
        line("Data expirării", 0.62, 0.66, 0.15),
        line("Document no.", 0.33, 0.69, 0.14),
        line("Date of expiry", 0.62, 0.69, 0.15),
        line("SP1236343", 0.33, 0.72, 0.16, 0.04),
        line("06 04 2035", 0.62, 0.72, 0.14, 0.04),
        line("Semnătura titularului", 0.33, 0.80, 0.22),
        line("Holder's signature", 0.33, 0.83, 0.20),
        line("013779", 0.80, 0.80, 0.10, 0.03),
    ]
}

@Suite("Reading by position")
struct LayoutReadingTests {

    let analyzer = CaptureAnalyzer()
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    private func fields(_ analysis: CaptureAnalyzer.Analysis) -> [CaptureFieldKey: CaptureField] {
        Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Rows

    @Test("Fragments on one row, closer than the text's height, are one line; columns stay apart")
    func mergesCloseFragments() {
        let arranged = TextLayout.arrange(Card.electronicFront).map(\.text)
        #expect(arranged.contains("03 07 1983"))
        #expect(arranged.contains("ROMÂNIA CARTE DE IDENTITATE"))
        #expect(arranged.contains("F"))
        #expect(arranged.contains("ROU"))
        #expect(!arranged.contains { $0.contains("Sex Cetățenie") })
        // Rows top to bottom, each left to right.
        let sex = arranged.firstIndex(of: "Sex"), citizenship = arranged.firstIndex(of: "Cetățenie")
        #expect(sex != nil && citizenship != nil && sex! < citizenship!)
        #expect(arranged.first == "ROMÂNIA CARTE DE IDENTITATE")
    }

    @Test("The merge threshold follows the text height, not a fixed distance")
    func thresholdScalesWithHeight() {
        let small = TextLayout.arrange([Card.line("12", 0.1, 0.1, 0.02, 0.01), Card.line("34", 0.135, 0.1, 0.02, 0.01)])
        #expect(small.map(\.text) == ["12", "34"])
        let large = TextLayout.arrange([Card.line("12", 0.1, 0.1, 0.1, 0.05), Card.line("34", 0.235, 0.1, 0.1, 0.05)])
        #expect(large.map(\.text) == ["12 34"])
    }

    // MARK: The electronic card

    @Test("Specimen CEI front: every label finds the value in its column")
    func electronicSpecimen() {
        let analysis = analyzer.analyze(pages: [TextLayout.arrange(Card.electronicFront)], referenceDate: today)
        #expect(analysis.kind == .identityCard)
        let byKey = fields(analysis)
        #expect(byKey[.surname]?.value.text == "MANOLE")
        #expect(byKey[.givenNames]?.value.text == "CORINA IOANA")
        #expect(byKey[.sex]?.value.text == "F")
        #expect(byKey[.nationality]?.value.text == "ROU")
        #expect(byKey[.birthDate]?.value.day == CaptureDay(year: 1983, month: 7, day: 3))
        #expect(byKey[.documentNumber]?.value.text == "SP1236343")
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2035, month: 4, day: 6))
        #expect(byKey[.issueDate] == nil)
        // The specimen's CNP is fictional and fails its control digit: kept, but marked for a look.
        #expect(byKey[.personalNumber]?.value.text == "2830703460094")
        #expect(byKey[.personalNumber]?.needsCheck == true)
        // Values read at their labels that pass their format need no check.
        for key in [CaptureFieldKey.surname, .givenNames, .sex, .nationality, .birthDate, .documentNumber, .expiryDate] {
            #expect(byKey[key]?.needsCheck == false, "\(key)")
        }
        #expect(analysis.hasMachineReadableZone == false)
    }

    @Test("Specimen CEI front: the text shown to people keeps each label with its value")
    func electronicReadableText() {
        let analysis = analyzer.analyze(pages: [TextLayout.arrange(Card.electronicFront)], referenceDate: today)
        #expect(analysis.readableText == """
        ROMÂNIA CARTE DE IDENTITATE
        ROMANIA
        IDENTITY CARD
        Nume
        Surname
        MANOLE
        Prenume
        Given names
        CORINA
        IOANA
        Sex
        Sex
        F
        Cetățenie
        Nationality
        ROU
        Data nașterii
        Date of birth
        03 07 1983
        CNP
        PIN
        2830703460094
        Nr. document
        Document no.
        SP1236343
        Data expirării
        Date of expiry
        06 04 2035
        Semnătura titularului
        Holder's signature
        013779
        Manole
        """)
    }

    @Test("A value beside its label on the same row is read too")
    func valueBesideLabel() {
        let text = CaptureText(pages: [TextLayout.arrange([
            Card.line("CNP", 0.1, 0.1, 0.05),
            Card.line("1800101990006", 0.3, 0.1, 0.3, 0.03),
            Card.line("Nume", 0.1, 0.2, 0.06),
            Card.line("EXEMPLU", 0.1, 0.24, 0.2, 0.04),
        ])])
        let layout = LabelledLayout(text: text, words: [("cnp", ["cnp"]), ("nume", ["nume"])])
        #expect(layout.value(for: "cnp")?.value == "1800101990006")
        #expect(layout.value(for: "nume")?.value == "EXEMPLU")
    }

    @Test("A label with nothing in its column gets no value, never the next label's")
    func neverCrossesALabel() {
        let text = CaptureText(pages: [TextLayout.arrange([
            Card.line("Data emiterii", 0.1, 0.1, 0.2),
            Card.line("Data expirării", 0.1, 0.2, 0.2),
            Card.line("15.03.2032", 0.1, 0.24, 0.2, 0.04),
            Card.line("01.01.1980", 0.6, 0.14, 0.2, 0.04),
        ])])
        let layout = LabelledLayout(text: text, words: [("issue", ["data emiterii"]), ("expiry", ["data expirarii"])])
        #expect(layout.day(for: "issue") == nil)
        #expect(layout.day(for: "expiry")?.0 == CaptureDay(year: 2032, month: 3, day: 15))
    }

    // MARK: Other layouts

    @Test("Older card with positions: one column, series at the top, validity as a range")
    func olderCardWithPositions() {
        let lines: [RecognizedLine] = [
            Card.line("ROMANIA ROUMANIE ROMANIA", 0.3, 0.03, 0.5, 0.03),
            Card.line("CARTE DE IDENTITATE", 0.3, 0.07, 0.4, 0.03),
            Card.line("SERIA XT NR 123456", 0.55, 0.12, 0.35, 0.03),
            Card.line("CNP 2851231990018", 0.3, 0.17, 0.4, 0.03),
            Card.line("Nume/Nom/Last name", 0.3, 0.23, 0.3),
            Card.line("EXEMPLU", 0.3, 0.26, 0.2, 0.035),
            Card.line("Prenume/Prenom/First name", 0.3, 0.31, 0.35),
            Card.line("MARIA", 0.3, 0.34, 0.15, 0.035),
            Card.line("Cetatenie/Nationalite/Nationality", 0.3, 0.39, 0.4),
            Card.line("Română / ROU", 0.3, 0.42, 0.2, 0.035),
            Card.line("Sex/Sexe/Sex", 0.75, 0.39, 0.15),
            Card.line("F", 0.75, 0.42, 0.03, 0.035),
            Card.line("Emisa de/Delivree par/Issued by", 0.3, 0.70, 0.35),
            Card.line("SPCLEP Exemplu", 0.3, 0.73, 0.25, 0.035),
            Card.line("Valabilitate/Validite/Validity", 0.68, 0.70, 0.3),
            Card.line("12.03.18-31.12.2028", 0.68, 0.73, 0.3, 0.035),
        ]
        let analysis = analyzer.analyze(pages: [TextLayout.arrange(lines)], referenceDate: today)
        let byKey = fields(analysis)
        #expect(analysis.kind == .identityCard)
        #expect(byKey[.surname]?.value.text == "EXEMPLU")
        #expect(byKey[.givenNames]?.value.text == "MARIA")
        #expect(byKey[.documentNumber]?.value.text == "XT123456")
        #expect(byKey[.sex]?.value.text == "F")
        #expect(byKey[.nationality]?.value.text == "ROU")
        #expect(byKey[.issuer]?.value.text == "SPCLEP Exemplu")
        #expect(byKey[.issueDate]?.value.day == CaptureDay(year: 2018, month: 3, day: 12))
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2028, month: 12, day: 31))
        #expect(byKey[.birthDate]?.value.day == CaptureDay(year: 1985, month: 12, day: 31))
        #expect(byKey[.birthDate]?.tier == .deterministic)
    }

    @Test("A single column with positions reads like plain text")
    func singleColumn() {
        let rows = ["Nume / Surname", "EXEMPLU", "Prenume / Given names", "ION", "Data nașterii / Date of birth", "01.01.1980",
                    "CNP / PIN 1800101990006", "Data expirării / Date of expiry", "15.03.2032", "CARTE DE IDENTITATE"]
        let lines = rows.enumerated().map { Card.line($0.element, 0.1, 0.05 + Double($0.offset) * 0.06, 0.6, 0.035) }
        let analysis = analyzer.analyze(pages: [lines.shuffled()].map(TextLayout.arrange), referenceDate: today)
        let byKey = fields(analysis)
        #expect(byKey[.surname]?.value.text == "EXEMPLU")
        #expect(byKey[.givenNames]?.value.text == "ION")
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2032, month: 3, day: 15))
        #expect(byKey[.sex]?.value.text == "M")
        #expect(byKey[.sex]?.tier == .deterministic)
    }

    @Test("Without positions, a label's translation on the next line is skipped")
    func translationsWithoutPositions() {
        let analysis = analyzer.analyze(text: """
        CARTE DE IDENTITATE
        Nume
        Surname
        EXEMPLU
        Data expirării
        Date of expiry
        06 04 2035
        """, referenceDate: today)
        let byKey = fields(analysis)
        #expect(byKey[.surname]?.value.text == "EXEMPLU")
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2035, month: 4, day: 6))
    }

    @Test("Dates printed with spaces read only in their strict shape")
    func spacedDates() {
        #expect(RomanianFieldExtractor.dates(inLine: "06 04 2035", index: 0).first?.day == CaptureDay(year: 2035, month: 4, day: 6))
        #expect(RomanianFieldExtractor.dates(inLine: "0722 12 34 56", index: 0).isEmpty)
        #expect(RomanianFieldExtractor.dates(inLine: "1 250 12 2024", index: 0).isEmpty)
    }

    @Test("Passport data page: dates in columns, each under its own label")
    func passportColumns() {
        let lines: [RecognizedLine] = [
            Card.line("PAȘAPORT", 0.05, 0.03, 0.2, 0.03), Card.line("PASSPORT", 0.30, 0.03, 0.2, 0.03),
            Card.line("Nume / Surname", 0.35, 0.12, 0.25), Card.line("EXEMPLU", 0.35, 0.15, 0.2, 0.035),
            Card.line("Prenume / Given names", 0.35, 0.21, 0.3), Card.line("MARIA", 0.35, 0.24, 0.15, 0.035),
            Card.line("Data nașterii / Date of birth", 0.35, 0.30, 0.3), Card.line("20.05.1990", 0.35, 0.33, 0.18, 0.035),
            Card.line("Sex", 0.70, 0.30, 0.05), Card.line("F", 0.70, 0.33, 0.03, 0.035),
            Card.line("Data eliberării / Date of issue", 0.35, 0.39, 0.3), Card.line("Data expirării / Date of expiry", 0.68, 0.39, 0.3),
            Card.line("01.03.2022", 0.35, 0.42, 0.18, 0.035), Card.line("01.03.2032", 0.68, 0.42, 0.18, 0.035),
            Card.line("CNP / Personal No.", 0.35, 0.48, 0.25), Card.line("2900520990015", 0.35, 0.51, 0.3, 0.035),
        ]
        let analysis = analyzer.analyze(pages: [TextLayout.arrange(lines)], referenceDate: today)
        let byKey = fields(analysis)
        #expect(analysis.kind == .passport)
        #expect(byKey[.birthDate]?.value.day == CaptureDay(year: 1990, month: 5, day: 20))
        #expect(byKey[.birthDate]?.tier == .deterministic)
        #expect(byKey[.issueDate]?.value.day == CaptureDay(year: 2022, month: 3, day: 1))
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2032, month: 3, day: 1))
        #expect(byKey[.givenNames]?.value.text == "MARIA")
    }

    @Test("Driving licence: 4d is the CNP only when its control digit is valid")
    func licencePersonalNumber() {
        let valid = fields(analyzer.analyze(text: """
        PERMIS DE CONDUCERE
        1. EXEMPLU
        2. ION
        3. 15.06.1970 EXEMPLU
        4a. 12.03.2021
        4b. 12.03.2031
        4c. DRPCIV EXEMPLU
        4d. 1700615990039
        5. 123456789
        9. B
        """, referenceDate: today))
        #expect(valid[.personalNumber]?.value.text == "1700615990039")
        #expect(valid[.personalNumber]?.needsCheck == false)
        #expect(valid[.birthDate]?.value.day == CaptureDay(year: 1970, month: 6, day: 15))
        #expect(valid[.issuer]?.value.text == "DRPCIV EXEMPLU")
        #expect(valid[.licenceCategories]?.value.text == "B")

        let invalid = fields(analyzer.analyze(text: "PERMIS DE CONDUCERE\n1. EXEMPLU\n4d. 1700615990038\n4b. 12.03.2031", referenceDate: today))
        #expect(invalid[.personalNumber]?.needsCheck == true)
    }

    @Test("A template's region breaks the tie when a label can't be read")
    func regionTieBreaker() {
        let template = IdentityTemplate(
            id: "test", kind: .identityCard, signals: [], distinctive: [], machineReadableFormats: [],
            fields: [.init(.documentNumber, ["nr. document"], .documentNumber(pattern: #"\b([A-Z]{2})(\d{6,7})\b"#),
                           region: TextBox(x: 0.3, y: 0.6, width: 0.3, height: 0.2))],
            otherLabels: [], agreements: []
        )
        let text = CaptureText(pages: [[
            Card.line("Nr. docvment", 0.3, 0.62, 0.2),
            Card.line("XY123456", 0.3, 0.70, 0.2, 0.035),
            Card.line("AB654321", 0.7, 0.10, 0.2, 0.035),
        ]])
        let read = IdentityDocumentReader.read(text, template: template, today: CaptureDay(year: 2026, month: 11, day: 2)!)
        let number = read.first { $0.key == .documentNumber }
        #expect(number?.value.text == "XY123456")
        #expect(number?.needsCheck == true)
    }

    @Test("Invoices keep a description and its amount on one row")
    func invoiceRowsStayTogether() throws {
        let lines: [RecognizedLine] = [
            Card.line("EXEMPLU SERVICE AUTO S.R.L.", 0.05, 0.05, 0.5, 0.03),
            Card.line("FACTURĂ FISCALĂ seria AUT nr. 004512", 0.05, 0.10, 0.6, 0.03),
            Card.line("Manopera", 0.05, 0.30, 0.2, 0.03),
            Card.line("150,00", 0.30, 0.30, 0.1, 0.03),
            Card.line("Plăcuțe frână față", 0.05, 0.25, 0.3, 0.03),
            Card.line("320,00", 0.40, 0.25, 0.1, 0.03),
            Card.line("Total de plată: 470,00 lei", 0.05, 0.40, 0.5, 0.03),
        ]
        let analysis = analyzer.analyze(pages: [TextLayout.arrange(lines)], referenceDate: today)
        #expect(analysis.kind == .serviceInvoice)
        let items = try #require(analysis.fields.first { $0.key == .lineItems }?.value.lineItems)
        #expect(items.map(\.description) == ["Plăcuțe frână față", "Manopera"])
        #expect(analysis.readableText.contains("Plăcuțe frână față 320,00"))
    }
}
