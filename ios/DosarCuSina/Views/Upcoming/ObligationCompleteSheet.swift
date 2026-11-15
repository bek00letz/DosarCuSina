import SwiftData
import SwiftUI

/// "Am rezolvat": what closing this deadline asks, as its kind says (`CompletionShape`): when,
/// what it cost or was paid, the paper (the invoice, the bill, the new document or policy, the
/// proof, the receipt, the result), a renewed document's new expiry, a note, the section's
/// counter. A chore never opens it: its "Gata" is one tap. Saving files through
/// `CaptureFiler` (`CompletionDraft` keeps only what the kind asks): the paper's date becomes
/// the next deadline, a bill is filed as a bill.
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

    private var shape: CompletionShape { obligation.kind.completion }
    private var isReading: Bool { session.phase == .reading }
    private var document: CaptureResult? { session.result }

    private var template: CategoryTemplate? {
        obligation.asset.flatMap { try? TemplateStore(context: context).template(forKey: $0.templateKey) }
    }

    /// The counter the sheet asks for, where the kind asks one and the section has one.
    private var counter: ObligationActions.Counter? {
        shape.asksReading ? ObligationActions.counter(completing: obligation, template: template?.definition) : nil
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
                DSPrimaryButton("Salvează", systemImage: "checkmark") { save() }
                    .disabled(isSaving || isReading || (shape.asksDate && draft.date == nil))
            } note: {
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                }
            }
            .navigationTitle(Text("Am rezolvat: \(obligation.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: filled.hasChanges)
            .examplePrompt($exampleQuestion) { save() }
            .readingPrompt($readingQuestion) { save(lowerReading: $0) }
            .onChange(of: document?.id) { _, _ in took(document) }
            .confirmationDialog(Text(shape.paper?.header ?? "Actul nou"), isPresented: $isChoosingSource, titleVisibility: .visible) {
                if CaptureSource.isCameraAvailable { Button("Fotografiază actul") { source = .camera } }
                Button("Alege din poze") { source = .photos }
                Button("Din Fișiere") { source = .files }
                Button("Renunță", role: .cancel) {}
            }
            .captureSourcePicker($source) { payload in
                read(payload)
            } onError: { _ in
                errorMessage = String(localized: "Poza nu s-a putut deschide. Încearcă din nou.")
            }
        }
    }

    // MARK: Details

    /// When, what it cost, the counter, the new expiry and the note: each only when the kind asks it.
    @ViewBuilder private var detailsCard: some View {
        if shape.asksDate || shape.cost != nil || counter != nil || shape.asksNewExpiry || shape.asksNote {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if shape.asksDate {
                        DSDateField("Când", date: $draft.date, in: Date.distantPast...Date.now, isRequired: true)
                    }
                    if let cost = shape.cost {
                        DSMoneyField(cost.title, amount: $draft.amount, currencyCode: $draft.currency, footnote: lastCostNote)
                    }
                    if let counter {
                        DSMetricField(LocalizedStringKey(counter.title), value: $draft.reading, unit: counter.unit)
                    }
                    if shape.asksNewExpiry {
                        DSExpiryDateField("Expiră pe", date: $draft.newExpiry, urgencyRule: obligation.reminders.urgencyRule,
                                          footnote: "De aici încep să-ți amintesc din nou.")
                    }
                    if shape.asksNote {
                        DSTextField("Notă", text: $draft.note, kind: .longText, prompt: "Ce s-a făcut, ce urmează.")
                    }
                }
            }
        }
    }

    private var lastCostNote: LocalizedStringKey? {
        guard let cost = obligation.history.first?.totalCost else { return nil }
        return "Data trecută: \(cost.formattedCompact())."
    }

    // MARK: Paper

    @ViewBuilder private var paperSection: some View {
        if let paper = shape.paper {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader(paper.header, subtitle: paper.purpose)
                if document != nil, let bill = billPlan {
                    // A photo of the bill: filed as a bill, as the review says it.
                    billNotices(bill)
                    Button("Alege alt act") { isChoosingSource = true }
                        .frame(minHeight: 44)
                } else if let document {
                    let next = CaptureFiler.nextDay(in: document)
                    // A photo kept only on request (a bank card, a page with a card's number) isn't promised here.
                    let message: LocalizedStringKey = if let next, !shape.asksNewExpiry {
                        "Următorul termen: \(DueWording.date(next, today: CalendarDay(Date())))."
                    } else if next != nil {
                        "Am trecut mai sus data la care expiră. Verifică-o."
                    } else if document.photoIsOnRequest {
                        "Nu am găsit o dată nouă pe el."
                    } else {
                        "Nu am găsit o dată nouă pe el. Îl păstrez oricum."
                    }
                    DSNotice(.success, title: "Am citit actul", message: message)
                    Button("Alege alt act") { isChoosingSource = true }
                        .frame(minHeight: 44)
                } else {
                    DSActionCard(paper.actionTitle, subtitle: paper.example, systemImage: "doc.viewfinder") {
                        isChoosingSource = true
                    }
                    .disabled(isReading)
                    if isReading { DSDelayedProgress(label: "Citesc actul…") }
                    if session.phase == .failed {
                        DSNotice(.warning, title: "Actul nu s-a citit", message: "Încearcă o poză mai clară, cu actul întins și fără umbre.")
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
            let name = obligation.asset?.name ?? ""
            DSNotice(.success, title: "Am citit factura",
                     message: LocalizedStringKey(String(localized: "O trec în istoricul „\(name)”.", comment: "Am rezolvat: a photo of the bill being paid is logged in its subscription's history.")))
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
                let message: LocalizedStringResource = outcome.nextDue.map {
                    "\(title): gata. Următorul termen e pe \(DueWording.date($0, today: CalendarDay(Date())))."
                } ?? "\(title): gata."
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
