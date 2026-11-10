import Foundation
import Testing
@testable import DosarCuSina

/// Words the person typed that this phone keeps outside the binder (recent searches, a
/// trip's plan) remember only what search may keep: one rule, `SearchPrivacy.mayRemember`,
/// when they are kept and when they are read back. Placeholder data only: the made-up CNP
/// with county code 99 and the networks' published test card numbers.
@Suite("Words remembered outside the binder")
struct RememberedWordsTests {
    private let cnp = "1800101990006"
    private let visa = "4111 1111 1111 1111"
    private let mastercard = "5555 5555 5555 4444"

    @Test func everydayWordsAreRemembered() {
        for query in ["golf", "RCA 2026", "tel 0712345678", "factura ENGIE Romania S.A.", "B-123-ABC", ""] {
            #expect(SearchPrivacy.mayRemember(query), "\(query)")
        }
    }

    @Test func nothingSearchNeverKeepsIsRemembered() throws {
        let sealed = try SecretSealer.ephemeral().seal("0000")
        for query in [cnp, "cnp \(cnp)", visa, "card \(visa)", mastercard, "card \(PaymentCardNumbers.mask) 1111", sealed, "cod \(sealed)"] {
            #expect(!SearchPrivacy.mayRemember(query), "\(query)")
            #expect(!SearchPrivacy.mayRemember(query, results: []), "\(query)")
        }
    }

    @Test func aSearchThatFoundALockedSectionIsNotRemembered() {
        let locked = SearchResult(document: SearchDocument(id: "b", kind: .document, title: "Cazier", subtitle: nil, route: .home, fields: [], isSensitive: true), score: 1)
        #expect(!SearchPrivacy.mayRemember("cazier", results: [locked]))
    }

    @MainActor
    @Test func recentSearchesLetGoOfWhatAnEarlierVersionKept() throws {
        let suite = "tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["golf", visa, "card \(mastercard)", cnp, "instalator"], forKey: "search.recent")

        let recent = RecentSearches(defaults: defaults)
        #expect(recent.items == ["golf", "instalator"])
        #expect(defaults.stringArray(forKey: "search.recent") == ["golf", "instalator"], "Gone from the phone too, not only from the list")

        recent.add("plata \(visa)", results: [])
        #expect(recent.items == ["golf", "instalator"])
        recent.add("ITP", results: [])
        #expect(recent.items == ["ITP", "golf", "instalator"])
    }

    @Test func aTripRemembersItsDestinationOnlyAsSearchWould() throws {
        let suite = "readiness.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        nonisolated(unsafe) let unsafeDefaults = defaults
        let store = TripPlanStore(defaults: { unsafeDefaults })
        let today = CalendarDay("2027-07-01")

        var plan = TripPlan(start: CalendarDay("2027-07-12"), end: CalendarDay("2027-07-20"), region: .europeanUnion, destination: "Grecia")
        store.save(plan)
        #expect(store.load(today: today)?.destination == "Grecia")

        plan.destination = "Grecia, card \(visa)"
        store.save(plan)
        let kept = try #require(store.load(today: today), "The trip itself is still kept")
        #expect(kept.destination.isEmpty)
        #expect(kept.end == plan.end)
        let stored = try #require(defaults.data(forKey: TripPlanStore.key))
        #expect(!String(decoding: stored, as: UTF8.self).contains("4111"))
    }

    @Test func aTripAnEarlierVersionKeptLosesWhatSearchWouldNotKeep() throws {
        let suite = "readiness.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let written = TripPlan(start: CalendarDay("2027-07-12"), end: CalendarDay("2027-07-20"), region: .outsideEU, destination: "CNP \(cnp)")
        defaults.set(try JSONEncoder().encode(written), forKey: TripPlanStore.key)
        nonisolated(unsafe) let unsafeDefaults = defaults
        let store = TripPlanStore(defaults: { unsafeDefaults })

        #expect(store.load(today: CalendarDay("2027-07-01"))?.destination == "")
        let stored = try #require(defaults.data(forKey: TripPlanStore.key))
        #expect(!String(decoding: stored, as: UTF8.self).contains(cnp), "Written again without it")
    }
}
