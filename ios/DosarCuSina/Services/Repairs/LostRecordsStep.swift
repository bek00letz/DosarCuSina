import Foundation
import SwiftData

// MARK: - Records whose section was deleted on another device

/// A deadline, a document, a record of history or a reading added to a section while another
/// device deleted it: the deletion arrives and the database lets go of the link (version 18),
/// so the record stays, its id still naming the section (`ParentLinks`). Once the binder has all
/// arrived and no copy of the section is here to go back to (`ParentLinks.rehome`), each is
/// offered here, to be kept in a section of its own, „Recuperate”, or left as it is.
///
/// The section's lock isn't known any more, so nothing of the record is named: the finding says
/// only what kind of record it is. „Recuperate” is a category of one's own with one key and one
/// section with one id on every device, so two devices that keep records there make one
/// (`RecordsMeet`); it is made locked while any section is locked here (`BinderLocks`). A part of
/// a record of history or a page of a document whose record was deleted is never offered: the
/// person deleted what it was part of.
struct LostRecordsStep: DataRepairStep {
    static let id = DataRepairStepID.lostRecords
    /// The category „Recuperate” and its one section, the same on every device.
    static let categoryKey = TemplateDefinition.customKeyPrefix + "recovered"
    static let sectionID = UUID(uuidString: "6F1C2B7E-5D4A-4E8B-9C3D-0A1B2C3D4E5F")!
    /// Its name, its symbol and the pockets it shows: what both apps make it with
    /// (`shared/catalog/ownCategories.json`, `recovered`).
    static var name: String {
        String(localized: "Recuperate", comment: "A section of one's own made for records whose section was deleted on another device.")
    }
    static let symbol = "tray.full"
    static let pockets: [SectionPocket] = [.upcoming, .documents, .history]

    var title: String { String(localized: "Rămase fără secțiune", comment: "Repair group: records whose section was deleted on another device.") }
    var applyTitle: String { String(localized: "Păstrează", comment: "Applies one repair: keep a record whose section was deleted on another device.") }

    /// One record left without its section.
    struct Lost: Hashable, Sendable {
        enum Kind: String, Hashable, Sendable { case deadline, document, history, reading }
        let kind: Kind
        let id: UUID
    }

    /// The records left without their section, none while the binder may still be arriving (the
    /// section, or its deletion of them, may be on its way).
    @MainActor
    static func lost(in context: ModelContext) throws -> [Lost] {
        guard CloudArrival.of(context.container).isWhole else { return [] }
        let loose = try ParentLinks.loose(in: context)
        let records = loose.obligations.map { Lost(kind: .deadline, id: $0.id) }
            + loose.attachments.map { Lost(kind: .document, id: $0.id) }
            + loose.history.map { Lost(kind: .history, id: $0.id) }
            + loose.readings.map { Lost(kind: .reading, id: $0.id) }
        return records.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.lost(in: scan.context).map { lost in
            DataRepairFinding(id: "\(Self.id.rawValue):\(lost.id.uuidString)", step: Self.id, message: Self.message(lost.kind),
                              subject: .lostRecord(lost))
        }
    }

    static func message(_ kind: Lost.Kind) -> String {
        switch kind {
        case .deadline:
            String(localized: "Un termen a rămas fără secțiune: secțiunea lui a fost ștearsă pe alt dispozitiv. Îl păstrez într-o secțiune nouă, „Recuperate”?",
                   comment: "Repair: a deadline whose section was deleted on another device.")
        case .document:
            String(localized: "Un document a rămas fără secțiune: secțiunea lui a fost ștearsă pe alt dispozitiv. Îl păstrez într-o secțiune nouă, „Recuperate”?",
                   comment: "Repair: a document whose section was deleted on another device.")
        case .history:
            String(localized: "O înregistrare din Istoric a rămas fără secțiune: secțiunea ei a fost ștearsă pe alt dispozitiv. O păstrez într-o secțiune nouă, „Recuperate”?",
                   comment: "Repair: a record of history (a visit, a repair, a purchase) whose section was deleted on another device.")
        case .reading:
            String(localized: "O citire de contor a rămas fără secțiune: secțiunea ei a fost ștearsă pe alt dispozitiv. O păstrez într-o secțiune nouă, „Recuperate”?",
                   comment: "Repair: a counter reading whose section was deleted on another device.")
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let still = Set(try Self.lost(in: context))
        let approved = findings.compactMap { finding -> Lost? in
            guard case .lostRecord(let lost) = finding.subject, still.contains(lost) else { return nil }
            return lost
        }
        guard !approved.isEmpty else { return }
        let section = try Self.section(in: context, calendar: calendar)
        for lost in approved {
            switch lost.kind {
            case .deadline: Obligation.find(lost.id.uuidString, in: context)?.asset = section
            case .document: Attachment.find(lost.id.uuidString, in: context)?.asset = section
            case .history: HistoryEntry.find(lost.id.uuidString, in: context)?.asset = section
            case .reading: MeasurementLog.find(lost.id.uuidString, in: context)?.asset = section
            }
        }
    }

    /// „Recuperate”'s section, made with its category the first time.
    @MainActor
    static func section(in context: ModelContext, calendar: Calendar) throws -> Asset {
        if let section = Asset.find(sectionID.uuidString, in: context), !section.isDeleted { return section }
        let store = TemplateStore(context: context)
        let template = try store.templatesByKey()[categoryKey]
            ?? store.createCustom(name: name, symbol: symbol, pockets: pockets,
                                  isSensitive: BinderLocks.read(in: context).anySectionLocked, key: categoryKey)
        let section = try AssetActions(context: context, calendar: calendar).create(name: name, template: template, values: FieldValues())
        section.id = sectionID
        return section
    }
}
