import Foundation
import Testing
@testable import DosarCuSina

/// Abonamente in `docs/COPY_MATRIX.md`: what each service a subscription can be says (its name,
/// the group it is listed under, the codes its edit form and the review ask for, with their
/// lines), the groups in their order, the billing cycles and what a missing bill's note says for
/// each. All of it read from the declarations (`ServiceKind.Service`, `SubscriptionGroup`,
/// `SubscriptionCode`, `BillingCycle`, `AttentionModel.missingTitle`), never written here.
extension CopyMatrixTests {
    /// The words every subscription shares.
    static var subscriptionSharedRows: [(String, String)] {
        let definition = BuiltInTemplates.subscription
        let group = definition.field(SubscriptionFields.group)
        let cycles = BillingCycle.options.map(\.key)
        return [
            ("The groups of Abonamente, in order", SubscriptionGroup.allCases.map(\.label).joined(separator: " · ")),
            ("Moving one to another group", [group?.label, group?.footnote].compactMap { $0 }.joined(separator: " — ")),
            ("„\(definition.field(SubscriptionFields.cycle)?.label ?? "")”", BillingCycle.options.map(\.label).joined(separator: " · ")),
            ("A bill that hasn't come, by cycle", cycles.map { AttentionModel.missingTitle(from: "ENGIE", cycle: BillingCycle.interval($0)) }
                .joined(separator: " / ")),
        ]
    }

    /// What one service says.
    static func subscriptionServiceRows(_ service: ServiceKind.Service) -> [(String, String)] {
        let codes = service.codes.map { code in code.footnote.map { "\(code.label) („\($0)”)" } ?? code.label }
        return [
            ("Its group", service.group.label),
            ("Its codes (edit form, review)", codes.isEmpty ? "None" : codes.joined(separator: " · ")),
            ("Where a new one goes", service.isTiedToHome ? "Under the home it supplies" : "On its own, in Abonamente"),
        ]
    }

    static func subscriptionsSection() -> String {
        var out = "## Abonamente by service\n\nWhat a subscription says by what it is (`ServiceKind.Service`): the group it is "
            + "listed under, which the person can change in its edit form; the codes its papers are identified by, the only "
            + "ones its edit form shows and the review offers (`SubscriptionCode`). A subscription whose service isn't "
            + "chosen yet is asked „\(ServiceKind.codes(of: nil).map(\.label).joined(separator: "” and „"))”.\n\n"
            + "### What every subscription shares\n\n" + table(subscriptionSharedRows) + "\n"
        for service in ServiceKind.services {
            out += "\n### \(service.label) (`\(service.key)`)\n\n" + table(subscriptionServiceRows(service)) + "\n"
        }
        return out
    }
}

@MainActor
@Suite("Copy matrix: subscriptions by service")
struct SubscriptionCopyRulesTests {
    @Test("Every service has a group and words for every code it asks, and no code another service's name")
    func everyServiceIsWorded() {
        for service in ServiceKind.services {
            for (place, words) in CopyMatrixTests.subscriptionServiceRows(service) {
                #expect(!words.isEmpty && !words.contains("„”"), "\(service.key): \(place)")
            }
        }
        for (place, words) in CopyMatrixTests.subscriptionSharedRows {
            #expect(!words.isEmpty && !words.contains("„”"), "\(place)")
        }
        // A telecom service is never asked for a utility's consumption point.
        for service in ServiceKind.services where service.group != .utilities {
            #expect(!service.codes.contains { $0.family == .consumptionPoint }, "\(service.key)")
        }
    }
}
