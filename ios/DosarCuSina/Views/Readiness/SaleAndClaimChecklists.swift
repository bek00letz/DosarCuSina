import SwiftUI

/// "Vinzi mașina": what the buyer asks for, the money to settle first and what to cancel
/// after, for one car.
struct SaleChecklistView: View {
    let assetID: UUID
    let assets: [ReadinessAsset]

    @Environment(\.calendar) private var calendar
    @State private var ticked: Set<String> = []
    @State private var request: ReadinessAction?
    @State private var toast: DSToast?

    var body: some View {
        let result = ReadinessEngine.checklist(.sellingVehicle(assetId: assetID), assets: assets,
                                               today: CalendarDay(Date(), calendar: calendar), calendar: calendar)
        ReadinessPage {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if let car = assets.first(where: { $0.id == assetID }) {
                        Text(verbatim: car.name)
                            .dsFont(.title)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ReadinessSummaryLine(checklist: result)
                }
            }
            ReadinessGroupsView(groups: result.groups, ticked: $ticked) { request = $0 }
        }
        .readinessActions($request, toast: $toast)
        .dsToast($toast)
    }
}

/// "Ai avut o daună": the policy to call, with its number to copy and its claims phone to
/// call, then what to photograph and the papers to have at hand. A car with RCA and CASCO,
/// or a home with PAD and an optional policy, asks which one first.
struct ClaimChecklistView: View {
    let assetID: UUID
    let assets: [ReadinessAsset]

    @Environment(\.calendar) private var calendar
    @State private var chosenPolicy: String?
    @State private var ticked: Set<String> = []
    @State private var request: ReadinessAction?
    @State private var toast: DSToast?

    var body: some View {
        let result = ReadinessEngine.checklist(.insuranceClaim(assetId: assetID, blueprintKey: chosenPolicy), assets: assets,
                                               today: CalendarDay(Date(), calendar: calendar), calendar: calendar)
        ReadinessPage {
            if result.policyOptions.isEmpty {
                DSEmptyState(
                    "Nicio asigurare în dosar",
                    systemImage: "exclamationmark.shield",
                    message: "Adaugă polița pe pagina secțiunii și aici găsești numărul și telefonul de daune."
                )
            } else {
                if result.policyOptions.count > 1 {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader("Ce asigurare folosești")
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                ForEach(result.policyOptions) { option in
                                    DSCheckRow(
                                        title: Text(verbatim: option.title),
                                        subtitle: option.whenToUse.map { Text(verbatim: $0) },
                                        isOn: result.policy?.blueprintKey == option.blueprintKey
                                    ) {
                                        chosenPolicy = option.blueprintKey
                                    }
                                }
                            }
                        }
                    }
                }
                if let policy = result.policy {
                    PolicyCallCard(policy: policy, showsWhen: result.policyOptions.count == 1,
                                   isSensitive: assets.first { $0.id == assetID }?.isSensitive ?? false)
                }
                ReadinessGroupsView(groups: result.groups, ticked: $ticked) { request = $0 }
            }
        }
        .dsAnimation(value: chosenPolicy)
        .readinessActions($request, toast: $toast)
        .dsToast($toast)
    }
}

/// The policy a claim goes to: who insures it, its number to copy and its claims line to
/// call, with the one thing to remember (call before repairing anything).
private struct PolicyCallCard: View {
    let policy: ReadinessPolicy
    /// Says when this policy applies, when there was no choice above to say it.
    let showsWhen: Bool
    /// From a section behind Face ID: a copied number stays on this phone, for a minute.
    let isSensitive: Bool

    var body: some View {
        DSPocketCard(policy.title) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let insurer = policy.insurer {
                    Text(verbatim: insurer)
                        .dsFont(.headline)
                }
                if showsWhen, let when = policy.whenToUse {
                    Text(verbatim: when)
                        .dsFont(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let phone = policy.claimsPhone {
                    if policy.insurer != nil || showsWhen { DSRowSeparator() }
                    DSActionValueRow(title: Text("Telefon pentru daune"), value: phone, action: .call)
                }
                if let number = policy.policyNumber {
                    DSRowSeparator()
                    DSActionValueRow(title: Text("Număr poliță"), value: number, action: .copy, copies: isSensitive ? .personal : .ordinary)
                }
                // The insured person's class, read from them: the insurer may ask for it.
                if let ownerClass = policy.policyholderClass {
                    DSRowSeparator()
                    DSReadOnlyValueRow(label: Text("Clasa proprietarului", comment: "Policy page: the bonus-malus class of the person the RCA insures."),
                                       value: Text(verbatim: ownerClass))
                }
                Text("Sună cât mai repede, înainte să repari ceva.", comment: "Claim: call the insurer before any repair.")
                    .dsFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.xxs)
            }
        }
    }
}
