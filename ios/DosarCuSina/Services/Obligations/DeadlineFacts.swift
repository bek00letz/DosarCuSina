import Foundation

/// The facts a deadline's page puts at hand: its own insurer, policy number and claims
/// phone, read through its blueprint's fact roles (`BlueprintFacts`). A car's CASCO page
/// shows the CASCO policy, never the RCA's, and a deadline whose blueprint names no facts
/// shows none but its own reference.
public struct DeadlineFacts: Hashable, Sendable {
    public var insurer: String?
    public var policyNumber: String?
    public var claimsPhone: String?

    public init(insurer: String? = nil, policyNumber: String? = nil, claimsPhone: String? = nil) {
        self.insurer = insurer
        self.policyNumber = policyNumber
        self.claimsPhone = claimsPhone
    }

    /// The facts of the deadline made from `blueprintKey`, read from the section's
    /// `values` with `template`'s roles. The deadline's own reference (a policy number
    /// typed on it) wins over the section's field.
    public static func of(blueprintKey: String?, in template: TemplateDefinition?, values: FieldValues, reference: String?) -> DeadlineFacts {
        let facts = blueprintKey.flatMap { key in template?.blueprints.first { $0.key == key }?.facts }
        func value(_ role: BlueprintFactRole) -> String? {
            facts?.field(for: role).flatMap { values[$0]?.textValue }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let reference = reference.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return DeadlineFacts(insurer: value(.insurer), policyNumber: reference ?? value(.policyNumber), claimsPhone: value(.claimsPhone))
    }

    /// The facts of `obligation`, from its section.
    @MainActor
    public static func of(_ obligation: Obligation, template: TemplateDefinition?) -> DeadlineFacts {
        of(blueprintKey: obligation.blueprintKey, in: template, values: obligation.asset?.values ?? FieldValues(), reference: obligation.reference)
    }
}
