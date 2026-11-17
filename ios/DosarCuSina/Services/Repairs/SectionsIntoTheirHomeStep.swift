import Foundation
import SwiftData

// MARK: - Plants kept on their own before they could stand in a home

/// Before catalog 17 a plant couldn't be filed under a home, so every plant stands on its own; a
/// category of one's own that now says what it belongs to ("Ține de…": a home, a car, a person)
/// has its sections on their own too. A section of a category that goes under the household's
/// only section of the part it may belong to by itself (`CategoryBehavior.goesUnderTheOnlyOne`),
/// standing on its own, is offered to move under that one, where its page lists it; it stays in
/// its category's box. It asks, because it changes where the section is listed. With several
/// nothing is guessed: one note says to move them with "Mută la…". With none, there is nothing
/// to offer. Examples are left as they are. Its words are the part's (`BelongingWording`).
/// Nothing was saved wrongly, so its findings are suggestions (`isSuggestion`): one calm note in
/// Urmează's "Din timp", never the repair list or its prompt. Its id and the answers kept by it stay.
struct SectionsIntoTheirHomeStep: DataRepairStep {
    static let id = DataRepairStepID.sectionsIntoTheirHome
    var title: String { String(localized: "Ce ține de altă secțiune", comment: "Repair group: sections (plants, a category of one's own) that can be filed under the household's only home, car or person.") }
    var isSuggestion: Bool { true }
    var applyTitle: String { String(localized: "Mută", comment: "Applies a suggestion that files a section (a plant) under the household's home.") }

    /// A category whose sections go under the only home, its sections on their own and the
    /// homes they could go under.
    struct Candidates {
        let category: CategoryTemplate
        let sections: [Asset]
        let parents: [Asset]
    }

    static func candidates(in context: ModelContext) throws -> [Candidates] {
        let categories = try TemplateStore.templatesByKey(in: context).values
            .filter { $0.behavior.goesUnderTheOnlyOne && $0.behavior.mayBelongTo != nil }
            .sorted { $0.key < $1.key }
        let assets = try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)]))
        return categories.compactMap { category -> Candidates? in
            let sections = assets.filter { $0.templateKey == category.key && $0.parent == nil && !$0.isExample && !$0.isDeleted }
            guard !sections.isEmpty else { return nil }
            let parents = AssetActions.possibleParents(for: category.behavior, in: context)
            return parents.isEmpty ? nil : Candidates(category: category, sections: sections, parents: parents)
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).flatMap { found -> [DataRepairFinding] in
            let role = found.category.behavior.mayBelongTo ?? .home
            guard found.parents.count == 1, let home = found.parents.first else {
                // Several homes: which one is the person's to say.
                return [DataRepairFinding(
                    id: "\(Self.id.rawValue):\(found.category.key):several",
                    step: Self.id,
                    message: BelongingWording.severalNote(role, category: found.category.name),
                    subject: .intoHome(assetID: nil, homeID: nil),
                    isFixable: false
                )]
            }
            return found.sections.map { section in
                DataRepairFinding(
                    id: "\(Self.id.rawValue):\(section.id.uuidString):\(home.id.uuidString)",
                    step: Self.id,
                    message: BelongingWording.moveSuggestion(role, section: section.name, parent: home.name, category: found.category.name),
                    subject: .intoHome(assetID: section.id, homeID: home.id)
                )
            }
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> UUID? in
            guard case .intoHome(let id?, _) = finding.subject else { return nil }
            return id
        })
        // Checked again: still on its own, and the home still the only one.
        for found in try Self.candidates(in: context) {
            guard found.parents.count == 1, let home = found.parents.first else { continue }
            for section in found.sections where approved.contains(section.id) && AssetActions.canFile(section, under: home) {
                section.parent = home
            }
        }
    }
}
