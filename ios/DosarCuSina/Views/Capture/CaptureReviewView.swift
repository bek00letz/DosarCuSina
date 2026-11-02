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
    let onClose: (CaptureFlowResult) -> Void

    init(
        review: CaptureReview,
        assets: [Asset],
        onReadWithCloud: (() -> Void)? = nil,
        onAddPages: ((CaptureRequest.Payload) -> Void)? = nil,
        rereading: CaptureReread? = nil,
        rereadResult: CaptureResult? = nil,
        readAgainError: String? = nil,
        onClose: @escaping (CaptureFlowResult) -> Void
    ) {
        self._review = State(initialValue: review)
        self.assets = assets
        self.onReadWithCloud = onReadWithCloud
        self.onAddPages = onAddPages
        self.rereading = rereading
        self.rereadResult = rereadResult
        self.readAgainError = readAgainError
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
    @State private var thumbnail: UIImage?
    @State private var pages: [UIImage] = []
    @State private var isShowingPages = false
    @State private var backSource: CaptureSource?
    @State private var backError: String?

    private var templatesByKey: [String: CategoryTemplate] {
        Dictionary(templates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                documentCard
                notices
                fieldsSection
                destinationSection
                reminderSection
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                }
                DSPrimaryButton(review.duplicateAttachmentID == nil ? "Salvează" : "Salvează doar datele", systemImage: "checkmark") {
                    requestSave()
                }
                .disabled(isSaving)
            }
            .padding(DS.Space.m)
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
                destination: $review.destination, newAssetName: $review.newAssetName, templates: templates, assets: assets,
                offersNewHolder: review.kind.isIdentityDocument,
                filesUnderSubscription: CaptureMapping.filesUnderSubscription(review.kind)
            )
        }
        .fullScreenCover(isPresented: $isShowingPages) {
            DocumentPagesViewer(pages: pages.isEmpty ? [thumbnail].compactMap { $0 } : pages)
        }
        .captureSourcePicker($backSource, onPicked: { payload in
            backError = nil
            onAddPages?(payload)
        }, onError: { _ in
            backError = String(localized: "Poza nu s-a putut deschide. Încearcă din nou.")
        })
        .task(id: review.documentID) { await loadThumbnail() }
        .task(id: review.result.id) { await explainCloudFailure() }
        .onChange(of: rereadResult?.id) { _, _ in mergeReread() }
        .onDisappear {
            // Closing without saving drops the pages from capture's memory. Not while the
            // camera covers the screen for the back of the card: the review comes back.
            if !isSaving, backSource == nil, !isShowingPages, let id = review.documentID {
                Task { await CaptureDocumentStore.shared().discard(id: id) }
            }
        }
    }

    // MARK: Document

    private var documentCard: some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Button { DocumentPagesViewer.present(reduceMotion: reduceMotion) { isShowingPages = true } } label: {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
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
                .disabled(thumbnail == nil && pages.isEmpty)
                .accessibilityLabel(Text("Vezi actul mare", comment: "VoiceOver label of the document thumbnail in the review."))
                .accessibilityHint(Text("Se deschide pe tot ecranul. Poți mări cu două degete.", comment: "VoiceOver hint of the document thumbnail."))

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: CaptureMapping.kindTitle(review.kind))
                        .dsFont(.title)
                    Menu {
                        Picker(selection: $review.kind) {
                            ForEach(CaptureDocumentKind.allCases, id: \.self) { kind in
                                Text(verbatim: CaptureMapping.kindTitle(kind)).tag(kind)
                            }
                        } label: { Text("Ce act e") }
                    } label: {
                        Text("Nu e asta? Schimbă")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
                    }
                    .onChange(of: review.kind) { _, _ in review.kindChanged(assets: assets) }
                    ForEach(review.kindAlternatives, id: \.self) { alternative in
                        CaptureAlternativeNote(text: kindAlternativeText(alternative)) {
                            withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review.useKind(alternative) }
                        }
                        .transition(.opacity)
                    }
                    Text(verbatim: tierNote)
                        .dsFont(.footnote)
                }
            }
        }
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
        if let duplicate = review.duplicateAttachmentID {
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
        // Offered whenever a provider is set up, whatever the phone read: a confident
        // reading can be wrong too, and only a second opinion can tell.
        if let onReadWithCloud, CaptureRunner.hasCloudKey, !review.usedCloudModel {
            if rereading == .cloud {
                DSDelayedProgress(label: "Citesc cu \(cloudProvider.shortName)…")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                DSSecondaryButton("Citește mai bine cu \(cloudProvider.shortName)", systemImage: "sparkles", action: onReadWithCloud)
                    .disabled(rereading != nil)
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                if review.kind.isIdentityDocument {
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
                    if review.showsLineItems {
                        CaptureLineItemsEditor(lines: $review.lineItems, currency: review.value(.total)?.money?.currencyCode ?? Money.defaultCurrency)
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
                    if case .newAsset(let key) = review.destination {
                        DSTextField(newAssetNameTitle(key), text: $review.newAssetName, isRequired: true)
                    }
                }
            }
        }
    }

    private func newAssetNameTitle(_ key: String) -> LocalizedStringKey {
        switch key {
        case BuiltInTemplates.Key.member: "Numele persoanei"
        case BuiltInTemplates.Key.subscription: "Numele abonamentului"
        case BuiltInTemplates.Key.home where CaptureMapping.filesUnderSubscription(review.kind): "Numele locuinței"
        default: "Numele secțiunii noi"
        }
    }

    private var destinationTitle: String {
        switch review.destination {
        case .none: return String(localized: "Doar păstrez actul")
        case .asset(let id): return assets.first { $0.id == id }?.name ?? String(localized: "Secțiune ștearsă")
        case .newAsset(let key) where key == BuiltInTemplates.Key.member:
            return String(localized: "Persoană nouă: \(review.newAssetName)")
        case .newAsset(let key) where key == BuiltInTemplates.Key.subscription:
            return String(localized: "Abonament nou: \(review.newAssetName)")
        case .newAsset(let key): return String(localized: "Secțiune nouă în \(templatesByKey[key]?.name ?? key)")
        }
    }

    private var destinationSubtitle: String {
        switch review.destination {
        case .none: return String(localized: "Îl găsești în Caută.")
        case .asset(let id):
            guard let asset = assets.first(where: { $0.id == id }) else { return "" }
            if asset.templateKey == BuiltInTemplates.Key.member { return String(localized: "Actul stă la actele acestei persoane.") }
            if CaptureMapping.filesUnderSubscription(review.kind) {
                if let subscription = review.existingSubscription(assets: assets), subscription.id != asset.id {
                    return String(localized: "La abonamentul „\(subscription.name)”")
                }
                if asset.templateKey == BuiltInTemplates.Key.home {
                    return String(localized: "Abonament nou aici: \(CaptureFiler.subscriptionName(review))")
                }
                if let parent = asset.parent { return String(localized: "Abonament la \(parent.name)") }
            }
            return templatesByKey[asset.templateKey]?.name ?? ""
        case .newAsset(let key) where key == BuiltInTemplates.Key.member:
            return String(localized: "Se adaugă în Acte când salvezi.")
        case .newAsset(let key) where key == BuiltInTemplates.Key.home && CaptureMapping.filesUnderSubscription(review.kind):
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
        case .newAsset(let key) where key == BuiltInTemplates.Key.member: return "person.crop.circle.badge.plus"
        case .newAsset(let key): return templatesByKey[key]?.symbol ?? "folder.badge.plus"
        }
    }

    // MARK: Reminder

    @ViewBuilder private var reminderSection: some View {
        let text = CaptureReminderPreview.text(for: review, templates: templatesByKey, assets: assets, today: CalendarDay(Date()))
        if text != nil || review.kind == .utilityInvoice {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Când te anunț")
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        if review.kind == .utilityInvoice, review.reminderDay != nil, !review.paysByDirectDebit(assets: assets) {
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
        errorMessage = nil
        let filer = CaptureFiler(context: context)
        if filer.touchesReminders(review) {
            saveRequest = ReminderSaveRequest { save() }
        } else {
            save()
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                let outcome = try await CaptureFiler(context: context).save(review)
                let place = outcome.asset?.name
                onClose(.filed(message: place.map { "Salvat în \($0)." } ?? "Actul e salvat.", assetID: outcome.asset?.id))
            } catch {
                isSaving = false
                errorMessage = SaveFailure.message(for: error, formKept: true)
            }
        }
    }

    private func loadThumbnail() async {
        guard let id = review.documentID, let processed = await CaptureDocumentStore.shared().processed(id: id) else { return }
        thumbnail = processed.thumbnailData.flatMap(UIImage.init(data:))
        pages = processed.pageData.compactMap(UIImage.init(data:))
    }

    /// Merges the newest reading into the review, keeping everything the person changed.
    /// Pages a reading with added pages replaced are let go.
    private func mergeReread() {
        guard let result = rereadResult, result.id != review.result.id else { return }
        let previousDocument = review.documentID
        let merged = CaptureReview(result: result, assets: assets, context: context).carryingEdits(from: review, assets: assets)
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review = merged }
        if let previousDocument, previousDocument != merged.documentID {
            Task { await CaptureDocumentStore.shared().discard(id: previousDocument) }
        }
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
        if field.key == .serviceKind {
            // A choice, kept as its stable key.
            DSChoiceField(title, selection: Binding(
                get: { field.value?.text },
                set: { key in field.confirm(key.map(CaptureValue.text)) }
            ), options: ServiceKind.all) { ServiceKind.label(for: $0) ?? $0 }
        } else {
            valueEditor(title)
        }
    }

    @ViewBuilder private func valueEditor(_ title: LocalizedStringKey) -> some View {
        switch field.value {
        case .day?:
            DSDateField(title, date: Binding(
                get: { field.value?.day?.date() },
                set: { field.confirm($0.map { .day(CaptureDay(date: $0)) }) }
            ))
        case .money(let money)?:
            DSMoneyField(title, amount: Binding(
                get: { field.value?.money?.amount },
                set: { amount in field.confirm(amount.map { .money(CaptureMoney(amount: $0, currencyCode: money.currencyCode)) }) }
            ), currencyCode: Binding(
                get: { field.value?.money?.currencyCode ?? money.currencyCode },
                set: { code in if let amount = field.value?.money?.amount { field.confirm(.money(CaptureMoney(amount: amount, currencyCode: code))) } }
            ))
        default:
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
        case .metric(let number, let unit)?: return "\(NSDecimalNumber(decimal: number).stringValue) \(unit)"
        default: return ""
        }
    }

    static func value(_ text: String, like original: CaptureValue?) -> CaptureValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch original {
        case .number?:
            return Money.parseAmount(trimmed).map(CaptureValue.number) ?? .text(trimmed)
        case .metric(_, let unit)?:
            let digits = trimmed.replacingOccurrences(of: unit, with: "")
            return Money.parseAmount(digits).map { .metric(value: $0, unit: unit) } ?? .text(trimmed)
        default:
            return .text(trimmed)
        }
    }
}

