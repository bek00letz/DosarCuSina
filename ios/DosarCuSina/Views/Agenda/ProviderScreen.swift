import SwiftUI
import SwiftData

/// One person or firm: call, message or copy the number; every job they did on
/// any section; and the household's own notes and rating, saved as you type.
struct ProviderScreen: View {
    let providerID: UUID
    @Query private var matches: [Provider]

    init(providerID: UUID) {
        self.providerID = providerID
        let id = providerID
        _matches = Query(filter: #Predicate<Provider> { $0.id == id })
    }

    var body: some View {
        if let provider = matches.first {
            ProviderContent(provider: provider)
        } else {
            MissingRecordView()
        }
    }
}

private struct ProviderContent: View {
    let provider: Provider

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(BiometricVaultManager.self) private var vault

    @State private var notes: String
    @State private var saveTask: Task<Void, Never>?
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var error: UserFacingError?
    @State private var toast: DSToast?

    init(provider: Provider) {
        self.provider = provider
        _notes = State(initialValue: provider.notes ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                contactActions
                opinion
                notesCard
                jobs
                sections
                DSSecondaryButton("Șterge din agendă", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background)
        .navigationTitle(Text(verbatim: provider.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isEditing = true } label: { Text("Editează", comment: "Toolbar button that edits a section's details.") }
            }
        }
        .sheet(isPresented: $isEditing) { ProviderEditSheet(provider: provider, linkTo: nil) }
        .confirmationDialog(Text("Ștergi „\(provider.name)” din agendă?", comment: "Delete confirmation for a provider."), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: delete) { Text("Șterge", comment: "Confirm deleting.") }
            Button(role: .cancel) {} label: { Text("Păstrează", comment: "Cancel a delete.") }
        } message: {
            Text("Lucrările rămân în istoric, doar fără numele lui.", comment: "Delete confirmation message for a provider.")
        }
        .onDisappear { flushNotes() }
        .dsToast($toast)
        .userErrorAlert($error)
    }

    // MARK: Parts

