import SwiftUI
import SwiftData

/// The full lists behind each pocket's "Vezi tot".
struct SectionListScreen: View {
    let route: SectionListRoute
    @Query private var matches: [Asset]

    init(route: SectionListRoute) {
        self.route = route
        let id: UUID
        switch route {
        case .obligations(let asset), .history(let asset), .people(let asset), .documents(let asset), .children(let asset, _):
            id = asset
        }
        _matches = Query(filter: #Predicate<Asset> { $0.id == id })
    }

    var body: some View {
        if let asset = matches.first {
            LockGate(asset: asset) {
                switch route {
                case .obligations: ObligationListScreen(asset: asset)
                case .history: HistoryListScreen(asset: asset)
                case .people: PeopleListScreen(asset: asset)
                case .documents: DocumentListScreen(asset: asset)
                case .children(_, let key): ChildrenListScreen(asset: asset, templateKey: key)
                }
            }
        } else {
            MissingRecordView()
        }
    }
}

/// Shows `content` only when the asset's category isn't locked right now.
struct LockGate<Content: View>: View {
    let asset: Asset
    @ViewBuilder var content: Content
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]

    init(asset: Asset, @ViewBuilder content: () -> Content) {
        self.asset = asset
        self.content = content()
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        if let template = templates.first, vault.isLocked(template) {
            LockedSectionView(title: asset.name)
        } else {
            content
        }
    }
}

// MARK: - Termene

struct ObligationListScreen: View {
    let asset: Asset
    @Environment(\.modelContext) private var context
    @Query private var templates: [CategoryTemplate]
    @State private var datePrompt: ObligationBlueprint?
    @State private var isAddingCustom = false
    @State private var error: UserFacingError?
    @State private var saveRequest: ReminderSaveRequest?
    @State private var addedCount = 0

    init(asset: Asset) {
        self.asset = asset
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        let obligations = (asset.obligations ?? []).filter { $0.status == .active || $0.status == .paused }.sorted { $0.dueDate < $1.dueDate }
        let suggestions = unusedBlueprints
        List {
            Section {
                if obligations.isEmpty {
                    Text("Niciun termen încă.", comment: "Empty list of obligations.")
                        .dsFont(.subheadline)
                }
                ForEach(obligations) { obligation in
                    NavigationLink(value: AppRoute.obligation(obligation.id)) {
                        ObligationRow(obligation: obligation)
                    }
                }
            } header: {
                Text("Termene", comment: "Header of the obligations list.")
            }
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { blueprint in
                        SuggestionRow(blueprint: blueprint, values: asset.values) { add(blueprint) }
                    }
                } header: {
                    Text("Poți adăuga", comment: "Header of suggested obligations.")
                } footer: {
                    Text("Sugestii pentru „\(asset.name)”. Le poți schimba oricând.", comment: "Footer of suggested obligations.")
                }
            }
            Section {
                Button {
                    isAddingCustom = true
                } label: {
                    Label { Text("Alt termen", comment: "Adds an obligation that isn't in the suggestions.") } icon: { Image(systemName: "plus") }
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationTitle(Text(SectionPocket.upcoming.title))
        .sheet(item: $datePrompt) { blueprint in
            FirstDateSheet(title: blueprint.title, reminders: blueprint.reminders(for: asset.values)) { day in
                create(blueprint, firstDue: day)
            }
        }
        .sheet(isPresented: $isAddingCustom) {
            CustomObligationSheet(asset: asset)
        }
        .userErrorAlert($error)
        .reminderPermissionGate($saveRequest)
        .sensoryFeedback(.success, trigger: addedCount)
    }

    private var unusedBlueprints: [ObligationBlueprint] {
        guard let template = templates.first else { return [] }
        let used = Set((asset.obligations ?? []).compactMap(\.blueprintKey))
        return template.blueprints.filter { !used.contains($0.key) && ($0.appliesWhen?.isMet(by: asset.values) ?? true) }
    }

    private func add(_ blueprint: ObligationBlueprint) {
        let today = CalendarDay(Date())
        if RecurrenceEngine.firstDue(for: blueprint, values: asset.values, today: today) != nil {
            create(blueprint, firstDue: nil)
        } else {
            datePrompt = blueprint
        }
    }

    private func create(_ blueprint: ObligationBlueprint, firstDue: CalendarDay?) {
        saveRequest = ReminderSaveRequest { performCreate(blueprint, firstDue: firstDue) }
    }

    private func performCreate(_ blueprint: ObligationBlueprint, firstDue: CalendarDay?) {
        do {
            try ObligationActions(context: context).create(from: blueprint, for: asset, firstDue: firstDue)
            addedCount += 1
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// A suggested obligation with its reminders in plain words and an Add button.
private struct SuggestionRow: View {
    let blueprint: ObligationBlueprint
    let values: FieldValues
    let add: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: blueprint.title).dsFont(.headline)
                Text(verbatim: ReminderWording.sentence(leadDays: blueprint.reminders(for: values).leadDays))
                    .dsFont(.subheadline)
                if let note = blueprint.note {
                    Text(verbatim: note).dsFont(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: add) {
                Text("Adaugă", comment: "Adds a suggested obligation.")
                    .frame(minHeight: 30)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Adaugă", comment: "Adds a suggested obligation."), add)
    }
}

/// Asks for the first due date of an obligation that can't work it out alone
/// (the current ITP's expiry, say).
struct FirstDateSheet: View {
    let title: String
    let reminders: ReminderProfile
    let onSave: (CalendarDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var date: Date? = nil
    @State private var reveals = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    Text("Când e următoarea dată pentru „\(title)”?", comment: "Question when adding an obligation that needs a date.")
                        .dsFont(.title)
                    DSDateField("Data", date: $date, isRequired: true, footnote: "De exemplu, data până la care e valabil ITP-ul de acum.")
                    Text(verbatim: ReminderWording.sentence(leadDays: reminders.leadDays))
                        .dsFont(.subheadline)
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, reveals)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let date else { reveals = true; return }
                        onSave(CalendarDay(date, calendar: calendar))
                        dismiss()
                    } label: {
                        Text("Adaugă", comment: "Adds a suggested obligation.")
                    }
                }
            }
        }
        .dsDiscardGuard(hasChanges: date != nil)
        .presentationDetents([.medium, .large])
    }
}

