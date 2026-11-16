import SwiftData
import SwiftUI

/// One visit, shaped by its category's kind (`VisitKind`, laid over the category by `VisitForm`):
/// a car's service with its parts, brands and kilometres; a tradesperson's job; a repair and its
/// warranty; a doctor's visit with what it was for and its papers; a vet's with the pet's
/// vaccines and treatments. The paper's photo fills what the kind asks by itself. One save
/// through `CaptureFiler` (the visit and its paper together), then the form closes with the
/// toast every save shows, the kind's own words with "Anulează" (`VisitEnding`).
///
/// A shaped screen: it holds no words of its own. Every word comes from the form (`VisitForm`,
/// `VisitShape`) or the words every kind shares (`VisitFormWording`); the architecture check
/// refuses a text literal here (`text-in-shaped-screen`).
struct AddVisitFlow: View {
    let assetID: UUID
    private let prefill: CaptureResult?
    private let embedsNavigation: Bool
    /// Called when the flow ends: with the saved visit's toast (its "Anulează" takes it back),
    /// or nil when nothing was saved.
    private let onFinish: ((DSToast?) -> Void)?

    /// Presented on its own (from a section's page): it brings its own navigation bar.
    init(assetID: UUID) {
        self.assetID = assetID
        self.prefill = nil
        self.embedsNavigation = true
        self.onFinish = nil
    }

    /// Opened from capture with a paper already read, or from "Scriu eu", inside their navigation.
    init(assetID: UUID, prefill: CaptureResult?, onFinish: @escaping (DSToast?) -> Void) {
        self.assetID = assetID
        self.prefill = prefill
        self.embedsNavigation = false
        self.onFinish = onFinish
    }

    @Query private var assets: [Asset]
    @Environment(\.modelContext) private var context

    var body: some View {
        let asset = assets.first { $0.id == assetID }
        Group {
            if embedsNavigation {
                NavigationStack { content(asset) }
            } else {
                content(asset)
            }
        }
    }

    @ViewBuilder private func content(_ asset: Asset?) -> some View {
        if let asset {
            let definition = (try? TemplateStore(context: context).template(forKey: asset.templateKey))?.definition
            if let form = definition.flatMap(VisitForm.make(for:)) {
                VisitFormView(asset: asset, form: form, prefill: prefill, onFinish: onFinish)
            } else {
                // A link to a visit of a section whose category has none.
                DSEmptyState(LocalizedStringKey(VisitFormWording.noVisits), systemImage: "calendar.badge.exclamationmark",
                             message: LocalizedStringKey(VisitFormWording.noVisitsMessage))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { DSCancelButton() } }
            }
        } else {
            DSEmptyState(LocalizedStringKey(VisitFormWording.sectionGone), systemImage: "questionmark.folder", message: LocalizedStringKey(VisitFormWording.sectionGoneMessage))
        }
    }
}

private struct VisitFormView: View {
    let asset: Asset
    let form: VisitForm
    let prefill: CaptureResult?
    let onFinish: ((DSToast?) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.announce) private var announce
    @Query(sort: \Provider.name) private var allProviders: [Provider]

    @State private var draft = VisitDraft(date: Date())
    @State private var didStart = false
    @State private var source: CaptureSource?
    @State private var isChoosingSource = false
    /// Reading a paper picked here. It ends with the form: a reading still running stops.
    @State private var session = CaptureSession()
    @State private var readNote: String?
    @State private var errorMessage: String?
    @State private var newProviderName = ""
    @State private var isSaving = false
    /// The visit is saved and the form is closing: nothing is left to lose.
    @State private var isDone = false
    @State private var saved: HistoryEntry?
    /// What saving the visit did, for "Anulează": a kept paper goes back where it was.
    @State private var receipt: UndoReceipt?
    @State private var toast: DSToast?
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var readingQuestion: LowerReadingQuestion?

    private var isReading: Bool { session.phase == .reading }
    private var shape: VisitShape { form.shape }

