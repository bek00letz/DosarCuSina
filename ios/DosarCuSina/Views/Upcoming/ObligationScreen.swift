import EventKitUI
import SwiftData
import SwiftUI

/// The heads-up page for one obligation: everything needed to act, not a bare
/// reminder. When it is and why it matters; last time's price, who did it, the
/// policy number and the claims phone; what to bring; the actions; and how it
/// reminds. Pushed inside the caller's navigation stack.
struct ObligationScreen: View {
    let obligationID: UUID

    @Query private var matches: [Obligation]

    init(obligationID: UUID) {
        self.obligationID = obligationID
        _matches = Query(filter: #Predicate<Obligation> { $0.id == obligationID })
    }

    var body: some View {
        if let obligation = matches.first {
            ObligationPage(obligation: obligation)
        } else {
            DSEmptyState("Termenul nu mai există", systemImage: "calendar.badge.exclamationmark", message: "Poate a fost șters împreună cu secțiunea lui.")
        }
    }
}

private struct ObligationPage: View {
    let obligation: Obligation

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.announce) private var announce

    @State private var toast: DSToast?
    @State private var isCompleting = false
    @State private var isSnoozing = false
    @State private var isAddingToCalendar = false
    @State private var isRescheduling = false
    @State private var isAddingCustomLead = false
    @State private var isEditingReminders = false
    @State private var saveRequest: ReminderSaveRequest?
    @State private var unlockFailed = false

    private var vault: BiometricVaultManager { .shared }
    private var today: CalendarDay { CalendarDay(Date()) }

    private var template: CategoryTemplate? {
        obligation.asset.flatMap { try? TemplateStore(context: context).template(forKey: $0.templateKey) }
    }

