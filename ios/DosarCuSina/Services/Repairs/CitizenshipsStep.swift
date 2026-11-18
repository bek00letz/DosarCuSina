import Foundation
import SwiftData

// MARK: - A second citizenship the documents show

/// An earlier version kept one citizenship on a person: the first one a filed document
/// printed, and never a second. A person with two (a Romanian identity card and a Moldovan
/// passport) kept only the first, and the trip check then read them as a citizen of a country
/// outside the EU. Since then a person keeps every citizenship their documents print
/// (`Citizenship.kept(in:)`, a list).
///
/// The single value becomes a list by itself (`ChoiceKeysStep`: only how it is stored). This
/// step finds a person whose kept list leaves out a citizenship one of their own personal
/// documents prints, and asks before adding it, as every correction does: it changes what the
/// person's page says. A person with no citizenship kept is read from their documents already,
/// and a citizenship the person took away is never offered again once its finding is left as it
/// is („Lasă așa”, remembered by its id).
struct CitizenshipsStep: DataRepairStep {
    static let id = DataRepairStepID.citizenships
    var title: String { String(localized: "Cetățenii", comment: "Repair group: a person's second citizenship, which an earlier version didn't keep.") }

    struct Candidate {
        let person: Asset
        /// The citizenships their documents print that the list leaves out.
        let missing: [String]

        var key: String { "\(person.id.uuidString):\(missing.joined(separator: ","))" }
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])).compactMap { person in
            guard !person.isExample, templates.plays(.holder, person.templateKey) else { return nil }
            let kept = Citizenship.kept(in: person.values)
            guard !kept.isEmpty else { return nil }
            let documents = (person.children ?? []).filter { templates.plays(.personalDocument, $0.templateKey) }.map(\.values)
            let missing = Citizenship.read(fromDocuments: documents).filter { !kept.contains($0) }
            return missing.isEmpty ? nil : Candidate(person: person, missing: missing)
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { candidate in
            let countries = candidate.missing.compactMap(Citizenship.label(for:)).formatted(.list(type: .and).locale(.dosarDefault))
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.key)",
                step: Self.id,
                message: String(localized: "Actele din „\(candidate.person.name)” arată și cetățenia: \(countries). O păstrez lângă celelalte?",
                                comment: "Repair: a person's documents show a citizenship their page doesn't keep. The first argument is the person, the second the countries."),
                subject: .citizenships(personID: candidate.person.id, add: candidate.missing)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        var approved: [UUID: [String]] = [:]
        for finding in findings {
            guard case .citizenships(let id, let add) = finding.subject else { continue }
            approved[id, default: []] += add
        }
        // Checked again: only what is still missing, and only what was approved.
        for candidate in try Self.candidates(in: context) {
            guard let add = approved[candidate.person.id] else { continue }
            let adding = candidate.missing.filter(add.contains)
            guard !adding.isEmpty,
                  let values = Citizenship.keeping(Citizenship.kept(in: candidate.person.values) + adding, in: candidate.person.values) else { continue }
            candidate.person.values = values
        }
    }
}