/// A deadline of the person's own: a name, a date, and whether it repeats.
struct CustomObligationSheet: View {
    let asset: Asset

    enum Repeat: String, CaseIterable, Hashable {
        case never, monthly, yearly

        var title: String {
            switch self {
            case .never: String(localized: "O singură dată", comment: "Repeat option.")
            case .monthly: String(localized: "În fiecare lună", comment: "Repeat option.")
            case .yearly: String(localized: "În fiecare an", comment: "Repeat option.")
            }
        }

        var rule: RecurrenceRule {
            switch self {
            case .never: .none
            case .monthly: .interval(.months(1), anchor: .dueDate)
            case .yearly: .interval(.years(1), anchor: .dueDate)
            }
        }
    }

    /// Reminders for the person's own deadlines: a week ahead and on the day.
    static let reminders = ReminderProfile(leadDays: [7, 0], consequence: .financial)

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var title = ""
    @State private var date: Date?
    @State private var repeats: Repeat? = .never
    @State private var reveals = false
    @State private var error: UserFacingError?
    @State private var saveRequest: ReminderSaveRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    DSTextField("Ce trebuie făcut", text: $title, prompt: "Plata asigurării, verificarea stingătorului", isRequired: true)
                    DSDateField("Până când", date: $date, isRequired: true)
                    DSChoiceField("Se repetă", selection: $repeats, options: Repeat.allCases, isRequired: true) { $0.title }
                    Text(verbatim: ReminderWording.sentence(leadDays: Self.reminders.leadDays))
                        .dsFont(.subheadline)
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, reveals)
            .navigationTitle(Text("Alt termen", comment: "Adds an obligation that isn't in the suggestions."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("Adaugă", comment: "Adds a suggested obligation.") }
                }
            }
            .userErrorAlert($error)
            .reminderPermissionGate($saveRequest)
        }
        .dsDiscardGuard(hasChanges: !title.isEmpty || date != nil)
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let date else { reveals = true; return }
        saveRequest = ReminderSaveRequest { performSave(name: name, date: date) }
    }

    private func performSave(name: String, date: Date) {
        do {
            try ObligationActions(context: context).create(
                title: name,
                kind: .renewal,
                dueDay: CalendarDay(date, calendar: calendar),
                for: asset,
                recurrence: (repeats ?? .never).rule,
                reminders: Self.reminders
            )
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

// MARK: - Istoric

struct HistoryListScreen: View {
    let asset: Asset
    @Query private var templates: [CategoryTemplate]

    init(asset: Asset) {
        self.asset = asset
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        let definition = templates.first?.definition ?? BuiltInTemplates.definition(for: asset.templateKey) ?? BuiltInTemplates.other
        let lines = HistoryLines.make(asset: asset, definition: definition)
        let hasComponents = lines.first.map { $0.id != $0.entryID.uuidString } ?? false
        List {
            if hasComponents {
                Section {
                    ForEach(lines) { line in
                        NavigationLink(value: AppRoute.historyEntry(line.entryID)) {
                            DSListRow(title: Text(verbatim: line.title), subtitle: Text(verbatim: line.detail)) { EmptyView() }
                        }
                    }
                } header: {
                    Text("Ultima dată", comment: "Header: the last time each part was done.")
                }
            }
            Section {
                if asset.timeline.isEmpty {
                    Text("Nimic notat încă.", comment: "Empty history list.").dsFont(.subheadline)
                }
                ForEach(asset.timeline) { entry in
                    NavigationLink(value: AppRoute.historyEntry(entry.id)) {
                        HistoryEntryRow(entry: entry)
                    }
                }
            } header: {
                Text("Tot istoricul", comment: "Header: every history entry.")
            }
        }
        .navigationTitle(Text(SectionPocket.history.title))
    }
}

/// A history entry: what was done, when, and what it cost.
struct HistoryEntryRow: View {
    let entry: HistoryEntry
    var showsAsset = false

    var body: some View {
        let detail = [showsAsset ? entry.asset?.name : nil, DosarFormat.day(entry.occurredAt), entry.effectiveCost.isEmpty ? nil : entry.effectiveCost.formatted()]
            .compactMap { $0 }
            .joined(separator: " · ")
        DSListRow(title: Text(verbatim: entry.title), subtitle: Text(verbatim: detail)) { EmptyView() }
    }
}

// MARK: - Oameni

struct PeopleListScreen: View {
    let asset: Asset
    @Environment(\.modelContext) private var context
    @State private var isAdding = false

    var body: some View {
        let people = ProviderDirectory(context: context).providers(for: asset)
        ScrollView {
            VStack(spacing: DS.Space.s) {
                ForEach(people) { provider in
                    DSCard { ProviderCard(provider: provider) }
                }
                DSWideButton("Adaugă o persoană", systemImage: "person.badge.plus", isProminent: false) { isAdding = true }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle(Text(SectionPocket.people.title))
        .sheet(isPresented: $isAdding) { ProviderEditSheet(provider: nil, linkTo: asset) }
    }
}

// MARK: - Acte

struct DocumentListScreen: View {
    let asset: Asset

    var body: some View {
        let personal = (asset.children ?? []).filter { $0.templateKey == BuiltInTemplates.Key.documents }.sorted { $0.name < $1.name }
        let papers = (asset.attachments ?? []).sorted { $0.createdAt > $1.createdAt }
        List {
            if !personal.isEmpty {
                Section {
                    ForEach(personal) { DocumentRowLink(item: .personal($0)) }
                } header: {
                    Text("Acte personale", comment: "Header: personal documents.")
                }
            }
            Section {
                if papers.filter({ !$0.isArchived }).isEmpty {
                    Text("Niciun document scanat.", comment: "Empty list of scanned documents.").dsFont(.subheadline)
                }
                ForEach(papers.filter { !$0.isArchived }) { DocumentRowLink(item: .paper($0)) }
            } header: {
                Text("Documente", comment: "Header: scanned documents.")
            }
            let archived = papers.filter(\.isArchived)
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { DocumentRowLink(item: .paper($0)) }
                } header: {
                    Text("Arhivate", comment: "Header: documents kept for reference.")
                } footer: {
                    Text("Polițe și contracte vechi, păstrate pentru orice eventualitate.", comment: "Footer of archived documents.")
                }
            }
        }
        .navigationTitle(Text(SectionPocket.documents.title))
    }
}

// MARK: - Children

struct ChildrenListScreen: View {
    let asset: Asset
    let templateKey: String
    @Environment(ShellRouter.self) private var router

    var body: some View {
        let children = (asset.children ?? []).filter { $0.templateKey == templateKey }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let definition = BuiltInTemplates.definition(for: templateKey)
        List {
            ForEach(children) { child in
                NavigationLink(value: AppRoute.asset(child.id)) {
                    ChildRow(child: child, definition: definition)
                }
            }
            Button {
                router.present(.addSection(AddSectionRequest(parentID: asset.id, templateKey: templateKey)))
            } label: {
                Label { Text("Adaugă", comment: "Adds a suggested obligation.") } icon: { Image(systemName: "plus") }
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle(Text(verbatim: asset.name))
    }
}
