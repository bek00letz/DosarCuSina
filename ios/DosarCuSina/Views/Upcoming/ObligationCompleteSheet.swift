import SwiftData
import SwiftUI

/// "Am rezolvat": what closing this deadline asks, as its blueprint states
/// (`Obligation.completion`, a `CompletionShape`): when, what it cost or was paid, the paper by
/// its name (the service's invoice, the bill, the ITP report, the new policy, the pet's health
/// booklet), a renewed document's or contract's new end, a note, the counter. A chore never
/// opens it: its "Gata" is one tap. Saving files through `CaptureFiler` (`CompletionDraft`
/// keeps only what the kind asks): the paper's date becomes the next deadline, a bill is filed
/// as a bill.
///
/// A shaped screen: it holds no words of its own. Every word comes from the deadline's shape
/// (its paper's, its note's, its new end's) or the words every kind shares
/// (`CompletionWording`); the architecture check refuses a text literal here
/// (`text-in-shaped-screen`).
struct ObligationCompleteSheet: View {
    let obligation: Obligation
    let onClose: (DSToast?) -> Void

    @Environment(\.modelContext) private var context
    @State private var draft = CompletionDraft()
    @State private var source: CaptureSource?
    @State private var isChoosingSource = false
    /// Reading the paper. It ends with the sheet: a reading still running stops.
    @State private var session = CaptureSession()
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var readingQuestion: LowerReadingQuestion?

    private var shape: CompletionShape { obligation.completion(template: template?.definition) }
    private var isReading: Bool { session.phase == .reading }
    private var document: CaptureResult? { session.result }

    private var template: CategoryTemplate? {
        obligation.asset.flatMap { try? TemplateStore(context: context).template(forKey: $0.templateKey) }
    }

    /// The counter the sheet asks for, where the kind asks one and the section has one.
    private var counter: ObligationActions.Counter? {
        shape.counter.flatMap { ObligationActions.counter(completing: obligation, template: template?.definition, asks: $0) }
    }

    /// The draft with the paper as read.
    private var filled: CompletionDraft {
        var filled = draft
        filled.document = document
        return filled
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    detailsCard
                    if shape.paper != nil { paperSection }
                    if let document, document.photoIsOnRequest {
                        KeepPhotoChoice(keepsPhoto: $draft.keepsPhotoOnRequest, kind: document.kind)
                    }
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .dsPinnedAction {
                DSPrimaryButton(verbatim: CompletionWording.save, systemImage: "checkmark") { save() }
                    .disabled(isSaving || isReading || (shape.asksDate && draft.date == nil))
            } note: {
                if let errorMessage {
                    DSNotice(.error, title: LocalizedStringKey(CompletionWording.notSaved), message: LocalizedStringKey(errorMessage))
                }
            }
            .navigationTitle(Text(verbatim: CompletionWording.title(obligation.title)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: filled.hasChanges)
            .examplePrompt($exampleQuestion) { save() }
            .readingPrompt($readingQuestion) { save(lowerReading: $0) }
            .onChange(of: document?.id) { _, _ in took(document) }
            .confirmationDialog(Text(verbatim: shape.paper?.headerWords ?? ""), isPresented: $isChoosingSource, titleVisibility: .visible) {
                if CaptureSource.isCameraAvailable, let paper = shape.paper { Button(paper.actionWords) { source = .camera } }
                Button(CompletionWording.photos) { source = .photos }
                Button(CompletionWording.files) { source = .files }
                Button(CompletionWording.cancel, role: .cancel) {}
            }
            .captureSourcePicker($source) { payload in
                read(payload)
            } onError: { _ in
                errorMessage = CompletionWording.photoDidNotOpen
            }
        }
    }

    // MARK: Details

