import Foundation
import Testing
@testable import DosarCuSina

/// The Romanian driving licence front, laid out as on the official specimen: numbered
/// fields, two of them sharing a row (4a with 4c, 4b with 4d), categories in boxes.
/// Names are placeholders. The CNPs use county code 99; the first has a valid control
/// digit, the second doesn't.
@Suite("Driving licence front")
struct DrivingLicenceTests {

    let analyzer = CaptureAnalyzer()
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    private func front(personalNumber: String) -> [RecognizedLine] {
        [
            Card.line("PERMIS DE CONDUCERE", 0.05, 0.04, 0.45, 0.04),
            Card.line("ROMÂNIA", 0.70, 0.04, 0.20, 0.04),
            Card.line("1. EXEMPLU", 0.35, 0.15, 0.25, 0.035),
            Card.line("2. ION ANDREI", 0.35, 0.21, 0.30, 0.035),
            Card.line("3. 01.01.1990", 0.35, 0.27, 0.22, 0.035),
            Card.line("BUCUREȘTI, B", 0.62, 0.27, 0.20, 0.035),
            Card.line("4a. 20.04.2018", 0.35, 0.33, 0.22, 0.035),
            Card.line("4c. DRPCIV EXEMPLU", 0.62, 0.33, 0.30, 0.035),
            Card.line("4b. 20.04.2028", 0.35, 0.39, 0.22, 0.035),
            Card.line("4d. " + personalNumber, 0.62, 0.39, 0.30, 0.035),
            Card.line("5. B00012345", 0.35, 0.45, 0.22, 0.035),
            Card.line("7.", 0.35, 0.52, 0.04, 0.035),
            Card.line("SPECIMEN", 0.60, 0.62, 0.25, 0.04),
            Card.line("9.", 0.05, 0.85, 0.03, 0.035),
            Card.line("A", 0.12, 0.85, 0.03, 0.035),
            Card.line("B", 0.20, 0.85, 0.03, 0.035),
            Card.line("C", 0.28, 0.85, 0.03, 0.035),
        ]
    }

    private func read(_ lines: [RecognizedLine]) -> [CaptureFieldKey: CaptureField] {
        let analysis = analyzer.analyze(pages: [TextLayout.arrange(lines)], referenceDate: today)
        #expect(analysis.kind == .drivingLicence)
        return Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test("Specimen layout: every numbered field, each value stopping at the next label")
    func specimenLayout() {
        let byKey = read(front(personalNumber: "1900101990010"))
        #expect(byKey[.surname]?.value.text == "EXEMPLU")
        #expect(byKey[.givenNames]?.value.text == "ION ANDREI")
        #expect(byKey[.birthDate]?.value.day == CalendarDay(printedYear: 1990, month: 1, day: 1))
        #expect(byKey[.issueDate]?.value.day == CalendarDay(printedYear: 2018, month: 4, day: 20))
        #expect(byKey[.expiryDate]?.value.day == CalendarDay(printedYear: 2028, month: 4, day: 20))
        #expect(byKey[.issuer]?.value.text == "DRPCIV EXEMPLU")
        #expect(byKey[.personalNumber]?.value.text == "1900101990010")
        #expect(byKey[.personalNumber]?.needsCheck == false)
        #expect(byKey[.sex]?.value.text == "M")
        #expect(byKey[.documentNumber]?.value.text == "B00012345")
        #expect(byKey[.licenceCategories]?.value.text == "A, B, C")
    }

    @Test("A 4d that fails its control digit is kept for a look, and decides nothing")
    func invalidPersonalNumber() {
        let byKey = read(front(personalNumber: "1900101990014"))
        #expect(byKey[.personalNumber]?.value.text == "1900101990014")
        #expect(byKey[.personalNumber]?.needsCheck == true)
        #expect(byKey[.sex] == nil)
        #expect(byKey[.birthDate]?.tier == .heuristic)
    }

    @Test("Two fields merged on one line still split at the second label")
    func sharedRowOnOneLine() {
        let analysis = analyzer.analyze(text: """
        PERMIS DE CONDUCERE
        1. EXEMPLU
        4a. 20.04.2018 4c. DRPCIV EXEMPLU
        4b. 20.04.2028 4d. 1900101990014
        9. A B C
        """, referenceDate: today)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byKey[.issueDate]?.value.day == CalendarDay(printedYear: 2018, month: 4, day: 20))
        #expect(byKey[.issuer]?.value.text == "DRPCIV EXEMPLU")
        #expect(byKey[.expiryDate]?.value.day == CalendarDay(printedYear: 2028, month: 4, day: 20))
        #expect(byKey[.personalNumber]?.value.text == "1900101990014")
        #expect(byKey[.licenceCategories]?.value.text == "A, B, C")
    }
}