    var body: some View {
        Group {
            if let saved {
                VisitSavedView(entry: saved, asset: asset) { finish(true) } onUndo: { undo() }
            } else {
                content
            }
        }
        .navigationTitle(Text(verbatim: form.title))
        .navigationBarTitleDisplayMode(.inline)
        .dsToast($toast)
        .task { start() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text(verbatim: asset.name)
                    .dsFont(.title)
                if let paper = shape.paper { paperCard(paper) }
                if form.hasChecklist, let work = shape.work { checklist(work) }
                if form.hasRows { rowsSection }
                if let note = shape.note { noteSection(note) }
                detailsSection
                if let provider = shape.provider { providerSection(provider) }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .scrollDismissesKeyboard(.interactively)
        .dsPinnedAction {
            DSPrimaryButton(verbatim: shape.save, systemImage: "checkmark") { save() }
                .disabled(isSaving || !draft.satisfies(form))
        } note: {
            if let errorMessage {
                DSNotice(.error, title: Text(verbatim: VisitFormWording.notSaved), message: Text(verbatim: errorMessage))
            } else if !draft.satisfies(form), let requirement = form.requirementNote {
                Text(verbatim: requirement)
                    .dsFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
        }
        .dsDiscardGuard(hasChanges: draft.hasContent && saved == nil && !isDone)
        .confirmationDialog(Text(verbatim: shape.paper?.sourceTitle ?? form.title), isPresented: $isChoosingSource, titleVisibility: .visible) {
            if CaptureSource.isCameraAvailable, let paper = shape.paper { Button(paper.camera) { source = .camera } }
            Button(VisitFormWording.photos) { source = .photos }
            Button(VisitFormWording.files) { source = .files }
            Button(VisitFormWording.cancel, role: .cancel) {}
        }
        .captureSourcePicker($source) { payload in
            read(payload)
        } onError: { _ in
            readNote = VisitFormWording.photoDidNotOpen
        }
        .onChange(of: session.phase) { _, phase in
            switch phase {
            case .read(let result): apply(result)
            case .failed: readNote = form.failedNote
            default: break
            }
        }
        .examplePrompt($exampleQuestion) { save() }
        .readingPrompt($readingQuestion) { save(lowerReading: $0) }
    }

    // MARK: The paper

    @ViewBuilder private func paperCard(_ paper: VisitShape.Paper) -> some View {
        if draft.document == nil {
            DSActionCard(LocalizedStringKey(paper.action), subtitle: form.paperHint.map { LocalizedStringKey($0) }, systemImage: "doc.viewfinder") {
                isChoosingSource = true
            }
            .disabled(isReading)
            .overlay(alignment: .bottomTrailing) {
                if isReading { DSDelayedProgress(label: LocalizedStringKey(paper.reading)).padding(DS.Space.s) }
            }
        } else {
            DSNotice(.success, title: Text(verbatim: draft.keepsPhoto ? paper.attached : paper.read), message: readNote.map { Text(verbatim: $0) })
            if paper.isInvoice { filedNotice }
            // Its photo shows a whole card number: kept only when the person asks.
            if let kind = draft.photoOnRequestKind {
                KeepPhotoChoice(keepsPhoto: $draft.keepsPhotoOnRequest, kind: kind)
            }
        }
        if draft.document == nil, let readNote {
            DSNotice(.warning, title: Text(verbatim: paper.unread), message: Text(verbatim: readNote))
        }
    }

    /// The invoice is already in the binder: the same photo, or another photo of the same
    /// invoice (`PaperIdentity`). Saving updates the visit it was filed with.
    @ViewBuilder private var filedNotice: some View {
        if let filed {
            DSFiledPaperNotice(filed: filed, paper: .invoice, onOpen: {
                finish(false)
                AppNavigator.shared.open(.historyEntry(filed.entryID))
            }, onAnother: { draft.isAnotherInvoice = true })
        }
    }

    /// The visit this paper was filed with before, as saving will find it.
    private var filed: FiledPaper? {
        visit.filedBefore(keptDocumentID: draft.document?.keptAttachmentID, calendar: .dosar)?.paper
    }

    // MARK: What was done

    private func checklist(_ work: VisitShape.WorkWords) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            DSSectionHeader(LocalizedStringKey(work.header), subtitle: LocalizedStringKey(work.checklistHint))
            ForEach(ComponentCatalog.checklist(for: form.components)) { group in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: group.title)
                        .dsFont(.captionEmphasized)
                        .textCase(.uppercase)
                        .padding(.horizontal, DS.Space.xxs)
                        .accessibilityAddTraits(.isHeader)
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            ForEach(Array(group.components.enumerated()), id: \.element.key) { index, component in
                                if index > 0 { DS.Hairline() }
                                partRow(component)
                            }
                        }
                    }
                }
            }
        }
    }

    private func partRow(_ component: ComponentDefinition) -> some View {
        DSCheckRow(
            title: Text(verbatim: component.name),
            subtitle: lastDone(component.key).map { Text(verbatim: $0) },
            isOn: draft.isTicked(component.key),
            action: { draft.toggle(component.key) }
        ) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                DSMoneyField(LocalizedStringKey(VisitFormWording.rowCost), amount: partCost(component.key), currencyCode: $draft.currency)
                if shape.asksBrand {
                    DSTextField(LocalizedStringKey(VisitFormWording.brand), text: partBrand(component.key), prompt: LocalizedStringKey(VisitFormWording.optional))
                }
            }
            .padding(.leading, DS.Space.xl)
        }
    }

    private func lastDone(_ key: String) -> String? {
        guard let last = MaintenanceLog.lastOccurrence(of: key, in: HistoryItemSnapshot.items(of: asset)) else { return nil }
        return VisitFormWording.lastDone(DosarFormat.monthYear(last.date))
    }

    private func partCost(_ key: String) -> Binding<Decimal?> {
        Binding(get: { draft.parts[key]?.cost }, set: { draft.parts[key, default: VisitDraft.Part()].cost = $0 })
    }

    private func partBrand(_ key: String) -> Binding<String> {
        Binding(get: { draft.parts[key]?.brand ?? "" }, set: { draft.parts[key, default: VisitDraft.Part()].brand = $0 })
    }

    /// Rows of one's own: beside the checklist for what isn't on it, or what was done, row by row.
    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(LocalizedStringKey(form.rowsHeader ?? ""), subtitle: form.rowsHint.map { LocalizedStringKey($0) })
            ForEach($draft.extras) { $extra in
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSTextField(LocalizedStringKey(shape.work?.rowName ?? ""), text: $extra.name)
                        DSMoneyField(LocalizedStringKey(VisitFormWording.rowCost), amount: $extra.cost, currencyCode: $draft.currency)
                        Button(VisitFormWording.removeRow, role: .destructive) {
                            draft.extras.removeAll { $0.id == extra.id }
                        }
                        .frame(minHeight: DS.Control.minimumHitTarget)
                    }
                }
            }
            DSSecondaryButton(verbatim: form.addRow ?? "", systemImage: "plus") {
                draft.extras.append(VisitDraft.Extra(name: "", cost: nil))
            }
        }
    }

    // MARK: A note

    private func noteSection(_ note: VisitShape.Note) -> some View {
        DSCard {
            DSTextField(LocalizedStringKey(note.label), text: $draft.note, kind: .longText, prompt: LocalizedStringKey(note.prompt))
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(LocalizedStringKey(VisitFormWording.details))
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    DatePicker(selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date) {
                        Text(verbatim: VisitFormWording.date).dsFont(.headline)
                    }
                    .frame(minHeight: DS.Control.minimumHitTarget)
                    if let warranty = form.warrantyNote(on: CalendarDay(draft.date, calendar: .dosar), values: asset.values) {
                        Text(verbatim: warranty)
                            .dsFont(.footnote)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let counterField = form.counterField, let unit = counterField.unit {
                        DSMetricField(LocalizedStringKey(counterField.label), value: Binding(
                            get: { draft.odometer },
                            set: { draft.odometer = $0; draft.odometerSource = .person }
                        ), unit: unit,
                                      footnote: draft.odometer == nil && draft.odometerEstimate != nil
                                          ? LocalizedStringKey(VisitFormWording.estimate) : nil,
                                      placeholder: draft.odometerEstimate)
                    }
                    DSMoneyField(LocalizedStringKey(shape.costLabel), amount: $draft.total, currencyCode: $draft.currency,
                                 footnote: costNote.map { LocalizedStringKey($0) })
                }
            }
        }
    }

    /// Under the money field: what the rows add up to, while no total is typed; else the kind's hint.
    private var costNote: String? {
        if draft.total == nil, let sum = draft.partsSum {
            return form.sumNote(Money(sum, currency: draft.currency).formattedCompact())
        }
        return shape.costHint
    }

    // MARK: Who did it

    private func providerSection(_ words: VisitShape.Provider) -> some View {
        let candidates = providerCandidates(trade: words.trade)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(LocalizedStringKey(words.header))
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { DS.Hairline() }
                        DSCheckRow(
                            title: Text(verbatim: provider.name),
                            subtitle: provider.rating.map { Text(verbatim: VisitFormWording.rating($0.formatted(.number.precision(.fractionLength(0...1)).locale(.dosarDefault)))) },
                            isOn: draft.provider == .existing(provider.id),
                            action: { draft.provider = draft.provider == .existing(provider.id) ? .none : .existing(provider.id) }
                        )
                    }
                    if !candidates.isEmpty { DS.Hairline() }
                    DSTextField(LocalizedStringKey(candidates.isEmpty ? VisitFormWording.name : VisitFormWording.someoneElse), text: Binding(
                        get: { if case .new(let name) = draft.provider { return name } else { return newProviderName } },
                        set: { name in
                            newProviderName = name
                            draft.provider = name.trimmingCharacters(in: .whitespaces).isEmpty ? .none : .new(name)
                        }
                    ), prompt: LocalizedStringKey(words.prompt))
                    if draft.provider != .none {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(verbatim: words.rating).dsFont(.footnote)
                            DSStarRating(rating: draft.rating.map(Double.init)) { draft.rating = $0 }
                        }
                        .transition(DS.Motion.transition(from: .top, reduceMotion: reduceMotion))
                    }
                }
            }
        }
        .dsAnimation(value: draft.provider)
    }

    /// People who worked on this asset first, then others with the kind's trade.
    private func providerCandidates(trade: ProviderTrade) -> [Provider] {
        let directory = ProviderDirectory(context: context)
        var result = directory.providers(for: asset)
        for provider in allProviders where provider.has(trade) && !result.contains(where: { $0.id == provider.id }) {
            result.append(provider)
        }
        return Array(result.prefix(6))
    }

    // MARK: Actions

    private func start() {
        guard !didStart else { return }
        didStart = true
        if let counterField = form.counterField {
            let readings = HouseholdMutations.readingSeries(of: asset, unit: counterField.unit).readings
            let fallback = asset.value(counterField.key)?.numberValue
            draft.odometerEstimate = OdometerEstimate.value(readings: readings, fallback: fallback, now: Date())
        }
        if let prefill { apply(prefill) }
    }

    private func read(_ payload: CaptureRequest.Payload) {
        readNote = nil
        session.read(payload)
    }

    private func apply(_ result: CaptureResult) {
        let before = draft.ticked.count + draft.extras.count
        if case .new(let name) = draft.provider { newProviderName = name }
        draft.apply(result, form: form)
        if case .new(let name) = draft.provider {
            // A paper from someone already in Oameni picks them, not a duplicate.
            let wanted = SearchText.normalize(name)
            if let known = allProviders.first(where: { SearchText.normalize($0.name) == wanted }) {
                draft.provider = .existing(known.id)
            } else {
                newProviderName = name
            }
        }
        let found = draft.ticked.count + draft.extras.count - before
        draft.documentTitle = CaptureMapping.defaultTitle(for: result.kind, fields: Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first }))
        readNote = draft.document != nil ? form.readNote(found: found) : form.failedNote
    }

    private func save(lowerReading: LowerReadingAnswer? = nil) {
        // One filing at a time: a second tap before the button shows it is busy files nothing.
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // The provider, the visit and the paper are one unit of work: all kept, or
                // none; a paper already in the binder moves to the visit, never left out.
                var filer = CaptureFiler(context: context)
                filer.lowerReading = lowerReading
                let outcome = try await filer.file(.visit(visit))
                receipt = outcome.receipt
                if VisitEnding.showsWhatChanged {
                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { saved = outcome.visit }
                } else {
                    // One ending, as every save: the form closes with the undo toast.
                    close(saving: outcome.receipt)
                }
            } catch let question as ExampleSectionQuestion {
                exampleQuestion = question
            } catch let question as LowerReadingQuestion {
                readingQuestion = question
            } catch {
                errorMessage = SaveFailure.message(for: error, formKept: true)
            }
        }
    }

    /// The visit as saving files it, from the form as it stands: only what its kind asks.
    private var visit: CaptureFiler.Visit {
        draft.filing(on: asset, form: form, provider: providerChoice)
    }

    private var providerChoice: CaptureFiler.Visit.ProviderChoice {
        switch draft.provider {
        case .none: return .none
        case .existing(let id): return allProviders.first { $0.id == id }.map { .existing($0) } ?? .none
        case .new(let name): return .named(name, trade: shape.provider?.trade ?? .other, taxID: draft.providerTaxID)
        }
    }

    private func undo() {
        do {
            guard let receipt else { throw UndoError.unavailable }
            try receipt.undo()
            self.receipt = nil
            saved = nil
            toast = DSToast(title: LocalizedStringResource(stringLiteral: VisitFormWording.undone), systemImage: "arrow.uturn.backward.circle.fill",
                            tint: DS.Palette.accent, actionTitle: nil)
        } catch {
            toast = .failure(error)
        }
    }

    /// The toast a saved visit closes with, in its kind's words.
    private func ending(_ receipt: UndoReceipt?) -> DSToast? {
        receipt.map { VisitEnding.toast($0, saying: shape.toast) }
    }

    /// Ends the flow. Saved and not taken back, the toast goes with it, so the screen
    /// underneath can still offer "Anulează" once this one closes.
    private func finish(_ didSave: Bool) {
        if let onFinish { onFinish(didSave ? ending(receipt) : nil) } else { dismiss() }
    }

    /// Closes the form once the visit is saved. Opened from capture or "Scriu eu", the screen
    /// underneath shows the toast; opened on its own (from a section's page), the shell's host
    /// shows it, so "Anulează" stays once the form has gone.
    private func close(saving receipt: UndoReceipt?) {
        isDone = true
        if let onFinish {
            onFinish(ending(receipt))
        } else {
            if let toast = ending(receipt) { announce(toast) }
            dismiss()
        }
    }
}

