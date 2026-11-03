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
    /// The documents of `category` (the household's personal documents when nil), grouped
    /// by the person each is filed under: whoever's category plays the `holder` part.
    public static func groups(in context: ModelContext, category: String? = nil, includeExamples: Bool = true, calendar: Calendar = .current) throws -> [HolderGroup] {
        let store = TemplateStore(context: context)
        let templates = try store.templatesByKey()
        guard let documentsKey = category ?? templates.key(withRole: .personalDocument) else { return [] }
        let documents = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == documentsKey }))
            .filter { includeExamples || !$0.isExample }
        let members = try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { templates.plays(.holder, $0.templateKey) && (includeExamples || !$0.isExample) }
        let expiryDefinition = templates[documentsKey]?.definition

        func expiry(_ asset: Asset) -> CalendarDay {
            expiryDefinition.flatMap { AssetFacts.expiry(asset.values, template: $0) } ?? CalendarDay(year: 9999, month: 12, day: 31)
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
