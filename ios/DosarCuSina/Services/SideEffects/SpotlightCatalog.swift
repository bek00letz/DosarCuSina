import Foundation
import SwiftData

/// One thing the iPhone's search (Spotlight) shows of the binder: a section, a
/// deadline or a document. Only a title and a short line, never field values,
/// notes or text read off a document.
public struct SpotlightEntry: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case section, deadline, document
    }

    public let kind: Kind
    /// Where a tap on the result opens.
    public let route: AppRoute
    public let title: String
    /// The line under the title: the category, the due day, the section.
    public let detail: String?
    /// Words that find it without being shown (the section a deadline belongs to).
    public let keywords: [String]

    public init(kind: Kind, route: AppRoute, title: String, detail: String?, keywords: [String] = []) {
        self.kind = kind
        self.route = route
        self.title = title
        self.detail = detail
        self.keywords = keywords
    }

    /// Stable for the record's lifetime: its own `dosarcusina://` link, so a result
    /// opens through `DeepLink` like any other link.
    public var identifier: String { DeepLink.url(for: route).absoluteString }

    /// Changes when what Spotlight shows changes, and only then.
    public var fingerprint: String {
        let parts = [kind.rawValue, title, detail ?? ""] + keywords
        return Hashing.sha256(Data(parts.joined(separator: "\u{1F}").utf8))
    }

    /// The place a Spotlight result opens, from the identifier it was indexed with.
    public static func route(forIdentifier identifier: String) -> AppRoute? {
        URL(string: identifier).flatMap(DeepLink.route(from:))
    }
}

/// What the iPhone's search may show, decided once, by the rules of `SearchPrivacy`:
/// - section names, deadlines ("RCA – VW Golf", "10 ianuarie 2027") and document titles;
/// - nothing from a category behind Face ID, whether or not it is open now, titles included;
/// - nothing from the examples (deadlines come from `ObligationSnapshot.fetchForOutside`,
///   the one list of what may leave the app);
/// - no CNP-shaped number, sealed value, or value the category keeps out of search
///   (a document number) inside a title, and never the text read off a document;
/// - no closed one-off deadline and no archived document: a result is something current.
public enum SpotlightCatalog {
    @MainActor
    public static func entries(
        obligations: [ObligationSnapshot],
        in context: ModelContext,
        locale: Locale = .dosarDefault
    ) throws -> [SpotlightEntry] {
        let templates = try TemplateStore.templatesByKey(in: context)
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let isLocked: (Asset?) -> Bool = { asset in asset.flatMap { templates[$0.templateKey]?.isSensitive } ?? false }
        let withheld = Dictionary(
            assets.map { ($0.id, SearchPrivacy.withheldValues(of: $0, definition: templates[$0.templateKey]?.definition)) },
            uniquingKeysWith: { first, _ in first }
        )
        var entries: [SpotlightEntry] = []

        for asset in assets where SearchPrivacy.mayShowOutside(isLocked: isLocked(asset), isExample: asset.isExample) {
            guard let title = SearchPrivacy.outsideText(asset.name, withholding: withheld[asset.id] ?? []) else { continue }
            let category = templates[asset.templateKey]?.name
            entries.append(SpotlightEntry(kind: .section, route: .asset(asset.id), title: title, detail: category,
                                          keywords: category.map { [$0] } ?? []))
        }

        for obligation in obligations where obligation.status == .active || obligation.status == .paused {
            guard SearchPrivacy.mayShowOutside(isLocked: obligation.isSensitive, isExample: obligation.isExample) else { continue }
            let hidden = obligation.assetId.flatMap { withheld[$0] } ?? []
            guard let name = SearchPrivacy.outsideText(obligation.title, withholding: hidden) else { continue }
            let section = SearchPrivacy.outsideText(obligation.assetName, withholding: hidden)
            let title = section.map { deadlineTitle(name, section: $0) } ?? name
            let due = DosarFormat.longDay(obligation.dueDay, locale: locale)
            let detail = obligation.status == .paused
                ? String(localized: "Pe pauză · \(due)", comment: "Spotlight: a paused deadline's line, e.g. 'Pe pauză · 10 ianuarie 2027'.")
                : due
            entries.append(SpotlightEntry(kind: .deadline, route: .obligation(obligation.id), title: title, detail: detail,
                                          keywords: section.map { [$0] } ?? []))
        }

        let attachments = try context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { !$0.isArchived && !$0.isExample }))
        for attachment in attachments {
            let section = SearchIndexBuilder.section(of: attachment)
            guard SearchPrivacy.mayShowOutside(isLocked: isLocked(section), isExample: attachment.isExample || section?.isExample == true) else { continue }
            let hidden = section.flatMap { withheld[$0.id] } ?? []
            guard let title = SearchPrivacy.outsideText(attachment.displayTitle, withholding: hidden) else { continue }
            let sectionName = SearchPrivacy.outsideText(section?.name, withholding: hidden)
            entries.append(SpotlightEntry(kind: .document, route: .document(attachment.id), title: title, detail: sectionName,
                                          keywords: sectionName.map { [$0] } ?? []))
        }
        return entries
    }

    /// "RCA – VW Golf"; a title that already names its section stays as it is.
    static func deadlineTitle(_ title: String, section: String) -> String {
        guard !RomanianText.fold(title).contains(RomanianText.fold(section)) else { return title }
        return String(localized: "\(title) – \(section)", comment: "Spotlight: a deadline and its section, e.g. 'RCA – VW Golf'.")
    }
}
