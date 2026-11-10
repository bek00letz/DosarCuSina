import SwiftData
import SwiftUI

/// What is being read again while the review stays on screen.
enum CaptureReread: Hashable, Sendable {
    /// The pages the person added (the back of a card), read with the others.
    case pages
    /// The person's AI provider, on a tap or by itself after a weak reading.
    case cloud
}

/// The confirm step of capture: what the document is, the values read from it
/// (the uncertain ones marked), where it goes, and the reminder it sets.
/// "Salvează" runs `CaptureFiler.save`, the one save path.
struct CaptureReviewView: View {
    @State var review: CaptureReview
    let assets: [Asset]
    var onReadWithCloud: (() -> Void)?
    /// Adds pages (the back of a card) and reads the document again.
    var onAddPages: ((CaptureRequest.Payload) -> Void)?
    /// What is being read again, if anything.
    var rereading: CaptureReread?
    /// The newest reading; merged into the review, keeping the person's edits.
    var rereadResult: CaptureResult?
    /// Why the last reading again didn't work.
    var readAgainError: String?
    /// "Citește automat" wants to send this identity document's photo: ask first.
    var asksToSendToProvider = false
    /// The answer to "Trimit poza la <provider>?".
    var onAnswerSending: ((Bool) -> Void)?
    let onClose: (CaptureFlowResult) -> Void

