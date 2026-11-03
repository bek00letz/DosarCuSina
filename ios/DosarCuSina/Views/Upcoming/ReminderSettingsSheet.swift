import SwiftData
import SwiftUI

/// What the reminder editor shows for one deadline: its reminders, and its usual ones when
/// "Revino la cele obișnuite" is offered.
struct ReminderSettings: Equatable {
    var profile: ReminderProfile
    /// The reminders its document gives, only when the person set others
    /// (`DeadlineReminders.restorable`); nil hides "Revino la cele obișnuite".
    var usual: ReminderProfile?

    init(profile: ReminderProfile, usual: ReminderProfile?) {
        self.profile = profile
        self.usual = usual
    }

    @MainActor
    init(obligation: Obligation, in context: ModelContext) {
        self.init(profile: obligation.reminders, usual: DeadlineReminders.restorable(obligation, in: context))
    }

    /// The lead rows, largest first: the presets and any other lead the profile holds.
    var leadRows: [Int] { ReminderPreset.rows(for: profile.leadDays) }
}

/// The editor itself: the reminder sentence, a row per lead, "Altă zi…", the follow-up and,
/// when offered, the usual reminders. It only reports taps; `ReminderSettingsSheet` saves.
struct ReminderSettingsForm: View {
    let settings: ReminderSettings
    var onToggleLead: (Int) -> Void = { _ in }
    var onOtherDay: () -> Void = {}
    var onToggleFollowUp: () -> Void = {}
    var onRestoreUsual: () -> Void = {}

    var body: some View {
        let profile = settings.profile
        VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(verbatim: ReminderWording.sentence(profile))
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

/// "Schimbă când te anunț": the deadline's reminder settings, opened from its page. Each
/// change is saved at once (after the notification explanation when it is due), as the
/// page's settings always were, so there is nothing to discard. Going back to the usual
/// reminders shows an undo toast.
struct ReminderSettingsSheet: View {
    let obligation: Obligation
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @State private var toast: DSToast?
    @State private var saveRequest: ReminderSaveRequest?
    @State private var isAddingCustomLead = false
    @State private var restoredCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                ReminderSettingsForm(
                    settings: ReminderSettings(obligation: obligation, in: context),
                    onToggleLead: { days in setLeads(ReminderPreset.toggling(days, in: obligation.reminders.leadDays)) },
                    onOtherDay: { isAddingCustomLead = true },
                    onToggleFollowUp: toggleFollowUp,
                    onRestoreUsual: { saveRequest = ReminderSaveRequest { restoreUsual() } }
                )
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .navigationTitle("Când te anunț")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gata", action: onClose) }
            }
        }
        .dsToast($toast)
        .reminderPermissionGate($saveRequest)
        .sensoryFeedback(.success, trigger: restoredCount)
        .presentationDetents([.large])
        .sheet(isPresented: $isAddingCustomLead) {
            CustomLeadSheet { days in
                isAddingCustomLead = false
                if let days { setLeads(obligation.reminders.leadDays + [days]) }
            }
            .presentationDetents([.medium])
        }
    }

    private func setLeads(_ leads: [Int]) {
        let profile = obligation.reminders.withLeadDays(leads)
        saveRequest = ReminderSaveRequest {
            run { try ObligationActions(context: context).setReminders(obligation, profile) }
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

    private func run(_ change: () throws -> Void) {
        do { try change() } catch { toast = UpcomingActions.failureToast(error) }
    }
}
