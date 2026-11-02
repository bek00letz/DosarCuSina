import Network
import SwiftData
import SwiftUI

/// The confirm step of capture: what the document is, the values read from it
/// (the uncertain ones marked), where it goes, and the reminder it sets.
/// "Salvează" runs `CaptureFiler.save`, the one save path.
struct CaptureReviewView: View {
    @State var review: CaptureReview
    let assets: [Asset]
    var onReadWithCloud: (() -> Void)?
    /// Adds pages (the back of a card) and reads the document again, keeping the person's edits.
    var onAddPages: ((CaptureReview, CaptureRequest.Payload) -> Void)?
    /// A read with added pages is running.
    var isReadingAgain = false
    /// Why the last read with added pages didn't work.
    var readAgainError: String?
    let onClose: (CaptureFlowResult) -> Void

    init(
        review: CaptureReview,
        assets: [Asset],
        onReadWithCloud: (() -> Void)? = nil,
        onAddPages: ((CaptureReview, CaptureRequest.Payload) -> Void)? = nil,
        isReadingAgain: Bool = false,
        readAgainError: String? = nil,
        onClose: @escaping (CaptureFlowResult) -> Void
    ) {
        self._review = State(initialValue: review)
        self.assets = assets
        self.onReadWithCloud = onReadWithCloud
        self.onAddPages = onAddPages
        self.isReadingAgain = isReadingAgain
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
                offersNewHolder: review.kind.isIdentityDocument
            )
        }
        .fullScreenCover(isPresented: $isShowingPages) {
            DocumentPagesViewer(pages: pages.isEmpty ? [thumbnail].compactMap { $0 } : pages)
        }
        .captureSourcePicker($backSource, onPicked: { payload in
            backError = nil
            onAddPages?(review, payload)
        }, onError: { _ in
            backError = String(localized: "Poza nu s-a putut deschide. Încearcă din nou.")
        })
        .task { await loadThumbnail() }
        .task(id: review.result.id) { await explainCloudFailure() }
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
                Button { isShowingPages = true } label: {
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
                    Text(verbatim: tierNote)
                        .dsFont(.footnote)
                }
            }
        }
    }

    private var tierNote: String {
        if review.usedCloudModel { return String(localized: "Citit și cu Gemini, cu cheia ta.") }
        switch review.mainTier {
        case .onDeviceModel?: return String(localized: "Citit pe telefon, cu Apple Intelligence.")
        default: return String(localized: "Citit pe telefon. Nimic n-a plecat de aici.")
        }
    }

    /// The back of an identity card, when only the front was read.
    @ViewBuilder private var backPageNotice: some View {
        if review.asksForBackPage || isReadingAgain {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSNotice(.info, title: "Ai și o poză cu spatele? Acolo e codul care confirmă datele.")
                if isReadingAgain {
                    DSDelayedProgress(label: "Citesc și spatele…")
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else if onAddPages != nil {
                    if CaptureSource.isCameraAvailable {
                        DSSecondaryButton("Fotografiază spatele", systemImage: "camera") { backSource = .camera }
                    }
                    DSSecondaryButton("Alege din poze", systemImage: "photo.on.rectangle") { backSource = .photos }
                }
                if let message = backError ?? readAgainError {
                    DSNotice(.error, title: "Nu am putut citi spatele", message: LocalizedStringKey(message))
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var notices: some View {
        backPageNotice
        if let duplicate = review.duplicateAttachmentID {
            DSNotice(.info, title: "Ai mai adăugat documentul ăsta", message: "Poți să-l deschizi, sau să salvezi doar datele de pe el.", actionTitle: "Vezi documentul") {
                onClose(.dismissed)
                AppNavigator.shared.open(.document(duplicate))
            }
        }
        ForEach(Array(review.result.notices.enumerated()), id: \.offset) { _, notice in
            switch notice {
            case .littleTextRecognized:
                DSNotice(.warning, title: "Am citit puțin text", message: "O poză mai clară, cu actul întins și fără umbre, ajută. Verifică valorile de mai jos.")
            case .pagesTruncated(let read, _):
                DSNotice(.info, title: "Am citit primele \(read) pagini", message: "E un document lung. Se păstrează tot, cu toate paginile.")
            case .machineReadableZoneUnverified:
                DSNotice(.warning, title: "Verifică numărul și datele", message: "Codul de jos al actului nu s-a citit sigur.")
            default:
                EmptyView()
            }
        }
        if let cloudMessage {
            DSNotice(.warning, title: "Gemini nu a citit actul", message: LocalizedStringKey(cloudMessage))
        }
        if let onReadWithCloud, CaptureRunner.hasCloudKey, !review.usedCloudModel, review.visibleFields.contains(where: \.needsCheck) || review.visibleFields.count < 2 {
            DSSecondaryButton("Citește mai bine cu Gemini", systemImage: "sparkles", action: onReadWithCloud)
            Text("Prima pagină se trimite la Google, cu cheia ta.")
                .dsFont(.footnote)
        }
    }

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
                            CaptureFieldEditor(field: $review.fields[index])
                        }
                    }
                    if let lines = review.value(.lineItems)?.lineItems, !lines.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Ce s-a făcut").dsFont(.footnote)
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                HStack {
                                    Text(verbatim: line.description).dsFont(.body)
                                    Spacer()
                                    if let amount = line.amount {
                                        Text(verbatim: CaptureMapping.money(amount).formattedCompact()).dsFont(.body, numeric: true)
                                    }
                                }
                            }
                        }
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
                        DSTextField(key == BuiltInTemplates.Key.member ? "Numele persoanei" : "Numele secțiunii noi",
                                    text: $review.newAssetName, isRequired: true)
                    }
                }
            }
        }
    }

    private var destinationTitle: String {
        switch review.destination {
        case .none: return String(localized: "Doar păstrez actul")
        case .asset(let id): return assets.first { $0.id == id }?.name ?? String(localized: "Secțiune ștearsă")
        case .newAsset(let key) where key == BuiltInTemplates.Key.member:
            return String(localized: "Persoană nouă: \(review.newAssetName)")
        case .newAsset(let key): return String(localized: "Secțiune nouă în \(templatesByKey[key]?.name ?? key)")
        }
    }

    private var destinationSubtitle: String {
        switch review.destination {
        case .none: return String(localized: "Îl găsești în Caută.")
        case .asset(let id):
            guard let asset = assets.first(where: { $0.id == id }) else { return "" }
            if asset.templateKey == BuiltInTemplates.Key.member { return String(localized: "Actul stă la actele acestei persoane.") }
            return templatesByKey[asset.templateKey]?.name ?? ""
        case .newAsset(let key) where key == BuiltInTemplates.Key.member:
            return String(localized: "Se adaugă în Acte când salvezi.")
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
                        if review.kind == .utilityInvoice, review.reminderDay != nil {
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
                onClose(.filed(message: place.map { "Salvat în \($0)." } ?? "Actul e salvat."))
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadThumbnail() async {
        guard let id = review.documentID, let processed = await CaptureDocumentStore.shared().processed(id: id) else { return }
        thumbnail = processed.thumbnailData.flatMap(UIImage.init(data:))
        pages = processed.pageData.compactMap(UIImage.init(data:))
    }

    /// Tells "offline" apart from "the key wasn't accepted".
    private func explainCloudFailure() async {
        for notice in review.result.notices {
            guard case .cloudModelFailed(let reason) = notice else { continue }
            if reason == "noKey" {
                cloudMessage = String(localized: "Nu ai adăugat o cheie Google. Citirea de pe telefon merge oricum.")
            } else if await NetworkCheck.isOnline() {
                cloudMessage = String(localized: "Google nu a acceptat cheia. Verifică în Setări dacă ai copiat-o întreagă.")
            } else {
                cloudMessage = String(localized: "Nu ești conectat la internet. Citirea de pe telefon a mers în continuare.")
            }
        }
    }
}

/// One value read from the document: editable, with where it was read from.
private struct CaptureFieldEditor: View {
    @Binding var field: CaptureReview.Field

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            editor
            if field.needsCheck {
                Label("Verifică", systemImage: "exclamationmark.circle.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DSStatus.soon.textColor)
            }
            if let source = sourceText {
                Text(source)
                    .dsFont(.footnote)
                    .lineLimit(2)
                    .accessibilityLabel(Text("Citit din: \(String(source.characters))"))
            }
        }
    }

    @ViewBuilder private var editor: some View {
        let title = LocalizedStringKey(field.label)
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
                set: { code in if let amount = field.value?.money?.amount { field.value = .money(CaptureMoney(amount: amount, currencyCode: code)) } }
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

/// "Where it goes": an existing section, a new one, or nowhere in particular.
private struct CaptureDestinationPicker: View {
    @Binding var destination: CaptureReview.Destination
    @Binding var newAssetName: String
    let templates: [CategoryTemplate]
    let assets: [Asset]
    /// An identity document can go to a new household member.
    var offersNewHolder = false

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
                            choice(.asset(asset.id), title: asset.name, subtitle: asset.isExample ? String(localized: "Exemplu") : nil, symbol: asset.symbolOverride ?? template.symbol)
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

/// One look at whether there is a network path, for wording errors.
enum NetworkCheck {
    static func isOnline() async -> Bool {
        let monitor = NWPathMonitor()
        let satisfied: Bool = await withCheckedContinuation { continuation in
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                if once.claim() { continuation.resume(returning: path.status == .satisfied) }
            }
            monitor.start(queue: DispatchQueue(label: "dosar.network-check"))
        }
        monitor.cancel()
        return satisfied
    }

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
