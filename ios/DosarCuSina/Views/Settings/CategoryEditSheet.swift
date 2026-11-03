import SwiftUI
import SwiftData

/// Changing a category of the person's own later: its name, symbol and what it keeps, with
/// the same questions as when it was made (`CustomCategoryForm`). Saving goes through
/// `TemplateStore.editCustom` as one step the toast can take back; when a switch touches
/// deadlines already running (a service turned off, or back on), it asks first.
struct CategoryEditSheet: View {
    let template: CategoryTemplate
    /// Called with the receipt of the saved change, for the toast's "Anulează".
    let onSaved: (UndoReceipt) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomSectionDraft
    private let original: CustomSectionDraft
    @State private var reveals = false
    @State private var question: TemplateStore.SwitchEffects?
    @State private var isConfirmingDelete = false
    @State private var error: UserFacingError?

    init(template: CategoryTemplate, onSaved: @escaping (UndoReceipt) -> Void) {
        self.template = template
        self.onSaved = onSaved
        var draft = CustomSectionDraft()
        draft.name = template.name
        draft.symbol = template.symbol
        draft.switches = CategorySwitches(reading: template.definition)
        self.original = draft
        _draft = State(initialValue: draft)
    }

    private var hasChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    CustomCategoryForm(
                        draft: $draft,
                        footnote: Text("Ce oprești nu se șterge: actele, abonamentele cu facturile lor și kilometrii sau orele rămân și apar din nou când pornești la loc.", comment: "Footer of a category's switches: turning one off keeps what was kept.")
                    )
                    DSSecondaryButton("Șterge categoria", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, reveals)
            .navigationTitle(Text(verbatim: template.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button { attemptSave() } label: { Text("Salvează", comment: "Saves the changes to a category.") }
                        .disabled(!hasChanges)
                }
            }
        }
        .dsDiscardGuard(hasChanges: hasChanges)
        .confirmationDialog(questionTitle, isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
                            titleVisibility: .visible, presenting: question) { effects in
            Button { save(changingDeadlines: true) } label: { changeTitle(effects) }
            Button { save(changingDeadlines: false) } label: { keepTitle(effects) }
            Button(role: .cancel) {} label: { Text("Înapoi", comment: "Closes the question and keeps editing.") }
        } message: { effects in
            Text(verbatim: questionMessage(effects))
        }
        .confirmationDialog(Text("Ștergi categoria „\(template.name)”?", comment: "Asks before deleting a category of one's own."),
                            isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive) { delete() } label: { Text("Șterge", comment: "Deletes a category of one's own.") }
        } message: {
            Text("Se poate șterge doar o categorie fără secțiuni. Mută-le sau șterge-le mai întâi.", comment: "Explains when a category can be deleted.")
        }
        .userErrorAlert($error)
    }

    // MARK: Saving

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func attemptSave() {
        guard !trimmedName.isEmpty else { reveals = true; return }
        do {
            let effects = try TemplateStore(context: context).effects(of: draft.switches, on: template)
            if effects.isEmpty { save(changingDeadlines: false) } else { question = effects }
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func save(changingDeadlines: Bool) {
        do {
            let receipt = try TemplateStore(context: context).editCustom(template, name: trimmedName, symbol: draft.symbol,
                                                                          switches: draft.switches, changingDeadlines: changingDeadlines)
            dismiss()
            onSaved(receipt)
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func delete() {
        do {
            try TemplateStore(context: context).delete(template)
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }

    // MARK: The question about deadlines

    private var questionTitle: Text {
        Text("Și termenele de revizie?", comment: "Asks what to do with service deadlines a category change touches.")
    }

    private func questionMessage(_ effects: TemplateStore.SwitchEffects) -> String {
        var lines: [String] = []
        if !effects.pausing.isEmpty {
            let names = Self.places(effects.pausing)
            lines.append(String(localized: "Revizia e încă programată la \(names). O pun pe pauză? O pornești din nou oricând.", comment: "A service turned off: its running deadlines, by section."))
        }
        if !effects.resuming.isEmpty {
            let names = Self.places(effects.resuming)
            lines.append(String(localized: "Revizia e pe pauză la \(names). O pornesc din nou?", comment: "A service turned back on: its paused deadlines, by section."))
        }
        return lines.joined(separator: "\n\n")
    }

    private func changeTitle(_ effects: TemplateStore.SwitchEffects) -> Text {
        switch (effects.pausing.isEmpty, effects.resuming.isEmpty) {
        case (false, true): Text("Pune pe pauză", comment: "Pauses the service deadlines a category change turned off.")
        case (true, false): Text("Pornește din nou", comment: "Resumes the paused service deadlines a category change turned back on.")
        default: Text("Da, schimbă-le", comment: "Pauses and resumes the service deadlines a category change touches.")
        }
    }

    private func keepTitle(_ effects: TemplateStore.SwitchEffects) -> Text {
        if effects.pausing.isEmpty {
            Text("Lasă-le pe pauză", comment: "Saves the category change and leaves its paused deadlines paused.")
        } else {
            Text("Lasă-le cum sunt", comment: "Saves the category change and leaves its deadlines as they are.")
        }
    }

    /// The sections the deadlines belong to: "Barca și Șalupa".
    private static func places(_ obligations: [Obligation]) -> String {
        let names = obligations.compactMap { $0.asset?.name }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.formatted(.list(type: .and).locale(.dosarDefault))
    }
}
