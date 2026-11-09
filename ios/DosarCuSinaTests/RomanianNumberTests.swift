import Foundation
import Testing
@testable import DosarCuSina

/// The one number reader. Each kind of number has one table of tricky inputs; every
/// reader and field in the app goes through it, so these tables are the rule.
@Suite("Romanian number reader")
struct RomanianNumberTests {
    /// What the reader should make of an input: a value (and whether a document's copy gets
    /// "Verifică"), or the reason it refuses.
    enum Expected: Equatable {
        case value(String, check: Bool = false)
        case refused(RomanianNumber.Problem)
    }

    static let tricky = ["3,750", "0,725", "45.724", "45,724", "86,420 km", "Index nou: 12.345", "1.250,50", "-", "12-05", "5²"]

    static let money: [Expected] = [
        .value("3.75", check: true), .value("0.725"), .value("45724", check: true), .value("45.724", check: true),
        .refused(.unreadable), .value("12345", check: true), .value("1250.5"),
        .refused(.unreadable), .refused(.unreadable), .refused(.unreadable),
    ]
    static let count: [Expected] = [
        .value("3750"), .refused(.notWhole), .value("45724"), .value("45724"),
        .refused(.unreadable), .value("12345"), .refused(.notWhole),
        .refused(.unreadable), .refused(.unreadable), .refused(.unreadable),
    ]
    static let meterIndex: [Expected] = [
        .value("3.75", check: true), .value("0.725"), .value("45724", check: true), .value("45.724", check: true),
        .refused(.unreadable), .value("12345", check: true), .value("1250.5"),
        .refused(.unreadable), .refused(.unreadable), .refused(.unreadable),
    ]
    static let kilometres: [Expected] = [
        .value("3750"), .refused(.notWhole), .value("45724"), .value("45724"),
        .value("86420"), .value("12345"), .refused(.notWhole),
        .refused(.unreadable), .refused(.unreadable), .refused(.unreadable),
    ]

    static func check(_ kind: NumberKind, _ table: [Expected]) {
        #expect(table.count == tricky.count)
        for (input, expected) in zip(tricky, table) {
            let read = RomanianNumber.read(input, as: kind, from: .document)
            switch (read, expected) {
            case (.success(let reading), .value(let value, let check)):
                #expect(reading.value == Decimal(string: value), "\(kind) \(input)")
                #expect(reading.needsCheck == check, "\(kind) \(input): Verifică")
            case (.failure(let problem), .refused(let wanted)):
                #expect(problem == wanted, "\(kind) \(input)")
            default:
                Issue.record("\(kind) \(input): read \(read), expected \(expected)")
            }
        }
    }

    @Test func moneyTable() { Self.check(.money, Self.money) }
    @Test func countTable() { Self.check(.count, Self.count) }
    @Test func meterIndexTable() { Self.check(.meterIndex, Self.meterIndex) }
    @Test func kilometresTable() { Self.check(.kilometres, Self.kilometres) }

    @Test("Other forms people and documents write", arguments: [
        ("1 234,50", NumberKind.money, "1234.5"), ("1\u{00A0}450,50 lei", .money, "1450.5"), ("1,250.50", .money, "1250.5"),
        ("12.5", .money, "12.5"), ("350 RON", .money, "350"), ("1.250.500", .count, "1250500"), ("84.200 km", .kilometres, "84200"),
        ("84200km", .kilometres, "84200"), ("4,5 kg", .meterIndex, "4.5"), ("1234,567", .meterIndex, "1234.567"), ("0", .count, "0"),
    ])
    func otherForms(input: String, kind: NumberKind, expected: String) {
        #expect(RomanianNumber.value(input, as: kind) == Decimal(string: expected), "\(input)")
    }

    @Test("Unclear text is refused, never read as 0 or cut short", arguments: [
        ".", ",", "12-5", "1.2.3", "1.25.500", "12:30", "12 km", "abc", "1,250.50,5", "+5",
    ])
    func refusesUnclearText(input: String) {
        #expect(RomanianNumber.value(input, as: .money) == nil, "\(input)")
    }

