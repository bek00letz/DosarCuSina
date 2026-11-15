import SwiftUI

/// One action of a page's "Mai multe": its words, its symbol and what it does.
struct DSMoreAction: Identifiable {
    /// Stable within the page ("move").
    let id: String
    let title: Text
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void
}

/// The one rule for a page's extra actions: none shows nothing, one shows that action itself
/// with its own words, two or more go in a "Mai multe" menu. A menu never hides a single item.
enum DSMoreActionsLayout: Equatable {
    case nothing
    case direct
    case menu

    init(count: Int) {
        switch count {
        case ..<1: self = .nothing
        case 1: self = .direct
        default: self = .menu
        }
    }
}

/// A page's extra actions in its toolbar, by `DSMoreActionsLayout`: the document page's
/// "Mută la…" shows as itself; with more beside it, they share "Mai multe".
struct DSMoreActionsToolbar: ToolbarContent {
    let actions: [DSMoreAction]

    private var layout: DSMoreActionsLayout { DSMoreActionsLayout(count: actions.count) }

    var body: some ToolbarContent {
        if layout == .direct, let only = actions.first {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: only.role, action: only.action) { only.title }
            }
        }
        if layout == .menu {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(actions) { item in
                        Button(role: item.role, action: item.action) {
                            Label { item.title } icon: { Image(systemName: item.systemImage) }
                        }
                    }
                } label: {
                    Label { Text("Mai multe", comment: "Toolbar menu with more actions for a page.") } icon: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }
}
