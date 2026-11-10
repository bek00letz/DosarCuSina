import SwiftData
import SwiftUI

/// One visit with many parts: a car service, a vet check-up, a tradesperson's
/// job. Big check rows grouped by the template's components, each with an
/// optional cost and brand; the date, the counter, the total and who did it;
/// and an invoice photo that ticks the rows by itself. One save through
/// `CaptureFiler` (the visit and its invoice together), then a summary of what changed.
struct AddVisitFlow: View {
    let assetID: UUID
    private let prefill: CaptureResult?
    private let embedsNavigation: Bool
    /// Called when the flow ends: with the saved visit's receipt, for the toast's "Anulează",
    /// or nil when nothing was saved.
    private let onFinish: ((UndoReceipt?) -> Void)?

    /// Presented on its own (from a section's Istoric): it brings its own navigation bar.
    init(assetID: UUID) {
        self.assetID = assetID
        self.prefill = nil
        self.embedsNavigation = true
        self.onFinish = nil
    }

    /// Opened from capture with an invoice already read, inside capture's navigation.
    init(assetID: UUID, prefill: CaptureResult?, onFinish: @escaping (UndoReceipt?) -> Void) {
        self.assetID = assetID
        self.prefill = prefill
        self.embedsNavigation = false
        self.onFinish = onFinish
    }

    @Query private var assets: [Asset]

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
            VisitForm(asset: asset, prefill: prefill, onFinish: onFinish)
        } else {
            DSEmptyState("Secțiunea nu mai există", systemImage: "questionmark.folder", message: "Poate a fost ștearsă. Închide și alege alta.")
        }
    }
}

private struct VisitForm: View {
    let asset: Asset
    let prefill: CaptureResult?
    let onFinish: ((UndoReceipt?) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Provider.name) private var allProviders: [Provider]

    @State private var draft = VisitDraft(date: Date())
    @State private var didStart = false
    @State private var source: CaptureSource?
    @State private var isChoosingSource = false
    /// Reading an invoice picked here. It ends with the form: a reading still running stops.
    @State private var session = CaptureSession()
    @State private var readNote: String?
    @State private var errorMessage: String?
    @State private var newProviderName = ""
    @State private var isSaving = false
    @State private var saved: HistoryEntry?
    /// What saving the visit did, for "Anulează vizita": a kept invoice goes back where it was.
    @State private var receipt: UndoReceipt?
    @State private var toast: DSToast?
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var readingQuestion: LowerReadingQuestion?

    private var isReading: Bool { session.phase == .reading }

    private var template: CategoryTemplate? { try? TemplateStore(context: context).template(forKey: asset.templateKey) }

    /// The category's own wording for its visits (`CategoryBehavior.visit`).
    private var wording: VisitWording { template?.behavior.visitWording ?? .standard }

    private var components: [ComponentDefinition] { template?.components ?? [] }

    /// The counter field (km, hours), when the template has one that only goes up.
    private var counterField: FieldDefinition? {
        guard let definition = template?.definition,
              let field = HouseholdMutations.heroMetricField(of: definition),
              MeasurementKind.forUnit(field.unit).isCumulative else { return nil }
        return field
    }

