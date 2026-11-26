import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Money is kept as a `Decimal` (`Money`, the models' `…Amount` properties), so an amount reads
/// back exactly as it was written: never as the nearest `Double`, whose binary fractions can't
/// hold most amounts in lei and bani. This writes amounts a `Double` can't keep to a store on
/// disk, reopens it, and reads them back. Every value is a placeholder.
@MainActor
@Suite("Money stays exact in the store")
struct MoneyStaysExactTests {
    /// Amounts a `Double` can't hold exactly, or holds only to about 15 significant digits.
    static let amounts: [String] = [
        "0.1", "0.3", "1.005", "19.99", "1234.56", "99999999.99",
        "12345678901234.56", "0.000001", "7000000000000000.01",
    ]

    @Test func everyAmountReadsBackAsItWasWritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "money-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar.store")

        let written = try Self.amounts.map { try #require(Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))) }
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
}
