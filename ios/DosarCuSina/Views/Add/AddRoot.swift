import SwiftUI

/// The Adaugă tab. Placeholder until the intake screens land; the shell
/// depends only on this type's name and initializer.
struct AddRoot: View {
    var body: some View {
        DSEmptyState("Adaugă", systemImage: "plus", message: "În curând")
    }
}

/// Records a visit (service, repair, vet) with many parts or jobs at once,
/// for the given asset. Presented from a section's Istoric pocket.
struct AddVisitFlow: View {
    let assetID: UUID

    var body: some View {
        DSEmptyState("Am fost la service", systemImage: "wrench.and.screwdriver", message: "În curând")
    }
}