    var body: some View {
        Group {
            if let saved {
                VisitSavedView(entry: saved, asset: asset) { finish(true) } onUndo: { undo() }
            } else {
                form
            }
        }
        .navigationTitle(Text(verbatim: wording.title))
        .navigationBarTitleDisplayMode(.inline)
        .dsToast($toast)
        .task { start() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text(verbatim: asset.name)
                    .dsFont(.title)
                invoiceCard
                checklist
                extrasSection
                detailsSection
                providerSection
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .scrollDismissesKeyboard(.interactively)
        .dsPinnedAction {
            DSPrimaryButton("Salvează vizita", systemImage: "checkmark") { save() }
                .disabled(isSaving || draft.isEmpty)
        } note: {
            if let errorMessage {
                DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
            } else if draft.isEmpty {
                Text("Bifează ce s-a făcut sau scrie totalul ca să poți salva.")
                    .dsFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
        }
        .dsDiscardGuard(hasChanges: !draft.isEmpty && saved == nil)
        .confirmationDialog("Atașează factura", isPresented: $isChoosingSource, titleVisibility: .visible) {
            if CaptureSource.isCameraAvailable { Button("Fotografiază factura") { source = .camera } }
            Button("Alege din poze") { source = .photos }
            Button("Din Fișiere") { source = .files }
            Button("Renunță", role: .cancel) {}
        }
        .captureSourcePicker($source) { payload in
            read(payload)
        } onError: { _ in
            readNote = String(localized: "Poza nu s-a putut deschide. Încearcă din nou.")
        }
        .onChange(of: session.phase) { _, phase in
            switch phase {
            case .read(let result): apply(result)
            case .failed: readNote = String(localized: "Încearcă o poză mai clară. Poți bifa și de mână.")
            default: break
            }
        }
        .examplePrompt($exampleQuestion) { save() }
        .readingPrompt($readingQuestion) { save(lowerReading: $0) }
    }

    // MARK: Invoice

    @ViewBuilder private var invoiceCard: some View {
        if draft.document == nil {
            DSActionCard("Atașează factura", subtitle: "Bifez singur ce scrie pe ea și trec sumele.", systemImage: "doc.viewfinder") {
                isChoosingSource = true
            }
            .disabled(isReading)
            .overlay(alignment: .bottomTrailing) {
                if isReading { DSDelayedProgress(label: "Citesc factura…").padding(DS.Space.s) }
            }
        } else {
            DSNotice(.success, title: "Factura e atașată", message: readNote.map { LocalizedStringKey($0) })
            filedNotice
        }
        if draft.document == nil, let readNote {
            DSNotice(.warning, title: "Factura nu s-a citit", message: LocalizedStringKey(readNote))
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

    /// The visit this invoice was filed with before, as saving will find it.
    private var filed: FiledPaper? {
        visit.filedBefore(keptDocumentID: draft.document?.keptAttachmentID, calendar: .dosar)?.paper
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            DSSectionHeader(LocalizedStringKey(wording.checklistTitle), subtitle: "Atinge ce s-a făcut. Prețul și marca sunt opționale.")
            ForEach(ComponentCatalog.checklist(for: components)) { group in
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
                DSMoneyField("Cât a costat", amount: partCost(component.key), currencyCode: $draft.currency)
                DSTextField("Marcă sau cod", text: partBrand(component.key), prompt: "Opțional")
            }
            .padding(.leading, DS.Space.xl)
        }
    }

    private func lastDone(_ key: String) -> String? {
        guard let last = MaintenanceLog.lastOccurrence(of: key, in: HistoryItemSnapshot.items(of: asset)) else { return nil }
        let date = DosarFormat.monthYear(last.date)
        return String(localized: "Ultima dată: \(date)")
    }

    private func partCost(_ key: String) -> Binding<Decimal?> {
        Binding(get: { draft.parts[key]?.cost }, set: { draft.parts[key, default: VisitDraft.Part()].cost = $0 })
    }

    private func partBrand(_ key: String) -> Binding<String> {
        Binding(get: { draft.parts[key]?.brand ?? "" }, set: { draft.parts[key, default: VisitDraft.Part()].brand = $0 })
    }

    // MARK: Extras

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Altceva", subtitle: "Ce nu e în listă.")
            ForEach($draft.extras) { $extra in
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSTextField("Ce s-a făcut", text: $extra.name)
                        DSMoneyField("Cât a costat", amount: $extra.cost, currencyCode: $draft.currency)
                        Button("Scoate rândul", role: .destructive) {
                            draft.extras.removeAll { $0.id == extra.id }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            DSSecondaryButton("Adaugă altceva", systemImage: "plus") {
                draft.extras.append(VisitDraft.Extra(name: "", cost: nil))
            }
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Detalii")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    DatePicker(selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date) {
                        Text("Data").dsFont(.headline)
                    }
                    .frame(minHeight: 44)
                    if let counterField, let unit = counterField.unit {
                        DSMetricField(LocalizedStringKey(counterField.label), value: Binding(
                            get: { draft.odometer },
                            set: { draft.odometer = $0; draft.odometerSource = .person }
                        ), unit: unit,
                                      footnote: draft.odometer == nil && draft.odometerEstimate != nil
                                          ? "Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi." : nil,
                                      placeholder: draft.odometerEstimate)
                    }
                    DSMoneyField("Total plătit", amount: $draft.total, currencyCode: $draft.currency,
                                 footnote: partsSumNote)
                }
            }
        }
    }

