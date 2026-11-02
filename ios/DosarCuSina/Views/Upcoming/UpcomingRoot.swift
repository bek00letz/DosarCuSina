import SwiftUI

/// The Urmează tab. Placeholder until the intake and upcoming screens land;
/// the shell depends only on this type's name and initializer.
struct UpcomingRoot: View {
    var body: some View {
        DSEmptyState("Urmează", systemImage: "clock", message: "În curând")
    }
}

/// Reminder setup and details for one obligation, presented from anywhere.
struct ObligationScreen: View {
    let obligationID: UUID

    var body: some View {
        DSEmptyState("Termen", systemImage: "clock", message: "În curând")
    }
}