    private var isLocked: Bool { vault.isLocked(sectionIsSensitive: template?.isSensitive ?? false) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                if isLocked {
                    lockedCard
                } else {
                    actions
                    lastTime
                    requirements
                    reminders
                    moreActions
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle(Text(verbatim: isLocked ? "" : obligation.title))
        .navigationBarTitleDisplayMode(.inline)
        .dsToast($toast)
        .dsAnimation(value: isLocked)
        .reminderPermissionGate($saveRequest)
        .task { await ReminderPermission.shared.refresh() }
        .sheet(isPresented: $isCompleting) {
            ObligationCompleteSheet(obligation: obligation) { result in
                isCompleting = false
                if let result { toast = result }
            }
        }
        .sheet(isPresented: $isAddingToCalendar) {
            CalendarEventEditor(title: obligation.title, day: obligation.dueDay(), notes: obligation.asset?.name)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isAddingCustomLead) {
            CustomLeadSheet { days in
                isAddingCustomLead = false
                if let days { setLead(days, on: true) }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isEditingReminders) {
            ReminderSettingsSheet(obligation: obligation) { isEditingReminders = false }
        }
        .sheet(isPresented: $isRescheduling) {
            RescheduleSheet(current: obligation.dueDay()) { day in
                isRescheduling = false
                if let day { reschedule(to: day) }
            }
            // A whole month and its button, without dragging the sheet up.
            .presentationDetents([.large])
        }
        .confirmationDialog(Text("Amâni până când?"), isPresented: $isSnoozing, titleVisibility: .visible) {
            ForEach(UpcomingActions.snoozeChoices, id: \.self) { days in
                Button(UpcomingActions.snoozeTitle(days: days)) { snooze(days) }
            }
            Button("Renunță", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                if let asset = obligation.asset, !isLocked {
                    Text(verbatim: asset.name).dsFont(.subheadline)
                } else if obligation.asset == nil {
                    Text("Pentru toată casa").dsFont(.subheadline)
                }
                if obligation.isExample { DSExampleBadge() }
            }
            Text(verbatim: isLocked ? String(localized: "O scadență protejată") : obligation.title)
                .dsFont(.display)
                .accessibilityAddTraits(.isHeader)
            if obligation.status == .active {
                let lines = DueWording.travelLines(due: obligation.dueDay(), rule: obligation.reminders.urgencyRule, today: today)
                    ?? [DueWording.line(kind: obligation.kind, due: obligation.dueDay(), today: today)]
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .dsFont(.headline, numeric: true)
                        .foregroundStyle(DSStatus.urgent(obligation.urgency().tone)?.textColor ?? DS.Palette.label)
                }
                if obligation.isSnoozed() {
                    Label("Amânat. Îți amintesc din nou pe \(DueWording.date(CalendarDay(obligation.snoozedUntil ?? Date()), today: today)).", systemImage: "clock.arrow.circlepath")
                        .dsFont(.subheadline)
                }
            } else {
                DSStatusBadge(obligation.status == .done ? .done : .later, text: Text(obligation.status == .paused ? "Pe pauză" : "Rezolvat"))
            }
            if !isLocked {
                Text(verbatim: obligation.notes ?? DueWording.consequence(obligation.reminders.consequence))
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(.top, DS.Space.xxs)
            }
        }
    }

    // MARK: Locked

    private var lockedCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label("Secțiunea e protejată", systemImage: vault.biometrySymbol)
                    .dsFont(.headline)
                Text("Deschide-o ca să vezi detaliile și să bifezi termenul.")
                    .dsFont(.subheadline)
                if unlockFailed {
                    Text("Nu s-a deschis. Poți încerca din nou, sau folosi codul telefonului.")
                        .dsFont(.footnote)
                        .foregroundStyle(DSStatus.soon.textColor)
                }
                DSPrimaryButton("Deschide cu \(vault.biometryName)", systemImage: vault.biometrySymbol) {
                    Task {
                        let result = await vault.unlock(reason: String(localized: "Deschide secțiunea protejată."))
                        unlockFailed = result != .success
                    }
                }
                .disabled(vault.isAuthenticating)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if obligation.status == .active {
            VStack(spacing: DS.Space.s) {
                DSPrimaryButton("Am rezolvat", systemImage: "checkmark") { isCompleting = true }
                HStack(spacing: DS.Space.s) {
                    DSSecondaryButton("Amână", systemImage: "clock.arrow.circlepath") { isSnoozing = true }
                    DSSecondaryButton("Pune în calendar", systemImage: "calendar.badge.plus") { isAddingToCalendar = true }
                }
            }
        } else if obligation.status == .paused {
            DSPrimaryButton("Pornește din nou", systemImage: "play.fill") { resume() }
        }
    }

    // MARK: Last time

    @ViewBuilder private var lastTime: some View {
        let last = obligation.history.first
        // This deadline's own facts, by its blueprint's roles: CASCO's page shows CASCO's policy.
        let facts = DeadlineFacts.of(obligation, template: template?.definition)
        let policyNumber = facts.policyNumber
        let claimsPhone = facts.claimsPhone
        // The class of the person the policy insures, read from them: it is theirs, not the car's.
        let ownerClass = facts.policyholder.flatMap { Policyholders.bonusMalus(ofPolicyholder: $0, among: Policyholders.people(in: context)) }
        let documents = documentsOnFile
        if last != nil || policyNumber != nil || claimsPhone != nil || ownerClass != nil || !documents.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Data trecută")
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        if let last {
                            lastCompletion(last)
                        }
                        if let policyNumber {
                            if last != nil { DS.Hairline() }
                            DSActionValueRow(title: Text("Număr poliță"), value: policyNumber, action: .copy)
                        }
                        if let claimsPhone {
                            DS.Hairline()
                            DSActionValueRow(title: Text("Telefon pentru daune"), value: claimsPhone, action: .call)
                        }
                        if let ownerClass {
                            if last != nil || policyNumber != nil || claimsPhone != nil { DS.Hairline() }
                            DSReadOnlyValueRow(label: Text("Clasa proprietarului", comment: "Policy page: the bonus-malus class of the person the RCA insures."),
                                               value: Text(verbatim: ownerClass))
                        }
                        if !documents.isEmpty {
                            DS.Hairline()
                            Text("Acte în dosar").dsFont(.footnote)
                            ForEach(documents) { document in
                                Button { AppNavigator.shared.open(.document(document.id)) } label: {
                                    DSListRow(
                                        title: Text(verbatim: document.title ?? document.fileName),
                                        subtitle: document.documentDate.map { Text(verbatim: DosarFormat.longDay($0)) },
                                        systemImage: "doc.text",
                                        showsChevron: true,
                                        trailing: { EmptyView() }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func lastCompletion(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: DosarFormat.longDay(entry.occurredAt))
                    .dsFont(.headline)
                Spacer()
                if !entry.effectiveCost.isEmpty {
                    Text(verbatim: entry.effectiveCost.formatted()).dsFont(.headline, numeric: true)
                }
            }
            ForEach(entry.providers ?? []) { provider in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.xs) {
                        Text(verbatim: provider.name).dsFont(.body)
                        DSStarRating(rating: provider.rating, style: .compact)
                    }
                    if let phone = provider.phone {
                        DSActionValueRow(title: Text("Telefon \(provider.name)"), value: phone, action: .call)
                    }
                }
            }
        }
    }

