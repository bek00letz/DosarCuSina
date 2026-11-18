import Foundation
import Testing
@testable import DosarCuSina

/// Capture learns where an issuer prints a value by the page's positions too: under its label in
/// a column, beside it far along its row, or after another value on its line, and reads the next
/// paper the same way on the phone alone. Placeholder firm, codes and amounts only.
@Suite("Capture learns two-column layouts")
struct CaptureLearnsLayoutsTests {
    static let issuer = IssuerKey(rawValue: "cui:12345674")

    /// One recognized line where it sits on the page: `x` and `y` from the page's top-left, a line
    /// two hundredths of the page high, about as wide as its text.
    static func line(_ text: String, x: Double, y: Double) -> RecognizedLine {
        RecognizedLine(text, box: TextBox(x: x, y: y, width: Double(text.count) * 0.012, height: 0.02))
    }

    /// A gas bill printed in two columns: each label over its value, the due date under a label
    /// the phone's tables don't have, and the amount to pay at the far end of its label's row.
    static func twoColumnBill(issued: String, due: String, nextReading: String, total: String,
                              dueLabel: String = "Termen achitare", totalLabel: String = "Sumă datorată",
                              extra: [RecognizedLine] = []) -> [[RecognizedLine]] {
        [[
            line("ENGIE Romania S.A.", x: 0.05, y: 0.04),
            line("CUI: RO12345674", x: 0.05, y: 0.07),
            line("FACTURĂ GAZE NATURALE", x: 0.05, y: 0.10),
            line("Seria EXM nr. 0000001", x: 0.05, y: 0.13),
            line("Data emiterii", x: 0.05, y: 0.20), line(dueLabel, x: 0.55, y: 0.20),
            line(issued, x: 0.05, y: 0.23), line(due, x: 0.55, y: 0.23),
            line("Următoarea citire", x: 0.05, y: 0.29), line("Cod client", x: 0.55, y: 0.29),
            line(nextReading, x: 0.05, y: 0.32), line("1000000000", x: 0.55, y: 0.32),
            line(totalLabel, x: 0.05, y: 0.38), line("\(total) lei", x: 0.80, y: 0.38),
        ] + extra]
    }

    static let firstBill = twoColumnBill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026", total: "123,45")
    static let secondBill = twoColumnBill(issued: "01.12.2026", due: "14.01.2027", nextReading: "21.01.2027", total: "98,10")
    static let due = CaptureValue.day(CalendarDay("2026-12-15"))
    static let total = CaptureValue.money(Money(Decimal(string: "123.45")!, currency: "RON"))

    static func source(_ pages: [[RecognizedLine]], on iso: String, lessons: LessonBook = .empty) -> CaptureReadingSource {
        CaptureReadingSource(text: CaptureText(pages: pages).joinedOriginal, pages: pages, barcodes: [], referenceDate: noon(iso),
                             modelFields: [], aiFields: nil, isSinglePhoto: true, lessons: lessons)
    }

    /// What the phone read of pasted text, which has no positions.
    static func source(text: String, on iso: String) -> CaptureReadingSource {
        CaptureReadingSource(text: text, pages: [], barcodes: [], referenceDate: noon(iso), modelFields: [], aiFields: nil,
                             isSinglePhoto: false)
    }

    static func read(_ pages: [[RecognizedLine]], on iso: String, lessons: LessonBook = .empty) -> CaptureAnalyzer.Analysis {
        CaptureAnalyzer.standard().learning(lessons).analyze(pages: pages, referenceDate: noon(iso))
    }

    static func value(_ key: CaptureFieldKey, in analysis: CaptureAnalyzer.Analysis) -> CaptureField? {
        analysis.fields.first { $0.key == key }
    }

    // MARK: Learned, then read on the phone alone

