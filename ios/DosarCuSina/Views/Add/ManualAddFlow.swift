import SwiftData
import SwiftUI

/// "Scriu eu": pick the section, then what to add to it: a deadline, a visit,
/// or a document. Everything saves through the engine's actions.
struct ManualAddFlow: View {
    /// Called when the flow closes, with a confirmation to show, if anything was saved.
    let onClose: (LocalizedStringResource?) -> Void

    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]
    @Query(sort: \Asset.name) private var assets: [Asset]

    @State private var path: [ManualStep] = []
    @State private var isCreatingSection = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if assets.isEmpty {
                    Text("Nu ai încă nicio secțiune. Fă una nouă mai jos.")
                        .dsFont(.subheadline)
                }
                ForEach(templates.filter { template in assets.contains { $0.templateKey == template.key } }) { template in
                    Section {
                        ForEach(assets.filter { $0.templateKey == template.key }) { asset in
                            NavigationLink(value: ManualStep.what(asset.id)) {
                                DSListRow(
                                    title: Text(verbatim: asset.name),
                                    subtitle: asset.isExample ? Text("Exemplu") : nil,
                                    systemImage: asset.symbolOverride ?? template.symbol,
                                    tint: (asset.tintOverride ?? template.tint).color,
                                    trailing: { EmptyView() }
                                )
                            }
                        }
                    } header: {
                        Text(verbatim: template.name).textCase(nil)
                    }
                }
                Section {
                    Button { isCreatingSection = true } label: {
                        DSListRow("Secțiune nouă", subtitle: "O mașină, o casă, un animal, un act…", systemImage: "folder.badge.plus", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Unde adaugi?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Închide") { onClose(nil) } }
            }
            .navigationDestination(for: ManualStep.self) { step in
                switch step {
                case .what(let id):
                    ManualWhatView(assetID: id, path: $path, onClose: onClose)
                case .deadline(let id):
                    AddDeadlineForm(assetID: id, onClose: onClose)
                case .visit(let id):
                    AddVisitFlow(assetID: id, prefill: nil) { saved in
                        onClose(saved ? "Vizita e în istoric." : nil)
                    }
                }
            }
            .sheet(isPresented: $isCreatingSection) {
                NewSectionForm { asset in
                    isCreatingSection = false
                    if let asset { path.append(.what(asset.id)) }
                }
            }
        }
    }
}

enum ManualStep: Hashable {
    case what(UUID)
    case deadline(UUID)
    case visit(UUID)
}

/// What to add to the chosen section.
private struct ManualWhatView: View {
    let assetID: UUID
    @Binding var path: [ManualStep]
    let onClose: (LocalizedStringResource?) -> Void

    @Query private var assets: [Asset]
    @State private var source: CaptureSource?
    @State private var isChoosingSource = false
    @State private var flow: CaptureFlowInput?
    @State private var errorMessage: String?

    var body: some View {
        let asset = assets.first { $0.id == assetID }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if let asset {
                    Text(verbatim: asset.name).dsFont(.title).padding(.bottom, DS.Space.xs)
                }
                DSActionCard("Un termen", subtitle: "ITP, o asigurare, un vaccin, o plată.", systemImage: "calendar.badge.clock") {
                    path.append(.deadline(assetID))
                }
                DSActionCard("O vizită sau o reparație", subtitle: "Ce s-a făcut, cât a costat, cine a lucrat.", systemImage: "wrench.and.screwdriver") {
                    path.append(.visit(assetID))
                }
                DSActionCard("Un act", subtitle: "Poză, PDF sau scanare. Îl citesc și ți-l arăt.", systemImage: "doc.viewfinder") {
                    isChoosingSource = true
                }
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a deschis", message: LocalizedStringKey(errorMessage))
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Ce adaugi?")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Un act", isPresented: $isChoosingSource, titleVisibility: .visible) {
            if CaptureSource.isCameraAvailable { Button("Fotografiază actul") { source = .camera } }
            Button("Alege din poze") { source = .photos }
            Button("Din Fișiere") { source = .files }
            Button("Renunță", role: .cancel) {}
        }
        .captureSourcePicker($source) { payload in
            flow = CaptureFlowInput(payload: payload, preferredAssetID: assetID)
        } onError: { error in
            errorMessage = error.localizedDescription
        }
        .sheet(item: $flow) { input in
            CaptureFlowView(input: input) { result in
                flow = nil
                switch result {
                case .filed(let message), .visitSaved(let message): onClose(message)
                case .dismissed: break
                }
            }
        }
    }
}

/// A new deadline for a section: one of its category's usual ones, or anything else.
private struct AddDeadlineForm: View {
    let assetID: UUID
    let onClose: (LocalizedStringResource?) -> Void

    @Environment(\.modelContext) private var context
    @Query private var assets: [Asset]

    private enum Choice: Hashable {
        case blueprint(String)
        case custom
    }

    private enum Importance: String, CaseIterable, Identifiable {
        case legal, money, health, reminder
        var id: String { rawValue }
        var kind: ObligationKind {
            switch self {
            case .legal: .legal
            case .money: .payment
            case .health: .health
            case .reminder: .routine
            }
        }
        var title: String {
            switch self {
            case .legal: String(localized: "Obligatoriu prin lege")
            case .money: String(localized: "Ține de bani")
            case .health: String(localized: "Ține de sănătate")
            case .reminder: String(localized: "Doar să nu uit")
            }
        }
    }

