import SwiftData
import SwiftUI

/// Removing the examples, the same step wherever it is offered: on the binder, where the
/// examples are, and in Setări › Exemple. One undoable step (`ExampleDataService.removeExamples`);
/// the toast takes it back, so it asks nothing first.
@MainActor
enum ExampleRemoval {
    /// Whether the binder offers "Șterge exemplele": while any example is in it.
    static func isOffered(assets: [Asset]) -> Bool {
        assets.contains(where: \.isExample)
    }

    /// Removes every example and says so, with "Anulează" bringing every example back; what the
    /// person added to an example stays theirs, and the toast says that too.
    static func remove(in context: ModelContext) throws -> DSToast {
        let removed = try ExampleDataService(context: context).removeExamples()
        return .undoDeletion(removed.value.isEmpty
            ? LocalizedStringResource("Am șters exemplele.", comment: "Toast after removing the examples.")
            : LocalizedStringResource("Am șters exemplele. Ce ai pus tu în ele a rămas al tău.",
                                      comment: "Toast after removing the examples, some kept because the person added to them."),
            receipt: removed.receipt)
    }
}

/// At the end of the binder while examples are in it: one calm way to remove them, where they are.
struct BinderExamplesNotice: View {
    let remove: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Text("Ce e marcat „Exemplu” e doar ca să vezi cum arată un dosar plin.", comment: "Note at the end of the binder while examples are in it.")
                .dsFont(.footnote)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            DSSecondaryButton("Șterge exemplele", systemImage: "trash", action: remove)
                .accessibilityHint(Text("Pleacă doar ce e marcat „Exemplu”. Poți anula.", comment: "VoiceOver hint of the binder's button that removes the examples."))
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.l)
    }
}
