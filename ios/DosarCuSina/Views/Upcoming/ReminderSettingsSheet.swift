import SwiftData
import SwiftUI

/// What the reminder editor shows for one deadline: its reminders, and its usual ones when
/// "Revino la cele obișnuite" is offered, how it repeats (a lead longer than the repeat doesn't
/// remind, `ReminderProfile.forCycle`) and its reminder time.
struct ReminderSettings: Equatable {
    var profile: ReminderProfile
    /// The reminders its document gives, only when the person set others
    /// (`DeadlineReminders.restorable`); nil hides "Revino la cele obișnuite".
    var usual: ReminderProfile?
    /// The cycle its leads count back in: its due day and how it repeats.
    var due: CalendarDay
    var rule: RecurrenceRule
    /// Its own reminder time, nil for the general one.
    var minuteOfDay: Int?
    /// The general reminder time, from Settings.
    var usualMinuteOfDay: Int

    init(profile: ReminderProfile, usual: ReminderProfile?, due: CalendarDay = CalendarDay(Date()), rule: RecurrenceRule = .none,
         minuteOfDay: Int? = nil, usualMinuteOfDay: Int = AppPreferences.defaultReminderMinuteOfDay) {
        self.profile = profile
        self.usual = usual
        self.due = due
        self.rule = rule
        self.minuteOfDay = minuteOfDay
        self.usualMinuteOfDay = usualMinuteOfDay
    }

    @MainActor
    init(obligation: Obligation, in context: ModelContext, usualMinuteOfDay: Int = AppPreferences.defaultReminderMinuteOfDay) {
        self.init(profile: obligation.reminders, usual: DeadlineReminders.restorable(obligation, in: context), due: obligation.dueDay,
                  rule: obligation.recurrence, minuteOfDay: obligation.reminderMinuteOfDay, usualMinuteOfDay: usualMinuteOfDay)
    }

    /// The reminders as this cycle sends them: what the sentence says.
    var cycleProfile: ReminderProfile { profile.forCycle(due: due, rule: rule) }

    /// Whether a lead reminds in this cycle, or is longer than how often it repeats.
    func fits(_ days: Int) -> Bool { profile.fits(lead: days, due: due, rule: rule) }

    /// The lead rows, largest first: the presets that fit how often it repeats, and every
    /// other lead the profile holds.
    var leadRows: [Int] { ReminderPreset.rows(for: profile.leadDays).filter { profile.leadDays.contains($0) || fits($0) } }

    /// "Ora obișnuită (09:00)" or "07:30".
    var timeText: String { ReminderWording.time(minuteOfDay, usual: usualMinuteOfDay) }
}

/// The editor itself: the reminder sentence, a row per lead, "Altă zi…", the follow-up and,
/// when offered, the usual reminders. It only reports taps; `ReminderSettingsSheet` saves.
struct ReminderSettingsForm: View {
    let settings: ReminderSettings
    var onToggleLead: (Int) -> Void = { _ in }
    var onOtherDay: () -> Void = {}
    var onToggleFollowUp: () -> Void = {}
    var onRestoreUsual: () -> Void = {}
    /// "Ora amintirii" as a row that opens its page; nil leaves the row out, for a screen that
    /// shows the time field itself (the deadline's "Editează").
    var onReminderTime: (() -> Void)?

    var body: some View {
        let profile = settings.profile
        VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(verbatim: ReminderWording.sentence(settings.cycleProfile))
                    .dsFont(.headline)
                if profile.followUpAfterLapse {
                    Text(verbatim: ReminderWording.followUp).dsFont(.footnote)
                }
            }
            .accessibilityElement(children: .combine)

            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(settings.leadRows, id: \.self) { days in
                        DSCheckRow(title: Text(verbatim: ReminderWording.rowTitle(days: days, from: .init(profile))),
                                   subtitle: settings.fits(days) ? nil : Text("Se repetă mai des de atât, așa că nu te anunț atât de devreme.",
                                                                              comment: "Under a reminder lead longer than how often the deadline repeats."),
                                   isOn: profile.leadDays.contains(days)) {
                            onToggleLead(days)
                        }
                    }
                    Button(action: onOtherDay) {
                        Label("Altă zi…", systemImage: "plus")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: DS.Control.minimumHitTarget, alignment: .leading)
                            .contentShape(.rect)
                    }
                }
            }

            if let onReminderTime {
                DSCard {
                    Button(action: onReminderTime) {
                        DSListRow(title: Text("Ora amintirii", comment: "Reminder settings: the time of day this deadline reminds at."),
                                  subtitle: Text(verbatim: settings.timeText), systemImage: "clock", showsChevron: true, trailing: { EmptyView() })
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Ora amintirii"))
                    .accessibilityValue(Text(verbatim: settings.timeText))
                }
            }

            DSCard {
                DSCheckRow(
                    title: Text("Amintește-mi și a doua zi după termen"),
                    subtitle: Text("O singură dată, doar dacă nu e rezolvat."),
                    isOn: profile.followUpAfterLapse,
                    action: onToggleFollowUp
                )
            }

            if let usual = settings.usual {
                DSCard { restoreUsualRow(usual) }
                    .transition(.opacity)
            }
        }
        .dsAnimation(value: settings.usual)
    }

    /// "Revino la cele obișnuite", with the usual reminders in words under it.
    private func restoreUsualRow(_ usual: ReminderProfile) -> some View {
        let sentence = ReminderWording.sentence(usual)
        return Button(action: onRestoreUsual) {
            DSListRow(title: Text("Revino la cele obișnuite", comment: "Reminder settings: put back the reminders the deadline's document gives."),
                      subtitle: Text(verbatim: sentence), systemImage: "arrow.uturn.backward", trailing: { EmptyView() })
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Revino la cele obișnuite"))
        .accessibilityValue(Text(verbatim: sentence))
        .accessibilityHint(Text("Pune la loc zilele în care anunț de obicei pentru acest termen.", comment: "VoiceOver hint of the button that puts back the usual reminders."))
    }
}

