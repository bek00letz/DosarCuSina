import SwiftUI
import SwiftData

/// Date importante: the template's key facts and the person's own rows.
/// Tap a row to copy it, tap a phone number to call. Own rows are added and
/// edited right here; a code (an alarm, a Wi-Fi password) is kept as a secret
/// row, sealed like a PIN and shown or copied only after Face ID.
struct KeyFactsPocket: View {
    let asset: Asset
    let definition: TemplateDefinition
    @Binding var toast: DSToast?
    @Binding var error: UserFacingError?

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]

    init(asset: Asset, definition: TemplateDefinition, toast: Binding<DSToast?>, error: Binding<UserFacingError?>) {
        self.asset = asset
        self.definition = definition
        _toast = toast
        _error = error
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    /// Anything copied from a locked section, or a sensitive row, is personal.
    private func clipboardKind(for row: FactRow) -> Clipboard.Kind {
        row.isSensitive || templates.first?.isSensitive == true ? .personal : .ordinary
    }
    /// The custom row being edited, or a new one.
    @State private var editing: CustomFact?
    @State private var copiedCount = 0

    var body: some View {
        let rows = AssetFacts.factRows(asset.values, customFacts: asset.customFacts, template: definition)
        DSPocketCard(SectionPocket.keyFacts.title) {
            if rows.isEmpty && editing == nil {
                PocketEmptyLine(text: String(localized: "Pune aici ce cauți des: numărul poliței, codul de client. Un cod sau o parolă rămân ascunse, ca un PIN.", comment: "Empty Date importante pocket."))
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

    @ViewBuilder
    private func factRow(_ row: FactRow) -> some View {
        if row.isSecret {
            secretRow(row)
        } else {
            plainRow(row)
        }
    }

    /// A code: masked, shown or copied only after a fresh Face ID.
    private func secretRow(_ row: FactRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSecretValueRow(title: Text(verbatim: row.label), isSet: row.sealed != nil) {
                guard let sealed = row.sealed else { return .notAuthenticated }
                return await SecretReveal(vault: vault).open(
                    sealed,
                    reason: String(localized: "Arată \(row.label)", comment: "Face ID reason when showing a secret code.")
                )
            }
            editButton(row)
        }
    }

    @ViewBuilder
    private func editButton(_ row: FactRow) -> some View {
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

    private func plainRow(_ row: FactRow) -> some View {
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

            editButton(row)
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
        Clipboard.copy(row.text, clipboardKind(for: row))
        copiedCount += 1
        toast = DSToast(title: LocalizedStringResource("Am copiat „\(row.label)”", comment: "Toast after copying a fact."), systemImage: "doc.on.doc.fill", actionTitle: nil, feedback: nil)
    }

    private func save(_ fact: CustomFact) {
        var facts = asset.customFacts
        // The rows as the editor started from them: the row as it opened, the others as they are.
        var start = facts
        if let index = facts.firstIndex(where: { $0.id == fact.id }) {
            facts[index] = fact
            if let opened = editing, opened.id == fact.id { start[index] = opened }
        } else {
            facts.append(fact)
        }
        apply(facts, startedFrom: start)
        editing = nil
    }

    private func remove(_ fact: CustomFact) {
        editing = nil
        guard let receipt = apply(asset.customFacts.filter { $0.id != fact.id }) else { return }
        toast = .undo(LocalizedStringResource("Am șters „\(fact.label)”", comment: "Toast after deleting a custom fact row."), receipt: receipt)
    }

    @discardableResult
    private func apply(_ facts: [CustomFact], startedFrom start: [CustomFact]? = nil) -> UndoReceipt? {
        do {
            return try AssetActions(context: context).setCustomFacts(asset, facts, startedFrom: start)
        } catch {
            self.error = UserFacingError(error)
            return nil
        }
    }
}

/// Inline editor for one of the person's own rows. Saves on "Gata". A row
/// whose label names a code ("Parolă Wi-Fi", "Cod alarmă") starts as a secret
/// until the person sets the switch themselves.
private struct CustomFactEditor: View {
    @State private var label: String
    @State private var value: String
    @State private var isSensitive: Bool
    @State private var isSecret: Bool
    /// The person set "Cod secret" themselves, so the label no longer decides it.
    @State private var choseSecret: Bool
    private let original: CustomFact
    let onSave: (CustomFact) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(fact: CustomFact, onSave: @escaping (CustomFact) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        original = fact
        _label = State(initialValue: fact.label)
        _value = State(initialValue: fact.value)
        _isSensitive = State(initialValue: fact.isSensitive)
        _isSecret = State(initialValue: fact.isSecret)
        // A row already saved keeps what it is; a new one follows its label.
        _choseSecret = State(initialValue: !fact.label.isEmpty || !fact.value.isEmpty)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    private var isEmpty: Bool {
        label.trimmingCharacters(in: .whitespaces).isEmpty && value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSTextField("Ce este", text: $label, prompt: "Număr contract, cod alarmă, parolă Wi-Fi")
            if isSecret {
                DSSecretField("Codul", value: $value, footnote: "Îl vezi sau îl copiezi doar după Face ID.", isPIN: false)
            } else {
                DSTextField("Valoarea", text: $value)
            }
            DSToggleField("Cod secret", isOn: Binding(get: { isSecret }, set: setSecret), footnote: "Ascuns ca un PIN. Nu intră în căutare și nici în copia de siguranță.")
            if !isSecret {
                DSToggleField("Nu arăta în căutare", isOn: $isSensitive)
            }
            HStack(spacing: DS.Space.s) {
                DSSecondaryButton(Text("Șterge rândul", comment: "Deletes a custom fact row."), role: .destructive, action: onDelete)
                DSPrimaryButton(Text("Gata", comment: "Closes an editor and keeps what was typed.")) {
                    if isEmpty {
                        onCancel()
                    } else {
                        var fact = original
                        fact.label = label.trimmingCharacters(in: .whitespaces)
                        fact.value = isSecret ? value : value.trimmingCharacters(in: .whitespaces)
                        fact.isSecret = isSecret
                        fact.isSensitive = isSensitive || isSecret
                        onSave(fact)
                    }
                }
            }
        }
        .padding(.vertical, DS.Space.xs)
        .transition(.opacity)
        .onChange(of: label) { _, newLabel in
            guard !choseSecret else { return }
            let looksLikeCode = CustomFact.looksLikeCode(newLabel)
            if looksLikeCode != isSecret { switchSecret(to: looksLikeCode) }
        }
    }

    private func setSecret(_ on: Bool) {
        choseSecret = true
        switchSecret(to: on)
    }

    /// A kept code is never turned back into plain text: switching off clears it, to be typed again.
    private func switchSecret(to on: Bool) {
        if !on, SecretSealer.isSealed(value) { value = "" }
        isSecret = on
    }
}
