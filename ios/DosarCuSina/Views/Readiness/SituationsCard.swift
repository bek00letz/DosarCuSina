import SwiftUI

/// "Situații" on a section's page: the situations its category offers
/// (`ReadinessSituation.offered`), each opening its checklist. Nothing when it offers none.
struct SituationsCard: View {
    let assetID: UUID
    let definition: TemplateDefinition

    var body: some View {
        let situations = ReadinessSituation.offered(by: definition)
        if !situations.isEmpty {
            DSPocketCard(String(localized: "Situații", comment: "Group on a section's page: checklists for situations such as a trip or an accident.")) {
                ForEach(Array(situations.enumerated()), id: \.element) { index, situation in
                    if index > 0 { DSRowSeparator() }
                    if let route = situation.route(for: assetID) {
                        SituationLink(situation: situation, route: route)
                    }
                }
            }
        }
    }
}

/// One situation as a row: its symbol, its name, what the checklist does, and a chevron.
/// In a `List`, the list draws the chevron and the pressed state itself (`inList`).
struct SituationLink: View {
    let situation: ReadinessSituation
    let route: AppRoute
    var inList = false

    var body: some View {
        if inList {
            NavigationLink(value: route) { row(showsChevron: false) }
        } else {
            NavigationLink(value: route) { row(showsChevron: true) }
                .buttonStyle(.dsPressable)
        }
    }

    private func row(showsChevron: Bool) -> some View {
        DSListRow(
            title: Text(verbatim: situation.title),
            subtitle: Text(verbatim: situation.summary),
            systemImage: situation.symbol,
            showsChevron: showsChevron
        ) { EmptyView() }
    }
}
