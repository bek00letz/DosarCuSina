import SwiftData
import SwiftUI

/// The one form for adding a deadline to a section, from Adaugă › Scriu eu and from
/// a section's "Alt termen": one of its category's usual deadlines, or one of the
/// person's own. A deadline of their own asks how important it is, takes its kind
/// from the answer and its reminders from the kind (`DeadlineChoice`), so the same
/// "Alt termen" reminds the same wherever it was typed.
///
/// A shaped screen: it holds no words of its own. What varies by category is the category's
/// own description (its usual deadlines, their notes and reminders); the rest are the words
/// every category shares (`DeadlineFormWording`). The architecture check refuses a text literal
/// here (`text-in-shaped-screen`); `docs/COPY_MATRIX.md` shows the form for every category.
struct DeadlineForm: View {
    let assetID: UUID
    /// Opens with "Alt termen" chosen, as from a section's own "Alt termen".
    var startsWithOwn = false
    /// Opens with this usual deadline of the category chosen (a checklist's "Adaugă" for RCA).
    var startsWithBlueprint: String?
    /// Called once the deadline is saved, with the confirmation to show.
    let onSaved: (LocalizedStringResource) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(AppPreferences.self) private var preferences
    @Query private var assets: [Asset]

    /// On: "Se repetă" is the shared control (`DSRepeatField`: every so many days, weeks, months
    /// or years, from the due day or from when it was done). Off: the earlier three choices
    /// (`DeadlineChoice.Repeat`), kept as the way back until the owner has used the new one.
    static let usesRepeatField = true

    private enum Choice: Hashable {
        case blueprint(String)
        case own
    }

    @State private var choice: Choice?
    @State private var ownTitle = ""
    @State private var importance: DeadlineChoice.Importance? = .reminder
    @State private var repeats: DeadlineChoice.Repeat? = .never
    @State private var repeatChoice = RepeatChoice.never
    /// Its own reminder time, or nil for the general one from Settings.
    @State private var reminderMinute: Int?
    @State private var due: Date?
    @State private var reveals = false
    @State private var errorMessage: String?
    @State private var saveRequest: ReminderSaveRequest?
    /// Adding to an example asks "Păstrezi … ca al tău?"; yes saves again.
    @State private var exampleQuestion: ExampleSectionQuestion?
    @State private var retryAfterKeeping: (() -> Void)?