    private var partsSumNote: LocalizedStringKey? {
        guard draft.total == nil, let sum = draft.partsSum else { return nil }
        let text = Money(sum, currency: draft.currency).formattedCompact()
        return "Piesele adună \(text). Lasă gol dacă ăsta e totalul."
    }

    // MARK: Provider

    private var providerSection: some View {
        let candidates = providerCandidates
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(LocalizedStringKey(wording.providerTitle))
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { DS.Hairline() }
                        DSCheckRow(
                            title: Text(verbatim: provider.name),
                            subtitle: provider.rating.map { Text("Notă \($0.formatted(.number.precision(.fractionLength(0...1)).locale(.dosarDefault))) din 5") },
                            isOn: draft.provider == .existing(provider.id),
                            action: { draft.provider = draft.provider == .existing(provider.id) ? .none : .existing(provider.id) }
                        )
                    }
                    if !candidates.isEmpty { DS.Hairline() }
                    DSTextField(candidates.isEmpty ? "Nume" : "Altcineva", text: Binding(
                        get: { if case .new(let name) = draft.provider { return name } else { return newProviderName } },
                        set: { name in
                            newProviderName = name
                            draft.provider = name.trimmingCharacters(in: .whitespaces).isEmpty ? .none : .new(name)
                        }
                    ), prompt: "Service Exemplu SRL")
                    if draft.provider != .none {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Cum a lucrat?").dsFont(.footnote)
                            DSStarRating(rating: draft.rating.map(Double.init)) { draft.rating = $0 }
                        }
                        .transition(DS.Motion.transition(from: .top, reduceMotion: reduceMotion))
                    }
                }
            }
        }
        .dsAnimation(value: draft.provider)
    }

    /// People who worked on this asset first, then others with the right trade.
    private var providerCandidates: [Provider] {
        let directory = ProviderDirectory(context: context)
        var result = directory.providers(for: asset)
        let trade = wording.trade
        for provider in allProviders where provider.has(trade) && !result.contains(where: { $0.id == provider.id }) {
            result.append(provider)
        }
        return Array(result.prefix(6))
    }

    // MARK: Actions

    private func start() {
        guard !didStart else { return }
        didStart = true
        let readings = HouseholdMutations.readingSeries(of: asset, unit: counterField?.unit).readings
        let fallback = counterField.flatMap { asset.value($0.key)?.numberValue }
        draft.odometerEstimate = counterField == nil ? nil : OdometerEstimate.value(readings: readings, fallback: fallback, now: Date())
        if let prefill { apply(prefill) }
    }

    private func read(_ payload: CaptureRequest.Payload) {
        readNote = nil
        session.read(payload)
    }

    private func apply(_ result: CaptureResult) {
        let before = draft.ticked.count + draft.extras.count
        if case .new(let name) = draft.provider { newProviderName = name }
        draft.apply(result, components: components)
        if case .new(let name) = draft.provider {
            // An invoice from someone already in Oameni picks them, not a duplicate.
            let wanted = SearchText.normalize(name)
            if let known = allProviders.first(where: { SearchText.normalize($0.name) == wanted }) {
                draft.provider = .existing(known.id)
            } else {
                newProviderName = name
            }
        }
        let found = draft.ticked.count + draft.extras.count - before
        draft.documentTitle = CaptureMapping.defaultTitle(for: result.kind, fields: Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first }))
        if draft.document != nil {
            readNote = found > 0
                ? String(localized: "Am bifat \(found) rânduri de pe factură. Verifică-le.")
                : String(localized: "Nu am găsit rânduri de bifat. Bifează de mână.")
        } else {
            readNote = String(localized: "Încearcă o poză mai clară. Poți bifa și de mână.")
        }
    }

    private func save(lowerReading: LowerReadingAnswer? = nil) {
        // One filing at a time: a second tap before the button shows it is busy files nothing.
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // The provider, the visit and the invoice are one unit of work: all kept, or
                // none; an invoice already in the binder moves to the visit, never left out.
                var filer = CaptureFiler(context: context)
                filer.lowerReading = lowerReading
                let outcome = try await filer.file(.visit(visit))
                receipt = outcome.receipt
                withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { saved = outcome.visit }
            } catch let question as ExampleSectionQuestion {
                exampleQuestion = question
            } catch let question as LowerReadingQuestion {
                readingQuestion = question
            } catch {
                errorMessage = SaveFailure.message(for: error, formKept: true)
            }
        }
    }

    /// The visit as saving files it, from the form as it stands.
    private var visit: CaptureFiler.Visit {
        CaptureFiler.Visit(
            asset: asset,
            kind: wording.kind,
            occurredAt: draft.date,
            checklist: draft.checklistItems,
            extraItems: draft.extraItems,
            totalCost: draft.totalMoney,
            odometer: draft.odometer,
            odometerSource: draft.odometerSource,
            provider: providerChoice,
            rating: draft.rating,
            document: draft.document,
            documentTitle: draft.documentTitle,
            documentText: draft.documentText,
            reference: draft.reference,
            isAnotherInvoice: draft.isAnotherInvoice
        )
    }

    private var providerChoice: CaptureFiler.Visit.ProviderChoice {
        switch draft.provider {
        case .none: return .none
        case .existing(let id): return allProviders.first { $0.id == id }.map { .existing($0) } ?? .none
        case .new(let name): return .named(name, trade: wording.trade, taxID: draft.providerTaxID)
        }
    }

    private func undo() {
        do {
            guard let receipt else { throw UndoError.unavailable }
            try receipt.undo()
            self.receipt = nil
            saved = nil
            toast = DSToast(title: "Vizita a fost anulată.", systemImage: "arrow.uturn.backward.circle.fill", tint: DS.Palette.accent, actionTitle: nil)
        } catch {
            toast = .failure(error)
        }
    }

    /// Ends the flow. Saved and not taken back, the receipt goes with it, so the screen
    /// underneath can still offer "Anulează" once this one closes.
    private func finish(_ didSave: Bool) {
        if let onFinish { onFinish(didSave ? receipt : nil) } else { dismiss() }
    }
}

/// After saving: what changed, part by part, and a way to take it back.
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
                    Text("Salvat în istoricul \(asset.name)")
                        .dsFont(.title)
                    if !entry.effectiveCost.isEmpty {
                        Text("Total: \(entry.effectiveCost.formatted())")
                            .dsFont(.body, numeric: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader("Ce s-a schimbat")
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
            DSPrimaryButton("Gata", action: onDone)
        } secondary: {
            DSSecondaryButton("Anulează vizita", systemImage: "arrow.uturn.backward", role: .destructive, action: onUndo)
        }
        .sensoryFeedback(.success, trigger: entry.id)
        .navigationBarBackButtonHidden()
    }

    private func detail(_ change: VisitChange) -> String {
        let day = DosarFormat.dayMonth(entry.occurredAt)
        guard let previous = change.previous else {
            return String(localized: "Pe \(day). Prima dată în dosar.")
        }
        let before = DosarFormat.monthYear(previous)
        return String(localized: "Pe \(day). Înainte: \(before).")
    }
}