    private enum Repeat: String, CaseIterable, Identifiable {
        case never, monthly, yearly
        var id: String { rawValue }
        var rule: RecurrenceRule {
            switch self {
            case .never: .none
            case .monthly: .interval(.months(1), anchor: .dueDate)
            case .yearly: .interval(.years(1), anchor: .dueDate)
            }
        }
        var title: String {
            switch self {
            case .never: String(localized: "O singură dată")
            case .monthly: String(localized: "În fiecare lună")
            case .yearly: String(localized: "În fiecare an")
            }
        }
    }

    @State private var choice: Choice?
    @State private var customTitle = ""
    @State private var importance: Importance? = .reminder
    @State private var repeats: Repeat? = .never
    @State private var due: Date?
    @State private var errorMessage: String?
    @State private var saveRequest: ReminderSaveRequest?

    var body: some View {
        let asset = assets.first { $0.id == assetID }
        let template = asset.flatMap { try? TemplateStore(context: context).template(forKey: $0.templateKey) }
        let taken = Set(asset?.activeObligations.compactMap(\.blueprintKey) ?? [])
        let blueprints = (template?.blueprints ?? []).filter { !taken.contains($0.key) && ($0.appliesWhen?.isMet(by: asset?.values ?? FieldValues()) ?? true) }

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSSectionHeader("Ce termen")
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            ForEach(Array(blueprints.enumerated()), id: \.element.key) { index, blueprint in
                                if index > 0 { DS.Hairline() }
                                DSCheckRow(title: Text(verbatim: blueprint.title), subtitle: blueprint.note.map { Text(verbatim: $0) },
                                           isOn: choice == .blueprint(blueprint.key)) {
                                    select(.blueprint(blueprint.key), blueprint: blueprint, asset: asset)
                                }
                            }
                            if !blueprints.isEmpty { DS.Hairline() }
                            DSCheckRow(title: Text("Alt termen"), subtitle: Text("Scrii tu ce e."), isOn: choice == .custom) {
                                select(.custom, blueprint: nil, asset: asset)
                            } detail: {
                                VStack(alignment: .leading, spacing: DS.Space.s) {
                                    DSTextField("Ce trebuie făcut", text: $customTitle, prompt: "Cazier pentru angajare", isRequired: true)
                                    DSChoiceField("Cât de important e", selection: $importance, options: Importance.allCases, isRequired: true) { $0.title }
                                    DSChoiceField("Se repetă", selection: $repeats, options: Repeat.allCases, isRequired: true) { $0.title }
                                }
                            }
                        }
                    }
                }
                if choice != nil {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader("Când e termenul")
                        DSCard {
                            DSDateField("Data", date: $due, isRequired: true)
                        }
                    }
                }
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                }
                DSPrimaryButton("Salvează termenul", systemImage: "checkmark") {
                    saveRequest = ReminderSaveRequest { save(asset: asset, blueprints: blueprints) }
                }
                .disabled(!canSave)
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Un termen")
        .navigationBarTitleDisplayMode(.inline)
        .reminderPermissionGate($saveRequest)
        .dsDiscardGuard(hasChanges: choice != nil)
    }

    private var canSave: Bool {
        guard due != nil, let choice else { return false }
        if choice == .custom { return !customTitle.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func select(_ value: Choice, blueprint: ObligationBlueprint?, asset: Asset?) {
        choice = value
        if let blueprint, let asset {
            let today = CalendarDay(Date())
            due = RecurrenceEngine.firstDue(for: blueprint, values: asset.values, today: today).map { $0.startDate() }
        }
    }

    private func save(asset: Asset?, blueprints: [ObligationBlueprint]) {
        guard let asset, let due, let choice else { return }
        let day = CalendarDay(due)
        let actions = ObligationActions(context: context)
        do {
            let obligation: Obligation
            switch choice {
            case .blueprint(let key):
                guard let blueprint = blueprints.first(where: { $0.key == key }) else { return }
                obligation = try actions.create(from: blueprint, for: asset, firstDue: day)
            case .custom:
                obligation = try actions.create(
                    title: customTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: (importance ?? .reminder).kind,
                    dueDay: day,
                    for: asset,
                    recurrence: (repeats ?? .never).rule
                )
            }
            onClose("Am adăugat \(obligation.title). \(ReminderWording.sentence(leadDays: obligation.reminderLeadDays))")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A new section, in two answers: what kind, and its name. Details are filled
/// later on its page.
private struct NewSectionForm: View {
    let onClose: (Asset?) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]
    @State private var templateKey: String?
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader("Ce fel de secțiune")
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                let choices = templates.filter { $0.key != BuiltInTemplates.Key.member }
                                ForEach(Array(choices.enumerated()), id: \.element.key) { index, template in
                                    if index > 0 { DS.Hairline() }
                                    DSCheckRow(title: Text(verbatim: template.name), subtitle: template.summary.map { Text(verbatim: $0) },
                                               isOn: templateKey == template.key) {
                                        templateKey = template.key
                                    }
                                }
                            }
                        }
                    }
                    DSTextField("Nume", text: $name, prompt: "VW Golf, Apartament, PawPaw", isRequired: true)
                    if let errorMessage {
                        DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                    }
                    DSPrimaryButton("Fă secțiunea", systemImage: "checkmark") { save() }
                        .disabled(templateKey == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .navigationTitle("Secțiune nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: templateKey != nil || !name.isEmpty)
        }
    }

    private func save() {
        guard let key = templateKey, let template = templates.first(where: { $0.key == key }) else { return }
        // No deadlines yet: the next step offers them, with their dates, one by one.
        do {
            let asset = try AssetActions(context: context).create(name: name.trimmingCharacters(in: .whitespacesAndNewlines), template: template, values: FieldValues())
            onClose(asset)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
