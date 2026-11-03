import SwiftUI

/// "Ce s-a făcut" in the review: the lines read off a bill, each one tappable to
/// correct its text or amount, or to remove it, plus adding a line and removing
/// them all. Big rows, no swipe-only actions.
struct CaptureLineItemsEditor: View {
    @Binding var lines: [CaptureLineItem]
    /// The currency new lines start with.
    let currency: String

    private struct Editing: Identifiable {
        let id = UUID()
        /// The line being edited, or nil for a new one.
        let index: Int?
    }

    @State private var editing: Editing?
    @State private var isConfirmingRemoveAll = false

    @ViewBuilder private var listActions: some View {
        Button { editing = Editing(index: nil) } label: {
            DSValueActionLabel(title: "Adaugă un rând", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        if lines.count > 1 {
            Button(role: .destructive) { isConfirmingRemoveAll = true } label: {
                DSValueActionLabel(title: "Elimină toate", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Ce s-a făcut", comment: "Review: the lines of a bill.").dsFont(.footnote)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index > 0 { DSRowSeparator() }
                Button { editing = Editing(index: index) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Text(verbatim: line.description)
                            .dsFont(.body)
                            .foregroundStyle(DS.Palette.label)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let amount = line.amount {
                            Text(verbatim: CaptureMapping.money(amount).formattedCompact())
                                .dsFont(.body, numeric: true)
                                .foregroundStyle(DS.Palette.label)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityHint(Text("Corectează sau elimină rândul", comment: "VoiceOver hint on a bill line in the review."))
            }
            DSAdaptiveStack(spacing: DS.Space.xs) { listActions }
            .padding(.top, DS.Space.xs)
        }
        .sheet(item: $editing) { editing in
            CaptureLineItemSheet(
                line: editing.index.map { lines[$0] },
                currency: currency,
                onSave: { saved in
                    if let index = editing.index { lines[index] = saved } else { lines.append(saved) }
                },
                onRemove: editing.index.map { index in { lines.remove(at: index) } }
            )
        }
        .confirmationDialog(
            Text("Elimini toate rândurile?", comment: "Confirms removing every bill line in the review."),
            isPresented: $isConfirmingRemoveAll, titleVisibility: .visible
        ) {
            Button(role: .destructive) { lines.removeAll() } label: { Text("Elimină toate", comment: "Removes every bill line.") }
            Button(role: .cancel) {} label: { Text("Renunță", comment: "Cancels a choice.") }
        } message: {
            Text("Actul se salvează la fel, doar fără ele.", comment: "Explains that removing the lines keeps the document.")
        }
    }
}

/// One bill line: what was done and what it cost.
private struct CaptureLineItemSheet: View {
    let line: CaptureLineItem?
    let currency: String
    let onSave: (CaptureLineItem) -> Void
    let onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var amount: Decimal?
    @State private var currencyCode = Money.defaultCurrency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    DSTextField("Ce s-a făcut", text: $text, kind: .longText, prompt: "de exemplu Plăcuțe frână față")
                    DSMoneyField("Cât a costat", amount: $amount, currencyCode: $currencyCode)
                    if let onRemove {
                        DSSecondaryButton("Elimină rândul", systemImage: "trash", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .navigationTitle(line == nil ? Text("Rând nou", comment: "Title when adding a bill line.") : Text("Rândul de pe factură", comment: "Title when editing a bill line."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("Gata", comment: "Saves the bill line.") }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = line?.description ?? ""
            amount = line?.amount?.amount
            currencyCode = line?.amount?.currencyCode ?? currency
        }
    }

    private func save() {
        let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // The part it names is worked out again from the corrected text.
        let edited = CaptureLineItem(
            description: description,
            quantity: line?.quantity,
            amount: amount.map { CaptureMoney(amount: $0, currencyCode: currencyCode) },
            componentKey: CatalogComponentResolver().componentKey(for: description)
        )
        onSave(edited)
        dismiss()
    }
}