    private var documentsOnFile: [Attachment] {
        var seen = Set<UUID>()
        let linked = (obligation.attachments ?? []) + (obligation.history.first?.attachments ?? [])
        return linked
            .filter { !$0.isArchived && seen.insert($0.id).inserted }
            .sorted { ($0.documentDate ?? $0.createdAt) > ($1.documentDate ?? $1.createdAt) }
    }

    // MARK: Requirements

    @ViewBuilder private var requirements: some View {
        let items = ObligationRequirements.list(forBlueprint: obligation.blueprintKey, values: obligation.asset?.values ?? FieldValues())
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Ce-ți trebuie")
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(items) { item in
                            let inDosar = ObligationRequirements.isInDosar(item, asset: obligation.asset, on: obligation.dueDay())
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                                Image(systemName: inDosar == true ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(inDosar == true ? DSStatus.done.color : DS.Palette.tertiaryLabel)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: item.title).dsFont(.body)
                                    if inDosar == true {
                                        Text("E în dosar").dsFont(.footnote)
                                    } else if inDosar == false {
                                        Text("Nu e încă în dosar").dsFont(.footnote)
                                    }
                                }
                            }
                            .padding(.vertical, DS.Space.xxs)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    // MARK: Reminders

    /// Off: the settings moved to their own sheet (`ReminderSettingsSheet`). The inline card
    /// below is kept, switched off, as the way back until the owner has used the sheet.
    private static let editsRemindersInline = false

    @ViewBuilder private var reminders: some View {
        if obligation.status == .active {
            if Self.editsRemindersInline {
                inlineReminderEditor
            } else {
                reminderSummary
            }
        }
    }