/// How the visit form ends once a visit is saved: it closes with the toast every save shows,
/// the kind's words („Vizita e în istoric.”, „Lucrarea e în istoric.”) with "Anulează", which
/// takes the visit, its paper and its firm back. What changed is on the visit's entry in Istoric.
enum VisitEnding {
    /// The first version showed what changed ("Ce s-a schimbat", `VisitSavedView`) with "Închide"
    /// and "Anulează vizita", and from capture a toast with "Anulează" after it: two endings.
    /// Off; kept as a way back until the toast alone is proven. Remove it with the owner's OK.
    nonisolated static let showsWhatChanged = false

    /// The toast a saved visit closes with, wherever the form was opened, in its kind's words
    /// (`VisitShape.toast`).
    @MainActor
    static func toast(_ receipt: UndoReceipt, saying words: String) -> DSToast {
        .undo(LocalizedStringResource(stringLiteral: words), receipt: receipt)
    }
}

/// After saving: what changed, part by part, and a way to take it back. Switched off
/// (`VisitEnding.showsWhatChanged`): the form closes with the undo toast instead.
private struct VisitSavedView: View {
    let entry: HistoryEntry
    let asset: Asset
    let onDone: () -> Void
    let onUndo: () -> Void

    var body: some View {
        let changes = VisitChange.changes(of: entry, on: asset)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(DSStatus.done.color)
                        .accessibilityHidden(true)
                    Text(verbatim: VisitFormWording.savedIn(asset.name))
                        .dsFont(.title)
                    if !entry.effectiveCost.isEmpty {
                        Text(verbatim: VisitFormWording.total(entry.effectiveCost.formatted()))
                            .dsFont(.body, numeric: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader(LocalizedStringKey(VisitFormWording.whatChanged))
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                                    if index > 0 { DS.Hairline() }
                                    DSListRow(
                                        title: Text(verbatim: change.name),
                                        subtitle: Text(verbatim: detail(change)),
                                        systemImage: "checkmark",
                                        tint: DSStatus.done.color,
                                        trailing: { change.cost.map { Text(verbatim: $0.formattedCompact()) } }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .dsPinnedAction {
            DSPrimaryButton(verbatim: VisitFormWording.close, action: onDone)
        } secondary: {
            DSSecondaryButton(verbatim: VisitFormWording.undo, systemImage: "arrow.uturn.backward", role: .destructive, action: onUndo)
        }
        .sensoryFeedback(.success, trigger: entry.id)
        .navigationBarBackButtonHidden()
    }

    private func detail(_ change: VisitChange) -> String {
        let day = DosarFormat.dayMonth(entry.occurredAt)
        guard let previous = change.previous else { return VisitFormWording.firstTime(on: day) }
        return VisitFormWording.before(on: day, previous: DosarFormat.monthYear(previous))
    }
}