    /// When, what it cost, the counter, the new end and the note: each only when the kind asks it.
    @ViewBuilder private var detailsCard: some View {
        if shape.asksDate || shape.cost != nil || counter != nil || shape.asksNewExpiry || shape.asksNote {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if shape.asksDate {
                        DSDateField(LocalizedStringKey(CompletionWording.when), date: $draft.date, in: Date.distantPast...Date.now, isRequired: true)
                    }
                    if let cost = shape.cost {
                        DSMoneyField(cost.title, amount: $draft.amount, currencyCode: $draft.currency, footnote: lastCostNote)
                    }
                    if let counter {
                        DSMetricField(LocalizedStringKey(counter.title), value: $draft.reading, unit: counter.unit)
                    }
                    if let newEnd = shape.newEnd {
                        DSExpiryDateField(LocalizedStringKey(newEnd.label), date: $draft.newExpiry, urgencyRule: obligation.reminders.urgencyRule,
                                          footnote: LocalizedStringKey(CompletionWording.newEndFootnote))
                    }
                    if let note = shape.note {
                        DSTextField(LocalizedStringKey(CompletionWording.note), text: $draft.note, kind: .longText, prompt: LocalizedStringKey(note.prompt))
                    }
                }
            }
        }
    }

    private var lastCostNote: LocalizedStringKey? {
        guard let cost = obligation.history.first?.totalCost else { return nil }
        return LocalizedStringKey(CompletionWording.lastCost(cost.formattedCompact()))
    }

    // MARK: Paper

    @ViewBuilder private var paperSection: some View {
        if let paper = shape.paper {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader(paper.header, subtitle: paper.purpose)
                if document != nil, let bill = billPlan {
                    // A photo of the bill: filed as a bill, as the review says it.
                    billNotices(bill)
                    Button(CompletionWording.anotherPhoto) { isChoosingSource = true }
                        .frame(minHeight: DS.Control.minimumHitTarget)
                } else if let document {
                    let next = CaptureFiler.nextDay(in: document)
                    // A photo kept only on request (a bank card, a page with a card's number) isn't promised here.
                    // A paper that carries no date (an invoice, a receipt) says only that it was read.
                    let message: String? = if let next, shape.newEnd == nil {
                        CompletionWording.nextDeadline(DueWording.date(next, today: CalendarDay(Date())))
                    } else if next != nil, let newEnd = shape.newEnd {
                        newEnd.filledFromPhoto
                    } else if !paper.readsADate {
                        nil
                    } else if document.photoIsOnRequest {
                        paper.noDateWords
                    } else {
                        paper.noDateKeptWords
                    }
                    DSNotice(.success, title: LocalizedStringKey(paper.readWords), message: message.map { LocalizedStringKey($0) })
                    Button(CompletionWording.anotherPhoto) { isChoosingSource = true }
                        .frame(minHeight: DS.Control.minimumHitTarget)
                } else {
                    DSActionCard(paper.actionTitle, subtitle: paper.exampleTitle, systemImage: "doc.viewfinder") {
                        isChoosingSource = true
                    }
                    .disabled(isReading)
                    if isReading { DSDelayedProgress(label: LocalizedStringKey(paper.readingWords)) }
                    if session.phase == .failed {
                        DSNotice(.warning, title: LocalizedStringKey(paper.unreadWords), message: LocalizedStringKey(CompletionWording.unreadMessage))
                    }
                }
            }
        }
    }

    /// What saving does with a photo of the bill on its subscription (`CaptureFiler.billPlan`):
    /// the bill in Istoric, once, and its meter index. Nil for any other document.
    private var billPlan: CaptureFilingPlan? {
        guard document != nil else { return nil }
        return try? CaptureFiler(context: context).billPlan(for: completion())
    }

    /// The bill already in the binder, or where it goes, and its index: the review's own words.
    @ViewBuilder private func billNotices(_ bill: CaptureFilingPlan) -> some View {
        if let filed = bill.filedBill {
            DSFiledPaperNotice(filed: filed, paper: .bill, onOpen: {
                onClose(nil)
                AppNavigator.shared.open(.historyEntry(filed.entryID))
            }, onAnother: { draft.isAnotherBill = true })
        } else {
            DSNotice(.success, title: LocalizedStringKey(CompletionWording.billRead),
                     message: LocalizedStringKey(CompletionWording.billLogged(in: obligation.asset?.name ?? "")))
        }
        if let meter = bill.meter {
            Label { Text(verbatim: meter.sentence).dsFont(.footnote) } icon: {
                Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(DS.Palette.secondaryLabel)
            }
            .labelStyle(DSLeadingIconLabelStyle())
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Saving

    /// What saving files, from the sheet as it stands: only what the kind asks.
    private func completion() -> CaptureFiler.Completion {
        filled.completion(of: obligation, shape: shape, counter: counter)
    }

    /// A paper just read: a new photo asks again whether it is another bill, and what it says
    /// fills what the person hasn't typed (its total, a renewed document's expiry).
    private func took(_ document: CaptureResult?) {
        draft.isAnotherBill = false
        guard let document else { return }
        if shape.cost != nil, draft.amount == nil, let total = document.field(.total)?.value.money {
            draft.amount = total.amount
            draft.currency = total.currency
        }
        if shape.asksNewExpiry, draft.newExpiry == nil, let next = CaptureFiler.nextDay(in: document) {
            draft.newExpiry = next.startDate()
        }
    }

    private func read(_ payload: CaptureRequest.Payload) {
        // A bank card's new card is read only on the phone, like any bank card (`PhoneOnlyReading`).
        session.destination.staysOnPhone = obligation.asset.map { PhoneOnlyReading.holdsOne($0.values) } ?? false
        session.read(payload)
    }

    private func save(lowerReading: LowerReadingAnswer? = nil) {
        // One filing at a time: a second tap before the button shows it is busy files nothing.
        guard !isSaving, !shape.asksDate || draft.date != nil else { return }
        isSaving = true
        errorMessage = nil
        let title = obligation.title
        let completion = completion()
        Task {
            do {
                var filer = CaptureFiler(context: context)
                filer.lowerReading = lowerReading
                let outcome = try await filer.file(.completion(completion))
                let message = outcome.nextDue.map {
                    CompletionWording.done(title, next: DueWording.date($0, today: CalendarDay(Date())))
                } ?? CompletionWording.done(title)
                let toast: DSToast = outcome.receipt.map { .undo(message, receipt: $0) } ?? DSToast(title: message, actionTitle: nil)
                session.close()
                onClose(toast)
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
}