    @Test("A due date under its label in a column, and an amount far along its label's row, are learned and read on the next bill")
    func twoColumnsAreLearnedAndRead() throws {
        let alone = Self.read(Self.firstBill, on: "2026-11-02")
        #expect(alone.kind == .utilityInvoice)
        #expect(Self.value(.dueDate, in: alone)?.value != Self.due, "Tiers 1–2 miss the due date in its column")
        #expect(Self.value(.total, in: alone)?.value != Self.total, "…and the amount under a label they don't know")

        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due, .total: Self.total])
        let outcome = try #require(CaptureLessonLearner.lessons(from: Self.source(Self.firstBill, on: "2026-11-02"), saved: saved))
        #expect(outcome.issuer == Self.issuer)
        #expect(outcome.learned == [
            CaptureLesson(issuer: Self.issuer, kind: .utilityInvoice, field: .dueDate, label: "Termen achitare"),
            CaptureLesson(issuer: Self.issuer, kind: .utilityInvoice, field: .total, label: "Sumă datorată"),
        ])

        // The next bill of the same firm, on the phone alone.
        let next = Self.read(Self.secondBill, on: "2026-12-02", lessons: LessonBook(outcome.learned))
        #expect(Self.value(.dueDate, in: next)?.value == .day(CalendarDay("2027-01-14")), "Read under its label, in its column")
        #expect(Self.value(.total, in: next)?.value == .money(Money(Decimal(string: "98.10")!, currency: "RON")), "Read along its row")
        #expect(Self.value(.dueDate, in: next)?.tier == .heuristic, "The phone's own reader read it")
        #expect(Self.value(.issueDate, in: next)?.value == .day(CalendarDay("2026-12-01")), "What the phone read right still reads the same")
        // Without the lessons the same page still reads as before.
        #expect(Self.value(.dueDate, in: Self.read(Self.secondBill, on: "2026-12-02"))?.value != .day(CalendarDay("2027-01-14")))
    }

    @Test("A due date in a column under the kind's own label is read right once its issuer's bill teaches it")
    func aColumnUnderTheKindsOwnLabel() throws {
        func bill(issued: String, due: String, nextReading: String) -> [[RecognizedLine]] {
            Self.twoColumnBill(issued: issued, due: due, nextReading: nextReading, total: "123,45", dueLabel: "Data scadentă")
        }
        let first = bill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026")
        #expect(Self.value(.dueDate, in: Self.read(first, on: "2026-11-02"))?.value != Self.due,
                "The kind's rows, read on rows joined across the page, take the other column's date")

        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due])
        let outcome = try #require(CaptureLessonLearner.lessons(from: Self.source(first, on: "2026-11-02"), saved: saved))
        #expect(outcome.learned == [CaptureLesson(issuer: Self.issuer, kind: .utilityInvoice, field: .dueDate, label: "Data scadentă")])
        let next = Self.read(bill(issued: "01.12.2026", due: "14.01.2027", nextReading: "21.01.2027"), on: "2026-12-02",
                             lessons: LessonBook(outcome.learned))
        #expect(Self.value(.dueDate, in: next)?.value == .day(CalendarDay("2027-01-14")))
    }

    @Test("A label after another value on its line is learned without that value, and read on the next bill")
    func aLabelAfterAnotherValueOnItsLine() throws {
        func bill(issued: String, due: String, nextReading: String) -> String {
            """
            ENGIE Romania S.A.
            CUI: RO12345674
            FACTURĂ GAZE NATURALE
            Data emiterii: \(issued) Termen achitare: \(due)
            Următoarea citire: \(nextReading)
            Total de plată: 123,45 lei
            """
        }
        let first = Self.source(text: bill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026"), on: "2026-11-02")
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due])
        let outcome = try #require(CaptureLessonLearner.lessons(from: first, saved: saved))
        #expect(outcome.learned == [CaptureLesson(issuer: Self.issuer, kind: .utilityInvoice, field: .dueDate, label: "Termen achitare")])

        let next = CaptureAnalyzer.standard().learning(LessonBook(outcome.learned))
            .analyze(text: bill(issued: "01.12.2026", due: "14.01.2027", nextReading: "21.01.2027"), referenceDate: noon("2026-12-02"))
        #expect(Self.value(.dueDate, in: next)?.value == .day(CalendarDay("2027-01-14")))
        #expect(Self.value(.issueDate, in: next)?.value == .day(CalendarDay("2026-12-01")), "The value before it keeps its own label")
    }

    // MARK: Refusals

    @Test("A column's label with digits, or holding a value of the person's, is never a lesson")
    func columnLabelsWithDigitsOrPersonalValuesAreRefused() {
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due])
        let digits = Self.twoColumnBill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026", total: "123,45",
                                        dueLabel: "Termen 30 zile")
        #expect(CaptureLessonLearner.lessons(from: Self.source(digits, on: "2026-11-02"), saved: saved) == nil)

        let personal = Self.twoColumnBill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026", total: "123,45",
                                          dueLabel: "Titular Exemplu")
        let withHolder = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due, .policyholder: .text("Ion Exemplu")])
        #expect(CaptureLessonLearner.lessons(from: Self.source(personal, on: "2026-11-02"), saved: withHolder) == nil)
    }

    @Test("A value printed under two different labels teaches nothing")
    func twoColumnLabelsTeachNothing() {
        let twice = Self.twoColumnBill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026", total: "123,45", extra: [
            Self.line("Data limită", x: 0.55, y: 0.44), Self.line("15.12.2026", x: 0.55, y: 0.47),
        ])
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due])
        #expect(CaptureLessonLearner.lessons(from: Self.source(twice, on: "2026-11-02"), saved: saved) == nil)
    }

    @Test("A column's label the kind reads as another value is never this value's lesson")
    func anotherFieldsLabelIsRefused() {
        let header = Self.twoColumnBill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026", total: "123,45",
                                        dueLabel: "Cod de plată")
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due])
        #expect(CaptureLessonLearner.lessons(from: Self.source(header, on: "2026-11-02"), saved: saved) == nil)
        #expect(CaptureDocumentKind.utilityInvoice.profile.wordings(otherThan: .dueDate).contains("cod de plata"))
        #expect(!CaptureDocumentKind.utilityInvoice.profile.wordings(otherThan: .dueDate).contains("data scadenta"))
    }

    @Test("Without positions, two columns joined into rows teach nothing: which label is a value's can't be told")
    func joinedColumnsTeachNothing() {
        let text = """
            ENGIE Romania S.A.
            CUI: RO12345674
            FACTURĂ GAZE NATURALE
            Data emiterii Termen achitare
            01.11.2026 15.12.2026
            Următoarea citire: 20.12.2026
            """
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: Self.due])
        #expect(CaptureLessonLearner.lessons(from: Self.source(text: text, on: "2026-11-02"), saved: saved) == nil)
    }

    @Test("A label starts after the date or the amount before it, and a bare number stays part of its label")
    func aLabelStartsAfterTheValueBeforeIt() {
        func label(_ line: String) -> String {
            let folded = RomanianText.fold(line)
            return String(folded[CaptureLessonLearner.afterLastValue(in: folded, before: folded.endIndex)...])
        }
        #expect(label("Data emiterii: 01.11.2026 Termen achitare:") == " termen achitare:")
        #expect(label("Total 123,45 lei Termen achitare") == " termen achitare", "The currency is the amount's")
        #expect(label("Termen 30 zile") == "termen 30 zile", "Refused for its digit")
        #expect(label("Termen achitare") == "termen achitare")
    }

    // MARK: The layout read both ways

    @Test("A label's value is the first place that reads as the field: beside it, else under it in its column")
    func theFirstPlaceThatReadsWins() throws {
        let text = CaptureText(pages: [[
            Self.line("Termen achitare", x: 0.05, y: 0.20), Self.line("Perioada", x: 0.40, y: 0.20),
            Self.line("15.12.2026", x: 0.05, y: 0.23),
        ]])
        let layout = LabelledLayout(text: text, words: [(CaptureFieldKey.dueDate, ["termen achitare"])], reach: LessonBook.rowReach)
        #expect(layout.found(for: .dueDate)?.value == "Perioada", "The nearest line on its row comes first")
        let field = try #require(layout.field(.dueDate, as: .dueDate, kind: .utilityInvoice, window: .aroundToday, currency: "RON",
                                              confidence: LessonBook.readingConfidence))
        #expect(field.value == Self.due, "The day is under it")

        // Read backwards: the date's label is the line above it in its column, the line beside it on its row nothing.
        let date = try #require(text.original.firstIndex(of: "15.12.2026"))
        #expect(LabelledLayout<CaptureFieldKey>.lineAbove(date, in: text) == 0)
        #expect(LabelledLayout<CaptureFieldKey>.lineBefore(date, in: text, reach: LessonBook.rowReach) == nil)
        let beside = try #require(text.original.firstIndex(of: "Perioada"))
        #expect(LabelledLayout<CaptureFieldKey>.lineBefore(beside, in: text, reach: LessonBook.rowReach) == 0, "Anywhere along its row")
        #expect(LabelledLayout<CaptureFieldKey>.lineBefore(beside, in: text, reach: LabelledLayout<CaptureFieldKey>.maximumBesideGap) == nil,
                "Further than an identity card's value sits from its label")
    }
}