    /// What the deadline reminds, in words, and the way into its settings.
    private var reminderSummary: some View {
        let profile = obligation.reminders
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Când te anunț")
            ReminderPermissionNotice()
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: ReminderWording.sentence(profile))
                        .dsFont(.headline)
                    if profile.followUpAfterLapse {
                        Text(verbatim: ReminderWording.followUp).dsFont(.footnote)
                    }
                    DS.Hairline().padding(.vertical, DS.Space.xxs)
                    Button { isEditingReminders = true } label: {
                        DSListRow("Schimbă când te anunț", systemImage: "bell", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The settings as they were on the page, before the sheet. Switched off
    /// (`editsRemindersInline`); remove once the owner agrees.
    @ViewBuilder private var inlineReminderEditor: some View {
        if obligation.status == .active {
            let profile = obligation.reminders
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Când te anunț")
                ReminderPermissionNotice()
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(verbatim: ReminderWording.sentence(profile))
                            .dsFont(.headline)
                        if profile.followUpAfterLapse {
                            Text(verbatim: ReminderWording.followUp).dsFont(.footnote)
                        }
                        DS.Hairline().padding(.vertical, DS.Space.xxs)
                        ForEach(ReminderPreset.rows(for: profile.leadDays), id: \.self) { days in
                            DSCheckRow(title: Text(verbatim: ReminderWording.rowTitle(days: days, from: .init(profile))), isOn: profile.leadDays.contains(days)) {
                                setLead(days, on: !profile.leadDays.contains(days))
                            }
                        }
                        Button { isAddingCustomLead = true } label: {
                            Label("Altă zi…", systemImage: "plus")
                                .font(.body.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        DS.Hairline().padding(.vertical, DS.Space.xxs)
                        DSCheckRow(
                            title: Text("Amintește-mi și a doua zi după termen"),
                            subtitle: Text("O singură dată, doar dacă nu e rezolvat."),
                            isOn: profile.followUpAfterLapse
                        ) {
                            let isOn = !profile.followUpAfterLapse
                            saveRequest = ReminderSaveRequest {
                                run { try ObligationActions(context: context).setFollowUpAfterLapse(obligation, isOn) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: More

    @ViewBuilder private var moreActions: some View {
        VStack(spacing: DS.Space.s) {
            if obligation.status == .active {
                DSCard {
                    VStack(spacing: 0) {
                        Button { isRescheduling = true } label: {
                            DSListRow("Schimbă data", subtitle: "Dacă termenul de pe act e altul.", systemImage: "calendar", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        DSRowSeparator()
                        Button(action: pause) {
                            DSListRow("Pune pe pauză", subtitle: "Nu-ți mai amintesc de el până îl pornești din nou.", systemImage: "pause.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // Taken back from the toast, so it doesn't ask first (docs/COPY_GUIDE.md).
            DSSecondaryButton("Șterge termenul", systemImage: "trash", role: .destructive, action: delete)
                .padding(.top, DS.Space.l)
        }
    }

    // MARK: Changes

    private func setLead(_ days: Int, on: Bool) {
        let current = obligation.reminders
        var leads = Set(current.leadDays)
        if on { leads.insert(days) } else { leads.remove(days) }
        let profile = current.withLeadDays(Array(leads))
        saveRequest = ReminderSaveRequest {
            run { try ObligationActions(context: context).setReminders(obligation, profile) }
        }
    }

    private func snooze(_ days: Int) {
        do {
            toast = try UpcomingActions(context: context).snooze(obligation, days: days, title: obligation.title)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    private func reschedule(to day: CalendarDay) {
        do {
            let receipt = try ObligationActions(context: context).reschedule(obligation, to: day)
            toast = .undo("Termenul e acum pe \(DueWording.date(day, today: today)).", receipt: receipt)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    private func pause() {
        do {
            let receipt = try ObligationActions(context: context).pause(obligation)
            toast = .undo("Am pus „\(obligation.title)” pe pauză.", receipt: receipt)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    private func resume() {
        do {
            let receipt = try ObligationActions(context: context).resume(obligation)
            toast = .undo("Am pornit din nou „\(obligation.title)”.", receipt: receipt)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    /// Deletes the deadline and closes its page; the shell keeps the toast's "Anulează".
    private func delete() {
        let title = obligation.title
        do {
            let receipt = try ObligationActions(context: context).delete(obligation)
            announce(.undoDeletion(LocalizedStringResource("Am șters termenul „\(title)”.", comment: "Toast after deleting a deadline."), receipt: receipt))
            dismiss()
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    private func run(_ change: () throws -> Void) {
        do { try change() } catch { toast = UpcomingActions.failureToast(error) }
    }
}

// MARK: - Complete

/// "Am rezolvat": when, how much, and optionally a photo of the new document,
/// whose date becomes the next deadline.
private struct ObligationCompleteSheet: View {
    let obligation: Obligation
    let onClose: (DSToast?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var date: Date? = Date()
    @State private var amount: Decimal?
    @State private var currency = Money.defaultCurrency
    @State private var source: CaptureSource?
    @State private var isChoosingSource = false
    /// Reading the new document. It ends with the sheet: a reading still running stops.
    @State private var session = CaptureSession()
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var readingQuestion: LowerReadingQuestion?
    /// A bank card's photo is kept only when the person asks.
    @State private var keepsPhotoOnRequest = false
    /// A bill that only looked like one already filed, by its day and total: the person
    /// said it is another bill ("E altă factură"). A new photo asks again.
    @State private var isAnotherBill = false

    private var isReading: Bool { session.phase == .reading }
    private var document: CaptureResult? { session.result }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            DSDateField("Când", date: $date, in: Date.distantPast...Date.now, isRequired: true)
                            DSMoneyField("Cât a costat", amount: $amount, currencyCode: $currency, footnote: lastCostNote)
                        }
                    }
                    documentSection
                    if let document, document.kind.profile.photoIsOptIn {
                        KeepPhotoChoice(keepsPhoto: $keepsPhotoOnRequest)
                    }
                    if let errorMessage {
                        DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                    }
                    DSPrimaryButton("Salvează", systemImage: "checkmark") { save() }
                        .disabled(isSaving || isReading || date == nil)
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .navigationTitle(Text("Am rezolvat: \(obligation.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: amount != nil || document != nil)
            .examplePrompt($exampleQuestion) { save() }
            .readingPrompt($readingQuestion) { save(lowerReading: $0) }
            .onChange(of: document?.id) { _, _ in
                isAnotherBill = false
                if amount == nil, let total = document?.field(.total)?.value.money {
                    amount = total.amount
                    currency = total.currency
                }
            }
            .confirmationDialog("Actul nou", isPresented: $isChoosingSource, titleVisibility: .visible) {
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

    private var lastCostNote: LocalizedStringKey? {
        guard let cost = obligation.history.first?.totalCost else { return nil }
        return "Data trecută: \(cost.formattedCompact())."
    }

    @ViewBuilder private var documentSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Actul nou", subtitle: "Opțional. Din el iau data următoare.")
            if document != nil, let bill = billPlan {
                // A photo of the bill: filed as a bill, as the review says it.
                billNotices(bill)
                Button("Alege alt act") { isChoosingSource = true }
                    .frame(minHeight: 44)
            } else if let document {
                let next = CaptureFiler.nextDay(in: document)
                // A bank card's photo is kept only on request, so it isn't promised here.
                let message: LocalizedStringKey = if let next {
                    "Următorul termen: \(DueWording.date(next, today: CalendarDay(Date())))."
                } else if document.kind.profile.photoIsOptIn {
                    "Nu am găsit o dată nouă pe el."
                } else {
                    "Nu am găsit o dată nouă pe el. Îl păstrez oricum."
                }
                DSNotice(.success, title: "Am citit actul", message: message)
                Button("Alege alt act") { isChoosingSource = true }
                    .frame(minHeight: 44)
            } else {
                DSActionCard("Fotografiază actul nou", subtitle: "Polița, raportul sau chitanța.", systemImage: "doc.viewfinder") {
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

    /// What saving does with a photo of the bill on its subscription (`CaptureFiler.billPlan`):
    /// the bill in Istoric, once, and its meter index. Nil for any other document.
    private var billPlan: CaptureFilingPlan? {
        guard document != nil else { return nil }
        return try? CaptureFiler(context: context).billPlan(for: completion(date: date ?? Date()))
    }

    /// The bill already in the binder, or where it goes, and its index: the review's own words.
    @ViewBuilder private func billNotices(_ bill: CaptureFilingPlan) -> some View {
        if let filed = bill.filedBill {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSNotice(.info, title: "Factura e deja în dosar",
                         message: LocalizedStringKey(CaptureReviewView.filedBillText(filed, today: CalendarDay(Date()))))
                if filed.mayBeAnother {
                    DSCompactButton("E altă factură", systemImage: "doc.badge.plus") {
                        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { isAnotherBill = true }
                    }
                }
            }
            .transition(.opacity)
        } else {
            let name = obligation.asset?.name ?? ""
            DSNotice(.success, title: "Am citit factura",
                     message: LocalizedStringKey(String(localized: "O trec în istoricul „\(name)”.", comment: "Am rezolvat: a photo of the bill being paid is logged in its subscription's history.")))
        }
        if let meter = bill.meter {
            Label { Text(verbatim: CaptureReviewView.meterText(meter)).dsFont(.footnote) } icon: {
                Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(DS.Palette.secondaryLabel)
            }
            .labelStyle(DSLeadingIconLabelStyle())
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What saving files, from the sheet as it stands.
    private func completion(date: Date) -> CaptureFiler.Completion {
        let cost = amount.map { Money($0, currency: currency) }
        return CaptureFiler.Completion(obligation: obligation, date: date, cost: cost, document: document,
                                       keepsPhotoOnRequest: keepsPhotoOnRequest, isAnotherBill: isAnotherBill)
    }

    private func read(_ payload: CaptureRequest.Payload) {
        // A bank card's new card is read only on the phone, like any bank card (`PhoneOnlyReading`).
        session.destination.staysOnPhone = obligation.asset.map { PhoneOnlyReading.holdsOne($0.values) } ?? false
        session.read(payload)
    }

    private func save(lowerReading: LowerReadingAnswer? = nil) {
        guard let date else { return }
        isSaving = true
        errorMessage = nil
        let title = obligation.title
        Task {
            do {
                var filer = CaptureFiler(context: context)
                filer.lowerReading = lowerReading
                let outcome = try await filer.file(.completion(completion(date: date)))
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

// MARK: - Small sheets

/// "Altă zi": a reminder this many days before, beyond the presets. A page pushed inside
/// the reminder settings sheet, whose back button is the way out without adding.
struct CustomLeadPage: View {
    let onAdd: (Int) -> Void
    @State private var days = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Stepper(value: $days, in: 1...365) {
                    // The page only adds a lead before the day (1 to 365 days), worded the same either way.
                    Text(verbatim: ReminderWording.rowTitle(days: days, from: .dueDay))
                        .dsFont(.headline, numeric: true)
                }
                .frame(minHeight: 44)
                DSPrimaryButton("Adaugă", systemImage: "plus") { onAdd(days) }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Altă zi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The same page in a sheet of its own, with "Renunță": only for the deadline page's
/// inline reminder settings, kept switched off as the way back (`editsRemindersInline`).
struct CustomLeadSheet: View {
    let onClose: (Int?) -> Void

    var body: some View {
        NavigationStack {
            CustomLeadPage { days in onClose(days) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Renunță") { onClose(nil) } }
                }
        }
    }
}

/// A different due date, for when the document says otherwise.
private struct RescheduleSheet: View {
    let current: CalendarDay
    let onClose: (CalendarDay?) -> Void
    @State private var date: Date

    init(current: CalendarDay, onClose: @escaping (CalendarDay?) -> Void) {
        self.current = current
        self.onClose = onClose
        self._date = State(initialValue: current.startDate())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("Data nouă", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(DS.Space.m)
            }
            .dsPinnedAction {
                DSPrimaryButton("Mută termenul", systemImage: "checkmark") { onClose(CalendarDay(date)) }
            }
            .navigationTitle("Schimbă data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Renunță") { onClose(nil) } }
            }
        }
    }
}

/// The system's own event editor. It writes to Calendar out of process, so the
/// app asks for no calendar permission and never depends on Calendar.
private struct CalendarEventEditor: UIViewControllerRepresentable {
    let title: String
    let day: CalendarDay
    let notes: String?

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = true
        event.startDate = day.startDate()
        event.endDate = day.startDate()
        event.notes = notes
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
