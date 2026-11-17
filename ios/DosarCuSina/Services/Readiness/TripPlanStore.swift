import Foundation

/// Keeps the trips the person described, on this phone, each until it is over, so a
/// checklist opens where they left it. Several at once: a summer holiday and a weekend away,
/// or two people of the household going at different times; each has its own days, region,
/// destination and who goes. They are plans, not records: not in the binder, its backups or
/// search, and each is forgotten the day after it ends. Its one line in the person's words,
/// where to, is remembered only as search would (`SearchPrivacy.mayRemember`): a destination
/// that holds a CNP or a card number is left out, when it is kept and when it is read back.
public struct TripPlanStore: Sendable {
    /// Where the trips are kept, in the app's machine JSON (`MachineText`).
    public static let key = "readiness.trips"
    /// Where the one trip was kept before there could be several. Read once, brought across
    /// into the list and removed.
    public static let singleTripKey = "readiness.tripPlan"

    private let defaults: @Sendable () -> UserDefaults

    public init(defaults: @escaping @Sendable () -> UserDefaults = { .standard }) {
        self.defaults = defaults
    }

    /// Every trip kept that isn't over by `today`, the soonest first. Trips that ended are
    /// forgotten; one kept before there could be several is brought across.
    public func load(today: CalendarDay) -> [TripPlan] {
        let stored = storedTrips()
        let kept = stored.filter { !$0.isOver(by: today) }.map(Self.remembered).sorted(by: Self.soonestFirst)
        if kept != stored || defaults().object(forKey: Self.singleTripKey) != nil {
            write(kept)
        }
        return kept
    }

    /// Keeps `plan`: a new trip, or the one with its id, changed.
    public func save(_ plan: TripPlan) {
        var trips = storedTrips().filter { $0.id != plan.id }
        trips.append(Self.remembered(plan))
        write(trips.sorted(by: Self.soonestFirst))
    }

    /// Forgets the trip with this id.
    public func remove(_ id: UUID) {
        write(storedTrips().filter { $0.id != id })
    }

    /// Forgets every trip.
    public func clear() {
        defaults().removeObject(forKey: Self.key)
        defaults().removeObject(forKey: Self.singleTripKey)
    }

    // MARK: Reading and writing

    /// The trips as stored, with the one kept before there could be several, if it is still there.
    private func storedTrips() -> [TripPlan] {
        var trips = defaults().data(forKey: Self.key).flatMap { try? MachineText.jsonDecoder().decode([TripPlan].self, from: $0) } ?? []
        if let data = defaults().data(forKey: Self.singleTripKey),
           let single = try? MachineText.jsonDecoder().decode(TripPlan.self, from: data),
           !trips.contains(where: { $0.id == single.id }) {
            trips.append(single)
        }
        return trips
    }

    private func write(_ trips: [TripPlan]) {
        if trips.isEmpty {
            defaults().removeObject(forKey: Self.key)
        } else if let data = try? MachineText.jsonEncoder().encode(trips.map(Self.remembered)) {
            defaults().set(data, forKey: Self.key)
        } else {
            return
        }
        // Brought across: the one-trip place is no longer read.
        defaults().removeObject(forKey: Self.singleTripKey)
    }

    static func soonestFirst(_ a: TripPlan, _ b: TripPlan) -> Bool {
        (a.start, a.end, a.id.uuidString) < (b.start, b.end, b.id.uuidString)
    }

    /// The plan as this phone may remember it: its destination only when search could keep it.
    static func remembered(_ plan: TripPlan) -> TripPlan {
        guard !SearchPrivacy.mayRemember(plan.destination) else { return plan }
        var kept = plan
        kept.destination = ""
        return kept
    }
}
