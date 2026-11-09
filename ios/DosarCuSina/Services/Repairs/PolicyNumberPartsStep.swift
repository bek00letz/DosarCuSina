import Foundation
import SwiftData

// MARK: - Policy numbers kept without their number

/// A policy number kept with only its series ("RO/00/X00/XX"), as earlier versions could
/// keep when one reader read the series and another the number into two fields. Any
/// deadline whose facts name a policy number is checked (a car's RCA and CASCO, a home's
/// policies), by the one rule for values printed in parts (`CompositeValue.policy`).
///
/// When the policy filed on the section still has its read text, the rule reads the whole
/// value from it again and the repair offers it ("Corectează"). Otherwise the finding only
/// says to read the policy again: nothing is guessed. It asks, because it changes a value
/// the person sees.
struct PolicyNumberPartsStep: DataRepairStep {
    static let id = DataRepairStepID.policyNumberParts
    var title: String { String(localized: "Numere de poliță fără număr", comment: "Repair group: policy numbers kept with only their series.") }

    struct Candidate {
        let asset: Asset
        let field: String
        let blueprintTitle: String
        /// What is kept: the series alone.
        let kept: String
        /// The whole value the filed policy's text gives, when it gives one.
        let whole: String?

        var key: String { "\(asset.id.uuidString):\(field):\(kept):\(whole ?? "")" }
    }

    /// Whether `value` is a policy number missing its number: a series and nothing else.
    static func isMissingItsNumber(_ value: String) -> Bool {
        guard let parts = CompositeValue.policy.parts(in: value) else { return false }
        return parts.series != nil && parts.number == nil
    }

    /// The whole value of `kept` in a policy's read text: read by the rule as a whole
    /// (never a number alone, never two values that differ), with the same series.
    static func whole(of kept: String, in text: String) -> String? {
        guard let found = RomanianFieldExtractor.policyNumber(in: CaptureText(text)),
              found.quality >= .joinedFromTwoPlaces, found.parts.series != nil, found.parts.number != nil,
              CompositeValue.policy.agreement(kept, found.value) == found.value else { return nil }
        return found.value
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        var found: [Candidate] = []
        for asset in try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])) {
            guard !asset.isExample, let template = templates[asset.templateKey]?.definition else { continue }
            for blueprint in template.blueprints {
                guard let field = blueprint.facts?.policyNumber, let kept = asset.values[field]?.textValue,
                      isMissingItsNumber(kept), !found.contains(where: { $0.asset.id == asset.id && $0.field == field }) else { continue }
                // The policies filed on the section, this deadline's first, newest first.
                let policies = (asset.attachments ?? [])
                    .filter { $0.kind == .policy && !$0.isExample && $0.extractedText?.isEmpty == false }
                    .sorted { lhs, rhs in
                        let left = lhs.obligation?.blueprintKey == blueprint.key, right = rhs.obligation?.blueprintKey == blueprint.key
                        return left != right ? left : lhs.createdAt > rhs.createdAt
                    }
                let whole = policies.lazy.compactMap { $0.extractedText.flatMap { whole(of: kept, in: $0) } }.first
                found.append(Candidate(asset: asset, field: field, blueprintTitle: blueprint.title, kept: kept, whole: whole))
            }
        }
        return found
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { candidate in
            let message: String
            if let whole = candidate.whole {
                message = String(localized: "La \(candidate.asset.name), numărul poliței \(candidate.blueprintTitle) e doar seria „\(candidate.kept)”. Îl completez cu „\(whole)”, de pe polița din dosar?",
                                 comment: "Repair: a policy number kept with only its series, completed from the filed policy's text.")
            } else {
                message = String(localized: "La \(candidate.asset.name), numărul poliței \(candidate.blueprintTitle) e doar seria „\(candidate.kept)”, fără număr. Citește polița din nou sau scrie numărul în Editează.",
                                 comment: "Repair: a policy number kept with only its series, and no filed text to complete it from.")
            }
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.key)",
                step: Self.id,
                message: message,
                subject: .policyNumberParts(assetID: candidate.asset.id, field: candidate.field, to: candidate.whole),
                isFixable: candidate.whole != nil
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> String? in
            guard case .policyNumberParts(let id, let field, let to?) = finding.subject else { return nil }
            return "\(id.uuidString):\(field):\(to)"
        })
        for candidate in try Self.candidates(in: context) {
            guard let whole = candidate.whole, approved.contains("\(candidate.asset.id.uuidString):\(candidate.field):\(whole)") else { continue }
            var values = candidate.asset.values
            values[candidate.field] = .text(whole)
            candidate.asset.values = values
        }
    }
}
