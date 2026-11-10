import SwiftUI
import SwiftData

/// "Adaugă o secțiune": pick a ready-made category or describe one of your own,
/// fill in only the essentials, then choose the obligations to start with.
struct AddSectionFlow: View {
    let request: AddSectionRequest
    /// Called with the new asset after it is saved.
    let onCreated: (Asset) -> Void

    enum Step: Hashable {
        case custom
        case essentials
        case obligations
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddSectionModel
    @State private var path: [Step] = []
    @State private var error: UserFacingError?
    /// A section under an example asks "Păstrezi … ca al tău?" first.
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var saveRequest: ReminderSaveRequest?
    @State private var createdCount = 0

    init(request: AddSectionRequest, onCreated: @escaping (Asset) -> Void) {
        self.request = request
        self.onCreated = onCreated
        _model = State(initialValue: AddSectionModel(request: request))
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .custom: CustomSectionStep(model: model) { path.append(.essentials) }
                    case .essentials: EssentialsStep(model: model, next: afterEssentials)
                    case .obligations: ObligationsStep(model: model, finish: finish)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                }
        }
        .dsDiscardGuard(hasChanges: model.hasChanges)
        .userErrorAlert($error)
        .examplePrompt($exampleQuestion) { create() }
        .reminderPermissionGate($saveRequest)
        .sensoryFeedback(.success, trigger: createdCount)
        .task { preselect() }
    }

    @ViewBuilder
    private var root: some View {
        if request.templateKey != nil {
            if model.template != nil {
                EssentialsStep(model: model, next: afterEssentials)
            } else {
                DSDelayedProgress()
            }
        } else {
            CatalogStep { template in
                model.choose(template)
                path.append(.essentials)
            } custom: {
                if model.custom == nil { model.custom = CustomSectionDraft() }
                path.append(.custom)
            }
        }
    }

    private func preselect() {
        guard let key = request.templateKey, model.template == nil else { return }
        if let template = try? TemplateStore(context: context).template(forKey: key) {
            model.choose(template)
        }
    }

    private func afterEssentials() {
        model.planObligations(context: context)
        if model.planned.isEmpty {
            finish()
        } else {
            path.append(.obligations)
        }
    }

    private func finish() {
        if model.planned.isEmpty {
            create()
        } else {
            saveRequest = ReminderSaveRequest { create() }
        }
    }

    private func create() {
        do {
            let asset = try model.create(context: context)
            createdCount += 1
            dismiss()
            onCreated(asset)
        } catch let question as ExampleSectionQuestion {
            exampleQuestion = question
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

// MARK: - Catalog

private struct CatalogStep: View {
    let choose: (CategoryTemplate) -> Void
    let custom: () -> Void

    @Query(sort: [SortDescriptor(\CategoryTemplate.homeOrder)]) private var templates: [CategoryTemplate]

    var body: some View {
        // What each category says about itself: its place in the shortlist, its option's title.
        let offers = SectionOffers(templates)
        List {
            if !offers.shortlist.isEmpty {
                Section {
                    ForEach(offers.shortlist) { template in row(template) }
                } header: {
                    Text("Cele mai des folosite", comment: "Header of the main ready-made sections.")
                }
            }
            if !offers.others.isEmpty {
                Section {
                    ForEach(offers.others) { template in row(template) }
                } header: {
                    Text("Alte secțiuni gata făcute", comment: "Header of the other ready-made sections.")
                }
            }
            Section {
                Button(action: custom) {
                    DSListRow(
                        title: Text("Altceva…", comment: "Creates a section of the person's own."),
                        subtitle: Text("Îi dai tu un nume și alegi ce ține minte.", comment: "Explains the custom section option."),
                        systemImage: "square.and.pencil",
                        showsChevron: true
                    ) { EmptyView() }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(Text("Ce adaugi?", comment: "Title of the add-section catalog."))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ template: CategoryTemplate) -> some View {
        Button {
            choose(template)
        } label: {
            DSListRow(
                title: Text(verbatim: SectionOffers.title(for: template)),
                subtitle: template.summary.map { Text(verbatim: $0) },
                systemImage: template.symbol,
                tint: template.tintColor,
                showsChevron: true
            ) { EmptyView() }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Altceva…

struct CustomSectionStep: View {
    @Bindable var model: AddSectionModel
    let next: () -> Void
    @State private var reveals = false

    /// The first version's step chose pockets one by one. Off: a category of one's own
    /// answers a few plain questions instead (`CategorySwitches`, `CustomCategoryForm`).
    /// Kept as a way back until the switches are proven; remove it with the owner's OK.
    nonisolated static let offersPocketList = false

    private var draft: Binding<CustomSectionDraft> {
        Binding { model.custom ?? CustomSectionDraft() } set: { model.custom = $0 }
    }

    var body: some View {
        ScrollView {
            Group {
                if Self.offersPocketList {
                    pocketList
                } else {
                    CustomCategoryForm(draft: draft)
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background)
        .environment(\.dsRevealsValidation, reveals)
        .navigationTitle(Text("Categorie nouă", comment: "Title of the step that describes a category of one's own."))
        .navigationBarTitleDisplayMode(.inline)
        .dsPinnedAction {
            DSPrimaryButton("Continuă") {
                guard let custom = model.custom, custom.isComplete else {
                    reveals = true
                    return
                }
                model.chooseCustom(custom)
                next()
            }
        }
    }

    /// The first version's step, not shown (`offersPocketList`).
    private var pocketList: some View {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DSTextField("Cum se numește", text: draft.name, prompt: "Barca, Rulota, Pianul", isRequired: true)
                CustomSymbolPicker(symbol: draft.symbol)

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    DSSectionHeader("Ce ține minte")
                    DSCard {
                        VStack(spacing: 0) {
                            ForEach(Array(CustomSectionDraft.offeredPockets.enumerated()), id: \.element) { index, pocket in
                                if index > 0 { DSRowSeparator() }
                                DSCheckRow(
                                    title: Text(verbatim: pocket.title),
                                    subtitle: Text(verbatim: CustomSectionDraft.explanation(for: pocket)),
                                    isOn: Binding(
                                        get: { draft.wrappedValue.pockets.contains(pocket) },
                                        set: { isOn in
                                            if isOn { draft.wrappedValue.pockets.insert(pocket) } else { draft.wrappedValue.pockets.remove(pocket) }
                                        }
                                    )
                                )
                                .padding(.vertical, DS.Space.xs)
                            }
                        }
                    }
                }
            }
    }
}

// MARK: - Essentials

private struct EssentialsStep: View {
    @Bindable var model: AddSectionModel
    let next: () -> Void
    @State private var reveals = false
    @Query(sort: \Asset.name) private var assets: [Asset]
    @Query private var templates: [CategoryTemplate]

    var body: some View {
        let fields = model.essentialFields
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if let definition = model.definition {
                    HStack(spacing: DS.Space.s) {
                        DSIconWell(systemImage: definition.symbol, tint: definition.tint.color)
                        Text(verbatim: definition.name).dsFont(.headline)
                    }
                }
                DSTextField(
                    "Nume",
                    text: $model.name,
                    prompt: LocalizedStringKey(model.definition.map { AddSectionModel.suggestedName(values: model.values, definition: $0) } ?? ""),
                    footnote: "Cum îi spui acasă: „Golful”, „Apartamentul”, „PawPaw”."
                )
                ForEach(fields) { field in
                    FieldEditor(field: field, values: $model.values,
                                urgencyRule: DateUrgency.rule(forField: field.key, values: model.values, definition: model.definition))
                }
                if model.template?.behavior.role == .personalDocument, model.request.parentID == nil {
                    holderPicker
                }
                if fields.isEmpty {
                    Text("Restul detaliilor le completezi oricând din pagina secțiunii, cu Editează.", comment: "Footnote when a category has no essential fields.")
                        .dsFont(.footnote)
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background)
        .environment(\.dsRevealsValidation, reveals)
        .navigationTitle(Text("Ce trebuie știut", comment: "Title of the essentials step."))
        .navigationBarTitleDisplayMode(.inline)
        .dsPinnedAction {
            DSPrimaryButton("Continuă") {
                guard FieldValuesCheck.canSave(model.values, fields: fields) else { reveals = true; return }
                next()
            }
        }
    }

    /// Whose document it is, from the people documents are filed under (`CategoryBehavior.Role.holder`).
    @ViewBuilder
    private var holderPicker: some View {
        let holderKeys = templates.keys(playing: .holder)
        let members = assets.filter { holderKeys.contains($0.templateKey) }
        if !members.isEmpty {
            DSChoiceField(
                "Al cui este",
                selection: Binding(get: { model.parentID }, set: { model.parentID = $0 }),
                options: members.map(\.id),
                footnote: "Actele stau grupate pe persoane."
            ) { id in members.first { $0.id == id }?.name ?? "" }
        }
    }
}

// MARK: - Obligations

private struct ObligationsStep: View {
    @Bindable var model: AddSectionModel
    let finish: () -> Void
    @State private var reveals = false
    @Environment(\.calendar) private var calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("Alege ce vrei să-ți amintim. Datele le poți schimba oricând.", comment: "Intro of the obligations step.")
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                DSCard {
                    VStack(spacing: 0) {
                        ForEach($model.planned) { $plan in
                            if plan.id != model.planned.first?.id { DSRowSeparator() }
                            DSCheckRow(
                                title: Text(verbatim: plan.blueprint.title),
                                subtitle: Text(verbatim: [
                                    ReminderWording.sentence(plan.blueprint.reminders(for: model.values)),
                                    plan.blueprint.note,
                                ].compactMap { $0 }.joined(separator: "\n")),
                                isOn: $plan.isSelected
                            )
                            .padding(.vertical, DS.Space.xs)
                            if plan.isSelected {
                                DSDateField(
                                    "Următoarea dată",
                                    date: Binding(
                                        get: { plan.firstDue?.noonDate(in: calendar) },
                                        set: { plan.firstDue = $0.map { CalendarDay($0, calendar: calendar) } }
                                    ),
                                    isRequired: true
                                )
                                .padding(.bottom, DS.Space.s)
                                .transition(.opacity)
                            }
                        }
                    }
                    .dsAnimation(value: model.planned.map(\.isSelected))
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
        .environment(\.dsRevealsValidation, reveals)
        .navigationTitle(Text("Termene", comment: "Header of the obligations list."))
        .navigationBarTitleDisplayMode(.inline)
        .dsPinnedAction {
            DSPrimaryButton("Adaugă în dosar") {
                guard model.missingDates.isEmpty else { reveals = true; return }
                finish()
            }
        }
    }
}

