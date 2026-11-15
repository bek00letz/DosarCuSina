import SwiftData
import SwiftUI

/// "Editează" on a deadline's page: everything about it the person sets, in one sheet saved
/// once. Its name and how important it is (only a deadline of their own), the due date, how it
/// repeats (`DSRepeatField`), its reminders and its reminder time (`DSReminderTimeField`). One
/// pinned *Salvează* saves it all as one undoable step (`ObligationActions.edit`), laying only
/// what was changed here over the deadline as it is then (`ThreeWay`, from `start`). Closing it
/// asks first only after a real change.
struct DeadlineEditSheet: View {
    let obligation: Obligation
    /// With the toast to show, or nil when nothing was saved.
    let onClose: (DSToast?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(AppPreferences.self) private var preferences

    /// The deadline as the sheet opened with it.
    private let start: DeadlineEdit
    @State private var draft: DeadlineEdit
    /// The due date as the field holds it: nil only while the person has cleared it.
    @State private var due: Date?
    /// "Se repetă" as the control holds it, so a number set before "Nu se repetă" comes back.
    @State private var repeatChoice: RepeatChoice
    @State private var isAddingCustomLead = false
    @State private var reveals = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveRequest: ReminderSaveRequest?

    init(obligation: Obligation, onClose: @escaping (DSToast?) -> Void) {
        self.obligation = obligation
        self.onClose = onClose
        let start = DeadlineEdit(obligation)
        self.start = start
        self._draft = State(initialValue: start)
        self._due = State(initialValue: start.dueDay.startDate(in: .dosar))
        self._repeatChoice = State(initialValue: RepeatChoice(rule: start.recurrence) ?? .never)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    if draft.isPersonsOwn { whatSection }
                    whenSection
                    repeatSection
                    remindersSection
                }
                .padding(DS.Space.m)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, reveals)
            .dsPinnedAction {
                DSPrimaryButton("Salvează", systemImage: "checkmark", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
            } note: {
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                }
            }
            .navigationTitle(Text("Editează termenul", comment: "Title of the sheet that edits a deadline."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            // "Altă zi…" is a page inside this sheet: back adds nothing, "Adaugă" adds the day.
            .navigationDestination(isPresented: $isAddingCustomLead) {
                CustomLeadPage { days in
                    isAddingCustomLead = false
                    draft.reminders = draft.reminders.withLeadDays(draft.reminders.leadDays + [days])
                }
            }
            .dsDiscardGuard(hasChanges: hasChanges)
        }
        .reminderPermissionGate($saveRequest)
        .presentationDetents([.large])
    }

    private var hasChanges: Bool { draft != start || due == nil }

    // MARK: Sections

    /// Its name and how important it is: only a deadline of the person's own.
    private var whatSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Ce termen")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSTextField("Ce trebuie făcut", text: $draft.title, prompt: "Cazier pentru angajare", isRequired: true)
                    if draft.offersImportance {
                        DSChoiceField("Cât de important e", selection: importance, options: DeadlineChoice.Importance.allCases,
                                      isRequired: true, footnote: "Hotărăște ce te întreb când îl bifezi.") { $0.title }
                    }
                }
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Când e termenul")
            DSCard {
                DSDateField("Data", date: dueDate, isRequired: true)
            }
        }
    }

    /// The control for a rule of every so many days, weeks, months or years; any other rule
    /// (fixed dates, a counter, the law) in words, since its category decides it.
    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Cum se repetă")
            DSCard {
                if start.offersRepeat {
                    DSRepeatField(choice: repeats)
                } else {
                    Text(verbatim: RepeatWording.sentence(start.recurrence))
                        .dsFont(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if draft.recurrence != start.recurrence {
                Text("Regula nouă se aplică după ce îl bifezi.", comment: "Under the repeat control in a deadline's edit sheet: the new rule counts from the next completion.")
                    .dsFont(.footnote)
                    .padding(.horizontal, DS.Space.xs)
                    .transition(.opacity)
            }
        }
        .dsAnimation(value: draft.recurrence != start.recurrence)
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Când te anunț")
            ReminderPermissionNotice()
            ReminderSettingsForm(
                settings: reminderSettings,
                onToggleLead: { days in draft.reminders = draft.reminders.withLeadDays(ReminderPreset.toggling(days, in: draft.reminders.leadDays)) },
                onOtherDay: { isAddingCustomLead = true },
                onToggleFollowUp: { draft.reminders.followUpAfterLapse.toggle() },
                onRestoreUsual: { if let usual { draft.reminders = usual } }
            )
            DSCard {
                DSReminderTimeField(minuteOfDay: $draft.reminderMinuteOfDay, usualMinuteOfDay: preferences.reminderMinuteOfDay, startsCollapsed: true)
            }
        }
    }

    // MARK: Values

    /// The reminders its category's blueprint gives; nil for a deadline of the person's own.
    private var usual: ReminderProfile? { DeadlineReminders.usual(for: obligation, in: context) }

    /// The editor's view of the draft: "Revino la cele obișnuite" while the draft's reminders
    /// differ from the usual ones; the sentence counted in the cycle the draft gives.
    private var reminderSettings: ReminderSettings {
        ReminderSettings(profile: draft.reminders, usual: usual.flatMap { $0 == draft.reminders ? nil : $0 }, due: draft.dueDay,
                         rule: draft.recurrence, minuteOfDay: draft.reminderMinuteOfDay, usualMinuteOfDay: preferences.reminderMinuteOfDay)
    }

    private var importance: Binding<DeadlineChoice.Importance?> {
        Binding { draft.importance } set: { if let answer = $0 { draft.choose(answer) } }
    }

    private var dueDate: Binding<Date?> {
        Binding { due } set: { date in
            due = date
            if let date { draft.dueDay = CalendarDay(date, calendar: calendar) }
        }
    }

    private var repeats: Binding<RepeatChoice> {
        Binding { repeatChoice } set: { choice in
            repeatChoice = choice
            draft.recurrence = choice.rule
        }
    }

    // MARK: Saving

    /// Returns at once while the save runs, so two quick taps save once.
    private func save() {
        guard !isSaving else { return }
        guard draft.canSave, due != nil else { reveals = true; return }
        guard draft != start else { onClose(nil); return }
        isSaving = true
        // The first save that reminds explains the notification question first.
        saveRequest = ReminderSaveRequest { commit() }
    }

    private func commit() {
        defer { isSaving = false }
        do {
            let receipt = try ObligationActions(context: context, calendar: calendar).edit(obligation, to: draft, startedFrom: start)
            errorMessage = nil
            onClose(receipt.map { .undo("Am salvat „\(obligation.title)”.", receipt: $0) })
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}