    @Test func emptyAndNegative() {
        #expect(RomanianNumber.read("  ", as: .money) == .failure(.empty))
        #expect(RomanianNumber.read("-12,50", as: .money) == .failure(.negative))
        #expect(RomanianNumber.read("45724,5 km", as: .kilometres) == .failure(.notWhole))
    }

    @Test func typedNumbersAreNeverMarkedForACheck() {
        let typed = try? RomanianNumber.read("3,750", as: .money).get()
        #expect(typed?.value == Decimal(string: "3.75"))
        #expect(typed?.isAmbiguous == true)
        #expect(typed?.needsCheck == false)
    }

    @Test func everyRefusalHasAMessage() {
        for kind in NumberKind.allCases {
            for problem in [RomanianNumber.Problem.unreadable, .negative, .notWhole] {
                #expect(!problem.message(for: kind).isEmpty)
            }
        }
    }

    @Test("A shown number reads back unchanged", arguments: NumberKind.allCases)
    func shownNumbersReadBackUnchanged(kind: NumberKind) {
        let values: [Decimal] = kind.isWhole ? [45724, 142_500, 7, 1_250_500, 0] : [45724, 142_500, 7, 1250.5, 0.5, Decimal(string: "0.725")!, 3]
        for value in values {
            for grouping in [true, false] {
                let shown = RomanianNumber.format(value, fractionDigits: 0...3, groupsDigits: grouping)
                #expect(RomanianNumber.value(shown, as: kind) == value, "\(kind): \(shown)")
            }
        }
    }

    @Test func machineFormIsReadOnlyAsWritten() {
        #expect(RomanianNumber.canonical("1250.5") == Decimal(string: "1250.5"))
        #expect(RomanianNumber.canonical("-3") == -3)
        #expect(RomanianNumber.canonical("1.250,5") == nil)
        #expect(RomanianNumber.canonical("45,724") == nil)
    }

    @Test func fieldKindsFollowTheUnit() {
        #expect(NumberKind.forField(unit: .kilometres) == .kilometres)
        #expect(NumberKind.forField(unit: .kilograms) == .meterIndex)
        #expect(NumberKind.forField(unit: nil, allowsDecimals: false) == .count)
    }

    /// K1 turned around: every reader in the app gives the same answer.
    @Test func everyReaderAgrees() {
        #expect(RomanianNumber.value("45,724", as: .money) == RomanianFieldExtractor.amount("45,724")?.value)
        #expect(FieldFormatter.value(from: "45.724", as: .metric, unit: .kilometres) == .number(45724))
        #expect(FieldFormatter.value(from: "45,724", as: .metric, unit: .kilometres) == .number(45724))
        let bill = BillReader.fields(in: CaptureText("ENGIE Romania\nCod client: 1234567890\nIndex nou: 12.345 mc"))
        #expect(bill.first { $0.key == .meterIndex }?.value == .number(12345))
        #expect(RomanianFieldExtractor.odometer(in: CaptureText("Total 86,420 km"))?.km == 86420)
        #expect(RomanianFieldExtractor.odometer(in: CaptureText("Km bord: 86420,5"))?.km == nil)
    }

    @Test func documentAmountsThatCouldReadTwoWaysAreMarked() {
        let total = RomanianFieldExtractor.total(in: CaptureText("Total de plată: 3,750 lei"))
        #expect(total?.money.amount == Decimal(string: "3.75"))
        #expect(total?.ambiguous == true)
        #expect(CaptureAnalyzer.confidence(0.8, ambiguous: true) < CaptureField.checkThreshold)
    }

    @Test func providerWholeNumbersAreNeverCutShort() {
        #expect(CloudSchema.wholeNumber(.string("45.724"), kind: .kilometres) == 45724)
        #expect(CloudSchema.wholeNumber(.number(45.7), kind: .kilometres) == nil)
        #expect(CloudSchema.wholeNumber(.int(45724), kind: .kilometres) == 45724)
    }
}