/// Kept, switched off (`ObligationPage.editsInOneSheet`), as the way back: the reminders and
/// their time are in the deadline's one "Editează" (`DeadlineEditSheet`) now, which reuses
/// `ReminderSettingsForm`.
///
/// "Schimbă când te anunț": the deadline's reminder settings, opened from its page. Each
/// change is saved at once (after the notification explanation when it is due), as the
/// page's settings always were, so there is nothing to discard. Going back to the usual
/// reminders shows an undo toast.
struct ReminderSettingsSheet: View {
    let obligation: Obligation
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var preferences
    @State private var toast: DSToast?
    @State private var saveRequest: ReminderSaveRequest?
    @State private var isAddingCustomLead = false
    @State private var isChoosingTime = false
    @State private var restoredCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                ReminderSettingsForm(
                    settings: ReminderSettings(obligation: obligation, in: context, usualMinuteOfDay: preferences.reminderMinuteOfDay),
                    onToggleLead: { days in setLeads(ReminderPreset.toggling(days, in: obligation.reminders.leadDays)) },
                    onOtherDay: { isAddingCustomLead = true },
                    onToggleFollowUp: toggleFollowUp,
                    onRestoreUsual: { saveRequest = ReminderSaveRequest { restoreUsual() } },
                    onReminderTime: { isChoosingTime = true }
                )
                .padding(DS.Space.m)
                .dsReadableWidth()
            }
            .background(DS.Palette.background)
            .navigationTitle("Când te anunț")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(action: onClose) { Text("Închide", comment: "Closes the reminders sheet; each choice is already saved.") } }
            }
            // "Altă zi…" is a page inside this sheet, with a back button, not a sheet on
            // top of it: back adds nothing, "Adaugă" adds the day and comes back.
            .navigationDestination(isPresented: $isAddingCustomLead) {
                CustomLeadPage { days in
                    isAddingCustomLead = false
                    setLeads(obligation.reminders.leadDays + [days])
                }
            }
            // "Ora amintirii" is a page inside this sheet too: back keeps the time as it was,
            // "Salvează ora" saves it as one step the toast can take back.
            .navigationDestination(isPresented: $isChoosingTime) {
                ReminderTimePage(startedFrom: obligation.reminderMinuteOfDay, usualMinuteOfDay: preferences.reminderMinuteOfDay) { minute in
                    isChoosingTime = false
                    saveRequest = ReminderSaveRequest { setTime(minute) }
                }
            }
        }
        .dsToast($toast)
        .reminderPermissionGate($saveRequest)
        .sensoryFeedback(.success, trigger: restoredCount)
        .presentationDetents([.large])
    }

    private func setLeads(_ leads: [Int]) {
        let current = obligation.reminders
        let profile = current.withLeadDays(leads)
        saveRequest = ReminderSaveRequest {
            run { try ObligationActions(context: context).setReminders(obligation, profile, startedFrom: current) }
        }
    }

    private func toggleFollowUp() {
        let isOn = !obligation.reminders.followUpAfterLapse
        saveRequest = ReminderSaveRequest {
            run { try ObligationActions(context: context).setFollowUpAfterLapse(obligation, isOn) }
        }
    }

    private func restoreUsual() {
        run {
            guard let restored = try ObligationActions(context: context).restoreUsualReminders(obligation) else { return }
            let sentence = ReminderWording.sentence(restored.value)
            toast = .undo("Am pus la loc cele obișnuite. \(sentence)", receipt: restored.receipt)
            restoredCount += 1
        }
    }

    private func setTime(_ minute: Int?) {
        let start = obligation.reminderMinuteOfDay
        guard minute != start else { return }
        run {
            let receipt = try ObligationActions(context: context).setReminderTime(obligation, minuteOfDay: minute, startedFrom: start)
            toast = .undo("\(ReminderWording.atTime(obligation.reminderMinuteOfDay, usual: preferences.reminderMinuteOfDay))", receipt: receipt)
        }
    }

    private func run(_ change: () throws -> Void) {
        do { try change() } catch { toast = UpcomingActions.failureToast(error) }
    }
}

/// "Ora amintirii": the general time or one of this deadline's own (`DSReminderTimeField`),
/// saved with "Salvează ora". A page pushed inside the reminder settings sheet, whose back
/// button leaves the time as it was.
struct ReminderTimePage: View {
    let usualMinuteOfDay: Int
    let onSave: (Int?) -> Void
    @State private var minuteOfDay: Int?

    init(startedFrom start: Int?, usualMinuteOfDay: Int, onSave: @escaping (Int?) -> Void) {
        self.usualMinuteOfDay = usualMinuteOfDay
        self.onSave = onSave
        self._minuteOfDay = State(initialValue: start)
    }

    var body: some View {
        ScrollView {
            DSCard {
                DSReminderTimeField(minuteOfDay: $minuteOfDay, usualMinuteOfDay: usualMinuteOfDay)
            }
            .padding(DS.Space.m)
            .dsReadableWidth()
        }
        .background(DS.Palette.background)
        .dsPinnedAction {
            DSPrimaryButton("Salvează ora", systemImage: "checkmark") { onSave(minuteOfDay) }
        }
        .navigationTitle("Ora amintirii")
        .navigationBarTitleDisplayMode(.inline)
    }
}
