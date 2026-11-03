import Foundation

/// The one rule for a deadline's reminders following what they come from.
///
/// A deadline made from a blueprint reminds as the blueprint says for its section's values
/// (`ObligationBlueprint.reminders(for:)`): a passport three months before its travel
/// cut-off, an identity card 90 and 30 days before it expires, a dog's rabies vaccine as the
/// law asks. When a value that profile depends on changes (a document's type, a pet's
/// species: whatever its `reminderVariants` reads), the deadline takes the new profile
/// whole: its leads, consequence, grace, follow-up and travel margin. A deadline whose
/// reminders the person set themselves (`Obligation.remindersCustomized`) keeps them.
///
/// Editează and capture's filing reach it through `AssetActions.update`; the repair list's
/// travel cut-off step (`TravelCutoffStep`) finds deadlines saved before it and gives them the
/// same profile, with the owner's OK. Nothing else writes a deadline's profile from its section.
@MainActor
enum DeadlineReminders {
    /// The profile `obligation` follows for `values`, or nil when it keeps its own: the person
    /// set its reminders, it isn't from `blueprint`, or it is done or archived.
    static func expected(for obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues) -> ReminderProfile? {
        guard let blueprint, obligation.blueprintKey == blueprint.key, !obligation.remindersCustomized,
              obligation.status == .active || obligation.status == .paused else { return nil }
        return blueprint.reminders(for: values)
    }

    /// After a section's values changed from `previous` to its current ones: each of its
    /// deadlines whose blueprint gives another profile for the new values takes it, unless the
    /// person set its reminders. Values the profile doesn't read change nothing. Doesn't save;
    /// returns the deadlines that changed.
    @discardableResult
    static func follow(_ asset: Asset, template: TemplateDefinition, from previous: FieldValues, now: Date) -> [Obligation] {
        let values = asset.values
        let blueprints = Dictionary(template.blueprints.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changed: [Obligation] = []
        for obligation in asset.obligations ?? [] where !obligation.isDeleted {
            guard let blueprint = obligation.blueprintKey.flatMap({ blueprints[$0] }),
                  blueprint.reminders(for: previous) != blueprint.reminders(for: values),
                  let profile = expected(for: obligation, blueprint: blueprint, values: values),
                  give(profile, to: obligation, now: now) else { continue }
            changed.append(obligation)
        }
        return changed
    }

    /// Gives `obligation` the profile its blueprint gives for its section's values; false when
    /// it already has it or keeps its own.
    @discardableResult
    static func refresh(_ obligation: Obligation, template: TemplateDefinition, now: Date) -> Bool {
        guard let asset = obligation.asset,
              let profile = expected(for: obligation, blueprint: template.blueprints.first { $0.key == obligation.blueprintKey }, values: asset.values)
        else { return false }
        return give(profile, to: obligation, now: now)
    }

    private static func give(_ profile: ReminderProfile, to obligation: Obligation, now: Date) -> Bool {
        guard obligation.reminders != profile else { return false }
        obligation.reminders = profile
        obligation.updatedAt = now
        return true
    }
}
