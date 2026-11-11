import Foundation
import SwiftData

// MARK: - Bills whose index was estimated, filed before readings said so

/// Before database version 14 a reading didn't keep how it was taken, so a bill's estimated
/// index was kept like a real one, and the real index that corrected it later looked like a
/// drop. A reading a bill recorded, not yet said to be anything, whose bill's kept text says
/// its index was estimated (read again by the bill's own reader, `BillReader.readingBasis`)
/// and prints that same index, is offered to be marked as an estimate. It asks, because it
/// changes which index counts: once marked, an estimate counts only until a later reading of
/// its counter is lower (`ReadingSeries.correctedEstimates`). Nothing else is guessed: a bill
/// that doesn't say, or whose text is gone, stays as it is.
struct EstimatedBillReadingsStep: DataRepairStep {
    static let id = DataRepairStepID.estimatedBillReadings
    var title: String { String(localized: "Indexuri estimate", comment: "Repair group: meter indexes a bill estimated, kept as if read.") }

    /// The readings to offer: on a counter whose readings may be estimated, recorded by a bill
    /// whose kept text says the index it prints, this one, was estimated.
    static func candidates(in context: ModelContext) throws -> [MeasurementLog] {
        try context.fetch(FetchDescriptor<MeasurementLog>()).filter { log in
            guard !log.isDeleted, log.basisRaw == nil, log.kind.mayBeEstimated, log.asset?.isExample == false else { return false }
            return (log.attachments ?? []).contains { document in billSaysEstimated(document, value: log.value) }
        }
    }

    /// Whether `document`'s kept text says its index is `value` and that it was estimated.
    static func billSaysEstimated(_ document: Attachment, value: Double) -> Bool {
        guard !document.isDeleted, let kept = document.extractedText, !kept.isEmpty else { return false }
        let text = CaptureText(kept)
        let layout = BillReader.layout(of: text)
        guard let index = BillReader.meterIndex(in: layout), SubscriptionMeter.number(index.value) == value,
              BillReader.readingBasis(in: text, layout: layout)?.value.text == ReadingBasis.estimated.rawValue else { return false }
        return true
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).compactMap { log in
            guard let asset = log.asset else { return nil }
            let shown = CounterWording.amount(log.value, unit: log.measurementUnit)
            let day = DosarFormat.day(log.recordedAt, calendar: scan.calendar)
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(log.id.uuidString):\(log.value)",
                step: Self.id,
                message: String(localized: "La „\(asset.name)”, factura din \(day) spune că indexul \(shown) e estimat. Îl marchez ca estimare?",
                                comment: "Repair: a bill's meter index the bill says was estimated, kept as if read; marked, it counts only until a lower real reading."),
                subject: .readingEstimate(logID: log.id)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let ids = Set(findings.compactMap { finding -> UUID? in
            guard case .readingEstimate(let id) = finding.subject else { return nil }
            return id
        })
        for log in try Self.candidates(in: context) where ids.contains(log.id) {
            log.basis = .estimated
            if let asset = log.asset { HouseholdMutations.syncHeroMetric(of: asset, in: context) }
        }
    }
}