    init(
        review: CaptureReview,
        assets: [Asset],
        onReadWithCloud: (() -> Void)? = nil,
        onAddPages: ((CaptureRequest.Payload) -> Void)? = nil,
        rereading: CaptureReread? = nil,
        rereadResult: CaptureResult? = nil,
        readAgainError: String? = nil,
        asksToSendToProvider: Bool = false,
        onAnswerSending: ((Bool) -> Void)? = nil,
        onClose: @escaping (CaptureFlowResult) -> Void
    ) {
        self._review = State(initialValue: review)
        self.assets = assets
        self.onReadWithCloud = onReadWithCloud
        self.onAddPages = onAddPages
        self.rereading = rereading
        self.rereadResult = rereadResult
        self.readAgainError = readAgainError
        self.asksToSendToProvider = asksToSendToProvider
        self.onAnswerSending = onAnswerSending
        self.onClose = onClose
    }

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]

    @State private var isPickingDestination = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var cloudMessage: String?
    @State private var saveRequest: ReminderSaveRequest?
    /// The pages waiting to be filed, as read; shown with the person's choices on top.
    @State private var processed: ProcessedDocument?
    @State private var isShowingPages = false
    @State private var backSource: CaptureSource?
    @State private var backError: String?
    /// The person added something to an example section: "Păstrezi … ca al tău?".
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var readingQuestion: LowerReadingQuestion?

    private var templatesByKey: [String: CategoryTemplate] {
        Dictionary(templates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// What saving will do, as the review stands now: what it shows is what happens.
    private var plan: CaptureFilingPlan {
        CaptureFilingPlan.make(for: review, templates: templatesByKey, assets: assets, today: CalendarDay(Date()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                documentCard
                notices
                fieldsSection
                destinationSection
                if review.kind.profile.photoIsOptIn {
                    KeepPhotoChoice(keepsPhoto: $review.keepsPhotoOnRequest)
                }
                reminderSection
            }
            .padding(DS.Space.m)
        }
        .dsPinnedAction {
            DSPrimaryButton("Salvează", systemImage: "checkmark") {
                requestSave()
            }
            .disabled(isSaving)
        } note: {
            if let errorMessage {
                DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
            }
        }
        .background(DS.Palette.background)
        .navigationTitle("Verifică actul")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
        }
        .dsDiscardGuard(hasChanges: !isSaving)
        .reminderPermissionGate($saveRequest)
        .sheet(isPresented: $isPickingDestination) {
            CaptureDestinationPicker(
                destination: Binding(get: { review.destination }, set: { review.choosePlace($0) }),
                newAssetName: $review.newAssetName, templates: templates, assets: assets,
                offersNewHolder: review.kind.isPersonalDocument,
                filesUnderSubscription: review.kind.profile.filing == .subscription
            )
        }
        .fullScreenCover(isPresented: $isShowingPages) {
            DocumentPagesViewer(pages: pageSources, editing: .review($review.pageChoices))
        }
        .captureSourcePicker($backSource, onPicked: { payload in
            backError = nil
            onAddPages?(payload)
        }, onError: { _ in
            backError = String(localized: "Poza nu s-a putut deschide. Încearcă din nou.")
        })
        .task(id: review.documentID) { await loadPages() }
        .task(id: review.result.id) { await explainCloudFailure() }
        .onChange(of: rereadResult?.id) { _, _ in mergeReread() }
        .examplePrompt($exampleQuestion) { save() }
        .readingPrompt($readingQuestion) { save(lowerReading: $0) }
        // The pages belong to the capture session, which lets go of them when the capture ends.
    }

    // MARK: Document

    private var documentCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(alignment: .top, spacing: DS.Space.s) {
                    Button { DocumentPagesViewer.present(reduceMotion: reduceMotion) { isShowingPages = true } } label: {
                        Group {
                            if let first = pageSources.first {
                                DocumentPageImage(source: first, maxLongEdge: 360, contentMode: .fill)
                            } else {
                                Image(systemName: "doc.text").font(.title).foregroundStyle(DS.Palette.secondaryLabel)
                            }
                        }
                        .frame(width: 64, height: 84)
                        .background(DS.Palette.fill)
                        .clipShape(ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.dsPressable)
                    .disabled(pageSources.isEmpty)
                    .accessibilityLabel(Text("Vezi actul mare", comment: "VoiceOver label of the document thumbnail in the review."))
                    .accessibilityHint(Text("Se deschide pe tot ecranul. Poți mări sau roti pagina.", comment: "VoiceOver hint of the document thumbnail."))

                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(verbatim: CaptureMapping.kindTitle(review.kind))
                            .dsFont(.title)
                        Menu {
                            Picker(selection: Binding(get: { review.kind }, set: { chooseKind($0) })) {
                                ForEach(CaptureDocumentKind.allCases, id: \.self) { kind in
                                    Text(verbatim: CaptureMapping.kindTitle(kind)).tag(kind)
                                }
                            } label: { Text("Ce act e") }
                        } label: {
                            Text("Nu e asta? Schimbă")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        ForEach(review.kindAlternatives, id: \.self) { alternative in
                            CaptureAlternativeNote(text: kindAlternativeText(alternative)) {
                                chooseKind(alternative.value, from: alternative)
                            }
                            .transition(.opacity)
                        }
                        Text(verbatim: tierNote)
                            .dsFont(.footnote)
                    }
                }
                cropChoice
            }
        }
    }

    /// Another kind, the person's choice: the page is read again as that kind, keeping their edits.
    private func chooseKind(_ kind: CaptureDocumentKind, from alternative: CaptureAlternative<CaptureDocumentKind>? = nil) {
        let read = review.choosingKind(kind, from: alternative, assets: assets, context: context)
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review = read }
    }

    /// "Pe telefon părea: Factură de utilități", beside a kind another reader didn't keep.
    private func kindAlternativeText(_ alternative: CaptureAlternative<CaptureDocumentKind>) -> String {
        let kind = CaptureMapping.kindTitle(alternative.value)
        return switch alternative.source {
        case .phone: String(localized: "Pe telefon părea: \(kind)", comment: "The kind the phone read, beside the AI provider's.")
        case .cloudModel: CaptureAlternativeNote.readBy(cloudProvider, value: kind)
        case .checked: String(localized: "Codul de jos al actului arată: \(kind)", comment: "The kind the checked machine-readable zone shows.")
        }
    }

    private var tierNote: String {
        if review.usedCloudModel {
            return String(localized: "Citit și cu \(cloudProvider.shortName), cu cheia ta.", comment: "The AI provider read the document too. The argument is the provider's short name.")
        }
        switch review.mainTier {
        case .onDeviceModel?: return String(localized: "Citit pe telefon, cu Apple Intelligence.")
        default: return String(localized: "Citit pe telefon. Nimic n-a plecat de aici.")
        }
    }

    /// The back of an identity card, when only the front was read.
    @ViewBuilder private var backPageNotice: some View {
        if review.asksForBackPage || rereading == .pages {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSNotice(.info, title: "Ai și o poză cu spatele? Acolo e codul care confirmă datele.")
                if rereading == .pages {
                    DSDelayedProgress(label: "Citesc și spatele…")
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else if onAddPages != nil {
                    if CaptureSource.isCameraAvailable {
                        DSSecondaryButton("Fotografiază spatele", systemImage: "camera") { backSource = .camera }
                    }
                    DSSecondaryButton("Alege din poze", systemImage: "photo.on.rectangle") { backSource = .photos }
                }
                if let message = backError ?? (rereading == nil ? readAgainError : nil) {
                    DSNotice(.error, title: "Nu am putut citi spatele", message: LocalizedStringKey(message))
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var notices: some View {
        backPageNotice
        if let filed = plan.filedBill {
            // A bill already in the binder: the same photo, or another photo of the same bill.
            DSFiledPaperNotice(filed: filed, paper: .bill, onOpen: {
                onClose(.dismissed)
                AppNavigator.shared.open(.historyEntry(filed.entryID))
            }, onAnother: { review.isAnotherBill = true })
        } else if let duplicate = review.duplicateAttachmentID {
            DSNotice(.info, title: "Ai mai adăugat poza asta", message: "Dacă salvezi, o pun la locul ales mai jos, împreună cu ce am citit.", actionTitle: "Vezi unde e acum") {
                onClose(.dismissed)
                AppNavigator.shared.open(.document(duplicate))
            }
        }
        ForEach(Array(review.result.notices.enumerated()), id: \.offset) { _, notice in
            switch notice {
            case .littleTextRecognized:
                DSNotice(.info, title: "Poza e greu de citit", message: "O poză nouă, dreaptă și fără reflexii, ajută.")
            case .pagesTruncated(let read, _):
                DSNotice(.info, title: "Am citit primele \(read) pagini", message: "E un document lung. Se păstrează tot, cu toate paginile.")
            case .machineReadableZoneUnverified:
                DSNotice(.warning, title: "Verifică numărul și datele", message: "Codul de jos al actului nu s-a citit sigur.")
            default:
                EmptyView()
            }
        }
        if let cloudMessage {
            DSNotice(.warning, title: "\(cloudProvider.name) nu a citit actul", message: LocalizedStringKey(cloudMessage))
        }
        if asksToSendToProvider, let onAnswerSending {
            // An identity document's photo never leaves the phone by itself: one question, for this document.
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSNotice(.info, title: "Trimit poza la \(cloudProvider.name)?",
                         message: "Nu sunt sigur ce am citit. \(cloudProvider.name) poate citi actul mai bine, cu cheia ta. Fără un da, poza rămâne pe telefon.")
                DSSecondaryButton("Trimite poza", systemImage: "sparkles") { onAnswerSending(true) }
                DSSecondaryButton("Nu, rămâne pe telefon", systemImage: "iphone") { onAnswerSending(false) }
                if let policy = cloudProvider.dataPolicyURL {
                    Link(destination: policy) {
                        Text("Cum folosește \(cloudProvider.name) ce trimiți", comment: "Link to the AI provider's data-use terms.")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .dsFont(.footnote)
                }
            }
            .transition(.opacity)
        }
        // A bank card, or a page that may be one, is read only on the phone: no button, and
        // one plain line so the person isn't left wondering where it went.
        if onReadWithCloud != nil, CaptureRunner.hasCloudKey, !review.usedCloudModel, !review.providerMayRead {
            Text("Cardurile bancare se citesc doar pe telefon.", comment: "Capture review: why a bank card can't be read by the AI provider.")
                .dsFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Offered whenever a provider is set up, whatever the phone read: a confident
        // reading can be wrong too, and only a second opinion can tell.
        if let onReadWithCloud, CaptureRunner.hasCloudKey, !review.usedCloudModel, !asksToSendToProvider, review.providerMayRead {
            if rereading == .cloud {
                DSDelayedProgress(label: "Citesc cu \(cloudProvider.shortName)…")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                DSSecondaryButton("Citește mai bine cu \(cloudProvider.shortName)", systemImage: "sparkles", action: onReadWithCloud)
                    .disabled(rereading != nil)
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                if review.kind.isPersonalDocument {
                    Text("Poza actului se trimite la \(cloudProvider.name), cu cheia ta.")
                } else {
                    Text("Prima pagină se trimite la \(cloudProvider.name), cu cheia ta.")
                }
                if let policy = cloudProvider.dataPolicyURL {
                    Link(destination: policy) {
                        Text("Cum folosește \(cloudProvider.name) ce trimiți", comment: "Link to the AI provider's data-use terms.")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
            .dsFont(.footnote)
        }
    }

    /// The AI provider the person set up in Settings.
    private var cloudProvider: AIProvider { AIProviderSettings.standard.provider }

    // MARK: Fields

    @ViewBuilder private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Ce am citit", subtitle: review.visibleFields.contains(where: \.needsCheck) ? "Verifică ce e marcat." : nil)
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    DSTextField("Numele actului", text: $review.title)
                    let fields = review.visibleFields
                    if fields.isEmpty {
                        Text("Nu am găsit date pe act. Îl păstrez oricum, cu numele de mai sus.")
                            .dsFont(.subheadline)
                    }
                    ForEach(fields) { field in
                        if let index = review.fields.firstIndex(where: { $0.id == field.id }) {
                            CaptureFieldEditor(field: $review.fields[index], kind: review.kind)
                        }
                    }
                    let addable = review.addableKeys
                    if !addable.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Nu am găsit pe act:")
                                .dsFont(.footnote)
                            ForEach(addable, id: \.self) { key in
                                Button {
                                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review.addField(key) }
                                } label: {
                                    Label("Adaugă: \(CaptureMapping.label(for: key))", systemImage: "plus.circle")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    if review.showsLineItems {
                        CaptureLineItemsEditor(lines: $review.lineItems, currency: review.value(.total)?.money?.currency ?? Money.defaultCurrency)
                    }
                    // A policy's class is the person's, never the car's: say where it goes, or why it doesn't.
                    if let bonusMalus = CaptureFilingPlan.bonusMalus(for: review, people: Policyholders.people(in: assets, templates: templatesByKey)) {
                        Text(bonusMalusText(bonusMalus))
                            .dsFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    // A bill's index goes to its subscription's meter: say where, as saving will do it.
                    if let meter = plan.meter {
                        Label { Text(verbatim: meter.sentence).dsFont(.footnote) } icon: {
                            Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(DS.Palette.secondaryLabel)
                        }
                        .labelStyle(DSLeadingIconLabelStyle())
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    // MARK: Destination

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Unde îl pun")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Button { isPickingDestination = true } label: {
                        DSListRow(
                            title: Text(verbatim: destinationTitle),
                            subtitle: Text(verbatim: destinationSubtitle),
                            systemImage: destinationSymbol,
                            showsChevron: true,
                            trailing: { Text("Alege alta") }
                        )
                    }
                    .buttonStyle(.plain)
                    if let check = review.placeCheck {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Label("Verifică", systemImage: "exclamationmark.circle.fill")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(DSStatus.soon.textColor)
                            Text(placeCheckText(check))
                                .dsFont(.footnote)
                        }
                        .accessibilityElement(children: .combine)
                        .transition(.opacity)
                    }
                    if case .newAsset(let key) = review.destination {
                        DSTextField(newAssetNameTitle(key), text: $review.newAssetName, isRequired: true)
                    }
                }
            }
        }
    }

    /// A printed line, kept short enough to read in a row: cut at a word, with "…".
    static func shortened(_ text: String, limit: Int = 90) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    /// Where a policy's bonus-malus class goes, in a line under what was read.
    private func bonusMalusText(_ choice: CaptureFilingPlan.BonusMalus) -> LocalizedStringKey {
        switch choice {
        case .keep(_, _, let name): "Clasa bonus-malus o păstrez la \(name): e a celui asigurat, nu a mașinii."
        case .noPolicyholder: "Clasa bonus-malus n-o păstrez: pe poliță nu scrie cine e asiguratul."
        case .notInHousehold(let name): "Clasa bonus-malus n-o păstrez: \(name) nu e printre persoanele din dosar. Adaugă persoana și citește polița din nou."
        }
    }

    /// Why the home was chosen without being sure: the supply address only partly agrees.
    private func placeCheckText(_ check: SubscriptionMatcher.HouseCheck) -> LocalizedStringKey {
        switch check {
        case .addressPartlyAgrees: "Adresa locului de consum seamănă cu cea a locuinței, dar nu e chiar aceeași."
        case .addressDiffers: "Adresa locului de consum nu e cea a locuinței."
        }
    }

    /// The part the category `key` plays (a person, a subscription, a home), if any.
    private func role(of key: String) -> CategoryBehavior.Role? {
        templatesByKey[key]?.behavior.role
    }

    private var filesUnderSubscription: Bool { review.kind.profile.filing == .subscription }

    private func newAssetNameTitle(_ key: String) -> LocalizedStringKey {
        switch role(of: key) {
        case .holder?: "Numele persoanei"
        case .subscription?: "Numele abonamentului"
        case .home? where filesUnderSubscription: "Numele locuinței"
        default: "Numele secțiunii noi"
        }
    }

    private var destinationTitle: String {
        switch review.destination {
        case .none: return String(localized: "Doar păstrez actul")
        case .asset(let id): return assets.first { $0.id == id }?.name ?? String(localized: "Secțiune ștearsă")
        case .newAsset(let key) where role(of: key) == .holder:
            return String(localized: "Persoană nouă: \(review.newAssetName)")
        case .newAsset(let key) where role(of: key) == .subscription:
            return String(localized: "Abonament nou: \(review.newAssetName)")
        case .newAsset(let key): return String(localized: "Secțiune nouă în \(templatesByKey[key]?.name ?? key)")
        }
    }

    private var destinationSubtitle: String {
        switch review.destination {
        case .none: return String(localized: "Îl găsești în Caută.")
        case .asset(let id):
            guard let asset = assets.first(where: { $0.id == id }) else { return "" }
            if role(of: asset.templateKey) == .holder { return String(localized: "Actul stă la actele acestei persoane.") }
            if filesUnderSubscription {
                if let subscription = review.existingSubscription(assets: assets), subscription.id != asset.id {
                    return String(localized: "La abonamentul „\(subscription.name)”")
                }
                if role(of: asset.templateKey) == .home {
                    return String(localized: "Abonament nou aici: \(CaptureFiler.subscriptionName(review))")
                }
                if let parent = asset.parent { return String(localized: "Abonament la \(parent.name)") }
            }
            return templatesByKey[asset.templateKey]?.name ?? ""
        case .newAsset(let key) where role(of: key) == .holder:
            return String(localized: "Se adaugă în Acte când salvezi.")
        case .newAsset(let key) where role(of: key) == .home && filesUnderSubscription:
            return String(localized: "Se creează când salvezi, cu abonamentul „\(CaptureFiler.subscriptionName(review))”.")
        case .newAsset: return String(localized: "Se creează când salvezi.")
        }
    }

    private var destinationSymbol: String {
        switch review.destination {
        case .none: return "tray"
        case .asset(let id):
            let asset = assets.first { $0.id == id }
            return asset?.symbolOverride ?? asset.flatMap { templatesByKey[$0.templateKey]?.symbol } ?? "folder"
        case .newAsset(let key) where role(of: key) == .holder: return "person.crop.circle.badge.plus"
        case .newAsset(let key): return templatesByKey[key]?.symbol ?? "folder.badge.plus"
        }
    }

    // MARK: Reminder

    @ViewBuilder private var reminderSection: some View {
        let text = CaptureReminderPreview.text(for: review, templates: templatesByKey, assets: assets, today: CalendarDay(Date()))
        let directDebit = review.directDebitStatement(assets: assets)
        if text != nil || review.kind.profile.deadlineIsOptIn || directDebit != nil {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Când te anunț")
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        if let directDebit {
                            // What the bill says, offered: turned on only by the person.
                            DSCheckRow(title: Text("Plătesc prin debit direct"),
                                       subtitle: Text("Pe factură scrie: „\(Self.shortened(directDebit))”. Dacă e așa, nu îți mai amintesc s-o plătești."),
                                       isOn: review.turnsOnDirectDebit) {
                                withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review.turnsOnDirectDebit.toggle() }
                            }
                        }
                        if review.kind.profile.deadlineIsOptIn, review.reminderDay != nil, !review.paysByDirectDebit(assets: assets) {
                            DSCheckRow(title: Text("Amintește-mi să o plătesc"), isOn: review.remindsToPay) {
                                review.remindsToPay.toggle()
                            }
                        }
                        if let text {
                            Label { Text(verbatim: text).dsFont(.body) } icon: {
                                Image(systemName: "bell").foregroundStyle(DS.Palette.accent)
                            }
                        }
                        Text("Poți schimba după, pe pagina termenului.")
                            .dsFont(.footnote)
                    }
                }
            }
        }
    }

    // MARK: Saving

    private func requestSave() {
        guard !isSaving else { return }
        errorMessage = nil
        let filer = CaptureFiler(context: context)
        if filer.touchesReminders(review) {
            saveRequest = ReminderSaveRequest { save() }
        } else {
            save()
        }
    }

    private func save(lowerReading: LowerReadingAnswer? = nil) {
        // One filing at a time: a second tap before the button shows it is busy files nothing.
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                var filer = CaptureFiler(context: context)
                filer.lowerReading = lowerReading
                let outcome = try await filer.save(review)
                onClose(.filing(in: outcome.asset?.name, assetID: outcome.asset?.id, receipt: outcome.receipt))
            } catch let question as ExampleSectionQuestion {
                isSaving = false
                exampleQuestion = question
            } catch let question as LowerReadingQuestion {
                isSaving = false
                readingQuestion = question
            } catch {
                isSaving = false
                errorMessage = SaveFailure.message(for: error, formKept: true)
            }
        }
    }

    private func loadPages() async {
        guard let id = review.documentID else { return processed = nil }
        processed = await CaptureDocumentStore.shared().processed(id: id)
    }

    /// The document's pages as they will be kept: as read, with the person's turns and
    /// crop choices on top; for a photo already in the binder, its kept pages.
    private var pageSources: [DocumentPageSource] {
        if let processed { return DocumentPages.sources(of: processed, choices: review.pageChoices) }
        if let id = review.duplicateAttachmentID, let kept = AttachmentActions(context: context).attachment(id: id) {
            return DocumentPages.sources(of: kept, framing: kept.framing.applying(review.pageChoices))
        }
        return []
    }

    /// "Folosește poza întreagă" for every page cut out of its photo, or the cut-out again.
    private var cropChoice: some View {
        let croppable = pageSources.filter(\.framing.hasCrop)
        let showsCrop = croppable.contains(where: \.framing.showsCrop)
        return Group {
            if !croppable.isEmpty {
                DSAdaptiveStack(spacing: DS.Space.s) {
                    Text(showsCrop
                         ? String(localized: "Am păstrat doar actul, fără ce e în jur.", comment: "The review: the document was cut out of its photo.")
                         : String(localized: "Se păstrează poza întreagă.", comment: "The review: the whole photo is kept, not the cut-out."))
                        .dsFont(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsCrop {
                        DSCompactButton("Folosește poza întreagă", systemImage: "photo") { chooseWholePhoto(true, on: croppable) }
                    } else {
                        DSCompactButton("Doar actul", systemImage: "crop") { chooseWholePhoto(false, on: croppable) }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func chooseWholePhoto(_ whole: Bool, on pages: [DocumentPageSource]) {
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
            for page in pages { review.pageChoices[page.index] = page.framing.showingWholePhoto(whole).choice }
        }
    }

    /// Merges the newest reading into the review, keeping everything the person changed.
    /// The capture session lets go of pages a reading with added pages replaced.
    private func mergeReread() {
        guard let result = rereadResult, result.id != review.result.id else { return }
        let merged = CaptureReview(result: result, assets: assets, context: context).carryingEdits(from: review, assets: assets)
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review = merged }
    }

    /// Says what went wrong with the cloud reading: offline, the key, the quota, the model.
    private func explainCloudFailure() async {
        cloudMessage = nil
        for notice in review.result.notices {
            guard case .cloudModelFailed(let reason) = notice else { continue }
            cloudMessage = AIProviderError(code: reason).message(provider: cloudProvider)
        }
    }
}

/// One value read from the document: editable, with where it was read from.
private struct CaptureFieldEditor: View {
    @Binding var field: CaptureReview.Field
    /// The document's kind, for how a checked value is named.
    let kind: CaptureDocumentKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            editor
            if field.needsCheck {
                Label("Verifică", systemImage: "exclamationmark.circle.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DSStatus.soon.textColor)
            }
            // What other readers read: offered beside the value, never applied by itself.
            ForEach(field.alternatives, id: \.self) { alternative in
                CaptureAlternativeNote(text: alternativeText(alternative)) {
                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { field.use(alternative) }
                }
                .transition(.opacity)
            }
            if let source = sourceText {
                Text(source)
                    .dsFont(.footnote)
                    .lineLimit(2)
                    .accessibilityLabel(Text("Citit din: \(String(source.characters))"))
            }
        }
    }

    /// "Pe telefon am citit: …", "Gemini a citit: …", "Pe spatele actului scrie: …".
    private func alternativeText(_ alternative: CaptureAlternative<CaptureValue>) -> String {
        let value = CaptureMapping.displayText(alternative.value)
        return switch alternative.source {
        case .phone:
            String(localized: "Pe telefon am citit: \(value)", comment: "The phone's value, beside the AI provider's.")
        case .cloudModel:
            CaptureAlternativeNote.readBy(AIProviderSettings.standard.provider, value: value)
        case .checked(machineReadable: true) where kind == .identityCard:
            String(localized: "Pe spatele actului scrie: \(value)", comment: "What the machine-readable zone on the back of the card says.")
        case .checked(machineReadable: true):
            String(localized: "În codul de jos al actului scrie: \(value)", comment: "What the machine-readable zone says.")
        case .checked:
            String(localized: "Pe act scrie: \(value)", comment: "A value that passed its own check digit, beside a different one.")
        }
    }

    @ViewBuilder private var editor: some View {
        let title = LocalizedStringKey(field.label)
        if let choices = CaptureMapping.choices(for: field.key, kind: kind) {
            // A choice, kept as its stable key: the service, a policy's cover.
            DSChoiceField(title, selection: Binding(
                get: { field.value?.text.flatMap { choices.option(for: $0)?.key } },
                set: { key in field.confirm(key.map(CaptureValue.text)) }
            ), options: choices.map(\.key)) { key in choices.option(for: key)?.label ?? key }
        } else {
            valueEditor(title)
        }
    }

    /// What kind of editor a value needs: from the value read, or, for an expected field the
    /// person added empty, from what that field holds. It stays the same while they type,
    /// so the editor keeps its focus.
    private enum EditorKind {
        case date
        case money(currencyCode: String)
        /// A number, with its unit when it is a reading ("km").
        case number(unit: MeasurementUnit?)
        case text
    }

    private var editorKind: EditorKind {
        switch field.value {
        case .day?: .date
        case .money(let money)?: .money(currencyCode: money.currency)
        case .number?: .number(unit: nil)
        case .metric(_, let unit)?: .number(unit: unit)
        case nil:
            switch ModelQuestions.format(of: field.key) {
            case .date: .date
            case .money: .money(currencyCode: Money.defaultCurrency)
            case .integer: .number(unit: field.key == .odometer ? .kilometres : nil)
            case .meterIndex: .number(unit: nil)
            default: .text
            }
        default: .text
        }
    }

    @ViewBuilder private func valueEditor(_ title: LocalizedStringKey) -> some View {
        switch editorKind {
        case .date:
            DSDateField(title, date: Binding(
                get: { field.value?.day?.startDate() },
                set: { field.confirm($0.map { .day(CalendarDay($0)) }) }
            ))
        case .money(let currencyCode):
            DSMoneyField(title, amount: Binding(
                get: { field.value?.money?.amount },
                set: { amount in field.confirm(amount.map { .money(Money($0, currency: field.value?.money?.currency ?? currencyCode)) }) }
            ), currencyCode: Binding(
                get: { field.value?.money?.currency ?? currencyCode },
                set: { code in if let amount = field.value?.money?.amount { field.confirm(.money(Money(amount, currency: code))) } }
            ))
        case .number(let unit):
            // The one number field: what it can't read clearly it refuses in the field.
            DSMetricField(title, value: Binding(
                get: { Self.number(of: field.value) },
                set: { number in field.confirm(number.map { Self.value(Decimal($0).rounded(scale: 6), unit: unit) }) }
            ), unit: unit, fractionDigits: 0...3)
        case .text:
            DSTextField(title, text: Binding(
                get: { Self.text(of: field.value) },
                set: { text in field.confirm(Self.value(text, like: field.value)) }
            ))
        }
    }

    /// The bit of the document the value came from, with the value highlighted.
    private var sourceText: AttributedString? {
        guard let source = field.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { return nil }
        var attributed = AttributedString(String(localized: "Din act: „\(source)”"))
        let needle = Self.text(of: field.value)
        if !needle.isEmpty, let range = attributed.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].backgroundColor = DS.Palette.accent.opacity(0.18)
            attributed[range].foregroundColor = DS.Palette.label
        }
        return attributed
    }

    static func text(of value: CaptureValue?) -> String {
        switch value {
        case .text(let text)?: return text
        case .number(let number)?: return NSDecimalNumber(decimal: number).stringValue
        case .metric(let number, let unit)?: return "\(NSDecimalNumber(decimal: number).stringValue) \(unit.label)"
        default: return ""
        }
    }

    static func value(_ text: String, like original: CaptureValue?) -> CaptureValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : .text(trimmed)
    }

    static func number(of value: CaptureValue?) -> Double? {
        switch value {
        case .number(let number)?, .metric(let number, _)?: NSDecimalNumber(decimal: number).doubleValue
        default: nil
        }
    }

    static func value(_ number: Decimal, unit: MeasurementUnit?) -> CaptureValue {
        unit.map { .metric(value: number, unit: $0) } ?? .number(number)
    }
}

