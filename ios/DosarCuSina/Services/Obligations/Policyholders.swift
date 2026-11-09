import Foundation
import SwiftData

/// Who a policy insures, among the household's people, and the bonus-malus class they
/// carry. The class follows the person's own driving history (Norma ASF nr. 20/2017), so
/// it is kept on the person (`MemberFields.bonusMalus`), never on a car; a policy's page
/// reads it from the person its facts name (`BlueprintFactRole.policyholder`), so it is
/// never stored twice. One rule for capture's filing, the deadline page and the claim
/// screen.
enum Policyholders {
    /// A person of the household: their name, the CNPs printed on their documents, and
    /// their class (a `BonusMalusClass` key).
    struct Person: Hashable, Sendable {
        let id: UUID
        let name: String
        let personalNumbers: Set<String>
        let bonusMalus: String?
    }

    /// The person a policy insures: by its CNP when one was read (the only person whose
    /// documents carry it), else by name, with the rule that files a holder's documents
    /// (`CaptureMapping.matchingMember`). Nil when no one matches, or more than one.
    static func person(named name: String?, personalNumber: String?, among people: [Person]) -> Person? {
        if let personalNumber, RomanianFieldExtractor.isValidCNP(personalNumber) {
            let byNumber = people.filter { $0.personalNumbers.contains(personalNumber) }
            if byNumber.count == 1 { return byNumber[0] }
        }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let id = CaptureMapping.matchingMember(holderSurname: nil, holderName: name, among: people.map { (id: $0.id, name: $0.name) })
        return id.flatMap { id in people.first { $0.id == id } }
    }

    /// The class of the person a policy's facts name, as printed ("B6"), or nil when the
    /// household doesn't know who they are or their class.
    static func bonusMalus(ofPolicyholder name: String?, among people: [Person]) -> String? {
        person(named: name, personalNumber: nil, among: people).flatMap { BonusMalusClass.label(for: $0.bonusMalus) }
    }

    /// The household's people: its members (the holder part), never examples, with the
    /// CNPs read on the documents filed under them.
    @MainActor
    static func people(in assets: [Asset], templates: [String: CategoryTemplate]) -> [Person] {
        assets.filter { !$0.isExample && templates.plays(.holder, $0.templateKey) }.map { member in
            let numbers = assets.filter { $0.parent?.id == member.id }.compactMap { $0.values[DocumentFields.personalNumber]?.textValue }
            return Person(id: member.id, name: member.name, personalNumbers: Set(numbers),
                          bonusMalus: member.values[MemberFields.bonusMalus]?.textValue)
        }
    }

    /// The same, from the readiness checks' snapshot.
    static func people(in assets: [ReadinessAsset]) -> [Person] {
        assets.filter { $0.role == .holder }.map { member in
            let numbers = assets.filter { $0.parentId == member.id }.compactMap { $0.values[DocumentFields.personalNumber]?.textValue }
            return Person(id: member.id, name: member.name, personalNumbers: Set(numbers),
                          bonusMalus: member.values[MemberFields.bonusMalus]?.textValue)
        }
    }

    /// The household's people, read from the database.
    @MainActor
    static func people(in context: ModelContext) -> [Person] {
        guard let templates = try? TemplateStore(context: context).templatesByKey(),
              let assets = try? context.fetch(FetchDescriptor<Asset>()) else { return [] }
        return people(in: assets, templates: templates)
    }
}