    var body: some View {
        let asset = assets.first { $0.id == assetID }
        let blueprints = asset.map(availableBlueprints) ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSSectionHeader(LocalizedStringKey(DeadlineFormWording.which))
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            ForEach(Array(blueprints.enumerated()), id: \.element.key) { index, blueprint in
                                if index > 0 { DS.Hairline() }
                                DSCheckRow(title: Text(verbatim: blueprint.title), subtitle: blueprint.shownNote.map { Text(verbatim: $0) },
                                           isOn: choice == .blueprint(blueprint.key)) {
                                    select(.blueprint(blueprint.key), blueprint: blueprint, asset: asset)
                                }
                            }
                            if !blueprints.isEmpty { DS.Hairline() }
                            DSCheckRow(title: Text(verbatim: DeadlineFormWording.own), subtitle: Text(verbatim: DeadlineFormWording.ownHint), isOn: choice == .own) {
                                select(.own, blueprint: nil, asset: asset)
                            } detail: {
                                VStack(alignment: .leading, spacing: DS.Space.s) {
                                    DSTextField(LocalizedStringKey(DeadlineFormWording.ownTitle), text: $ownTitle, prompt: LocalizedStringKey(DeadlineFormWording.ownTitleExample), isRequired: true)
                                    DSChoiceField(LocalizedStringKey(DeadlineFormWording.importance), selection: $importance, options: DeadlineChoice.Importance.allCases, isRequired: true) { $0.title }
                                    if Self.usesRepeatField {
                                        DSRepeatField(choice: $repeatChoice)
                                    } else {
                                        DSChoiceField(LocalizedStringKey(DeadlineFormWording.repeats), selection: $repeats, options: DeadlineChoice.Repeat.allCases, isRequired: true) { $0.title }
                                    }
                                }
                            }
                        }
                    }
                }
                if choice != nil {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader(LocalizedStringKey(DeadlineFormWording.when))
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Space.s) {
                                DSDateField(LocalizedStringKey(DeadlineFormWording.date), date: $due, isRequired: true)
                                if let reminders = reminders(blueprints: blueprints, asset: asset) {
                                    Text(verbatim: ReminderWording.sentence(reminders))
                                        .dsFont(.subheadline)
                                }
                                DS.Hairline()
                                // Optional: one row with the general time until the person opens it.
                                DSReminderTimeField(minuteOfDay: $reminderMinute, usualMinuteOfDay: preferences.reminderMinuteOfDay, startsCollapsed: true)
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .dsPinnedAction {
            DSPrimaryButton(verbatim: DeadlineFormWording.save, systemImage: "checkmark") {
                guard canSave else { reveals = true; return }
                saveRequest = ReminderSaveRequest { save(asset: asset, blueprints: blueprints) }
            }
        } note: {
            if let errorMessage {
                DSNotice(.error, title: LocalizedStringKey(DeadlineFormWording.notSaved), message: LocalizedStringKey(errorMessage))
            }
        }
        .environment(\.dsRevealsValidation, reveals)
        .navigationTitle(Text(verbatim: DeadlineFormWording.title))
        .navigationBarTitleDisplayMode(.inline)
        .reminderPermissionGate($saveRequest)
        .examplePrompt($exampleQuestion) { retryAfterKeeping?() }
        .dsDiscardGuard(hasChanges: !ownTitle.isEmpty || due != nil || (choice != nil && choice != initialChoice)
                            || repeatChoice != .never || reminderMinute != nil)
        .onAppear {
            if choice == nil, startsWithOwn { choice = .own }
            if choice == nil, let key = startsWithBlueprint, let blueprint = blueprints.first(where: { $0.key == key }) {
                select(.blueprint(key), blueprint: blueprint, asset: asset)
            }
        }
    }

    private var initialChoice: Choice? {
        if startsWithOwn { return .own }
        return startsWithBlueprint.map(Choice.blueprint)
    }

    private var canSave: Bool {
        guard due != nil, let choice else { return false }
        if choice == .own { return !ownTitle.trimmingCharacters(in: .whitespaces).isEmpty && importance != nil && repeats != nil }
        return true
    }

    /// The category's usual deadlines the section doesn't have yet and that apply to it.
    private func availableBlueprints(_ asset: Asset) -> [ObligationBlueprint] {
        let template = try? TemplateStore(context: context).template(forKey: asset.templateKey)
        let taken = Set(asset.activeObligations.compactMap(\.blueprintKey))
        return (template?.blueprints ?? []).filter { !taken.contains($0.key) && ($0.appliesWhen?.isMet(by: asset.values) ?? true) }
    }

    /// The reminders the chosen deadline will have, said before it is saved: within its first
    /// cycle, as they will remind (`ReminderProfile.forCycle`).
    private func reminders(blueprints: [ObligationBlueprint], asset: Asset?) -> ReminderProfile? {
        let profile: ReminderProfile?
        let rule: RecurrenceRule
        switch choice {
        case .blueprint(let key):
            let blueprint = blueprints.first { $0.key == key }
            profile = blueprint?.reminders(for: asset?.values ?? FieldValues())
            rule = blueprint?.recurrence ?? .none
        case .own:
            profile = importance.map { DeadlineChoice.reminders(for: $0) }
            rule = ownRule
        case nil:
            return nil
        }
        guard let profile, let due else { return profile }
        return profile.forCycle(due: CalendarDay(due, calendar: calendar), rule: rule, calendar: calendar)
    }

    /// How a deadline of the person's own repeats, from the control in use.
    private var ownRule: RecurrenceRule {
        Self.usesRepeatField ? repeatChoice.rule : (repeats ?? .never).rule
    }

    private func select(_ value: Choice, blueprint: ObligationBlueprint?, asset: Asset?) {
        choice = value
        if let blueprint, let asset {
            let today = CalendarDay(Date(), calendar: calendar)
            due = RecurrenceEngine.firstDue(for: blueprint, values: asset.values, today: today, calendar: calendar).map { $0.startDate(in: calendar) }
        }
    }

    private func save(asset: Asset?, blueprints: [ObligationBlueprint]) {
        guard let asset, let due, let choice else { return }
        let day = CalendarDay(due, calendar: calendar)
        let actions = ObligationActions(context: context, calendar: calendar)
        do {
            let obligation: Obligation
            switch choice {
            case .blueprint(let key):
                guard let blueprint = blueprints.first(where: { $0.key == key }) else { return }
                obligation = try actions.create(from: blueprint, for: asset, firstDue: day, reminderMinuteOfDay: reminderMinute)
            case .own:
                let importance = importance ?? .reminder
                obligation = try actions.create(
                    title: ownTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: importance.kind,
                    dueDay: day,
                    for: asset,
                    recurrence: ownRule,
                    reminders: DeadlineChoice.reminders(for: importance),
                    reminderMinuteOfDay: reminderMinute
                )
            }
            errorMessage = nil
            onSaved(DeadlineFormWording.added(obligation.title, reminders: ReminderWording.sentence(obligation.cycleReminders)))
        } catch let question as ExampleSectionQuestion {
            retryAfterKeeping = { save(asset: asset, blueprints: blueprints) }
            exampleQuestion = question
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}
