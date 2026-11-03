import SwiftUI
import SwiftData

/// Adding a document for a household member who is already chosen: a photo
/// first (the capture flow reads the type, the fields and the expiry and files
/// it under them), or "Scriu eu" on one screen. Either way it lands on the
/// document's own page.
struct AddPersonalDocumentFlow: View {
    let holderID: UUID
    /// Called after the document is saved, with its id, once the sheet is closing.
    let onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var matches: [Asset]

    @State private var source: CaptureSource?
    @State private var capture: CaptureFlowInput?
    @State private var isTyping = false
    @State private var draft = PersonalDocumentDraft()
    @State private var errorMessage: String?

    init(holderID: UUID, onCreated: @escaping (UUID) -> Void) {
        self.holderID = holderID
        self.onCreated = onCreated
        let id = holderID
        _matches = Query(filter: #Predicate<Asset> { $0.id == id })
    }

    var body: some View {
        Group {
            if let holder = matches.first {
                if let capture {
                    CaptureFlowView(input: capture) { result in finishCapture(result, holder: holder) }
                        .transition(.opacity)
                } else {
                    start(holder)
                        .transition(.opacity)
                }
            } else {
                NavigationStack { MissingRecordView() }
            }
        }
        .dsAnimation(value: capture?.id)
        .dsDiscardGuard(hasChanges: !draft.isEmpty)
    }

    // MARK: Start

    private func start(_ holder: Asset) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Pentru \(holder.name)", comment: "Who a new document is for, at the top of the add-document sheet.")
                        .dsFont(.title)
                        .padding(.bottom, DS.Space.xs)
                    if CaptureSource.isCameraAvailable {
                        DSActionCard("Fotografiază", subtitle: "Fotografiezi actul, iar eu completez ce act e, datele și când expiră.", systemImage: "camera.fill") {
                            source = .camera
                        }
                    }
                    DSActionCard("Din poze", subtitle: "O poză cu actul, făcută mai demult.", systemImage: "photo.on.rectangle") {
                        source = .photos
                    }
                    DSActionCard("Scriu eu", subtitle: "Alegi ce act e și până când e valabil.", systemImage: "square.and.pencil") {
                        isTyping = true
                    }
                    if let errorMessage {
                        DSNotice(.error, title: "Nu s-a deschis", message: LocalizedStringKey(errorMessage))
                    }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(DS.Palette.background)
            .navigationTitle(Text("Un act nou", comment: "Title of the sheet that adds a document for a person."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .navigationDestination(isPresented: $isTyping) {
                PersonalDocumentForm(holder: holder, draft: $draft) { document in
                    dismiss()
                    onCreated(document.id)
                }
            }
            .captureSourcePicker($source) { payload in
                errorMessage = nil
                capture = CaptureFlowInput(payload: payload, preferredAssetID: holder.id, filesAsPersonalDocument: true)
            } onError: { error in
                errorMessage = SaveFailure.message(for: error, formKept: false)
            }
        }
    }

    // MARK: Capture

    private func finishCapture(_ result: CaptureFlowResult, holder: Asset) {
        switch result {
        case .filed(_, let assetID):
            dismiss()
            if let assetID { onCreated(assetID) }
        case .visitSaved:
            dismiss()
        case .dismissed:
            capture = nil
        }
    }
}

// MARK: - Scriu eu

/// One screen: what the document is (with its variant, only where there are
/// real ones), the name it gets by itself, the expiry with its reminder in
/// plain words, and "Salvează".
private struct PersonalDocumentForm: View {
    let holder: Asset
    @Binding var draft: PersonalDocumentDraft
    let onSaved: (Asset) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Query private var templates: [CategoryTemplate]

    @State private var isEditingName = false
    @State private var reveals = false
    @State private var errorMessage: String?
    @State private var saveRequest: ReminderSaveRequest?
    @State private var savedCount = 0
    /// A document for an example person asks "Păstrezi … ca a ta?" first.
    @State private var exampleQuestion: ExampleSectionQuestion?

    init(holder: Asset, draft: Binding<PersonalDocumentDraft>, onSaved: @escaping (Asset) -> Void) {
        self.holder = holder
        self._draft = draft
        self.onSaved = onSaved
    }

