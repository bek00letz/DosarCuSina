import Foundation
import SwiftData

// MARK: - Whole card numbers kept from before

/// Before the unit of work kept card numbers out of every record's words (`FreeText`), a
/// card number typed into a row under Date importante, a note, a title or any other text was
/// kept whole; so was one in a backup's notes or titles. Every record whose words hold one is
/// offered, in plain words, to keep only the last four digits, by the same rule a save uses.
/// It asks, because it changes what the person sees. A record saved again for any other
/// reason is masked by that save.
struct CardNumbersStep: DataRepairStep {
    static let id = DataRepairStepID.cardNumbers
    var title: String { String(localized: "Numere de card întregi", comment: "Repair group: whole bank card numbers kept in rows, notes or titles by older builds.") }

    /// A record whose words hold a whole card number, and what to call it.
    struct Candidate {
        let ref: RecordRef
        /// Its own name: a section's, a visit's, a document's title.
        let name: String
        /// The section it belongs to, when it isn't one.
        let section: String?
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        try FreeText.types.flatMap { try candidates(of: $0, in: context) }
    }

    private static func candidates<M: HoldsFreeText>(of type: M.Type, in context: ModelContext) throws -> [Candidate] {
        try context.fetch(FetchDescriptor<M>()).compactMap { record in
            guard !FreeText.mask(record, write: false).isEmpty else { return nil }
            // The names are shown in the list: never with the number they may hold.
            let (name, section) = names(of: record)
            let shown = PaymentCardNumbers.redact(name)
            return Candidate(ref: RecordRef(record), name: shown,
                             section: section.map { PaymentCardNumbers.redact($0) }.flatMap { $0 == shown ? nil : $0 })
        }
    }

    /// What the list calls a record, and the section it belongs to.
    private static func names(of record: any HoldsFreeText) -> (String, String?) {
        switch record {
        case let asset as Asset: (asset.name, nil)
        case let obligation as Obligation: (obligation.title, obligation.asset?.name)
        case let entry as HistoryEntry: (entry.title, entry.asset?.name)
        case let item as ServiceItem: (item.name, item.entry?.asset?.name)
        case let reading as MeasurementLog: (reading.name, reading.asset?.name)
        case let document as Attachment: (document.title ?? document.fileName, document.asset?.name)
        case let provider as Provider: (provider.name, nil)
        case let template as CategoryTemplate: (template.name, nil)
        default: ("", nil)
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { candidate in
            let message: String
            if let section = candidate.section {
                message = String(localized: "La \(section), „\(candidate.name)” păstrează un număr de card întreg. Păstrez doar ultimele patru cifre?",
                                 comment: "Repair: a whole bank card number kept in a record's text (a visit, a deadline, a document) under a section.")
            } else {
                message = String(localized: "„\(candidate.name)” păstrează un număr de card întreg. Păstrez doar ultimele patru cifre?",
                                 comment: "Repair: a whole bank card number kept in a section's, a firm's or a category's text.")
            }
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.ref.type):\(candidate.ref.key)",
                step: Self.id,
                message: message,
                subject: .cardNumbers(candidate.ref)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        for finding in findings {
            guard case .cardNumbers(let ref) = finding.subject,
                  let record = UndoableRecords.find(ref, in: context) as? any HoldsFreeText else { continue }
            FreeText.mask(record, write: true)
        }
    }
}
