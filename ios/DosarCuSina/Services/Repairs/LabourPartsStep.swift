import Foundation
import SwiftData

// MARK: - Labour kept as a part

/// Before labour had a rule of its own (`LabourLine`, its words in `CaptureLexicon.labourWords`),
/// an invoice's labour line („Manoperă”, „Mână de lucru”) was saved as a part of one's own
/// (`custom.<slug>`), so it was listed with the parts in Istoric, in search under „Piese și
/// lucrări”, with its kilometres and date, and counted when a part was last done. A visit saved
/// today keeps it as its labour (`HouseholdMutations.addItems`). This finds every line of a
/// visit that is a part of one's own and whose name is labour, and keeps it as the visit's
/// labour: no part, its cost the labour's. What the visit cost stays the same. It asks first, as
/// every correction does: it changes what Istoric lists.
struct LabourPartsStep: DataRepairStep {
    static let id = DataRepairStepID.labourParts
    var title: String { String(localized: "Manoperă", comment: "Repair group: labour lines an earlier version kept as parts of a visit.") }

    /// Lines kept as a part of one's own whose words are labour. A catalog part is never one.
    static func candidates(in context: ModelContext) throws -> [ServiceItem] {
        try context.fetch(FetchDescriptor<ServiceItem>(sortBy: [SortDescriptor(\.name)])).filter { item in
            guard !item.isExample, item.entry != nil,
                  let key = item.componentKey, key.hasPrefix(ComponentCatalog.customKeyPrefix) else { return false }
            return LabourLine.matches(item.name)
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { item in
            let entry = item.entry
            let place = entry?.asset.map { "„\($0.name)”" } ?? "„\(entry?.title ?? item.name)”"
            let day = entry.map { DosarFormat.day($0.occurredAt, calendar: scan.calendar) } ?? ""
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(item.id.uuidString)",
                step: Self.id,
                message: String(localized: "La \(place), rândul „\(item.name)” din vizita din \(day) e trecut ca piesă. Îl păstrez ca manoperă a vizitei? Costul vizitei rămâne același.",
                                comment: "Repair: a visit's labour line kept as a part by an earlier version. The first argument is the section, the second the line's name, the third the visit's day."),
                subject: .labourPart(itemID: item.id)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> UUID? in
            guard case .labourPart(let id) = finding.subject else { return nil }
            return id
        })
        // Checked again: a line renamed or changed since the list was made stays.
        for item in try Self.candidates(in: context) where approved.contains(item.id) {
            Self.keepAsLabour(item)
        }
    }

    /// The line as a visit saved today keeps its labour: no part, its cost the labour's.
    static func keepAsLabour(_ item: ServiceItem) {
        item.componentKey = nil
        item.group = nil
        if item.laborCostAmount == nil, let cost = item.costAmount {
            item.laborCostAmount = cost
            item.costAmount = nil
        }
    }
}