    /// The category of personal documents.
    private var documentsTemplate: CategoryTemplate? {
        templates.filter { $0.behavior.role == .personalDocument }.sorted { $0.isBuiltIn && !$1.isBuiltIn }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                typeSection
                if draft.type != nil {
                    nameSection
                    expirySection
                }
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .dsAnimation(value: draft.type)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background)
        .environment(\.dsRevealsValidation, reveals)
        .navigationTitle(Text("Scriu eu", comment: "Title of the screen where a document is typed in by hand."))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                DSPrimaryButton("Salvează", systemImage: "checkmark") { requestSave() }
            }
        }
        .reminderPermissionGate($saveRequest)
        .examplePrompt($exampleQuestion) { save() }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    // MARK: Sections

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Ce act e")
            DSCard {
                VStack(spacing: 0) {
                    ForEach(Array(DocumentType.options.enumerated()), id: \.element.key) { index, option in
                        if index > 0 { DSRowSeparator() }
                        DSCheckRow(title: Text(verbatim: option.label), isOn: draft.type == option.key, action: { draft.choose(type: option.key) }) {
                            variants(of: option)
                        }
                        .padding(.vertical, DS.Space.xxs)
                    }
                }
            }
            if reveals, draft.type == nil {
                Text("Alege ce act e.", comment: "Error when saving a personal document without a type.")
                    .dsFont(.footnote)
                    .foregroundStyle(DSStatus.overdue.textColor)
            }
        }
    }

    /// The variant question, under its type and only for types that have variants.
    @ViewBuilder
    private func variants(of type: ChoiceOption) -> some View {
        let options = DocumentType.variants(of: type.key)
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ce fel de \(type.label.lowercased(with: .dosarDefault))?", comment: "Question for the variant of a document type, e.g. what kind of cazier.")
                    .dsFont(.subheadline)
                    .padding(.top, DS.Space.xxs)
                ForEach(options) { variant in
                    DSCheckRow(title: Text(verbatim: variant.label), isOn: draft.variant == variant.key) {
                        draft.variant = variant.key
                    }
                }
            }
            .padding(.leading, DS.Space.xl)
            .padding(.bottom, DS.Space.xs)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Nume")
            DSCard {
                if isEditingName {
                    DSTextField("Nume", text: nameBinding, footnote: "Așa apare în Acte.")
                } else {
                    DSAdaptiveStack(spacing: DS.Space.s) {
                        Text(verbatim: draft.name(holder: holder.name))
                            .dsFont(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            draft.customName = draft.name(holder: holder.name)
                            isEditingName = true
                        } label: {
                            Text("Schimbă", comment: "Button that lets the person edit a document's automatic name.")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        }
    }

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if draft.isDatedByIssue {
                // A cazier prints the day it was issued; how long it is valid follows from its rule.
                DSDateField("Eliberat pe", date: issuedBinding, in: Date.distantPast...Date.now, footnote: "Data scrisă pe act.")
            } else {
                DSExpiryDateField("Valabil până la", date: expiryBinding, urgencyRule: expiryRule)
            }
            if let line = reminderLine {
                Text(verbatim: line)
                    .dsFont(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Amintirea o poți schimba oricând, din pagina termenului.", comment: "Footnote under a document's reminder line.")
                    .dsFont(.footnote)
            } else if draft.isDatedByIssue, draft.validityMonths == nil {
                if draft.variant == nil, !draft.variantOptions.isEmpty, let type = draft.type.flatMap(DocumentType.label(for:)) {
                    Text("Alege ce fel de \(type.lowercased(with: .dosarDefault)) e, ca să știu cât timp e valabil.",
                         comment: "Footnote under a cazier's issue date before its variant is chosen.")
                        .dsFont(.footnote)
                } else {
                    // A cazier fiscal or auto: no rule is known, so nothing reminds.
                    Text("Nu știu cât timp e valabil, așa că nu îți amintesc de el.",
                         comment: "Footnote under the issue date of a document with no known validity, e.g. a cazier fiscal.")
                        .dsFont(.footnote)
                }
            } else {
                Text("Fără o dată nu am când să-ți amintesc. O poți adăuga oricând.", comment: "Footnote when a document has no expiry date.")
                    .dsFont(.footnote)
            }
        }
    }

    // MARK: Bindings

    private var nameBinding: Binding<String> {
        Binding { draft.customName ?? "" } set: { draft.customName = $0 }
    }

    private var expiryBinding: Binding<Date?> {
        Binding {
            draft.expiry?.noonDate(in: calendar)
        } set: { date in
            draft.expiry = date.map { CalendarDay($0, calendar: calendar) }
        }
    }

    private var issuedBinding: Binding<Date?> {
        Binding {
            draft.issued?.noonDate(in: calendar)
        } set: { date in
            draft.issued = date.map { CalendarDay($0, calendar: calendar) }
        }
    }

    private var expiryRule: UrgencyRule {
        guard let template = documentsTemplate else { return .noReminders }
        return PersonalDocumentFiling.urgencyRule(draft, template: template, actions: AssetActions(context: context, calendar: calendar))
    }

    private var reminderLine: String? {
        guard let template = documentsTemplate else { return nil }
        return PersonalDocumentFiling.reminderLine(draft, template: template, actions: AssetActions(context: context, calendar: calendar),
                                                   today: CalendarDay(Date(), calendar: calendar), calendar: calendar)
    }

    // MARK: Save

    private func requestSave() {
        errorMessage = nil
        guard draft.type != nil else { reveals = true; return }
        if reminderLine != nil {
            saveRequest = ReminderSaveRequest { save() }
        } else {
            save()
        }
    }

    private func save() {
        do {
            let document = try PersonalDocumentFiling.save(draft, holder: holder, context: context, calendar: calendar)
            savedCount += 1
            draft = PersonalDocumentDraft()
            onSaved(document)
        } catch let question as ExampleSectionQuestion {
            exampleQuestion = question
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}
