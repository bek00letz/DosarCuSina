import SwiftData
import SwiftUI

/// The one form for adding a deadline to a section, from Adaugă › Scriu eu and from
/// a section's "Alt termen": one of its category's usual deadlines, or one of the
/// person's own. A deadline of their own asks how important it is, takes its kind
/// from the answer and its reminders from the kind (`DeadlineChoice`), so the same
/// "Alt termen" reminds the same wherever it was typed.
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
                    DSSectionHeader("Ce termen")
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            ForEach(Array(blueprints.enumerated()), id: \.element.key) { index, blueprint in
                                if index > 0 { DS.Hairline() }
                                DSCheckRow(title: Text(verbatim: blueprint.title), subtitle: blueprint.note.map { Text(verbatim: $0) },
                                           isOn: choice == .blueprint(blueprint.key)) {
                                    select(.blueprint(blueprint.key), blueprint: blueprint, asset: asset)
                                }
                            }
                            if !blueprints.isEmpty { DS.Hairline() }
                            DSCheckRow(title: Text("Alt termen"), subtitle: Text("Scrii tu ce e."), isOn: choice == .own) {
                                select(.own, blueprint: nil, asset: asset)
                            } detail: {
                                VStack(alignment: .leading, spacing: DS.Space.s) {
                                    DSTextField("Ce trebuie făcut", text: $ownTitle, prompt: "Cazier pentru angajare", isRequired: true)
                                    DSChoiceField("Cât de important e", selection: $importance, options: DeadlineChoice.Importance.allCases, isRequired: true) { $0.title }
                                    if Self.usesRepeatField {
                                        DSRepeatField(choice: $repeatChoice)
                                    } else {
                                        DSChoiceField("Se repetă", selection: $repeats, options: DeadlineChoice.Repeat.allCases, isRequired: true) { $0.title }
                                    }
                                }
                            }
                        }
                    }
                }
                if choice != nil {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSSectionHeader("Când e termenul")
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Space.s) {
                                DSDateField("Data", date: $due, isRequired: true)
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
            DSPrimaryButton("Salvează termenul", systemImage: "checkmark") {
                guard canSave else { reveals = true; return }
                saveRequest = ReminderSaveRequest { save(asset: asset, blueprints: blueprints) }
            }
        } note: {
            if let errorMessage {
                DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
            }
        }
        .environment(\.dsRevealsValidation, reveals)
        .navigationTitle("Un termen")
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
            onSaved("Am adăugat \(obligation.title). \(ReminderWording.sentence(obligation.cycleReminders))")
        } catch let question as ExampleSectionQuestion {
            retryAfterKeeping = { save(asset: asset, blueprints: blueprints) }
            exampleQuestion = question
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}

/// What a deadline of the person's own is, from two plain answers: how important
/// it is and whether it repeats. Its kind comes from the first, its reminders from
/// the kind's default profile.
enum DeadlineChoice {
    enum Importance: String, CaseIterable, Identifiable, Hashable {
        case legal, money, health, reminder

        var id: String { rawValue }

        var kind: ObligationKind {
            switch self {
            case .legal: .legal
            case .money: .payment
            case .health: .health
            case .reminder: .routine
            }
        }

        /// The answer a deadline's kind is, for the four kinds the answers give; nil for any
        /// other (a deadline from an older backup with no category's blueprint), whose kind
        /// "Editează" then leaves as it is.
        init?(kind: ObligationKind) {
            guard let answer = Self.allCases.first(where: { $0.kind == kind }) else { return nil }
            self = answer
        }

        var title: String {
            switch self {
            case .legal: String(localized: "Obligatoriu prin lege", comment: "How important a deadline is.")
            case .money: String(localized: "Ține de bani", comment: "How important a deadline is.")
            case .health: String(localized: "Ține de sănătate", comment: "How important a deadline is.")
            case .reminder: String(localized: "Doar să nu uit", comment: "How important a deadline is.")
            }
        }
    }

    /// The three choices "Se repetă" offered before `DSRepeatField`. Kept, switched off
    /// (`DeadlineForm.usesRepeatField`), as the way back; remove once the owner agrees.
    enum Repeat: String, CaseIterable, Identifiable, Hashable {
        case never, monthly, yearly

        var id: String { rawValue }

        var rule: RecurrenceRule {
            switch self {
            case .never: .none
            case .monthly: .interval(.months(1), anchor: .dueDate)
            case .yearly: .interval(.years(1), anchor: .dueDate)
            }
        }

        var title: String {
            switch self {
            case .never: String(localized: "O singură dată", comment: "Repeat option.")
            case .monthly: String(localized: "În fiecare lună", comment: "Repeat option.")
            case .yearly: String(localized: "În fiecare an", comment: "Repeat option.")
            }
        }
    }

    /// The reminders a deadline of this importance gets: its kind's default profile.
    static func reminders(for importance: Importance) -> ReminderProfile {
        importance.kind.defaultProfile
    }

    /// A deadline's reminders once its importance moves it from kind `old` to `new`: what the
    /// person can't set (how serious it is, how many days late is still calm) is the new kind's;
    /// the leads and the follow-up the new kind's only while they are still the old kind's own,
    /// else the person's, as they set them. The travel margin stays. The one rule, for
    /// `ObligationActions.setImportance` and for the edit sheet while it is open.
    static func reminders(_ profile: ReminderProfile, from old: ObligationKind, to new: ObligationKind) -> ReminderProfile {
        guard old != new else { return profile }
        let was = old.defaultProfile
        let becomes = new.defaultProfile
        let isTheKinds = profile.leadDays == was.leadDays && profile.followUpAfterLapse == was.followUpAfterLapse
        return ReminderProfile(
            leadDays: isTheKinds ? becomes.leadDays : profile.leadDays,
            consequence: becomes.consequence,
            graceDays: becomes.graceDays,
            followUpAfterLapse: isTheKinds ? becomes.followUpAfterLapse : profile.followUpAfterLapse,
            travelMarginDays: profile.travelMarginDays
        )
    }
}
