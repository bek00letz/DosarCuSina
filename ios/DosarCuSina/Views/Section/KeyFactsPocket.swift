import SwiftUI
import SwiftData

/// Date importante: the template's key facts and the person's own rows.
/// Tap a row to copy it, tap a phone number to call. Own rows are added and
/// edited right here.
struct KeyFactsPocket: View {
    let asset: Asset
    let definition: TemplateDefinition
    @Binding var toast: DSToast?
    @Binding var error: UserFacingError?

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    /// The custom row being edited, or a new one.
    @State private var editing: CustomFact?
    @State private var copiedCount = 0

    var body: some View {
        let rows = AssetFacts.factRows(asset.values, customFacts: asset.customFacts, template: definition)
        DSPocketCard(SectionPocket.keyFacts.title) {
            if rows.isEmpty && editing == nil {
                PocketEmptyLine(text: String(localized: "Pune aici ce cauți des: numărul poliței, codul de client, parola de la Wi-Fi.", comment: "Empty Date importante pocket."))
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { DSRowSeparator() }
                if let editing, editing.id.uuidString == row.id {
                    CustomFactEditor(fact: editing, onSave: save, onDelete: { remove(editing) }, onCancel: { self.editing = nil })
                } else {
                    factRow(row)
                }
            }
            if let editing, !asset.customFacts.contains(where: { $0.id == editing.id }) {
                if !rows.isEmpty { DSRowSeparator() }
                CustomFactEditor(fact: editing, onSave: save, onDelete: { self.editing = nil }, onCancel: { self.editing = nil })
            }
        } footer: {
            if editing == nil {
                DSSecondaryButton("Adaugă un rând", systemImage: "plus") {
                    editing = CustomFact(label: "", value: "")
                }
                .padding(.top, DS.Space.s)
            }
        }
        .sensoryFeedback(.success, trigger: copiedCount)
    }

    private func factRow(_ row: FactRow) -> some View {
        HStack(spacing: DS.Space.xs) {
            Button {
                activate(row)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.label)
                            .dsFont(.subheadline)
                        Text(verbatim: row.text)
                            .dsFont(.headline, numeric: true)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: row.isCallable ? "phone.fill" : "doc.on.doc")
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, DS.Space.xs)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.dsPressable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(row.isCallable
                ? Text("Atinge ca să suni.", comment: "VoiceOver hint of a phone fact row.")
                : Text("Atinge ca să copiezi.", comment: "VoiceOver hint of a fact row."))
            .contextMenu {
                Button {
                    copy(row)
                } label: {
                    Label { Text("Copiază", comment: "Copy a value.") } icon: { Image(systemName: "doc.on.doc") }
                }
                if row.isCallable, let url = PhoneLinks.call(row.text) {
                    Button { openURL(url) } label: {
                        Label { Text("Sună", comment: "Call a phone number.") } icon: { Image(systemName: "phone") }
                    }
                }
            }

            if row.isCustom, let fact = asset.customFacts.first(where: { $0.id.uuidString == row.id }) {
                Button {
                    editing = fact
                } label: {
                    Text("Editează", comment: "Edits one of the person's own rows.")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func activate(_ row: FactRow) {
        if row.isCallable, let url = PhoneLinks.call(row.text) {
            openURL(url)
        } else {
            copy(row)
        }
    }

    private func copy(_ row: FactRow) {
        Clipboard.copy(row.text)
        copiedCount += 1
        toast = DSToast(title: LocalizedStringResource("Am copiat „\(row.label)”", comment: "Toast after copying a fact."), systemImage: "doc.on.doc.fill", actionTitle: nil, feedback: nil)
    }

    private func save(_ fact: CustomFact) {
        var facts = asset.customFacts
        if let index = facts.firstIndex(where: { $0.id == fact.id }) {
            facts[index] = fact
        } else {
            facts.append(fact)
        }
        apply(facts)
        editing = nil
    }

    private func remove(_ fact: CustomFact) {
        let previous = asset.customFacts
        apply(previous.filter { $0.id != fact.id })
        editing = nil
        toast = .undo(LocalizedStringResource("Am șters „\(fact.label)”", comment: "Toast after deleting a custom fact row.")) {
            apply(previous)
        }
    }

    private func apply(_ facts: [CustomFact]) {
        do {
            try AssetActions(context: context).setCustomFacts(asset, facts)
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// Inline editor for one of the person's own rows. Saves on "Gata".
private struct CustomFactEditor: View {
    @State private var label: String
    @State private var value: String
    @State private var isSensitive: Bool
    private let original: CustomFact
    let onSave: (CustomFact) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(fact: CustomFact, onSave: @escaping (CustomFact) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        original = fact
        _label = State(initialValue: fact.label)
        _value = State(initialValue: fact.value)
        _isSensitive = State(initialValue: fact.isSensitive)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    private var isEmpty: Bool {
        label.trimmingCharacters(in: .whitespaces).isEmpty && value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSTextField("Ce este", text: $label, prompt: "Cod alarmă, Wi-Fi, număr contract")
            DSTextField("Valoarea", text: $value)
            DSToggleField("Nu arăta în căutare", isOn: $isSensitive, footnote: "Pentru coduri și parole.")
            HStack(spacing: DS.Space.s) {
                Button(role: .destructive, action: onDelete) {
                    Text("Șterge rândul", comment: "Deletes a custom fact row.")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button {
                    if isEmpty {
                        onCancel()
                    } else {
                        var fact = original
                        fact.label = label.trimmingCharacters(in: .whitespaces)
                        fact.value = value.trimmingCharacters(in: .whitespaces)
                        fact.isSensitive = isSensitive
                        onSave(fact)
                    }
                } label: {
                    Text("Gata", comment: "Closes an editor and keeps what was typed.")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .transition(.opacity)
    }
}
