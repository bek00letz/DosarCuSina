import Foundation
import SwiftData

// MARK: - Plants kept on their own before they could stand in a home

/// Before catalog 17 a plant couldn't be filed under a home, so every plant stands on its own.
/// A section of a category that goes under the household's only home by itself
/// (`CategoryBehavior.goesUnderTheOnlyOne`, plants), standing on its own, is offered to move under
/// that home, where its page lists it; it stays in its category's box. It asks, because it
/// changes where the section is listed. With several homes nothing is guessed: one note says to
/// move them with "Mută la…". With none, there is nothing to offer. Examples are left as they are.
struct SectionsIntoTheirHomeStep: DataRepairStep {
    static let id = DataRepairStepID.sectionsIntoTheirHome
    var title: String { String(localized: "Ce stă într-o locuință", comment: "Repair group: plants that can be filed under the household's home.") }

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
            guard found.parents.count == 1, let home = found.parents.first else {
                // Several homes: which one is the person's to say.
                return [DataRepairFinding(
                    id: "\(Self.id.rawValue):\(found.category.key):several",
                    step: Self.id,
                    message: String(localized: "„\(found.category.name)” pot sta acum și într-o locuință. Ai mai multe, așa că le muți tu, din pagina fiecăreia, cu „Mută la…”.",
                                    comment: "Repair note: a category's sections (plants) can now be filed under a home; with several homes the person moves each with 'Mută la…'."),
                    subject: .intoHome(assetID: nil, homeID: nil),
                    isFixable: false
                )]
            }
            return found.sections.map { section in
                DataRepairFinding(
                    id: "\(Self.id.rawValue):\(section.id.uuidString):\(home.id.uuidString)",
                    step: Self.id,
                    message: String(localized: "Trec „\(section.name)” la „\(home.name)”? Apare pe pagina locuinței și rămâne în „\(found.category.name)”.",
                                    comment: "Repair: file a section standing on its own (a plant) under the household's only home; it stays in its category's box."),
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
