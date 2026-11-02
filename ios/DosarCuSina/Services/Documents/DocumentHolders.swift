import Foundation
import SwiftData

/// The documents of one household member, for the Acte box.
public struct HolderGroup: Identifiable {
    /// The member they belong to; nil for documents not filed under anyone yet.
    public var holder: Asset?
    /// Personal documents (ID card, passport, licence…), soonest expiry first.
    public var documents: [Asset]

    public var id: String { holder?.id.uuidString ?? "unassigned" }
    public var title: String { holder?.name ?? String(localized: "Fără titular", comment: "Acte group for documents not filed under a person") }
}

/// Personal documents grouped by the household member they are filed under.
/// Members are a name only; no personal identification number is stored on them.
@MainActor
public enum DocumentHolders {
    public static func groups(in context: ModelContext, includeExamples: Bool = true, calendar: Calendar = .current) throws -> [HolderGroup] {
        let documentsKey = BuiltInTemplates.Key.documents
        let memberKey = BuiltInTemplates.Key.member
        let documents = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == documentsKey }))
            .filter { includeExamples || !$0.isExample }
        let members = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == memberKey }, sortBy: [SortDescriptor(\.createdAt)]))
            .filter { includeExamples || !$0.isExample }

        func expiry(_ asset: Asset) -> CalendarDay {
            asset.value("document.expiry")?.dateValue ?? CalendarDay(year: 9999, month: 12, day: 31)
        }
        var groups = members.map { member in
            HolderGroup(holder: member, documents: documents.filter { $0.parent?.id == member.id }.sorted { expiry($0) < expiry($1) })
        }
        let unassigned = documents.filter { document in !members.contains { $0.id == document.parent?.id } }
        if !unassigned.isEmpty {
            groups.append(HolderGroup(holder: nil, documents: unassigned.sorted { expiry($0) < expiry($1) }))
        }
        return groups
    }
}
