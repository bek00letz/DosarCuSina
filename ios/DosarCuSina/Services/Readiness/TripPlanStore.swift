import Foundation

/// Keeps the trip the person described, on this phone, until it is over, so the checklist
/// opens where they left it. It is a plan, not a record: it isn't in the binder, its
/// backups or search, and it is forgotten the day after the trip ends. Its one line in the
/// person's words, where to, is remembered only as search would (`SearchPrivacy.mayRemember`):
/// a destination that holds a CNP or a card number is left out, when it is kept and when it
/// is read back.
public struct TripPlanStore: Sendable {
    public static let key = "readiness.tripPlan"

    private let defaults: @Sendable () -> UserDefaults

    public init(defaults: @escaping @Sendable () -> UserDefaults = { .standard }) {
        self.defaults = defaults
    }

    /// The trip kept, unless it has ended before `today` (then it is forgotten).
    public func load(today: CalendarDay) -> TripPlan? {
        guard let data = defaults().data(forKey: Self.key),
              let plan = try? JSONDecoder().decode(TripPlan.self, from: data) else { return nil }
        guard plan.end >= today else {
            clear()
            return nil
        }
        let kept = Self.remembered(plan)
        if kept != plan { save(kept) }
        return kept
    }

    public func save(_ plan: TripPlan) {
        guard let data = try? JSONEncoder().encode(Self.remembered(plan)) else { return }
        defaults().set(data, forKey: Self.key)
    }

    /// The plan as this phone may remember it: its destination only when search could keep it.
    static func remembered(_ plan: TripPlan) -> TripPlan {
        guard !SearchPrivacy.mayRemember(plan.destination) else { return plan }
        var kept = plan
        kept.destination = ""
        return kept
    }

    public func clear() {
        defaults().removeObject(forKey: Self.key)
    }
}
