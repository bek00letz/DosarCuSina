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

    /// Where the section's name in the header goes: its section's page; nil for a deadline of
    /// the whole household, and while its section is locked (the name isn't shown then).
    static func sectionRoute(for obligation: Obligation, isLocked: Bool) -> AppRoute? {
        guard !isLocked, let asset = obligation.asset else { return nil }
        return .asset(asset.id)
    }
}

private struct ObligationPage: View {
    let obligation: Obligation

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.announce) private var announce
    @Environment(AppPreferences.self) private var preferences

    @State private var toast: DSToast?
    /// "Am rezolvat" open, for a kind that asks something (`CompletionEntry`).
    @State private var completing: CompletionRequest?
    @State private var isSnoozing = false
    @State private var isAddingToCalendar = false
    @State private var isRescheduling = false
    @State private var isAddingCustomLead = false
    @State private var isEditingReminders = false
    /// "Editează": the one sheet for its name, date, repeat and reminders.
    @State private var isEditing = false
    @State private var saveRequest: ReminderSaveRequest?
    @State private var unlockFailed = false
    /// "Adaugă o notă" after a chore's "Gata".
    @State private var noteRequest: HistoryNoteRequest?
    /// The toast of the last one-tap "Gata", while it shows.
    @State private var quickToastID: UUID?

    private var vault: BiometricVaultManager { .shared }
    private var today: CalendarDay { CalendarDay(Date()) }

    private var template: CategoryTemplate? {
        obligation.asset.flatMap { try? TemplateStore(context: context).template(forKey: $0.templateKey) }
    }

    private var isLocked: Bool { vault.isLocked(sectionIsSensitive: template?.isSensitive ?? false) }

    /// On: one "Editează" (the toolbar's, and the schedule card's) opens one sheet for the
    /// deadline's name, importance, date, repeat, reminders and reminder time, saved once
    /// (`DeadlineEditSheet`). Off: the four earlier ways ("Schimbă data", "Schimbă cum se repetă",
    /// "Schimbă când te anunț" with its "Ora amintirii"), kept as the way back until the owner
    /// has used the sheet.
    static let editsInOneSheet = true

    /// "Editează" is offered while the deadline runs or is paused, and the section is open.
    private var canEdit: Bool {
        Self.editsInOneSheet && !isLocked && (obligation.status == .active || obligation.status == .paused)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                if isLocked {
                    lockedCard
                } else {
                    let facts = DeadlinePageFacts.of(obligation, template: template?.definition, in: context)
                    actions
                    lastTime(facts)
                    policyCard(facts)
                    requirements
                    if Self.editsInOneSheet {
                        schedule
                    } else {
                        if obligation.status == .active { ObligationRepeatSection(obligation: obligation, toast: $toast) }
                        reminders
                    }
                    moreActions
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle(Text(verbatim: isLocked ? "" : obligation.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isEditing = true } label: {
                        Text("Editează", comment: "Toolbar button that edits a deadline: its name, date, repeat and reminders.")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            DeadlineEditSheet(obligation: obligation) { result in
                isEditing = false
                if let result { toast = result }
            }
        }
        .dsToast($toast)
        .historyNoteSheet($noteRequest, toast: $toast)
        .dsAnimation(value: isLocked)
        .reminderPermissionGate($saveRequest)
        .task { await ReminderPermission.shared.refresh() }
        .completionSheet($completing, toast: $toast)
        .sheet(isPresented: $isAddingToCalendar) {
            CalendarEventEditor(title: obligation.title, day: obligation.dueDay, notes: obligation.asset?.name)
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
            RescheduleSheet(current: obligation.dueDay) { day in
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
                if let asset = obligation.asset, let route = ObligationScreen.sectionRoute(for: obligation, isLocked: isLocked) {
                    // The section's name opens the section.
                    NavigationLink(value: route) {
                        HStack(spacing: DS.Space.xxs) {
                            Text(verbatim: asset.name)
                                .dsFont(.subheadline)
                                .foregroundStyle(DS.Palette.accent)
                            Image(systemName: "chevron.forward")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(DS.Palette.accent)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: DS.Control.minimumHitTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityHint(Text("Deschide secțiunea.", comment: "VoiceOver hint of the section's name on a deadline's page."))
                } else if obligation.asset == nil {
                    Text("Pentru toată casa").dsFont(.subheadline)
                }
                if obligation.isExample { DSExampleBadge() }
            }
            Text(verbatim: isLocked ? String(localized: "O scadență protejată") : obligation.title)
                .dsFont(.display)
                .accessibilityAddTraits(.isHeader)
            if obligation.status == .active {
                let lines = DueWording.travelLines(due: obligation.dueDay, rule: obligation.urgencyRule, today: today)
                    ?? [DueWording.line(kind: obligation.kind, due: obligation.dueDay, today: today)]
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .dsFont(.headline, numeric: true)
                        .foregroundStyle(DSStatus.urgent(obligation.urgency().tone)?.textColor ?? DS.Palette.label)
                }
                if obligation.isSnoozed() {
                    Label("Amânat. Îți amintesc din nou pe \(DueWording.date(obligation.snoozedUntil ?? today, today: today)).", systemImage: "clock.arrow.circlepath")
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
            // What completing asks is the kind's: a chore is done in one tap, the rest open the
            // sheet, the same entry as Urmează's swipe and menu (`CompletionEntry`).
            let shape = obligation.completion(template: template?.definition)
            // The cycle this page shows, as the person saw it when they tapped.
            let seen = obligation.dueDay
            VStack(spacing: DS.Space.s) {
                DSPrimaryButton(shape.actionTitle, systemImage: "checkmark") {
                    startCompleting(cycle: seen)
                }
                // A second "Gata" waits while the first one's toast shows, so a double tap
                // never closes the next cycle too.
                .disabled(shape.isOneTap && quickToastID != nil && toast?.id == quickToastID)
                HStack(spacing: DS.Space.s) {
                    DSSecondaryButton("Amână", systemImage: "clock.arrow.circlepath") { isSnoozing = true }
                    DSSecondaryButton("Pune în calendar", systemImage: "calendar.badge.plus") { isAddingToCalendar = true }
                }
            }
        } else if obligation.status == .paused {
            DSPrimaryButton("Pornește din nou", systemImage: "play.fill") { resume() }
        } else if obligation.status == .done, let document = obligation.asset,
                  let replacement = obligation.completion(template: template?.definition).replacement {
            // A personal document renewed: the new one is a document of its own.
            DocumentReplacementCard(document: document, replacement: replacement) { dismiss() }
        }
    }

    // MARK: Last time

    /// *Data trecută*: the last time it was done (its day, cost, note and who did it), only
    /// once it has been.
    @ViewBuilder private func lastTime(_ facts: DeadlinePageFacts) -> some View {
        if let last = facts.lastCompletion {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Data trecută")
                DSCard { lastCompletion(last) }
            }
        }
    }

    /// This deadline's own policy (CASCO's page shows CASCO's) and the documents on file, only
    /// what it has; a separator only between two rows.
    @ViewBuilder private func policyCard(_ facts: DeadlinePageFacts) -> some View {
        if facts.showsPolicyCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader(verbatim: String(localized: facts.policyCardTitle))
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        ForEach(Array(facts.policyRows.enumerated()), id: \.element) { index, row in
                            if index > 0 { DS.Hairline() }
                            policyRow(row)
                        }
                        if facts.namesDocumentsInside {
                            DS.Hairline()
                            Text("Acte în dosar").dsFont(.footnote)
                        }
                        ForEach(facts.documents) { document in
                            Button { AppNavigator.shared.open(.document(document.id)) } label: {
                                DSListRow(
                                    title: Text(verbatim: document.title ?? document.fileName),
                                    subtitle: document.documentDay.map { Text(verbatim: DosarFormat.longDay($0)) },
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

    @ViewBuilder private func policyRow(_ row: DeadlinePageFacts.PolicyRow) -> some View {
        switch row {
        case .policyNumber(let number):
            DSActionValueRow(title: Text("Număr poliță"), value: number, action: .copy)
        case .claimsPhone(let phone):
            DSActionValueRow(title: Text("Telefon pentru daune"), value: phone, action: .call)
        case .ownerClass(let ownerClass):
            // The class of the person the policy insures, read from them: it is theirs, not the car's.
            DSReadOnlyValueRow(label: Text("Clasa proprietarului", comment: "Policy page: the bonus-malus class of the person the RCA insures."),
                               value: Text(verbatim: ownerClass))
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
            // What the person noted last time ("Adaugă o notă" after a chore, a check-up's note).
            if let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(verbatim: note)
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Requirements

    @ViewBuilder private var requirements: some View {
        let items = ObligationRequirements.list(forBlueprint: obligation.blueprintKey, values: obligation.asset?.values ?? FieldValues())
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Ce-ți trebuie")
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(items) { item in
                            let inDosar = ObligationRequirements.isInDosar(item, asset: obligation.asset, on: obligation.dueDay)
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

    /// How it repeats and when it reminds, in one line („La fiecare 3 zile, de la data la care
    /// l-ai făcut · Îți amintesc cu o zi înainte, la 07:30”), and "Editează" again, where the
    /// person reads it. While it runs; the sheet is the toolbar's too.
    @ViewBuilder private var schedule: some View {
        if obligation.status == .active {
            let profile = obligation.cycleReminders
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Cum se repetă și când te anunț")
                ReminderPermissionNotice()
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(verbatim: ReminderWording.schedule(rule: obligation.recurrence, profile: profile,
                                                                minuteOfDay: obligation.reminderMinuteOfDay, usual: preferences.reminderMinuteOfDay))
                            .dsFont(.headline, numeric: true)
                            .fixedSize(horizontal: false, vertical: true)
                        if profile.followUpAfterLapse {
                            Text(verbatim: ReminderWording.followUp).dsFont(.footnote)
                        }
                        DS.Hairline().padding(.vertical, DS.Space.xxs)
                        Button { isEditing = true } label: {
                            DSListRow("Editează termenul", subtitle: "Data, cum se repetă și când te anunț.", systemImage: "slider.horizontal.3", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// What the deadline reminds, in words, and the way into its settings. Switched off with
    /// the other earlier ways (`editsInOneSheet`).
    private var reminderSummary: some View {
        let profile = obligation.cycleReminders
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Când te anunț")
            ReminderPermissionNotice()
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: ReminderWording.sentence(profile))
                        .dsFont(.headline)
                    Text(verbatim: ReminderWording.atTime(obligation.reminderMinuteOfDay, usual: preferences.reminderMinuteOfDay))
                        .dsFont(.subheadline, numeric: true)
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
                        // The date is in "Editează" now; this row is the way back (`editsInOneSheet`).
                        if !Self.editsInOneSheet {
                            Button { isRescheduling = true } label: {
                                DSListRow("Schimbă data", subtitle: "Dacă termenul de pe act e altul.", systemImage: "calendar", showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            DSRowSeparator()
                        }
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
            run { try ObligationActions(context: context).setReminders(obligation, profile, startedFrom: current) }
        }
    }

    /// "Gata" or "Am rezolvat", by the kind (`CompletionEntry`): a chore is done today, no
    /// sheet, and the toast takes it back or adds a note to it; any other kind opens the sheet.
    /// Only for `cycle`, the due day the page showed when the person tapped.
    private func startCompleting(cycle: CalendarDay) {
        do {
            let start = try CompletionEntry(context: context).start(obligation, cycle: cycle) { entryID, shown in
                noteRequest = HistoryNoteRequest(entryID: entryID, restoring: shown)
            }
            switch start {
            case .done(let done):
                quickToastID = done.id
                toast = done
            case .asks(let request):
                completing = request
            }
        } catch {
            if let failure = UpcomingActions.quietFailureToast(error) { toast = failure }
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
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .dsPinnedAction {
            DSPrimaryButton("Adaugă", systemImage: "plus") { onAdd(days) }
        }
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

/// A different due date, for when the document says otherwise. Kept, switched off with the
/// page's other earlier ways (`ObligationPage.editsInOneSheet`): the date is in "Editează" now.
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
