import SwiftData
import SwiftUI

/// What a note is for: a record of Istoric's own note, or a new dated note on a section (a plant,
/// whose category takes notes instead of visits, `VisitKind.note`); and the toast to show again
/// when the sheet closes without saving (a chore's "Gata", whose "Anulează" still works then).
struct HistoryNoteRequest: Identifiable {
    enum Target: Hashable {
        /// The note of a record already in Istoric.
        case entry(UUID)
        /// A new record of its own, a dated note, in this section's Istoric.
        case newNote(assetID: UUID)
    }

    let target: Target
    var restoring: DSToast?
    var id: Target { target }

    init(entryID: UUID, restoring: DSToast? = nil) {
        self.target = .entry(entryID)
        self.restoring = restoring
    }

    init(newNoteOn assetID: UUID) {
        self.target = .newNote(assetID: assetID)
    }
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
            .dsSheet(item: $request, onDismiss: {
                toast = saved ?? restoring
                saved = nil
                restoring = nil
            }) { request in
                HistoryNoteSheet(target: request.target) { result in
                    saved = result
                    restoring = nil
                    self.request = nil
                }
                .presentationDetents([.medium, .large])
            }
    }
}

/// "Adaugă o notă": the note of one record in Istoric, from a chore's toast right after its
/// "Gata", or from the record's page, saved through `HistoryActions.setNote`; or a dated note of
/// its own on a section whose category takes notes (a plant), saved through
/// `HistoryActions.addNote`. One note path; either is one step the toast takes back.
struct HistoryNoteSheet: View {
    let target: HistoryNoteRequest.Target
    /// The toast for what was saved; nil when nothing changed.
    let onSave: (DSToast?) -> Void

    @Environment(\.modelContext) private var context
    @Query private var matches: [HistoryEntry]
    @Query private var sections: [Asset]
    @State private var text = ""
    @State private var original = ""
    @State private var day = Date()
    @State private var didStart = false
    @State private var errorMessage: String?
    @State private var exampleQuestion: ExampleSectionQuestion?

    init(target: HistoryNoteRequest.Target, onSave: @escaping (DSToast?) -> Void) {
        self.target = target
        self.onSave = onSave
        // The one record or section it is for; the other query looks for an id nothing has.
        let entryID: UUID = if case .entry(let id) = target { id } else { UUID() }
        let assetID: UUID = if case .newNote(let id) = target { id } else { UUID() }
        _matches = Query(filter: #Predicate<HistoryEntry> { $0.id == entryID })
        _sections = Query(filter: #Predicate<Asset> { $0.id == assetID })
    }

    private var entry: HistoryEntry? { matches.first }
    private var section: Asset? { sections.first }
    private var isNew: Bool { if case .newNote = target { true } else { false } }
    /// What the note is written on is still there.
    private var canSave: Bool { isNew ? section != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : entry != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if let entry {
                        Text(verbatim: "\(entry.title) · \(DosarFormat.longDay(entry.occurredAt))")
                            .dsFont(.subheadline, numeric: true)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    } else if let section {
                        Text(verbatim: section.name)
                            .dsFont(.subheadline)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            DSTextField("Notă", text: $text, kind: .longText, prompt: "Ce ai făcut sau ce ai observat.")
                            if isNew {
                                DatePicker(selection: $day, in: ...Date.now, displayedComponents: .date) {
                                    Text("Data").dsFont(.headline)
                                }
                                .frame(minHeight: DS.Control.minimumHitTarget)
                            }
                        }
                    }
                }
                .padding(DS.Space.m)
                .dsReadableWidth()
            }
            .background(DS.Palette.background)
            .dsPinnedAction {
                DSPrimaryButton("Salvează", systemImage: "checkmark") { save() }
                    .disabled(!canSave)
            } note: {
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                } else if !isNew, entry == nil, didStart {
                    DSNotice(.warning, title: "Nu mai e în istoric", message: "Poate a fost anulat sau șters între timp.")
                } else if isNew, section == nil, didStart {
                    DSNotice(.warning, title: "Secțiunea nu mai există", message: "Poate a fost ștearsă. Închide și alege alta.")
                }
            }
            .navigationTitle(original.isEmpty ? Text("Adaugă o notă") : Text("Schimbă nota"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: text != original)
            .examplePrompt($exampleQuestion) { save() }
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
        if isNew {
            addNote()
            return
        }
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

    /// A new dated note in the section's Istoric.
    private func addNote() {
        guard let section else { return }
        do {
            let note = try HistoryActions(context: context).addNote(on: section, text, occurredAt: day)
            onSave(.undo(LocalizedStringResource("Am păstrat nota.", comment: "Toast after saving a record's note."), receipt: note.receipt))
        } catch let question as ExampleSectionQuestion {
            exampleQuestion = question
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}
