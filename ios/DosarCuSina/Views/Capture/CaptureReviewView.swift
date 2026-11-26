import SwiftData
import SwiftUI

/// The review's words: its kind's (`CaptureKindProfile`) and every kind's (`CaptureReviewWording`).
private typealias Words = CaptureReviewWording

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
    /// Read from De verificat: "Șterge din De verificat" takes the item out, with "Anulează".
    var onRemoveFromInbox: (() -> Void)?
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
        onRemoveFromInbox: (() -> Void)? = nil,
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
        self.onRemoveFromInbox = onRemoveFromInbox
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
    /// The person opened the notices behind the first one ("Mai sunt 2 observații").
    @State private var showsEveryNotice = false

    private var templatesByKey: [String: CategoryTemplate] {
        Dictionary(templates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// What saving will do, as the review stands now: what it shows is what happens.
    private var plan: CaptureFilingPlan {
        CaptureFilingPlan.make(for: review, templates: templatesByKey, assets: assets, today: CalendarDay(Date()))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    // What needs confirming most comes first: what it is, where it goes, when
                    // you'll be reminded. Then one notice at a time, then the values.
                    summaryCard(proxy)
                    noticeArea
                    fieldsSection
                    if review.photoIsOnRequest {
                        KeepPhotoChoice(keepsPhoto: $review.keepsPhotoOnRequest, kind: review.kind)
                    }
                    readingOffer
                }
                .padding(DS.Space.m)
                .dsReadableWidth()
            }
        }
        .dsPinnedAction {
            DSPrimaryButton(verbatim: Words.save, systemImage: "checkmark") {
                requestSave()
            }
            .disabled(isSaving)
        } note: {
            if let errorMessage {
                DSNotice(.error, title: Text(verbatim: Words.notSaved), message: Text(verbatim: errorMessage))
            }
        }
        .background(DS.Palette.background)
        .navigationTitle(Words.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // From De verificat, closing keeps the item there for later: the button says so.
                if onRemoveFromInbox != nil {
                    DSCancelButton(Text(verbatim: Words.later))
                } else {
                    DSCancelButton()
                }
            }
            if let onRemoveFromInbox {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive, action: onRemoveFromInbox) {
                        Label {
                            Text(verbatim: Words.removeFromInbox)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        // Asks only once the person changed what the reading proposed: closing loses nothing else.
        .dsDiscardGuard(hasChanges: review.hasPersonsChanges && !isSaving, message: discardMessage)
        .reminderPermissionGate($saveRequest)
        .dsSheet(isPresented: $isPickingDestination) {
            CaptureDestinationPicker(
                title: review.kind.profile.noun.wherePutWords,
                destination: Binding(get: { review.destination }, set: { review.choosePlace($0) }),
                newAssetName: $review.newAssetName, templates: templates, assets: assets,
                offer: CaptureDestinations.offer(for: review, assets: assets),
                offersNewHolder: review.kind.isPersonalDocument,
                filesUnderSubscription: review.kind.profile.filing == .subscription
            )
        }
        .dsFullScreenCover(isPresented: $isShowingPages) {
            DocumentPagesViewer(pages: pageSources, editing: .review($review.pageChoices))
        }
        .captureSourcePicker($backSource, onPicked: { payload in
            backError = nil
            onAddPages?(payload)
        }, onError: { _ in
            backError = Words.photoDidNotOpen
        })
        .task(id: review.documentID) { await loadPages() }
        .task(id: review.result.id) { await explainCloudFailure() }
        .onChange(of: rereadResult?.id) { _, _ in mergeReread() }
        .examplePrompt($exampleQuestion) { save() }
        .readingPrompt($readingQuestion) { save(lowerReading: $0) }
        // The pages belong to the capture session, which lets go of them when the capture ends.
    }

    /// What "Renunță la modificări" loses, from De verificat: the item itself stays.
    private var discardMessage: Text? {
        guard onRemoveFromInbox != nil else { return nil }
        return Text(verbatim: Words.discardFromInbox)
    }

    // MARK: Summary

    /// One card for what needs confirming most: what the document is, where it goes and when
    /// you'll be reminded, each changed from here.
    private func summaryCard(_ proxy: ScrollViewProxy) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                documentHeader
                DS.Hairline()
                placeRow
                reminderPart(proxy)
            }
        }
    }

    /// A short heading inside the summary card: "Unde o pun", "Când te anunț".
    private func summaryHeading(_ title: String) -> some View {
        Text(verbatim: title)
            .dsFont(.captionEmphasized)
            .foregroundStyle(DS.Palette.secondaryLabel)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Document

    private var documentHeader: some View {
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
                .accessibilityLabel(Text(verbatim: Words.seeLarge))
                .accessibilityHint(Text(verbatim: Words.seeLargeHint))

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: CaptureMapping.kindTitle(review.kind))
                        .dsFont(.title)
                    Menu {
                        Picker(selection: Binding(get: { review.kind }, set: { chooseKind($0) })) {
                            ForEach(CaptureDocumentKind.allCases, id: \.self) { kind in
                                Text(verbatim: CaptureMapping.kindTitle(kind)).tag(kind)
                            }
                        } label: { Text(verbatim: Words.whatKind) }
                    } label: {
                        Text(verbatim: Words.notThis)
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

    /// Another kind, the person's choice: the page is read again as that kind, keeping their edits.
    private func chooseKind(_ kind: CaptureDocumentKind, from alternative: CaptureAlternative<CaptureDocumentKind>? = nil) {
        let read = review.choosingKind(kind, from: alternative, assets: assets, context: context)
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review = read }
    }

    /// "Pe telefon părea: Factură de utilități", beside a kind another reader didn't keep.
    private func kindAlternativeText(_ alternative: CaptureAlternative<CaptureDocumentKind>) -> String {
        let kind = CaptureMapping.kindTitle(alternative.value)
        return switch alternative.source {
        case .phone: Words.phoneSawKind(kind)
        case .cloudModel: Words.readBy(cloudProvider, value: kind)
        case .checked: Words.checkedKind(kind)
        }
    }

    private var tierNote: String {
        if review.usedCloudModel {
            return Words.readWithProvider(cloudProvider.shortName)
        }
        switch review.mainTier {
        case .onDeviceModel?: return Words.readWithAppleIntelligence
        default: return Words.readOnPhone
        }
    }

    // MARK: Notices

    /// Everything the review has to say about the reading, most important first (`ReviewNotice`).
    private var reviewNotices: [ReviewNotice] {
        ReviewNotice.present(
            asksToSend: asksToSendToProvider && onAnswerSending != nil,
            filedBill: plan.filedBill,
            samePhoto: review.duplicateAttachmentID,
            asksForBackPage: review.asksForBackPage,
            readingBackPage: rereading == .pages,
            backPageError: backError ?? (rereading == nil ? readAgainError : nil),
            resultNotices: review.result.notices,
            cloudMessage: cloudMessage
        )
    }

    /// One notice at a time; the others behind "Mai sunt 2 observații", nothing lost.
    @ViewBuilder private var noticeArea: some View {
        let notices = reviewNotices
        if let first = notices.first {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                noticeView(first)
                if notices.count > 1 {
                    if showsEveryNotice {
                        ForEach(notices.dropFirst()) { notice in
                            noticeView(notice)
                                .transition(.opacity)
                        }
                    } else {
                        Button {
                            withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { showsEveryNotice = true }
                        } label: {
                            Label {
                                Text(verbatim: Words.moreNotices(notices.count - 1))
                            } icon: {
                                Image(systemName: "chevron.down")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private func noticeView(_ notice: ReviewNotice) -> some View {
        switch notice {
        case .askToSend:
            sendQuestion
        case .alreadyFiled(let filed):
            // A bill already in the binder: the same photo, or another photo of the same bill.
            DSFiledPaperNotice(filed: filed, paper: .bill, onOpen: {
                onClose(.dismissed)
                AppNavigator.shared.open(.historyEntry(filed.entryID))
            }, onAnother: { review.isAnotherBill = true })
        case .samePhoto(let duplicate):
            DSNotice(.info, title: Text(verbatim: Words.samePhoto), message: Text(verbatim: Words.samePhotoMessage),
                     actionTitle: Text(verbatim: Words.seeWhereItIs)) {
                onClose(.dismissed)
                AppNavigator.shared.open(.document(duplicate))
            }
        case .backPage(let isReading, let error):
            backPageNotice(isReading: isReading, error: error)
        case .checkNumbers:
            DSNotice(.warning, title: Text(verbatim: Words.checkNumbers), message: Text(verbatim: Words.checkNumbersMessage))
        case .cloudFailed(let message):
            DSNotice(.warning, title: Text(verbatim: Words.providerDidNotRead(cloudProvider.name)), message: Text(verbatim: message))
        case .hardToRead:
            DSNotice(.info, title: Text(verbatim: Words.hardToRead), message: Text(verbatim: Words.hardToReadMessage))
        case .pagesTruncated(let read):
            DSNotice(.info, title: Text(verbatim: Words.firstPagesRead(read)), message: Text(verbatim: Words.longDocument))
        }
    }

    /// The back of an identity card, when only the front was read.
    private func backPageNotice(isReading: Bool, error: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSNotice(.info, title: Text(verbatim: Words.backPage))
            if isReading {
                DSDelayedProgress(label: LocalizedStringKey(Words.readingBack))
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if onAddPages != nil {
                if CaptureSource.isCameraAvailable {
                    DSSecondaryButton(verbatim: Words.photographBack, systemImage: "camera") { backSource = .camera }
                }
                DSSecondaryButton(verbatim: Words.choosePhotos, systemImage: "photo.on.rectangle") { backSource = .photos }
            }
            if let error {
                DSNotice(.error, title: Text(verbatim: Words.backNotRead), message: Text(verbatim: error))
            }
        }
    }

    /// An identity document's photo never leaves the phone by itself: one question, for this document.
    @ViewBuilder private var sendQuestion: some View {
        if let onAnswerSending {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSNotice(.info, title: Text(verbatim: Words.sendPhotoQuestion(cloudProvider.name)),
                         message: Text(verbatim: Words.sendPhotoMessage(cloudProvider.name)))
                DSSecondaryButton(verbatim: Words.sendPhoto, systemImage: "sparkles") { onAnswerSending(true) }
                DSSecondaryButton(verbatim: Words.keepOnPhone, systemImage: "iphone") { onAnswerSending(false) }
                dataPolicyLink
            }
        }
    }

    /// "Cum folosește Gemini ce trimiți", when the provider publishes its terms; for a service
    /// with none to link (a compatible one), that its rules are its own, so every provider says
    /// something before a document goes.
    @ViewBuilder private var dataPolicyLink: some View {
        if let policy = cloudProvider.dataPolicyURL {
            Link(destination: policy) {
                Text(verbatim: Words.dataPolicy(cloudProvider.name))
                    .frame(minHeight: 44, alignment: .leading)
            }
            .dsFont(.footnote)
        } else {
            Text(verbatim: Words.ownServiceRules)
                .dsFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Under the values, where a wrong one is seen: a second opinion from the person's AI
    /// provider, or why a bank card has none. Offered whenever a provider is set up, whatever
    /// the phone read: a confident reading can be wrong too.
    @ViewBuilder private var readingOffer: some View {
        if let onReadWithCloud, CaptureRunner.hasCloudKey, !review.usedCloudModel, !asksToSendToProvider {
            if !review.providerMayRead {
                // A bank card, or a page that may be one, is read only on the phone: one plain
                // line so the person isn't left wondering where the button went.
                Text(verbatim: Words.cardsStayOnPhone)
                    .dsFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if rereading == .cloud {
                        DSDelayedProgress(label: LocalizedStringKey(Words.readingWith(cloudProvider.shortName)))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        DSSecondaryButton(verbatim: Words.readBetter(cloudProvider.shortName), systemImage: "sparkles", action: onReadWithCloud)
                            .disabled(rereading != nil)
                    }
                    Text(verbatim: review.kind.profile.sentToProviderWords(cloudProvider.name))
                        .dsFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    dataPolicyLink
                }
            }
        }
    }

    /// The AI provider the person set up in Settings.
    private var cloudProvider: AIProvider { AIProviderSettings.standard.provider }

    // MARK: Fields

    @ViewBuilder private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(LocalizedStringKey(Words.whatWasRead),
                            subtitle: review.visibleFields.contains(where: \.needsCheck) ? LocalizedStringKey(Words.checkMarked) : nil)
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    DSTextField(LocalizedStringKey(Words.documentName), text: $review.title)
                    let fields = review.visibleFields
                    if fields.isEmpty {
                        Text(verbatim: review.kind.profile.noun.nothingReadWords)
                            .dsFont(.subheadline)
                    }
                    ForEach(fields) { field in
                        if let index = review.fields.firstIndex(where: { $0.id == field.id }) {
                            CaptureFieldEditor(field: $review.fields[index], kind: review.kind)
                                // The summary's "Schimbă ziua" scrolls here.
                                .id(field.key)
                        }
                    }
                    let addable = review.addableKeys
                    if !addable.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: Words.notFound)
                                .dsFont(.footnote)
                            ForEach(addable, id: \.self) { key in
                                Button {
                                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review.addField(key) }
                                } label: {
                                    Label(Words.add(CaptureMapping.label(for: key)), systemImage: "plus.circle")
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
                    if let bonusMalus = plan.bonusMalus {
                        Text(verbatim: Words.bonusMalus(bonusMalus))
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

    /// "Unde o pun", in the summary card: the place, tapped to choose another.
    private var placeRow: some View {
        let place = CaptureReviewPlace(review: review, assets: assets, templates: templatesByKey)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            summaryHeading(review.kind.profile.noun.wherePutWords)
            Button { isPickingDestination = true } label: {
                DSListRow(
                    title: Text(verbatim: place.title),
                    subtitle: Text(verbatim: place.subtitle),
                    systemImage: place.systemImage,
                    showsChevron: true,
                    trailing: { Text(verbatim: Words.chooseAnother) }
                )
            }
            .buttonStyle(.plain)
            if let check = review.placeCheck {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Label(Words.check, systemImage: "exclamationmark.circle.fill")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(DSStatus.soon.textColor)
                    Text(verbatim: Words.placeCheck(check, address: review.placeAddressKey))
                        .dsFont(.footnote)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
            if let newNameTitle = place.newNameTitle {
                DSTextField(LocalizedStringKey(newNameTitle), text: $review.newAssetName, isRequired: true)
            }
        }
    }

    // MARK: Reminder

    /// The value whose day the reminder follows (an expiry, a due date), when the review shows
    /// it: "Schimbă ziua" scrolls to it.
    private var reminderDayField: CaptureFieldKey? {
        guard let key = review.kind.profile.deadlineField, review.visibleFields.contains(where: { $0.key == key }) else { return nil }
        return key
    }

    /// "Când te anunț", in the summary card: the reminder saving sets, the day it follows a tap
    /// away, and for a bill whether to be reminded to pay it.
    @ViewBuilder private func reminderPart(_ proxy: ScrollViewProxy) -> some View {
        let text = CaptureReminderPreview.text(for: review, templates: templatesByKey, assets: assets, today: CalendarDay(Date()))
        let directDebit = review.directDebitStatement(assets: assets)
        if text != nil || review.kind.profile.isBill || directDebit != nil {
            DS.Hairline()
            VStack(alignment: .leading, spacing: DS.Space.s) {
                summaryHeading(Words.whenHeading)
                if let text {
                    if let key = reminderDayField {
                        Button {
                            withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(key, anchor: .center)
                            }
                        } label: {
                            DSListRow(title: Text(verbatim: text), systemImage: "bell", trailing: { Text(verbatim: Words.changeDay) })
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text(verbatim: Words.changeDayHint))
                    } else {
                        DSListRow(title: Text(verbatim: text), systemImage: "bell", trailing: { EmptyView() })
                    }
                }
                if let directDebit {
                    // What the paper says, offered: turned on only by the person.
                    DSCheckRow(title: Text(verbatim: Words.directDebit),
                               subtitle: Text(verbatim: review.kind.profile.noun.directDebitWords(Words.shortened(directDebit))),
                               isOn: review.turnsOnDirectDebit) {
                        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { review.turnsOnDirectDebit.toggle() }
                    }
                }
                if review.kind.profile.isBill, review.reminderDay != nil, !review.paysByDirectDebit(assets: assets) {
                    DSCheckRow(title: Text(verbatim: review.kind.profile.noun.remindToPayWords), isOn: review.remindsToPay) {
                        review.remindsToPay.toggle()
                    }
                }
                Text(verbatim: Words.changeLater)
                    .dsFont(.footnote)
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
                    Text(verbatim: showsCrop ? Words.cropped : Words.wholePhotoKept)
                        .dsFont(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsCrop {
                        DSCompactButton(verbatim: Words.useWholePhoto, systemImage: "photo") { chooseWholePhoto(true, on: croppable) }
                    } else {
                        DSCompactButton(verbatim: Words.onlyDocument, systemImage: "crop") { chooseWholePhoto(false, on: croppable) }
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
                Label(Words.check, systemImage: "exclamationmark.circle.fill")
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
                    .accessibilityLabel(Text(verbatim: Words.readFrom(String(source.characters))))
            }
        }
    }

    /// "Pe telefon am citit: …", "Gemini a citit: …", "Pe spatele actului scrie: …".
    private func alternativeText(_ alternative: CaptureAlternative<CaptureValue>) -> String {
        let value = CaptureMapping.displayText(alternative.value)
        return switch alternative.source {
        case .phone: Words.phoneRead(value)
        case .cloudModel: Words.readBy(AIProviderSettings.standard.provider, value: value)
        case .checked(machineReadable: true): kind.profile.machineReadableWords(value)
        case .checked: kind.profile.noun.printedWords(value)
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
        var attributed = AttributedString(Words.fromDocument(source))
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
        case .number(let number)?, .metric(let number, _)?: RomanianNumber.double(number)
        default: nil
        }
    }

    static func value(_ number: Decimal, unit: MeasurementUnit?) -> CaptureValue {
        unit.map { .metric(value: number, unit: $0) } ?? .number(number)
    }
}

/// A reading that wasn't kept, beside the one shown: what it says and "Folosește". The one
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
            Text(verbatim: Words.use)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: Words.useThis(text)))
    }
}

/// "Where it goes": a section the document fits, any other one, a new one, or nowhere in
/// particular. What fits comes first (`CaptureDestinations`); "Altă secțiune…" lists them all.
/// A new section is made by `AddSectionFlow`, the one way to make one, and the document goes
/// into it.
private struct CaptureDestinationPicker: View {
    /// "Unde o pun", agreeing with the paper's noun (`CaptureKindProfile.Noun.wherePutWords`).
    let title: String
    @Binding var destination: CaptureReview.Destination
    @Binding var newAssetName: String
    let templates: [CategoryTemplate]
    let assets: [Asset]
    /// The sections that fit the document, and the category a new one starts with.
    let offer: CaptureDestinations.Offer
    /// An identity document can go to a new household member.
    var offersNewHolder = false
    /// A bill or a contract: a home stands for its subscription there, or a new one.
    var filesUnderSubscription = false

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingNewCategory = false
    @State private var isShowingEverything = false
    /// The section being made, started from the category the document fits or the catalog.
    @State private var newSection: AddSectionRequest?
    /// A section was made: the picker closes once the flow's sheet has gone.
    @State private var closesAfterNewSection = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(.none, title: Words.keepOnly, subtitle: Words.keepOnlySubtitle, systemImage: "tray")
                    if offersNewHolder, let holders = templates.first(where: { $0.behavior.role == .holder }) {
                        choice(.newAsset(templateKey: holders.key), title: Words.newPersonChoice,
                               subtitle: Words.groupedByPerson, systemImage: "person.crop.circle.badge.plus")
                    }
                }
                if let fitting = offer.fitting {
                    sections(of: assets.filter { fitting.contains($0.id) })
                    Section {
                        if let key = offer.newSectionKey, let template = templates.first(where: { $0.key == key }) {
                            newSectionRow(title: Words.newSectionChoice(in: template.name), subtitle: Words.thenFiled,
                                          systemImage: template.symbol, request: AddSectionRequest(templateKey: key))
                        }
                        Button { isShowingEverything = true } label: {
                            DSListRow(title: Text(verbatim: Words.otherSection), subtitle: Text(verbatim: Words.everySectionSubtitle),
                                      systemImage: "folder", showsChevron: true) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    everything
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Words.close) { dismiss() } }
            }
            .navigationDestination(isPresented: $isShowingEverything) {
                List { everything }
                    .navigationTitle(Words.everySection)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $isPickingNewCategory) {
                List(CategoryTemplate.oncePerKey(templates).filter { $0.behavior.role != .holder }) { template in
                    choice(.newAsset(templateKey: template.key), title: template.name, subtitle: template.summary, systemImage: template.symbol)
                }
                .navigationTitle(Words.whatSection)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .dsSheet(isPresented: Binding(get: { newSection != nil }, set: { if !$0 { newSection = nil } }), onDismiss: {
            // Waits for the flow's sheet to have gone before this one closes.
            if closesAfterNewSection { dismiss() }
        }) {
            if let newSection {
                AddSectionFlow(request: newSection) { asset in
                    destination = .asset(asset.id)
                    closesAfterNewSection = true
                }
            }
        }
    }

    /// Every section, by category, and a new one from the catalog.
    @ViewBuilder private var everything: some View {
        sections(of: assets)
        Section {
            newSectionRow(title: Words.newSectionPlain, subtitle: Words.chooseCategoryFirst,
                          systemImage: "folder.badge.plus", request: .topLevel)
        }
    }

    /// The sections given, grouped by category, in the categories' order.
    @ViewBuilder private func sections(of shown: [Asset]) -> some View {
        ForEach(CategoryTemplate.oncePerKey(templates).filter { template in shown.contains { $0.templateKey == template.key } }) { template in
            Section {
                ForEach(shown.filter { $0.templateKey == template.key }) { asset in
                    choice(.asset(asset.id), title: asset.name, subtitle: subtitle(for: asset), systemImage: asset.symbolOverride ?? template.symbol)
                }
            } header: {
                Text(verbatim: template.name).textCase(nil)
            }
        }
    }

    /// "Secțiune nouă": `AddSectionFlow`, or, switched off, the first version's list of categories.
    private func newSectionRow(title: String, subtitle: String, systemImage symbol: String, request: AddSectionRequest) -> some View {
        Button {
            if CaptureDestinations.makesSectionFromAName {
                isPickingNewCategory = true
            } else {
                newSection = request
            }
        } label: {
            DSListRow(title: Text(verbatim: title), subtitle: Text(verbatim: subtitle), systemImage: symbol, showsChevron: true) { EmptyView() }
        }
        .buttonStyle(.plain)
    }

    /// What the asset's category does.
    private func behavior(of asset: Asset) -> CategoryBehavior {
        templates.first { $0.key == asset.templateKey }?.behavior ?? .standard
    }

    /// What choosing an asset means: an example is marked; for a bill, a home holds its
    /// subscription and a subscription says whose it is.
    private func subtitle(for asset: Asset) -> String? {
        if asset.isExample { return Words.example }
        guard filesUnderSubscription else { return nil }
        if behavior(of: asset).role == .home {
            return Words.homeHoldsSubscription
        }
        if behavior(of: asset).role == .subscription, let parent = asset.parent { return parent.name }
        return nil
    }

    private func choice(_ value: CaptureReview.Destination, title: String, subtitle: String?, systemImage symbol: String) -> some View {
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
                        Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent).accessibilityLabel(Text(verbatim: Words.chosen))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
