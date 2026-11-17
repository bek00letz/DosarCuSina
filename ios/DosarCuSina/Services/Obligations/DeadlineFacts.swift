import Foundation

/// The facts a deadline's page puts at hand: its own insurer, policy number, claims phone and
/// insured sum, read through its blueprint's fact roles (`BlueprintFacts`). A car's CASCO page
/// shows the CASCO policy, never the RCA's, and a deadline whose blueprint names no facts
/// shows none but its own reference.
public struct DeadlineFacts: Hashable, Sendable {
    public var insurer: String?
    public var policyNumber: String?
    public var claimsPhone: String?
    /// Who the policy insures, as a household member's name (`Policyholders`).
    public var policyholder: String?
    /// The sum the policy insures for (a home's PAD and optional policy, a car's CASCO).
    public var insuredSum: Money?

    public init(insurer: String? = nil, policyNumber: String? = nil, claimsPhone: String? = nil, policyholder: String? = nil,
                insuredSum: Money? = nil) {
        self.insurer = insurer
        self.policyNumber = policyNumber
        self.claimsPhone = claimsPhone
        self.policyholder = policyholder
        self.insuredSum = insuredSum
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
        let insuredSum = facts?.field(for: .insuredSum).flatMap { values[$0]?.moneyValue }.flatMap { $0.amount > 0 ? $0 : nil }
        return DeadlineFacts(insurer: value(.insurer), policyNumber: reference ?? value(.policyNumber), claimsPhone: value(.claimsPhone),
                             policyholder: value(.policyholder), insuredSum: insuredSum)
    }

    /// The facts of `obligation`, from its section.
    @MainActor
    public static func of(_ obligation: Obligation, template: TemplateDefinition?) -> DeadlineFacts {
        of(blueprintKey: obligation.blueprintKey, in: template, values: obligation.asset?.values ?? FieldValues(), reference: obligation.reference)
    }
}
