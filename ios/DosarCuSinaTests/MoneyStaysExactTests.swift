import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Money is kept as a `Decimal` (`Money`, the models' `…Amount` properties), and the store keeps
/// it through a `Double`, which holds up to 15 significant digits exactly. So the binder keeps
/// an amount only within them (`Money.keepsExactly`, `Money.mostDigits`), and every amount it
/// keeps reads back exactly as it was written: never as the nearest `Double`. Every value is a
/// placeholder.
@MainActor
@Suite("Money stays exact in the store")
struct MoneyStaysExactTests {
    /// Amounts a `Double` can't hold as written in binary, up to the 15 digits the binder keeps.
    static let kept: [String] = [
        "0.1", "0.3", "1.005", "19.99", "1234.56", "99999999.99", "0.000001",
        "9999999999999.99", "123456789012.345", "100000000000000",
    ]

    static func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test func everyAmountTheBinderKeepsReadsBackAsItWasWritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "money-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar.store")

        let written = try Self.kept.map(Self.decimal)
        #expect(written.allSatisfy(Money.keepsExactly), "Every one is within what the binder keeps")
        do {
            let context = ModelContext(try PersistenceController.makeContainer(storeURL: url))
            for (index, amount) in written.enumerated() {
                let entry = HistoryEntry(kind: .purchase, title: "Exemplu \(index)", occurredAt: Date(timeIntervalSince1970: Double(index)))
                entry.totalCostAmount = amount
                entry.totalCostCurrency = "RON"
                context.insert(entry)
            }
            try UnitOfWork.save(context)
        }

        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let read = try reopened.fetch(FetchDescriptor<HistoryEntry>()).sorted { $0.occurredAt < $1.occurredAt }
        #expect(read.count == written.count)
        for (entry, amount) in zip(read, written) {
            #expect(entry.totalCostAmount == amount, "\(amount) came back as \(String(describing: entry.totalCostAmount))")
        }
    }

    @Test func anAmountWithMoreDigitsIsNeverTakenIn() throws {
        // Typed or read off a paper: refused with its own words, never rounded.
        for text in ["12.345.678.901.234,56", "0,1234567890123456"] {
            #expect(RomanianNumber.read(text, as: .money) == .failure(.tooManyDigits), "\(text)")
        }
        #expect(RomanianNumber.read("9.999.999.999.999,99", as: .money).map(\.value) == .success(try Self.decimal("9999999999999.99")))
        #expect(RomanianNumber.Problem.tooManyDigits.message(for: .money) == "Scrie suma cu cel mult 15 cifre.")
        // Other kinds keep what they read: a meter index isn't money.
        #expect((try? RomanianNumber.read("12.345.678.901.234,56", as: .meterIndex).get()) != nil)

        // From a backup: not an amount the binder keeps, as a text that isn't one.
        #expect(Money(amountString: "12345678901234.56", currency: "RON") == nil)
        #expect(Money(amountString: "9999999999999.99", currency: "RON")?.amount == (try Self.decimal("9999999999999.99")))
        let json = Data(#"{"amount":"12345678901234.56","currency":"RON"}"#.utf8)
        #expect(throws: DecodingError.self) { try MachineText.jsonDecoder().decode(Money.self, from: json) }
    }

    @Test func digitsAreCountedFromTheFirstToTheLastThatIsntZero() throws {
        #expect(Money.significantDigits(try Self.decimal("0.000001")) == 1)
        #expect(Money.significantDigits(try Self.decimal("100000000000000")) == 1)
        #expect(Money.significantDigits(try Self.decimal("1250.50")) == 5)
        #expect(Money.significantDigits(try Self.decimal("-12345678901234.56")) == 16)
        #expect(Money.significantDigits(0) == 0)
    }
}