    private var header: some View {
        DSCard(padding: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(verbatim: provider.name)
                    .dsFont(.display)
                    .accessibilityAddTraits(.isHeader)
                if let trades = provider.tradeLine {
                    Text(verbatim: trades).dsFont(.headline).foregroundStyle(DS.Palette.secondaryLabel)
                }
                if let phone = provider.phone {
                    Text(verbatim: phone).dsFont(.body, numeric: true).textSelection(.enabled)
                }
                if let email = provider.email {
                    Text(verbatim: email).dsFont(.body).textSelection(.enabled)
                }
                if let address = provider.address {
                    Text(verbatim: address).dsFont(.subheadline).textSelection(.enabled)
                }
                if provider.isExample { DSExampleBadge() }
            }
        }
    }

    @ViewBuilder
    private var contactActions: some View {
        if let phone = provider.phone {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s)) : AnyLayout(HStackLayout(spacing: DS.Space.s))
            layout {
                DSPrimaryButton("Sună", systemImage: "phone.fill") {
                    if let url = PhoneLinks.call(phone) { openURL(url) }
                }
                DSSecondaryButton("Mesaj", systemImage: "message.fill") {
                    if let url = PhoneLinks.message(phone) { openURL(url) }
                }
                DSSecondaryButton("Copiază", systemImage: "doc.on.doc") {
                    Clipboard.copy(phone, .ordinary)
                    toast = DSToast(title: LocalizedStringResource("Am copiat numărul", comment: "Toast after copying a phone number."), systemImage: "doc.on.doc.fill", actionTitle: nil, feedback: .success)
                }
            }
        } else {
            DSNotice(.info, title: "Nu ai trecut un telefon", message: "Adaugă-l din Editează și îl suni de aici.")
        }
    }

    private var opinion: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Părerea ta")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSStarRating(rating: provider.rating) { rate($0) }
                    if (provider.historyEntries ?? []).contains(where: { $0.rating != nil }) {
                        Text("Stelele sunt media notelor date lucrărilor lui.", comment: "Footnote: provider stars come from job ratings.")
                            .dsFont(.footnote)
                    }
                    DSToggleField("Aș chema din nou", isOn: Binding(
                        get: { provider.wouldCallAgain == true },
                        set: { setWouldCallAgain($0) }
                    ))
                }
            }
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Note")
            DSTextField("Note", text: $notes, kind: .longText, prompt: "Program, prețuri, cum ajungi la el", footnote: "Se salvează pe măsură ce scrii.")
                .onChange(of: notes) { _, _ in scheduleNotesSave() }
        }
    }

    @ViewBuilder
    private var jobs: some View {
        let work = ProviderDirectory(context: context).work(by: provider)
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Ce a lucrat", count: work.isEmpty ? nil : work.count)
            DSCard {
                VStack(spacing: 0) {
                    if work.isEmpty {
                        PocketEmptyLine(text: String(localized: "Nicio lucrare notată încă.", comment: "Provider with no jobs."))
                    }
                    ForEach(Array(work.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { DSRowSeparator() }
                        if let asset = entry.asset, isHidden(asset) {
                            DSListRow(title: Text("O lucrare într-o secțiune protejată", comment: "A job hidden behind a lock."), subtitle: Text(verbatim: DosarFormat.day(entry.occurredAt))) { EmptyView() }
                        } else {
                            NavigationLink(value: AppRoute.historyEntry(entry.id)) {
                                HistoryEntryRow(entry: entry, showsAsset: true)
                            }
                            .buttonStyle(.dsPressable)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        let assets = (provider.assets ?? []).sorted { $0.name < $1.name }
        if !assets.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                DSSectionHeader("Are grijă de")
                DSCard {
                    VStack(spacing: 0) {
                        ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 { DSRowSeparator() }
                            NavigationLink(value: AppRoute.asset(asset.id)) {
                                DSListRow(title: Text(verbatim: asset.name), showsChevron: true) { EmptyView() }
                            }
                            .buttonStyle(.dsPressable)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func isHidden(_ asset: Asset) -> Bool {
        guard let template = try? TemplateStore(context: context).template(forKey: asset.templateKey) else { return false }
        return vault.isLocked(template)
    }

    private func rate(_ value: Int?) {
        run { try ProviderActions(context: context).setRating(provider, value) }
    }

    private func setWouldCallAgain(_ value: Bool) {
        run { try ProviderActions(context: context).setWouldCallAgain(provider, value) }
    }

    private func scheduleNotesSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flushNotes()
        }
    }

    private func flushNotes() {
        saveTask?.cancel()
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (provider.notes ?? "") else { return }
        var details = provider.details
        details.notes = trimmed
        run { try ProviderActions(context: context).update(provider, with: details) }
    }

    private func delete() {
        do {
            try ProviderActions(context: context).delete(provider)
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { self.error = UserFacingError(error) }
    }
}

extension Provider {
    var details: ProviderDetails {
        ProviderDetails(name: name, trades: trades, phone: phone, email: email, address: address, notes: notes, contactIdentifier: contactIdentifier)
    }
}

/// Adds or edits a provider. "Alege din agendă" fills the name and phone from
/// Contacts without asking for Contacts access; typing works just as well.
struct ProviderEditSheet: View {
    let provider: Provider?
    /// The section a new provider is added from; they are linked to it.
    let linkTo: Asset?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var contact: DSContactValue?
    @State private var name: String
    @State private var trade: ProviderTrade?
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var notes: String
    @State private var reveals = false
    @State private var error: UserFacingError?
    private let original: ProviderDetails

    init(provider: Provider?, linkTo: Asset?) {
        self.provider = provider
        self.linkTo = linkTo
        let details = provider?.details ?? ProviderDetails(name: "")
        original = details
        _name = State(initialValue: details.name)
        _trade = State(initialValue: details.trades.first.flatMap(ProviderTrade.init(rawValue:)))
        _phone = State(initialValue: details.phone ?? "")
        _email = State(initialValue: details.email ?? "")
        _address = State(initialValue: details.address ?? "")
        _notes = State(initialValue: details.notes ?? "")
        _contact = State(initialValue: nil)
    }

    private var draft: ProviderDetails {
        var trades = original.trades
        if let trade {
            if trades.isEmpty { trades = [trade.rawValue] } else { trades[0] = trade.rawValue }
        } else if !trades.isEmpty, ProviderTrade(rawValue: trades[0]) != nil {
            trades.removeFirst()
        }
        return ProviderDetails(name: name, trades: trades, phone: phone, email: email, address: address, notes: notes,
                               contactIdentifier: contact?.contactIdentifier ?? original.contactIdentifier)
    }

    private var hasChanges: Bool {
        draft.name != original.name || draft.trades != original.trades || phone != (original.phone ?? "") || email != (original.email ?? "")
            || address != (original.address ?? "") || notes != (original.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    DSContactField("Din agenda telefonului (opțional)", contact: $contact, footnote: "Aplicația vede doar persoana pe care o alegi.")
                        .onChange(of: contact) { _, picked in
                            guard let picked else { return }
                            name = picked.name
                            if let number = picked.phone { phone = number }
                            if let mail = picked.email { email = mail }
                        }
                    DSTextField("Nume", text: $name, prompt: "Service Exemplu SRL", isRequired: true)
                    DSChoiceField("Ce face", selection: $trade, options: ProviderTrade.allCases) { $0.title }
                    DSTextField("Telefon", text: $phone, kind: .phone)
                    DSTextField("E-mail", text: $email, kind: .email,
                                validator: { FieldEditor.validation(FieldFormatter.validate($0, as: .email)) })
                    DSTextField("Adresă", text: $address, kind: .address)
                    DSTextField("Note", text: $notes, kind: .longText, prompt: "Program, prețuri, cum ajungi la el")
                }
                .padding(DS.Space.m)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, reveals)
            .navigationTitle(provider == nil ? Text("Persoană nouă", comment: "Title when adding a provider.") : Text("Editează", comment: "Title of the edit sheet."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("Gata", comment: "Closes an editor and keeps what was typed.") }
                }
            }
            .userErrorAlert($error)
        }
        .dsDiscardGuard(hasChanges: hasChanges)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FieldFormatter.validate(email, as: .email).allowsSaving else {
            reveals = true
            return
        }
        do {
            let actions = ProviderActions(context: context)
            if let provider {
                try actions.update(provider, with: draft)
            } else {
                let created = try actions.create(
                    name: trimmed,
                    trades: trade.map { [$0] } ?? [],
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    address: address.isEmpty ? nil : address,
                    notes: notes.isEmpty ? nil : notes,
                    contactIdentifier: contact?.contactIdentifier,
                    linkedTo: linkTo.map { [$0] } ?? []
                )
                _ = created
            }
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}
