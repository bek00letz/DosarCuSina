import SwiftData
import SwiftUI

/// Which record of Istoric a note is for, and the toast to show again when the sheet closes
/// without saving (a chore's "Gata", whose "Anulează" still works then).
struct HistoryNoteRequest: Identifiable {
    let entryID: UUID
    var restoring: DSToast?
    var id: UUID { entryID }
}

extension View {
    /// Presents the note sheet for `request`: saving shows its toast, with "Anulează" for the
    /// note; closing it without saving shows `request.restoring` again.
    func historyNoteSheet(_ request: Binding<HistoryNoteRequest?>, toast: Binding<DSToast?>) -> some View {
        modifier(HistoryNoteSheetModifier(request: request, toast: toast))
    }
}

private struct HistoryNoteSheetModifier: ViewModifier {
    @Binding var request: HistoryNoteRequest?
    @Binding var toast: DSToast?
    /// What the sheet saved, shown once it has gone.
    @State private var saved: DSToast?
    @State private var restoring: DSToast?

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { _, _ in
                if let request { restoring = request.restoring }
            }
            .sheet(item: $request, onDismiss: {
                toast = saved ?? restoring
                saved = nil
                restoring = nil
            }) { request in
                HistoryNoteSheet(entryID: request.entryID) { result in
                    saved = result
                    restoring = nil
                    self.request = nil
                }
                .presentationDetents([.medium, .large])
            }
    }
}

/// "Adaugă o notă": the note of one record in Istoric, from a chore's toast right after its
/// "Gata", or from the record's page. Saved through `HistoryActions.setNote`, one step the
/// toast takes back.
struct HistoryNoteSheet: View {
    let entryID: UUID
    /// The toast for what was saved; nil when nothing changed.
    let onSave: (DSToast?) -> Void

    @Environment(\.modelContext) private var context
    @Query private var matches: [HistoryEntry]
    @State private var text = ""
    @State private var original = ""
    @State private var didStart = false
    @State private var errorMessage: String?

    init(entryID: UUID, onSave: @escaping (DSToast?) -> Void) {
        self.entryID = entryID
        self.onSave = onSave
        _matches = Query(filter: #Predicate<HistoryEntry> { $0.id == entryID })
    }

    private var entry: HistoryEntry? { matches.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if let entry {
                        Text(verbatim: "\(entry.title) · \(DosarFormat.longDay(entry.occurredAt))")
                            .dsFont(.subheadline, numeric: true)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    DSCard {
                        DSTextField("Notă", text: $text, kind: .longText, prompt: "Ce ai făcut sau ce ai observat.")
                    }
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .dsPinnedAction {
                DSPrimaryButton("Salvează", systemImage: "checkmark") { save() }
                    .disabled(entry == nil)
            } note: {
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                } else if entry == nil, didStart {
                    DSNotice(.warning, title: "Nu mai e în istoric", message: "Poate a fost anulat sau șters între timp.")
                }
            }
            .navigationTitle(original.isEmpty ? Text("Adaugă o notă") : Text("Schimbă nota"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: text != original)
            .onAppear(perform: start)
        }
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        original = entry?.note ?? ""
        text = original
    }

    private func save() {
        guard let entry else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != original.trimmingCharacters(in: .whitespacesAndNewlines) else {
            onSave(nil)
            return
        }
        do {
            let receipt = try HistoryActions(context: context).setNote(entry, trimmed)
            let message: LocalizedStringResource = trimmed.isEmpty
                ? LocalizedStringResource("Am șters nota.", comment: "Toast after clearing a record's note.")
                : LocalizedStringResource("Am păstrat nota.", comment: "Toast after saving a record's note.")
            onSave(.undo(message, receipt: receipt))
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}