/// A reading that wasn't kept, beside the one shown: what it says and "Folosește-l". The one
/// mechanism for every alternative: the phone's value or kind, the AI's, a checked code's.
private struct CaptureAlternativeNote: View {
    let text: String
    let onUse: () -> Void

    var body: some View {
        DSAdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: DS.Space.s, stackedSpacing: DS.Space.xxs) { note; button }
    }

    private var note: some View {
        Text(verbatim: text)
            .dsFont(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var button: some View {
        Button(action: onUse) {
            Text("Folosește-l", comment: "Applies a value another reader read instead of the one shown.")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Folosește: \(text)", comment: "VoiceOver label of the button that applies another reader's value."))
    }

    /// "Gemini a citit: …", in the provider's own name.
    static func readBy(_ provider: AIProvider, value: String) -> String {
        switch provider {
        case .openAICompatible:
            String(localized: "Modelul tău a citit: \(value)", comment: "The value the person's own AI model read.")
        default:
            String(localized: "\(provider.shortName) a citit: \(value)", comment: "The value the AI provider read. The first argument is the provider's short name.")
        }
    }
}

/// "Where it goes": an existing section, a new one, or nowhere in particular.
private struct CaptureDestinationPicker: View {
    @Binding var destination: CaptureReview.Destination
    @Binding var newAssetName: String
    let templates: [CategoryTemplate]
    let assets: [Asset]
    /// An identity document can go to a new household member.
    var offersNewHolder = false
    /// A bill or a contract: a home stands for its subscription there, or a new one.
    var filesUnderSubscription = false

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingNewCategory = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(.none, title: String(localized: "Doar păstrez actul"), subtitle: String(localized: "Fără secțiune; îl găsești în Caută."), symbol: "tray")
                    if offersNewHolder, let holders = templates.first(where: { $0.behavior.role == .holder }) {
                        choice(.newAsset(templateKey: holders.key), title: String(localized: "Persoană nouă"),
                               subtitle: String(localized: "Actele stau grupate pe persoane."), symbol: "person.crop.circle.badge.plus")
                    }
                }
                ForEach(templates.filter { template in assets.contains { $0.templateKey == template.key } }) { template in
                    Section {
                        ForEach(assets.filter { $0.templateKey == template.key }) { asset in
                            choice(.asset(asset.id), title: asset.name, subtitle: subtitle(for: asset), symbol: asset.symbolOverride ?? template.symbol)
                        }
                    } header: {
                        Text(verbatim: template.name).textCase(nil)
                    }
                }
                Section {
                    Button { isPickingNewCategory = true } label: {
                        DSListRow("Secțiune nouă", subtitle: "Alege tipul, apoi scrii un nume.", systemImage: "folder.badge.plus", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Unde îl pun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Închide") { dismiss() } }
            }
            .navigationDestination(isPresented: $isPickingNewCategory) {
                List(templates.filter { $0.behavior.role != .holder }) { template in
                    choice(.newAsset(templateKey: template.key), title: template.name, subtitle: template.summary, symbol: template.symbol)
                }
                .navigationTitle("Ce fel de secțiune")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    /// What the asset's category does.
    private func behavior(of asset: Asset) -> CategoryBehavior {
        templates.first { $0.key == asset.templateKey }?.behavior ?? .standard
    }

    /// What choosing an asset means: an example is marked; for a bill, a home holds its
    /// subscription and a subscription says whose it is.
    private func subtitle(for asset: Asset) -> String? {
        if asset.isExample { return String(localized: "Exemplu") }
        guard filesUnderSubscription else { return nil }
        if behavior(of: asset).role == .home {
            return String(localized: "La abonamentul de aici, sau unul nou", comment: "Destination picker: a bill filed under a home goes to its subscription there.")
        }
        if behavior(of: asset).role == .subscription, let parent = asset.parent { return parent.name }
        return nil
    }

    private func choice(_ value: CaptureReview.Destination, title: String, subtitle: String?, symbol: String) -> some View {
        Button {
            destination = value
            dismiss()
        } label: {
            DSListRow(
                title: Text(verbatim: title),
                subtitle: subtitle.map { Text(verbatim: $0) },
                systemImage: symbol,
                trailing: {
                    if destination == value {
                        Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent).accessibilityLabel(Text("Ales"))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
