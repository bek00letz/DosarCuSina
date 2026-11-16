import SwiftUI

/// What grouping a category's boxes offers, in the same words wherever it is offered: a box's
/// press-and-hold menu (and VoiceOver's actions) and Setări › Ecranul Dosar.
extension BoxGrouping {
    /// The offer that leads to this choice: "Grupează într-o singură cutie", "Arată fiecare separat".
    var offerTitle: Text {
        switch self {
        case .grouped: Text("Grupează într-o singură cutie", comment: "Menu item: show all of a category's sections (the cars) in one box on the binder.")
        case .separate: Text("Arată fiecare separat", comment: "Menu item: give each of a category's sections its own box on the binder again.")
        }
    }

    var offerSymbol: String {
        switch self {
        case .grouped: "square.stack.fill"
        case .separate: "square.grid.2x2.fill"
        }
    }
}

/// A menu item that makes a category's sections share one box, or have one each again.
struct BoxGroupingButton: View {
    let offer: BoxGrouping
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { offer.offerTitle } icon: { Image(systemName: offer.offerSymbol) }
        }
    }
}
