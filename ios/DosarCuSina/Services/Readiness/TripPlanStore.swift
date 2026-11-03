import Foundation

/// Keeps the trip the person described, on this phone, until it is over, so the checklist
/// opens where they left it. It is a plan, not a record: it isn't in the binder, its
/// backups or search, and it is forgotten the day after the trip ends.
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
        return plan
    }

    public func save(_ plan: TripPlan) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults().set(data, forKey: Self.key)
    }

    public func clear() {
        defaults().removeObject(forKey: Self.key)
    }
}
