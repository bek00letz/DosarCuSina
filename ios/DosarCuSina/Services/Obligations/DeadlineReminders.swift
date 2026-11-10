import Foundation
import SwiftData

/// The one rule for a deadline's reminders following what they come from.
///
/// A deadline made from a blueprint reminds as the blueprint says for its section's values
/// (`ObligationBlueprint.reminders(for:)`): a passport three months before its travel
/// cut-off, an identity card 90 and 30 days before it expires, a dog's rabies vaccine as the
/// law asks. When a value that profile depends on changes (a document's type, a pet's
/// species: whatever its `reminderVariants` reads), the deadline takes the new profile
/// whole: its leads, consequence, grace, follow-up and travel margin.
///
/// A deadline whose reminders the person set themselves (`Obligation.remindersCustomized`)
/// keeps its leads, consequence, grace and follow-up, but its travel margin still follows the
/// document: the cut-off is a fact about the document, not a preference. A customised
/// passport that turns out to be an identity card stops counting from one, and the other way
/// round; its leads then count from the new anchor.
///
/// Editează and capture's filing reach it through `AssetActions.update`; the repair list's
/// travel cut-off step (`TravelCutoffStep`) finds deadlines saved before it and gives them the
/// same profile, with the owner's OK. "Revino la cele obișnuite"
/// (`ObligationActions.restoreUsualReminders`) gives a customised deadline its `usual`
/// reminders back. Nothing else writes a deadline's profile from its section.
@MainActor
enum DeadlineReminders {
    /// The reminders `obligation`'s blueprint gives for `values`, whether or not the person
    /// changed them; nil when it isn't from `blueprint`.
    static func usual(for obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues) -> ReminderProfile? {
        guard let blueprint, obligation.blueprintKey == blueprint.key else { return nil }
        return blueprint.reminders(for: values)
    }

    /// The reminders `obligation`'s blueprint gives for its section's current values, with the
    /// category looked up in `context`; nil for a deadline not made from a blueprint, or whose
    /// category is gone.
    static func usual(for obligation: Obligation, in context: ModelContext) -> ReminderProfile? {
        guard let asset = obligation.asset, let key = obligation.blueprintKey,
              let template = try? TemplateStore(context: context).template(forKey: asset.templateKey) else { return nil }
        return usual(for: obligation, blueprint: template.definition.blueprints.first { $0.key == key }, values: asset.values)
    }

    /// The usual reminders, when "Revino la cele obișnuite" has something to give back: the
    /// person set this deadline's reminders and they differ from what its document gives.
    static func restorable(_ obligation: Obligation, in context: ModelContext) -> ReminderProfile? {
        guard obligation.remindersCustomized, let usual = usual(for: obligation, in: context),
              usual != obligation.reminders else { return nil }
        return usual
    }

    /// Whether `profile` is the person's own for `obligation`: anything but its usual reminders.
    /// Setting exactly the usual ones back by hand lets it follow its document again. A
    /// deadline not made from a blueprint has no usual ones, so whatever is set is the person's.
    static func isCustomized(_ profile: ReminderProfile, for obligation: Obligation, in context: ModelContext) -> Bool {
        usual(for: obligation, in: context).map { $0 != profile } ?? true
    }

    /// The profile `obligation` follows for `values`, or nil when it isn't from `blueprint` or
    /// is done or archived: its blueprint's profile whole, or for a deadline whose reminders
    /// the person set, their own with the document's travel margin.
    static func expected(for obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues) -> ReminderProfile? {
        guard obligation.status == .active || obligation.status == .paused,
              let usual = usual(for: obligation, blueprint: blueprint, values: values) else { return nil }
        guard obligation.remindersCustomized else { return usual }
        var own = obligation.reminders
        own.travelMarginDays = usual.travelMarginDays
        return own
    }

    /// After a section's values changed from `previous` to its current ones: each of its
    /// deadlines whose blueprint gives another profile for the new values takes it; one whose
    /// reminders the person set takes only the new travel margin. Values the profile doesn't
    /// read change nothing. Doesn't save; returns the deadlines that changed.
    @discardableResult
    static func follow(_ asset: Asset, template: TemplateDefinition, from previous: FieldValues) -> [Obligation] {
        let values = asset.values
        let blueprints = Dictionary(template.blueprints.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changed: [Obligation] = []
        for obligation in asset.obligations ?? [] where !obligation.isDeleted {
            guard let blueprint = obligation.blueprintKey.flatMap({ blueprints[$0] }),
                  blueprint.reminders(for: previous) != blueprint.reminders(for: values),
                  let profile = expected(for: obligation, blueprint: blueprint, values: values),
                  give(profile, to: obligation) else { continue }
            changed.append(obligation)
        }
        return changed
    }

    /// Gives `obligation` the profile it follows for its section's values (`expected`); false
    /// when it already has it or follows nothing. The repair list runs it as the app's own step
    /// (`ChangeOrigin.app`), so the deadline keeps its change time.
    @discardableResult
    static func refresh(_ obligation: Obligation, template: TemplateDefinition) -> Bool {
        guard let asset = obligation.asset,
              let profile = expected(for: obligation, blueprint: template.blueprints.first { $0.key == obligation.blueprintKey }, values: asset.values)
        else { return false }
        return give(profile, to: obligation)
    }

    private static func give(_ profile: ReminderProfile, to obligation: Obligation) -> Bool {
        guard obligation.reminders != profile else { return false }
        obligation.reminders = profile
        return true
    }
}