/// A reading that wasn't kept, beside the one shown: what it says and "Folosește-l". The one
/// mechanism for every alternative: the phone's value or kind, the AI's, a checked code's.
private struct CaptureAlternativeNote: View {
    let text: String
    let onUse: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) { note; button }
            VStack(alignment: .leading, spacing: DS.Space.xxs) { note; button }
        }
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
                    if offersNewHolder {
                        choice(.newAsset(templateKey: BuiltInTemplates.Key.member), title: String(localized: "Persoană nouă"),
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
                List(templates.filter { $0.key != BuiltInTemplates.Key.member }) { template in
                    choice(.newAsset(templateKey: template.key), title: template.name, subtitle: template.summary, symbol: template.symbol)
                }
                .navigationTitle("Ce fel de secțiune")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    /// What choosing an asset means: an example is marked; for a bill, a home holds its
    /// subscription and a subscription says whose it is.
    private func subtitle(for asset: Asset) -> String? {
        if asset.isExample { return String(localized: "Exemplu") }
        guard filesUnderSubscription else { return nil }
        if asset.templateKey == BuiltInTemplates.Key.home {
            return String(localized: "La abonamentul de aici, sau unul nou", comment: "Destination picker: a bill filed under a home goes to its subscription there.")
        }
        if asset.templateKey == BuiltInTemplates.Key.subscription, let parent = asset.parent { return parent.name }
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
