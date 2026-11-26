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
        #expect(ModelQuestions.wholeNumber(.string("45.724"), kind: .kilometres) == 45724)
        #expect(ModelQuestions.wholeNumber(.number(45.7), kind: .kilometres) == nil)
        #expect(ModelQuestions.wholeNumber(.int(45724), kind: .kilometres) == 45724)
    }

    /// A water meter's decimals read by the AI provider are kept: the index is asked for as
    /// printed and read as a meter index, like the phone's own reading of the bill.
    @Test func providerMeterIndexesKeepTheirDecimals() throws {
        let schema = CloudSchema(kind: .utilityInvoice)
        let field = try #require(schema.fields.first { $0.key == .meterIndex })
        #expect(field.format == .meterIndex)
        #expect(field.description.contains("decimals"))
        guard case .object(let properties)? = schema.json["properties"], case .object(let meter)? = properties[field.name] else {
            Issue.record("The schema lists the meter index")
            return
        }
        #expect(meter["type"] == ["string", "null"], "Asked as printed, not as a whole number")

        func mapped(_ value: String, printed: String) throws -> CaptureField? {
            let answer = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"documentKind":"utilityInvoice","meterIndex":\#(value)}"#.utf8))
            return ModelAnswerMapper.fields(from: answer, asked: schema.questions, recognizedText: printed, today: ContractCaptureTests.today,
                                            resolver: CatalogComponentResolver()).first { $0.key == .meterIndex }
        }
        let water = try #require(try mapped(#""1.234,567""#, printed: "Index nou: 1.234,567 m³"))
        #expect(water.value == .number(Decimal(string: "1234.567")!))
        #expect(water.confidence >= CaptureField.checkThreshold, "Printed on the page as read")
        let plain = try #require(try mapped("1234.567", printed: "Index nou: 1.234,567 m³"))
        #expect(plain.value == .number(Decimal(string: "1234.567")!), "A JSON number is the machine form")
        let gas = try #require(try mapped(#""12.345""#, printed: "Index nou: 12.345"))
        #expect(gas.value == .number(12_345), "The Romanian rule decides")
        #expect(gas.confidence < CaptureField.checkThreshold, "And says so: Verifică, as for the phone's reading")
        #expect(try mapped(#""citit""#, printed: "") == nil, "Not a number")
    }

    // MARK: As a Double

    /// Short numbers (up to three decimals) Foundation's `NSDecimalNumber.doubleValue`, the
    /// conversion of earlier versions, missed: each with what it gave and the Double it is.
    static let missedBefore: [(text: String, old: Double, right: Double)] = {
        var found: [(String, Double, Double)] = []
        for whole in stride(from: 0, to: 2_000_000, by: 7_919) {
            for thousandths in stride(from: 1, to: 1_000, by: 7) {
                let digits = String(thousandths)
                let text = "\(whole)." + String(repeating: "0", count: 3 - digits.count) + digits
                let old = NSDecimalNumber(decimal: Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!).doubleValue
                let right = Double(text)!
                if old != right { found.append((text, old, right)) }
            }
        }
        return found
    }()

    /// The one conversion is correctly rounded: the Double Swift reads from the number's own text,
    /// the one Kotlin's `BigDecimal.toDouble()` gives, where the old conversion missed some.
    @Test func aNumberBecomesTheDoubleNearestIt() throws {
        let posix = Locale(identifier: "en_US_POSIX")
        let printed = try #require(Decimal(string: "98765.4321", locale: posix))
        #expect(RomanianNumber.double(printed) == 98765.4321)
        #expect(try RomanianNumber.read("98.765,4321", as: .meterIndex).get().doubleValue == 98765.4321)
        #expect(NSDecimalNumber(decimal: printed).doubleValue == 98765.43209999999, "What earlier versions stored")
        try #require(!Self.missedBefore.isEmpty, "The old conversion missed some short numbers")
        for (text, _, right) in Self.missedBefore {
            #expect(RomanianNumber.double(try #require(Decimal(string: text, locale: posix))) == right, "\(text)")
        }
        for text in ["0", "1", "45724", "0.125", "1250.5", "-3.75", "0.1", "123456789012345678901234567890", "0.00000000000000000001"] {
            #expect(RomanianNumber.double(try #require(Decimal(string: text, locale: posix))) == Double(text), "\(text)")
        }
    }

    /// The repair's rule: a Double up to three steps off a short number's (up to the kind's
    /// decimals) is put back on it; every other Double stands.
    @Test func aNumberKeptAStepOffIsPutBack() {
        for (text, old, right) in Self.missedBefore {
            #expect(RomanianNumber.correction(of: old, as: .meterIndex) == right, "\(text) kept as \(old)")
            #expect(RomanianNumber.correction(of: right, as: .meterIndex) == nil, "\(text) stands")
            #expect(RomanianNumber.correction(of: -old, as: .meterIndex) == -right, "Below zero alike")
        }
        // Money keeps two decimals: a three-decimal number a step off stands as money.
        #expect(RomanianNumber.correction(of: 1250.55.nextUp, as: .money) == 1250.55)
        #expect(RomanianNumber.correction(of: 1250.555.nextUp, as: .money) == nil)
        #expect(RomanianNumber.correction(of: 1250.555.nextUp, as: .meterIndex) == 1250.555)
        // A meter index keeps up to six decimals: 98765.4321 kept a step off is put back.
        #expect(RomanianNumber.correction(of: 98765.43209999999, as: .meterIndex) == 98765.4321)
        #expect(RomanianNumber.correction(of: 98765.4321, as: .meterIndex) == nil)
        #expect(RomanianNumber.correction(of: 1.234_567_8.nextUp, as: .meterIndex) == nil, "Seven decimals are no short number")
        // Whole kinds: only a whole number's neighbour is put back.
        #expect(RomanianNumber.correction(of: 45_724.0.nextUp, as: .kilometres) == 45_724)
        #expect(RomanianNumber.correction(of: 45_724.0.nextDown, as: .count) == 45_724)
        #expect(RomanianNumber.correction(of: 45_724.5, as: .kilometres) == nil)
        // Up to three steps off, the old conversion's largest miss; four is none of its.
        #expect(RomanianNumber.correction(of: 1250.55.nextUp.nextUp, as: .money) == 1250.55)
        #expect(RomanianNumber.correction(of: 1250.55.nextDown.nextDown, as: .money) == 1250.55)
        #expect(RomanianNumber.correction(of: 1250.55.nextUp.nextUp.nextUp, as: .money) == 1250.55)
        #expect(RomanianNumber.correction(of: 1250.55.nextUp.nextUp.nextUp.nextUp, as: .money) == nil)
        // Where a step is too large for the decimals to be told apart, nothing changes.
        #expect(RomanianNumber.correction(of: 4_000_000_000_000.125.nextUp, as: .meterIndex) == nil)
        #expect(RomanianNumber.correction(of: 2_147_483_648.5.nextUp, as: .meterIndex) == nil, "From 2³⁰, six decimals are out of reach")
        #expect(RomanianNumber.correction(of: 2_147_483_648.5.nextUp, as: .money) == 2_147_483_648.5, "Money's two still are")
        #expect(RomanianNumber.correction(of: 9_007_199_254_740_992, as: .kilometres) == nil)
        for stands in [0, -0.0, .infinity, -.infinity, .nan, 5e-324, 45_724, 0.125] as [Double] {
            #expect(RomanianNumber.correction(of: stands, as: .meterIndex) == nil, "\(stands)")
        }
    }
}
