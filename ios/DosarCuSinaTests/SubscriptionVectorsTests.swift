import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A subscription's engines (what a service is, `ServiceKind`; how often it is paid and what that
/// comes to a month, `BillingCycle` and `SubscriptionMath`; its bills' trend and the bill that
/// hasn't come, `BillHistory` and `AttentionModel.missingBills`; where a bill or a contract
/// belongs, `SubscriptionMatcher` over `PostalAddress`; the codes a paper keeps,
/// `SubscriptionCode.keeping`; how subscriptions are listed, `SubscriptionGroup`; a bill's meter
/// index, `SubscriptionMeter`; and the bill reminder following direct debit, `BillReminders`), run
/// over cases chosen to bite and written to `shared/test-vectors/subscriptions/`, one file per
/// rule: each input with the answer this app gives. The Android app's tests read the same files and
/// must give the same answers (docs/ANDROID_PLAN.md, "How parity is kept"): its engines in
/// android/core, `core.subscriptions`. A sibling of `ValueVectorsTests`, with a folder of its own.
///
/// No answer depends on the machine: days are counted in Bucharest's calendar whatever the
/// simulator's zone (`Calendar.bucharest`), and every "today" is a case's own. Ids are fixed
/// (`id(_:)`). Placeholder data only: `ENGIE Romania S.A.`, made-up POD, CLC and client codes.
@MainActor
@Suite("Subscription vectors")
struct SubscriptionVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/subscriptions")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the subscription rules. Bring shared/test-vectors/subscriptions up to date: \
    TEST_RUNNER_SUBSCRIPTION_VECTORS_WRITE=1 ./tests/run_tests.sh (or run SubscriptionVectorsTests in Xcode \
    with SUBSCRIPTION_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run \
    the Android tests (./gradlew :core:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    /// The one calendar every case counts days in.
    static let calendar = Calendar.bucharest

    @Test("shared/test-vectors/subscriptions is up to date with the subscription rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["SUBSCRIPTION_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/SubscriptionVectorsTests.swift")
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
        }
        // A file no rule writes any more goes, so Android never tests against an old answer.
        let names = Set(files.map { "\($0.name).json" })
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && !names.contains(stale) {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
    }

    static func all() throws -> [Vectors] {
        try [
            services(), billingCycles(), monthly(), billTrends(), missingBill(), missingBills(), postalAddresses(),
            addressAgreements(), homes(), matcher(), providerNames(), codesKept(), groups(), meter(), billReminders(),
        ]
    }

    // MARK: Helpers

    /// A fixed id: `A0000000-B000-C000-D000-E00000000001` for 1. Letters keep apart the runs of digits, so no id
    /// reads as a card number (the privacy check refuses one that passes the card check digit).
    nonisolated static func id(_ number: Int) -> UUID {
        let digits = String(number)
        return UUID(uuidString: "A0000000-B000-C000-D000-E" + String(repeating: "0", count: 11 - digits.count) + digits)!
    }

    nonisolated static func day(_ iso: String) -> CalendarDay { CalendarDay(iso) }

    nonisolated static func money(_ value: Money?) -> JSONValue {
        guard let value else { return .null }
        return .object(["amount": .string("\(value.amount)"), "currency": .string(value.currency)])
    }

    nonisolated static func money(_ amount: String, _ currency: String = "RON") -> Money {
        Money(Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))!, currency: currency)
    }

    nonisolated static func interval(_ value: RecurrenceInterval) -> JSONValue {
        .object(["every": .int(value.every), "unit": .string(value.unit.rawValue)])
    }

    nonisolated static func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }

    // MARK: Services

    static func services() -> Vectors {
        let inputs: [String?] = ServiceKind.all.map(Optional.some) + [
            "Gaze naturale", "gaz", "CURENT", "Energie electrică", "apa-canal", "Termoficare", "Internet", "telefonie   mobilă",
            "Netflix", "", nil,
        ]
        var cases: [JSONValue] = inputs.map { input in
            .object([
                "text": text(input),
                "service": text(ServiceKind.service(input)?.key),
                "isTiedToHome": .bool(ServiceKind.isTiedToHome(input)),
                "sendsRegularBills": .bool(ServiceKind.sendsRegularBills(input)),
                "meter": text(ServiceKind.meterKind(for: input)?.rawValue),
                "codes": .array(ServiceKind.codes(of: input).map { .string($0.rawValue) }),
                "group": .string(SubscriptionGroup.of(service: input).rawValue),
            ])
        }
        for code in SubscriptionCode.allCases {
            cases.append(.object(["carrying": .string(code.rawValue), "services": .array(ServiceKind.keys(carrying: code).map(JSONValue.string))]))
        }
        return Vectors(
            name: "services",
            rule: "ServiceKind.service(_:), isTiedToHome, sendsRegularBills, meterKind(for:), codes(of:), keys(carrying:), SubscriptionGroup.of(service:)",
            source: "ios/DosarCuSina/Models/Fields/ChoiceOptions.swift",
            shape: "text: a stored or typed service (null for none), the service it names (null for none), whether it lives under a home, whether it bills on a rhythm, its meter's kind (null without one), its codes' names in order, and its group's key. carrying: a code's name and the services whose papers carry it, in order.",
            cases: cases
        )
    }

    static func billingCycles() -> Vectors {
        let inputs: [String?] = BillingCycle.options.map { Optional.some($0.key) } + [
            "Săptămânal", "saptamanala", "LUNAR", "Lunară", "Trimestrial", "quarterly", "Annual", "Anuală", "  Anual  ", "bianual", "", nil,
        ]
        let cases: [JSONValue] = inputs.map { input in
            .object(["text": text(input), "interval": interval(BillingCycle.interval(input))])
        }
        return Vectors(
            name: "billing-cycle",
            rule: "BillingCycle.interval(_:)",
            source: "ios/DosarCuSina/Models/Fields/ChoiceOptions.swift",
            shape: "text: a stored or typed cycle (null for none); interval: how long one cycle lasts, as every and unit (day, week, month, year).",
            cases: cases
        )
    }

    static func monthly() -> Vectors {
        let prices: [(String, String, RecurrenceInterval)] = [
            ("12", "RON", .weeks(1)), ("49.99", "RON", .weeks(1)), ("7.5", "RON", .weeks(2)), ("39.90", "RON", .months(1)),
            ("90", "RON", .months(3)), ("129.99", "RON", .months(3)), ("100", "RON", .months(2)), ("120", "RON", .years(1)),
            ("99.99", "RON", .years(1)), ("0.30", "RON", .years(1)), ("1.50", "RON", .years(1)), ("0.06", "RON", .years(2)),
            ("10", "RON", .days(1)), ("1", "RON", .days(30)), ("9.99", "EUR", .months(1)), ("2.99", "EUR", .weeks(1)),
            ("0", "RON", .months(1)), ("1234567.89", "RON", .weeks(1)),
        ]
        var cases: [JSONValue] = prices.map { amount, currency, cycle in
            let price = money(amount, currency)
            return .object(["price": money(price), "every": interval(cycle), "monthly": money(SubscriptionMath.monthly(price, every: cycle))])
        }
        // What a subscription's values come to: its price, else its last bill when asked to.
        let equivalents: [(price: String?, lastBill: String?, cycle: String?, usingLastBill: Bool)] = [
            ("12", nil, BillingCycle.weekly, true), ("90", "200", BillingCycle.quarterly, true), (nil, "245.30", nil, true),
            (nil, "245.30", BillingCycle.monthly, false), (nil, nil, BillingCycle.yearly, true), ("99.99", nil, "Anual", true),
            ("19.99", nil, "bogus", true),
        ]
        for equivalent in equivalents {
            var values = FieldValues()
            values[SubscriptionFields.price] = equivalent.price.map { .money(money($0)) }
            values[SubscriptionFields.lastBill] = equivalent.lastBill.map { .money(money($0)) }
            values[SubscriptionFields.cycle] = equivalent.cycle.map(FieldValue.text)
            cases.append(.object([
                "equivalentOf": .object([
                    "price": money(equivalent.price.map { money($0) }), "lastBill": money(equivalent.lastBill.map { money($0) }),
                    "cycle": text(equivalent.cycle), "usingLastBill": .bool(equivalent.usingLastBill),
                ]),
                "monthly": money(SubscriptionMath.monthlyEquivalent(values, usingLastBill: equivalent.usingLastBill)),
            ]))
        }
        return Vectors(
            name: "monthly",
            rule: "SubscriptionMath.monthly(_:every:) and monthlyEquivalent(_:usingLastBill:)",
            source: "ios/DosarCuSina/Services/Templates/SubscriptionMath.swift",
            shape: "price: an amount (as Foundation's Decimal writes it) and its currency; every: how often it is paid; monthly: what it comes to a month, rounded to two decimals, half away from zero. Or equivalentOf: a subscription's price and last bill (null for none), its stored cycle (null for none) and whether its last bill may stand in; monthly: what it comes to a month, null without a price.",
            cases: cases
        )
    }

    // MARK: Bills

    /// A bill in a case: its day and amount, null for none.
    struct Bill {
        var day: String
        var amount: String?
        var currency = "RON"

        var record: BillRecord { BillRecord(day: CalendarDay(day), amount: amount.map { SubscriptionVectorsTests.money($0, currency) }) }
        var json: JSONValue { .object(["day": .string(day), "amount": SubscriptionVectorsTests.money(record.amount)]) }
    }

    static func billTrends() -> Vectors {
        let cases: [(String, [Bill])] = [
            ("2026-11-10", [Bill(day: "2026-09-05", amount: "213.20"), Bill(day: "2026-10-05", amount: "245.30")]),
            ("2026-11-10", [Bill(day: "2026-10-05", amount: "245.30"), Bill(day: "2026-09-05", amount: "213.20"), Bill(day: "2026-11-05", amount: "200")]),
            ("2026-11-10", [Bill(day: "2026-10-05", amount: "100"), Bill(day: "2026-11-05", amount: "100.00")]),
            ("2026-11-10", [Bill(day: "2026-09-05", amount: "100"), Bill(day: "2026-10-05", amount: "10", currency: "EUR")]),
            ("2026-11-10", [Bill(day: "2026-08-05", amount: "50"), Bill(day: "2026-09-05", amount: "10", currency: "EUR"), Bill(day: "2026-10-05", amount: "70")]),
            ("2026-11-10", [Bill(day: "2026-11-05", amount: nil)]),
            ("2026-11-10", [Bill(day: "2026-10-05", amount: "80"), Bill(day: "2026-11-05", amount: nil)]),
            ("2026-11-10", []),
            // A year ago to the day is left out of the average; a day after it counts.
            ("2026-11-10", [Bill(day: "2025-11-10", amount: "300"), Bill(day: "2025-11-11", amount: "100"), Bill(day: "2026-11-01", amount: "101")]),
            // A leap year's 365 days.
            ("2028-03-01", [Bill(day: "2027-03-01", amount: "90"), Bill(day: "2027-03-02", amount: "10.01"), Bill(day: "2028-02-29", amount: "10.02")]),
            ("2026-11-10", [Bill(day: "2026-07-05", amount: "33.33"), Bill(day: "2026-08-05", amount: "33.33"), Bill(day: "2026-09-05", amount: "33.34")]),
            ("2026-11-10", [Bill(day: "2026-10-05", amount: "0.01"), Bill(day: "2026-11-05", amount: "0.02")]),
        ]
        let written: [JSONValue] = cases.map { today, bills in
            let trend = BillHistory.trend(bills.map(\.record), today: day(today), calendar: calendar)
            let answer: JSONValue = trend.map { trend in
                .object([
                    "last": .object(["day": .string(trend.last.day.isoString), "amount": money(trend.last.amount)]),
                    "change": money(trend.change),
                    "direction": trend.direction.map { .string("\($0)") } ?? .null,
                    "averageLastYear": .array(trend.averageLastYear.map { money($0) }),
                ])
            } ?? .null
            return .object(["today": .string(today), "bills": .array(bills.map(\.json)), "trend": answer])
        }
        return Vectors(
            name: "bill-trend",
            rule: "BillHistory.trend(_:today:calendar:)",
            source: "ios/DosarCuSina/Services/Subscriptions/BillHistory.swift",
            shape: "today and a subscription's bills (each its day and amount, null for none); trend: the newest bill with an amount, how much more or less it is than the one before it in the same currency (null for none), its direction (up, down, same; null for none) and the average over the last 365 days, one per currency in the currencies' order; null without a bill with an amount.",
            cases: written
        )
    }

    static func missingBill() -> Vectors {
        let cases: [(today: String, cycle: RecurrenceInterval, days: [String])] = [
            // Monthly: well past its usual day; within the grace; a provider that always bills late.
            ("2026-11-10", .months(1), ["2026-07-20", "2026-08-20", "2026-09-20"]),
            ("2026-11-10", .months(1), ["2026-11-05"]),
            ("2026-11-10", .months(1), ["2026-10-05"]),
            ("2026-11-10", .months(1), ["2026-10-01"]),
            ("2026-11-10", .months(1), ["2026-09-30"]),
            ("2026-11-10", .months(1), ["2026-07-17", "2026-08-29", "2026-09-29"]),
            ("2026-11-10", .months(1), ["2026-07-05", "2026-08-30", "2026-09-29"]),
            // Two missed cycles: it stops saying so.
            ("2026-11-10", .months(1), ["2026-08-25"]),
            ("2026-11-10", .months(1), ["2026-08-09"]),
            ("2026-11-10", .months(1), ["2026-08-10"]),
            ("2026-11-10", .months(1), ["2026-08-11"]),
            // A month end: the 31st's next bill is due on the month's last day.
            ("2026-03-11", .months(1), ["2026-01-31"]),
            ("2026-03-10", .months(1), ["2026-01-31"]),
            ("2028-03-10", .months(1), ["2028-01-31"]),
            ("2026-05-12", .months(1), ["2026-01-31", "2026-02-28", "2026-03-31"]),
            // Quarterly, weekly, yearly.
            ("2026-11-10", .months(3), ["2026-07-21"]),
            ("2026-11-10", .months(3), ["2026-07-05"]),
            ("2026-11-10", .months(3), ["2026-04-05", "2026-07-15"]),
            ("2026-11-10", .weeks(1), ["2026-10-06", "2026-10-13", "2026-10-20", "2026-10-27"]),
            ("2026-11-10", .weeks(1), ["2026-11-02"]),
            ("2026-11-10", .weeks(1), ["2026-11-06"]),
            ("2026-11-10", .weeks(2), ["2026-10-20"]),
            ("2026-11-10", .years(1), ["2025-10-01"]),
            ("2026-11-10", .years(1), ["2025-10-15"]),
            ("2029-03-31", .years(1), ["2028-02-29"]),
            ("2026-11-10", .days(10), ["2026-10-25"]),
            // The same day twice counts once; no bill says nothing.
            ("2026-11-10", .months(1), ["2026-09-20", "2026-09-20"]),
            ("2026-11-10", .months(1), []),
            // A bill dated after today.
            ("2026-11-10", .months(1), ["2026-12-01"]),
        ]
        let written: [JSONValue] = cases.map { today, cycle, days in
            let bills = days.map { BillRecord(day: day($0), amount: nil) }
            let missing = BillHistory.missing(bills, cycle: cycle, today: day(today), calendar: calendar)
            return .object([
                "today": .string(today), "cycle": interval(cycle), "days": .array(days.map(JSONValue.string)),
                "missing": missing.map { .object(["lastDay": .string($0.lastDay.isoString), "expectedDay": .string($0.expectedDay.isoString)]) } ?? .null,
            ])
        }
        return Vectors(
            name: "missing-bill",
            rule: "BillHistory.missing(_:cycle:today:calendar:)",
            source: "ios/DosarCuSina/Services/Subscriptions/BillHistory.swift",
            shape: "today, how often the bills come (cycle) and the days its bills came; missing: the last one's day and the day the next was expected, or null when none is missing.",
            cases: written
        )
    }

    static func missingBills() -> Vectors {
        struct Watch {
            var number: Int
            var service: String?
            var cycle: RecurrenceInterval = .months(1)
            var days: [String]
            var isSensitive = false
            var isExample = false
        }
        let lists: [(String, [Watch])] = [
            ("2026-11-10", [
                Watch(number: 1, service: ServiceKind.gas, days: ["2026-09-20"]),
                Watch(number: 2, service: ServiceKind.streaming, days: ["2026-09-20"]),
                Watch(number: 3, service: ServiceKind.gas, days: ["2026-09-20"], isExample: true),
                Watch(number: 4, service: ServiceKind.mobile, days: ["2026-09-10"], isSensitive: true),
                Watch(number: 5, service: ServiceKind.electricity, days: ["2026-11-01"]),
                Watch(number: 6, service: nil, days: ["2026-09-20"]),
                Watch(number: 7, service: "Gaze naturale", cycle: .weeks(1), days: ["2026-10-27"]),
                Watch(number: 8, service: ServiceKind.water, cycle: .months(3), days: ["2026-07-05"]),
                Watch(number: 9, service: ServiceKind.heating, days: []),
            ]),
            ("2026-11-10", []),
        ]
        let written: [JSONValue] = lists.map { today, watches in
            let snapshots = watches.map { watch in
                BillWatchSnapshot(id: id(watch.number), name: "Abonament", provider: "ENGIE Romania S.A.", service: watch.service, cycle: watch.cycle,
                                  bills: watch.days.map { BillRecord(day: day($0), amount: nil) }, isSensitive: watch.isSensitive, isExample: watch.isExample)
            }
            let notes = AttentionModel.missingBills(snapshots, now: day(today).noonDate(in: calendar), calendar: calendar)
            return .object([
                "today": .string(today),
                "subscriptions": .array(watches.map { watch in
                    .object([
                        "id": .string(id(watch.number).uuidString), "service": text(watch.service), "cycle": interval(watch.cycle),
                        "days": .array(watch.days.map(JSONValue.string)), "isSensitive": .bool(watch.isSensitive), "isExample": .bool(watch.isExample),
                    ])
                }),
                "missing": .array(notes.map { note in
                    .object(["id": .string(note.assetId?.uuidString ?? "?"), "expectedDay": .string(note.expectedDay?.isoString ?? "?")])
                }),
            ])
        }
        return Vectors(
            name: "missing-bills",
            rule: "AttentionModel.missingBills(_:now:calendar:locale:): which subscriptions' bills haven't come, and in which order",
            source: "ios/DosarCuSina/Services/Attention/MissingBills.swift",
            shape: "today and the binder's subscriptions (each its id, its stored service, null for none, how often it bills, the days its bills came, whether it is locked and whether it is an example); missing: the ones with a bill that hasn't come, oldest expected first, each its id and the day its bill was expected. The notes' words are the screens', not pinned here.",
            cases: written
        )
    }

    // MARK: Addresses

    nonisolated static func parts(_ address: PostalAddress?) -> JSONValue {
        guard let address else { return .null }
        return .object([
            "street": .array(address.street.map(JSONValue.string)), "streetType": text(address.streetType), "number": text(address.number),
            "block": text(address.block), "staircase": text(address.staircase), "apartment": text(address.apartment),
            "sector": text(address.sector), "locality": .array(address.locality.map(JSONValue.string)),
            "county": .array(address.county.map(JSONValue.string)),
        ])
    }

    static func postalAddresses() -> Vectors {
        let texts = [
            "Str. Exemplului nr. 1, bl. A1, sc. B, et. 3, ap. 12, Sector 3, București", "Sat Exemplu nr. 12, Com. Exemplu, Jud. Exemplu",
            "Cod client 1000000000", "1234", "Index citit la locul de consum", "STRADA EXEMPLULUI NR.1 BL.A1 SC.B AP.12 SECTOR 3 BUCUREȘTI",
            "Str. Exemplului 1, bl. A 1, sc. b, ap. 12, sect. 3, Bucuresti", "B-dul Exemplului nr. 2", "Bulevardul Exemplului 2, România",
            "Str. Al. I. Cuza nr. 3", "Exemplului 1, Brașov", "Str. Exemplului 1", "Calea Exemplului nr. 12 A", "Str. Exemplului nr. 01",
            "Str. Exemplului nr. 1, cod poștal 012345", "Aleea Exemplu bl. A 1 ap. 01, et. 0", "Strada Exemplului, sector 0",
            "Str. Exemplului nr 3; Mun. Exemplu; jud. Exemplu", "Șos. Exemplu nr. 7 | Loc. Exemplu", "Str. Exemplului nr. 5 nr. 7",
            "Sat Exemplu, Com. Exemplu", "Strada Exemplului", "Exemplu nr. 4", "Str. Gh. Exemplu nr. 3, UAT Exemplu", "Intr. Exemplu nr. 2B",
            "Splaiul Exemplu nr. 1, ap. 3\nSector 4", "Str. Ştefan cel Mare nr. 5", "Prel. Exemplu 9, Bl. 2", "", "  ",
        ]
        var cases: [JSONValue] = texts.map { .object(["text": .string($0), "address": parts(PostalAddress($0))]) }
        for word in ["Str.", "nr", "BL.", "sector", "Jud.", "Exemplu", "ap", "UAT", "B-dul", "1", ""] {
            cases.append(.object(["isMarker": .string(word), "answer": .bool(PostalAddress.isMarker(word))]))
        }
        for line in ["Sector 3, București", "Jud. Brașov", "Str. Exemplului nr. 1", "Ap. 12", "Exemplu", "București", ""] {
            cases.append(.object(["namesOnlyThePlace": .string(line), "answer": .bool(PostalAddress.namesOnlyThePlace(line))]))
        }
        return Vectors(
            name: "postal-address",
            rule: "PostalAddress(_:), PostalAddress.isMarker(_:), PostalAddress.namesOnlyThePlace(_:)",
            source: "ios/DosarCuSina/Services/Subscriptions/PostalAddress.swift",
            shape: "text: an address as printed; address: its parts (street words, street type, number, block, staircase, apartment, sector, locality words, county words, folded; null for a part not printed), or null when it names no place. isMarker: a word, and whether it marks a part of an address. namesOnlyThePlace: a line, and whether it names only where a street is.",
            cases: cases
        )
    }

    static func addressAgreements() throws -> Vectors {
        let pairs: [(String, String)] = [
            ("STRADA EXEMPLULUI NR.1 BL.A1 SC.B AP.12 SECTOR 3 BUCUREȘTI", "Str. Exemplului 1, bl. A 1, sc. b, ap. 12, sect. 3, Bucuresti"),
            ("Str. Ștefan cel Mare nr. 5", "Strada Stefan cel Mare nr. 5"), ("B-dul Exemplului nr. 2", "Bulevardul Exemplului 2"),
            ("Str. Gh. Exemplu nr. 3", "Str. Gheorghe Exemplu nr. 3"), ("Str. Exemplului nr. 01", "Str. Exemplului nr. 1"),
            ("Str. Exemplului nr. 12A", "Str. Exemplului nr. 12 A"), ("Str. Exemplului nr. 1, București", "Str. Exemplului nr. 1"),
            ("Str. Exemplului nr. 1", "Str. Exemplului nr. 5"), ("Str. Exemplului nr. 1, Brașov", "Str. Exemplului nr. 1, Cluj-Napoca"),
            ("Str. Exemplului nr. 1, Sector 3", "Str. Exemplului nr. 1, Sector 4"), ("Str. Exemplului nr. 1", "Str. Alta nr. 1"),
            ("Str. Exemplului nr. 1, bl. A1, ap. 12", "Str. Exemplului nr. 1, bl. A1, ap. 14"),
            ("Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12", "Str. Exemplului nr. 1, bl. A1, sc. C, ap. 12"),
            ("Str. Exemplului nr. 1, bl. A1, ap. 12", "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12"),
            ("Str. Exemplului nr. 1, bl. A1", "Str. Exemplului nr. 1, bl. A1, ap. 12"), ("Str. Exemplu nr. 3", "Str. Exemplului nr. 3"),
            ("Strada Exemplului", "Strada Exemplului nr. 3"), ("Calea Exemplului nr. 3", "Strada Exemplului nr. 3"),
            ("Sat Exemplu nr. 12, Com. Exemplu", "Sat Exemplu nr. 12"), ("Sat Exemplu nr. 12", "Sat Altul nr. 12"),
            ("Sat Exemplu nr. 12", "Sat Exemplu nr. 14"), ("Str. Exemplului nr. 5", "Str. Exemplului nr. 5, ap. 12"),
            ("Str. Exemplelor nr. 5", "Str. Exemplului nr. 5"), ("Str. Ion Exemplu nr. 5", "Str. Exemplu nr. 5"),
        ]
        let cases: [JSONValue] = try pairs.map { left, right in
            let a = try #require(PostalAddress(left), "\(left)")
            let b = try #require(PostalAddress(right), "\(right)")
            return .object(["a": .string(left), "b": .string(right), "agreement": .string("\(a.agreement(with: b))")])
        }
        return Vectors(
            name: "address-agreement",
            rule: "PostalAddress.agreement(with:)",
            source: "ios/DosarCuSina/Services/Subscriptions/PostalAddress.swift",
            shape: "a, b: two addresses as printed, each one that reads; agreement: how sure it is they name the same place (different, unknown, likely, same).",
            cases: cases
        )
    }

    // MARK: Where a paper belongs

    /// A home in a case: its number (its id), its address and the codes kept on it.
    struct Home {
        var number: Int
        var address: String?
        var fields: [String: String] = [:]

        var home: SubscriptionMatcher.Home {
            var values = FieldValues()
            for (key, value) in fields { values[key] = .text(value) }
            return SubscriptionMatcher.Home(id: SubscriptionVectorsTests.id(number), values: values, address: address)
        }

        var json: JSONValue {
            .object([
                "id": .string(SubscriptionVectorsTests.id(number).uuidString), "address": SubscriptionVectorsTests.text(address),
                "fields": .object(fields.mapValues(JSONValue.string)),
            ])
        }
    }

    nonisolated static func check(_ value: SubscriptionMatcher.HouseCheck?) -> JSONValue { value.map { .string("\($0)") } ?? .null }

    static func homes() -> Vectors {
        let lists: [[Home]] = [
            [Home(number: 1, address: "Str. Exemplului nr. 1, București"), Home(number: 5, address: "Str. Exemplului nr. 5, București")],
            [Home(number: 12, address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12"), Home(number: 14, address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 14")],
            [Home(number: 1, address: "Str. Exemplului nr. 5, ap. 12"), Home(number: 2, address: "Str. Alta nr. 2"), Home(number: 3, address: "Str. Exemplului nr. 5")],
            [Home(number: 1, address: "Str. Exemplului nr. 1")],
            [Home(number: 1, address: nil)],
            [Home(number: 1, address: "Str. Exemplului nr. 1"), Home(number: 2, address: "Strada Exemplului 1")],
            [Home(number: 1, address: "Str. Exemplu nr. 3"), Home(number: 2, address: "Str. Alta nr. 3")],
            [],
        ]
        let addresses: [String?] = [
            "Strada Exemplului 5, Sector 3, Bucuresti", "Str. Exemplului nr. 9", "Str. Exemplului nr. 1, bl. A1, ap. 14", "Str. Exemplului nr. 1, bl. A1",
            "Str. Exemplului nr. 5", "Str. Exemplului nr. 5, ap. 12", "Str. Alta nr. 7", "Str. Exemplului nr. 1", "Str. Exemplului nr. 3",
            "Cod client 1000000000", nil,
        ]
        var cases: [JSONValue] = []
        for homes in lists {
            for address in addresses {
                let house = SubscriptionMatcher.house(at: address, among: homes.map(\.home))
                let home = SubscriptionMatcher.home(at: address, among: homes.map(\.home))
                cases.append(.object([
                    "address": text(address), "homes": .array(homes.map(\.json)),
                    "house": house.map { .object(["id": .string($0.id.uuidString), "check": check($0.check)]) } ?? .null,
                    "home": home.map { .object(["id": .string($0.id.uuidString), "check": check($0.check)]) } ?? .null,
                ]))
            }
        }
        return Vectors(
            name: "homes",
            rule: "SubscriptionMatcher.house(at:among:) and home(at:among:)",
            source: "ios/DosarCuSina/Services/Subscriptions/SubscriptionMatcher.swift",
            shape: "address: as a paper prints it (null for none); homes: each its id, its address (null for none) and the fields kept on it; house: the home the address picks by itself, with what is worth a look (addressPartlyAgrees, addressDiffers, null), or null when it can't tell; home: the same, else the only home, or null.",
            cases: cases
        )
    }

    /// A subscription in a case: its number (its id), the home it is filed under, and its values.
    struct Subscription {
        var number: Int
        var parent: Int?
        var provider: String?
        var service: String?
        /// The codes kept on it, by their fields' keys.
        var fields: [String: String] = [:]

        var subscription: SubscriptionMatcher.Subscription {
            var values = FieldValues()
            values[SubscriptionFields.provider] = provider.map(FieldValue.text)
            values[SubscriptionFields.service] = service.map(FieldValue.text)
            for (key, value) in fields { values[key] = .text(value) }
            return .init(id: SubscriptionVectorsTests.id(number), parentID: parent.map(SubscriptionVectorsTests.id), values: values)
        }

        var json: JSONValue {
            .object([
                "id": .string(SubscriptionVectorsTests.id(number).uuidString),
                "parentID": parent.map { .string(SubscriptionVectorsTests.id($0).uuidString) } ?? .null,
                "provider": SubscriptionVectorsTests.text(provider), "service": SubscriptionVectorsTests.text(service),
                "fields": .object(fields.mapValues(JSONValue.string)),
            ])
        }
    }

    struct Placing {
        var name: String
        var provider: String? = "ENGIE Romania S.A."
        var service: String? = ServiceKind.gas
        var codes: [SubscriptionCode: String] = [:]
        var isBill = true
        var supplyAddress: String?
        var subscriptions: [Subscription] = []
        var homes: [Home] = []
        var within: Int?
    }

    nonisolated static func decision(_ decision: SubscriptionMatcher.Decision) -> JSONValue {
        switch decision {
        case .existing(let id): .object(["type": "existing", "id": .string(id.uuidString)])
        case .newUnder(let home): .object(["type": "newUnder", "id": .string(home.uuidString)])
        case .newStandalone: .object(["type": "newStandalone", "id": .null])
        case .undecided: .object(["type": "undecided", "id": .null])
        }
    }

    static func matcher() -> Vectors {
        let clc = SubscriptionFields.clc, pod = SubscriptionFields.pod, client = SubscriptionFields.clientCode
        let engie = "ENGIE Romania S.A."
        func gas(_ number: Int, under parent: Int?, _ fields: [String: String] = [:], provider: String? = engie) -> Subscription {
            Subscription(number: number, parent: parent, provider: provider, service: ServiceKind.gas, fields: fields)
        }
        let twoStreetHomes = [Home(number: 1, address: "Str. Exemplului nr. 1"), Home(number: 5, address: "Str. Exemplului nr. 5")]
        let placings: [Placing] = [
            Placing(name: "Codes come first", codes: [.clc: "DEG0000000000002"],
                    subscriptions: [gas(11, under: 1, [clc: "DEG0000000000001"]), gas(12, under: 5, [clc: "DEG 0000-0000-0000-2"])], homes: twoStreetHomes),
            Placing(name: "A different consumption point is never the one", codes: [.clc: "DEG0000000000003"],
                    subscriptions: [gas(11, under: 1, [clc: "DEG0000000000001"])], homes: [Home(number: 1, address: nil)]),
            Placing(name: "A code from another service is never read", codes: [.pod: "RO005E000000001"],
                    subscriptions: [gas(11, under: 1, [clc: "DEG0000000000001"]),
                                    Subscription(number: 12, parent: 1, provider: "Enel Energie S.A.", service: ServiceKind.electricity, fields: [pod: "RO005E000000001"])],
                    homes: [Home(number: 1, address: nil)]),
            Placing(name: "A stray POD never tells two internet contracts apart", provider: "Vodafone Romania", service: ServiceKind.internetTV,
                    codes: [.pod: "RO005E000000001", .account: "3000000000"],
                    subscriptions: [Subscription(number: 11, parent: 1, provider: "Vodafone Romania S.A.", service: ServiceKind.internetTV, fields: [pod: "RO005E000000009"])],
                    homes: [Home(number: 1, address: nil)]),
            Placing(name: "A bill that matches by its address only", supplyAddress: "Str. Exemplului nr. 5",
                    subscriptions: [gas(11, under: 1), gas(12, under: 5)], homes: twoStreetHomes),
            Placing(name: "Two homes on one street: the number decides", supplyAddress: "Strada Exemplului 5, Sector 3, Bucuresti", homes: twoStreetHomes),
            Placing(name: "No address and no code with two homes: the person picks", homes: twoStreetHomes),
            Placing(name: "An address neither home has", supplyAddress: "Str. Exemplului nr. 9", homes: twoStreetHomes),
            Placing(name: "Two flats in one block, by the apartment", supplyAddress: "Str. Exemplului nr. 1, bl. A1, ap. 14",
                    homes: [Home(number: 12, address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12"), Home(number: 14, address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 14")]),
            Placing(name: "Two flats in one block, the bill not saying which", supplyAddress: "Str. Exemplului nr. 1, bl. A1",
                    homes: [Home(number: 12, address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12"), Home(number: 14, address: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 14")]),
            Placing(name: "A partial match is suggested with a check", supplyAddress: "Str. Exemplului nr. 5",
                    homes: [Home(number: 1, address: "Str. Exemplului nr. 5, ap. 12"), Home(number: 2, address: "Str. Alta nr. 2")]),
            Placing(name: "The only home at another address is kept but checked", supplyAddress: "Str. Alta nr. 7",
                    homes: [Home(number: 1, address: "Str. Exemplului nr. 1")]),
            Placing(name: "The only home at another address, an existing contract there", supplyAddress: "Str. Alta nr. 7",
                    subscriptions: [gas(11, under: 1)], homes: [Home(number: 1, address: "Str. Exemplului nr. 1")]),
            Placing(name: "The home's own code outranks the address", codes: [.clc: "DEG0000000000001"], supplyAddress: "Str. Exemplului nr. 5",
                    homes: [Home(number: 1, address: "Str. Exemplului nr. 1", fields: [HomeFields.clc: "DEG0000000000001"]), Home(number: 5, address: "Str. Exemplului nr. 5")]),
            Placing(name: "A client code alone can't tell two homes apart", codes: [.clientCode: "1000000000"],
                    subscriptions: [gas(11, under: 1, [client: "1000000000"]), gas(12, under: 5, [client: "1000000000"])], homes: twoStreetHomes),
            Placing(name: "A client code alone, inside the home the person chose", codes: [.clientCode: "1000000000"],
                    subscriptions: [gas(11, under: 1, [client: "1000000000"]), gas(12, under: 5, [client: "1000000000"])], homes: twoStreetHomes, within: 5),
            Placing(name: "Two contracts with the same client code and one home", codes: [.clientCode: "1000000000"],
                    subscriptions: [gas(11, under: 1, [client: "1000000000"]), gas(12, under: 1, [client: "1000000000"])], homes: [Home(number: 1, address: nil)]),
            Placing(name: "A client code and a contract number outrank a client code", codes: [.clientCode: "1000000000", .contractNumber: "CTR-0001"],
                    subscriptions: [gas(11, under: 1, [client: "1000000000"]), gas(12, under: 1, [client: "1000000000", SubscriptionFields.contractNumber: "ctr 0001"])],
                    homes: [Home(number: 1, address: nil)]),
            Placing(name: "The provider decides inside the home, two with the same one", supplyAddress: "Str. Exemplului nr. 5",
                    subscriptions: [gas(11, under: 5), gas(12, under: 5, provider: "Engie")], homes: twoStreetHomes),
            Placing(name: "Another provider in the home is a new contract", provider: "Exemplu Gaz S.R.L.", supplyAddress: "Str. Exemplului nr. 5",
                    subscriptions: [gas(11, under: 5)], homes: twoStreetHomes),
            Placing(name: "No homes: a gas contract stands on its own"),
            Placing(name: "A phone plan, by its number in another form", provider: "Orange Romania S.A.", service: ServiceKind.mobile,
                    codes: [.phoneNumber: "+40 712 345 678"],
                    subscriptions: [Subscription(number: 11, parent: nil, provider: "Orange Romania S.A.", service: ServiceKind.mobile,
                                                 fields: [SubscriptionFields.phoneNumber: "0712345678"])],
                    homes: twoStreetHomes),
            Placing(name: "A phone plan with another number", provider: "Orange Romania S.A.", service: ServiceKind.mobile,
                    codes: [.phoneNumber: "0040 722 000 000"],
                    subscriptions: [Subscription(number: 11, parent: nil, provider: "Orange Romania S.A.", service: ServiceKind.mobile,
                                                 fields: [SubscriptionFields.phoneNumber: "0712345678"])],
                    homes: twoStreetHomes),
            Placing(name: "A phone plan by its provider, on its own", provider: "Orange Romania", service: ServiceKind.mobile,
                    subscriptions: [Subscription(number: 11, parent: nil, provider: "Orange Romania S.A.", service: ServiceKind.mobile),
                                    Subscription(number: 12, parent: 1, provider: "Orange Romania S.A.", service: ServiceKind.internetTV)],
                    homes: twoStreetHomes),
            Placing(name: "An unknown service with a POD goes under the home that keeps it", provider: nil, service: nil, codes: [.pod: "RO005E000000001"],
                    homes: [Home(number: 1, address: nil), Home(number: 2, address: nil, fields: [HomeFields.pod: "ro005e000000001"])]),
            Placing(name: "A contract with no service and no code stands on its own", provider: "Exemplu Servicii S.R.L.", service: nil, isBill: false,
                    homes: twoStreetHomes),
            Placing(name: "A bill with no service named is a utility's", provider: "Exemplu Servicii S.R.L.", service: nil, homes: [Home(number: 1, address: nil)]),
            Placing(name: "An unspecified service is never told apart from gas",
                    subscriptions: [Subscription(number: 11, parent: 1, provider: engie, service: ServiceKind.other)], homes: [Home(number: 1, address: nil)]),
            Placing(name: "Another service is never the one",
                    subscriptions: [Subscription(number: 11, parent: 1, provider: engie, service: ServiceKind.electricity)], homes: [Home(number: 1, address: nil)]),
            Placing(name: "A service typed as text", service: "Gaze naturale", subscriptions: [Subscription(number: 11, parent: 1, provider: "Engie", service: "gaz")],
                    homes: [Home(number: 1, address: nil)]),
            Placing(name: "Inside the home the person chose, a new one there", codes: [.clc: "DEG0000000000009"],
                    subscriptions: [gas(11, under: 1, [clc: "DEG0000000000009"])], homes: twoStreetHomes, within: 5),
            Placing(name: "A code that is only spaces is no code", codes: [.clc: " - "], subscriptions: [gas(11, under: 1, [clc: "DEG0000000000001"])],
                    homes: [Home(number: 1, address: nil)]),
        ]
        let cases: [JSONValue] = placings.map { placing in
            let reading = SubscriptionMatcher.Reading(provider: placing.provider, service: placing.service, codes: placing.codes,
                                                      isBill: placing.isBill, supplyAddress: placing.supplyAddress)
            let placement = SubscriptionMatcher.place(reading, subscriptions: placing.subscriptions.map(\.subscription), homes: placing.homes.map(\.home),
                                                      within: placing.within.map(id))
            return .object([
                "name": .string(placing.name),
                "reading": .object([
                    "provider": text(placing.provider), "service": text(placing.service),
                    "codes": .object(Dictionary(placing.codes.map { ($0.key.rawValue, JSONValue.string($0.value)) }, uniquingKeysWith: { first, _ in first })),
                    "isBill": .bool(placing.isBill), "supplyAddress": text(placing.supplyAddress),
                ]),
                "subscriptions": .array(placing.subscriptions.map(\.json)),
                "homes": .array(placing.homes.map(\.json)),
                "within": placing.within.map { .string(id($0).uuidString) } ?? .null,
                "keptCodes": .array(SubscriptionCode.allCases.filter { reading.codes[$0] != nil }.map { .string($0.rawValue) }),
                "isTiedToHome": .bool(reading.isTiedToHome),
                "decision": decision(placement.decision),
                "check": check(placement.check),
            ])
        }
        return Vectors(
            name: "matcher",
            rule: "SubscriptionMatcher.Reading(provider:service:codes:isBill:supplyAddress:) and SubscriptionMatcher.place(_:subscriptions:homes:within:)",
            source: "ios/DosarCuSina/Services/Subscriptions/SubscriptionMatcher.swift",
            shape: "reading: what a paper says (its provider and service, null for none, its codes by name, whether it is a bill, its supply address); subscriptions: each its id, the home it is filed under (null for none), its provider and stored service (null for none), and its codes by their fields' keys; homes: as homes.json; within: the home the person chose (null for none). keptCodes: the codes the reading keeps, in order; isTiedToHome: whether it belongs under a home; decision: existing (the subscription's id), newUnder (the home's id), newStandalone or undecided; check: what is worth a look about the house (null for nothing).",
            cases: cases
        )
    }

    static func providerNames() -> Vectors {
        let names = [
            "ENGIE Romania S.A.", "E.ON Energie Romania", "Apa Nova București S.A.", "Engie", "Exemplu Gaz S.R.L.", "Orange Romania S.A.",
            "Romania S.A.", "S.C. Exemplu Furnizare S.R.L.", "The Exemplu Energy Company", "Digi  Exemplu", "  ", "", "Ș.A. Țară",
        ]
        let cases: [JSONValue] = names.map { name in
            .object([
                "name": .string(name), "short": .string(SubscriptionMatcher.shortProviderName(name)),
                "words": .array(SubscriptionMatcher.providerWords(name).sorted().map(JSONValue.string)),
            ])
        }
        return Vectors(
            name: "provider-names",
            rule: "SubscriptionMatcher.shortProviderName(_:) and providerWords(_:)",
            source: "ios/DosarCuSina/Services/Subscriptions/SubscriptionMatcher.swift",
            shape: "name: a provider as printed; short: as people say it; words: the folded words that name it, sorted.",
            cases: cases
        )
    }

    static func codesKept() -> Vectors {
        let read: [(service: String?, fields: [(CaptureFieldKey, String)])] = [
            (ServiceKind.internetTV, [(.serviceKind, ServiceKind.internetTV), (.podCode, "RO005E000000001"), (.clientCode, "2000000000")]),
            (ServiceKind.gas, [(.podCode, "RO002G000000001"), (.account, "3000000000")]),
            (ServiceKind.water, [(.clcCode, "123456"), (.placeCode, "654321")]),
            (ServiceKind.water, [(.clcCode, "123456"), (.podCode, "654321")]),
            (nil, [(.podCode, "RO005E000000001"), (.clcCode, "DEG0000000001")]),
            ("Gaze naturale", [(.podCode, "RO002G000000001"), (.total, "245.30")]),
            (ServiceKind.streaming, [(.clientCode, "2000000000"), (.provider, "Exemplu Streaming")]),
            (ServiceKind.mobile, [(.phoneNumber, "0712345678"), (.podCode, "RO005E000000001"), (.account, "3000000000"), (.clientCode, "2000000000")]),
            (ServiceKind.electricity, [(.clcCode, "DEG0000000001"), (.podCode, "RO005E000000001")]),
            ("Netflix", [(.podCode, "RO005E000000001")]),
        ]
        let cases: [JSONValue] = read.map { service, fields in
            let captured = fields.map { CaptureField(key: $0.0, value: .text($0.1), confidence: 0.7, sourceText: nil, tier: .heuristic) }
            let kept = SubscriptionCode.keeping(captured, service: service)
            func written(_ field: CaptureField) -> JSONValue { .object(["key": .string(field.key.rawValue), "value": .string(field.value.text ?? "")]) }
            return .object(["service": text(service), "fields": .array(captured.map(written)), "kept": .array(kept.map(written))])
        }
        return Vectors(
            name: "codes-kept",
            rule: "SubscriptionCode.keeping(_:service:)",
            source: "ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift",
            shape: "service: the service a paper was read as (null for none); fields: what it read, each its capture key and value, in order; kept: what it keeps, in order, a code read under another service's name kept as its own code of the same family.",
            cases: cases
        )
    }

    // MARK: Lists

    static func groups() -> Vectors {
        var cases: [JSONValue] = []
        let values: [(group: String?, service: String?)] = [
            (nil, ServiceKind.gas), (nil, ServiceKind.streaming), (SubscriptionGroup.other.rawValue, ServiceKind.gas), ("Transport", ServiceKind.gas),
            ("utilitati", nil), ("bogus", ServiceKind.mobile), (nil, nil), (nil, "Telefon mobil"), (nil, "bogus"),
        ]
        for value in values {
            var stored = FieldValues()
            stored[SubscriptionFields.group] = value.group.map(FieldValue.text)
            stored[SubscriptionFields.service] = value.service.map(FieldValue.text)
            cases.append(.object(["group": text(value.group), "service": text(value.service), "listedIn": .string(SubscriptionGroup.of(stored).rawValue)]))
        }
        struct Item { var name: String; var group: String?; var service: String? }
        let lists: [[Item]] = [
            [Item(name: "Netflix", service: ServiceKind.streaming), Item(name: "Gaz", service: ServiceKind.gas), Item(name: "Telefon", service: ServiceKind.mobile),
             Item(name: "Curent", service: ServiceKind.electricity)],
            [Item(name: "Apă", service: ServiceKind.water), Item(name: "Internet", service: ServiceKind.internetTV), Item(name: "Curent", service: ServiceKind.electricity),
             Item(name: "Gaz", service: ServiceKind.gas)],
            [Item(name: "Apă", service: ServiceKind.water)],
            [Item(name: "Gaz mutat", group: SubscriptionGroup.other.rawValue, service: ServiceKind.gas), Item(name: "Altceva", service: nil),
             Item(name: "Metrou", service: ServiceKind.transport), Item(name: "Curent", service: ServiceKind.electricity)],
            [],
        ]
        var withoutGroups = BuiltInTemplates.subscription
        withoutGroups.sections = withoutGroups.sections.map { section in
            var section = section
            section.fields.removeAll { $0.key == SubscriptionFields.group }
            return section
        }
        for items in lists {
            for (keepsGroups, definition) in [(true, BuiltInTemplates.subscription), (false, withoutGroups)] {
                let listing = SubscriptionGroup.listing(items, in: definition) { item in
                    var stored = FieldValues()
                    stored[SubscriptionFields.group] = item.group.map(FieldValue.text)
                    stored[SubscriptionFields.service] = item.service.map(FieldValue.text)
                    return stored
                }
                var firstRows: [JSONValue] = []
                for limit in [0, 1, 3, 4, 10] {
                    let rows = SubscriptionGroup.firstRows(of: listing, limit: limit)
                    firstRows.append(.object([
                        "limit": .int(limit),
                        "rows": .array(rows.map { .object(["opens": text($0.opens?.rawValue), "item": .string($0.item.name)]) }),
                    ]))
                }
                cases.append(.object([
                    "items": .array(items.map { .object(["name": .string($0.name), "group": text($0.group), "service": text($0.service)]) }),
                    "keepsGroups": .bool(keepsGroups),
                    "listing": .array(listing.map { .object(["group": text($0.group?.rawValue), "items": .array($0.items.map { .string($0.name) })]) }),
                    "firstRows": .array(firstRows),
                ]))
            }
        }
        return Vectors(
            name: "groups",
            rule: "SubscriptionGroup.of(_:), listing(_:in:values:) and firstRows(of:limit:)",
            source: "ios/DosarCuSina/Models/Fields/ChoiceOptions.swift",
            shape: "group, service: a subscription's stored group and service (null for none); listedIn: the group it is listed in. Or items (each its name, stored group and service) and whether the category keeps groups (keepsGroups: the subscription category, else one without the group field); listing: its groups in order, each its key (null for the one list of a category that keeps none) and its items' names; firstRows: for each limit, the rows a pocket shows, each the group it opens (null for none) and the item's name.",
            cases: cases
        )
    }

    // MARK: The meter

    static func meter() -> Vectors {
        // An index becomes the Double nearest it (`RomanianNumber.double`), as Kotlin's `BigDecimal.toDouble()`
        // gives it: 98765.4321 is stored as 98765.4321, where Foundation's `NSDecimalNumber.doubleValue`, the
        // conversion of earlier versions, gave 98765.43209999999.
        let readings: [(index: String?, basis: String?, service: String?)] = [
            ("12345", nil, ServiceKind.gas), ("1234.567", "estimated", ServiceKind.electricity), ("0", "read", ServiceKind.water),
            ("-5", nil, ServiceKind.gas), (nil, nil, ServiceKind.gas), ("100", nil, ServiceKind.heating), ("100", nil, ServiceKind.mobile),
            ("100", nil, nil), ("100", "bogus", "Gaze naturale"), ("98765.5", "read", "Curent"), ("0.125", nil, ServiceKind.water),
            ("98765.4321", "read", ServiceKind.gas), ("4321.0987", nil, ServiceKind.water), ("1.001", "estimated", ServiceKind.electricity),
        ]
        let days = ["2026-10-05", "2026-03-29", "2026-10-25"]
        var cases: [JSONValue] = []
        for (number, reading) in readings.enumerated() {
            let dayText = days[number % days.count]
            let index = reading.index.map { CaptureValue.number(Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))!) }
            let basis = reading.basis.map(CaptureValue.text)
            let answer = SubscriptionMeter.reading(index, basis: basis, service: reading.service, day: day(dayText))
            let noon = day(dayText).noonDate(in: calendar)
            cases.append(.object([
                "index": text(reading.index), "basis": text(reading.basis), "service": text(reading.service), "day": .string(dayText),
                "reading": answer.map { answer in
                    .object([
                        "value": .number(answer.value), "kind": .string(answer.kind.rawValue), "unit": .string(answer.unit.key),
                        "day": .string(answer.day.isoString), "basis": text(answer.basis?.rawValue),
                        "at": .string(ISO8601DateFormatter().string(from: noon)),
                    ])
                } ?? .null,
            ]))
        }
        return Vectors(
            name: "meter",
            rule: "SubscriptionMeter.reading(_:basis:service:day:), and the moment a bill's reading is dated at (Reading.planned: noon in Bucharest)",
            source: "ios/DosarCuSina/Services/Subscriptions/SubscriptionMeter.swift",
            shape: "index: the number a bill prints (null for none), basis: how the bill says it was taken (null for unsaid), service: the subscription's stored service (null for none), day: the bill's day; reading: the value, its kind and unit's key, its day, its basis (null for none) and the UTC moment it is recorded at, or null when the service has no meter or the index isn't one.",
            cases: cases
        )
    }

    // MARK: The bill reminder

    static func billReminders() throws -> Vectors {
        struct Reminder { var status: ObligationStatus; var due: String }
        let cases: [(before: Bool?, after: Bool, today: String, reminders: [Reminder])] = [
            (false, true, "2026-11-02", [Reminder(status: .active, due: "2026-11-20")]),
            (nil, true, "2026-11-02", [Reminder(status: .active, due: "2026-11-20")]),
            (true, false, "2026-11-10", [Reminder(status: .paused, due: "2026-11-20")]),
            (true, false, "2026-11-20", [Reminder(status: .paused, due: "2026-11-20")]),
            (true, false, "2026-11-25", [Reminder(status: .paused, due: "2026-11-20")]),
            (true, true, "2026-11-02", [Reminder(status: .active, due: "2026-11-20")]),
            (false, false, "2026-11-02", [Reminder(status: .paused, due: "2026-11-20")]),
            (false, true, "2026-11-02", []),
            (true, false, "2026-11-02", [Reminder(status: .active, due: "2026-11-20")]),
            (false, true, "2026-11-02", [Reminder(status: .paused, due: "2026-11-20")]),
            (true, false, "2026-11-10", [Reminder(status: .paused, due: "2026-11-05"), Reminder(status: .paused, due: "2026-12-05"),
                                         Reminder(status: .active, due: "2026-12-20")]),
            (false, true, "2026-11-10", [Reminder(status: .active, due: "2026-11-05"), Reminder(status: .paused, due: "2026-12-05"),
                                         Reminder(status: .active, due: "2026-12-20")]),
        ]
        var written: [JSONValue] = []
        for (before, after, today, reminders) in cases {
            let context = try makeContext()
            let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.subscription))
            let blueprint = try #require(template.blueprints.first { $0.key == SubscriptionFields.billBlueprint })
            var values = FieldValues()
            values[SubscriptionFields.provider] = .text("ENGIE Romania S.A.")
            values[SubscriptionFields.service] = .text(ServiceKind.gas)
            values[SubscriptionFields.directDebit] = before.map(FieldValue.bool)
            let date = noon("2026-10-01")
            let gas = try AssetActions(context: context, calendar: calendar, now: { date })
                .create(name: "Gaze – ENGIE Romania S.A.", template: template, values: values)
            let deadlines = ObligationActions(context: context, calendar: calendar, now: { date })
            var made: [Obligation] = []
            for reminder in reminders {
                let bill = try deadlines.create(from: blueprint, for: gas, firstDue: day(reminder.due))
                if reminder.status == .paused { _ = try deadlines.pause(bill) }
                made.append(bill)
            }
            var edited = gas.values
            edited[SubscriptionFields.directDebit] = .bool(after)
            let now = noon(today, calendar: calendar)
            let outcome = try AssetActions(context: context, calendar: calendar, now: { now })
                .update(gas, name: gas.name, values: edited, notes: gas.notes)
            written.append(.object([
                "directDebitBefore": before.map(JSONValue.bool) ?? .null, "directDebitAfter": .bool(after), "today": .string(today),
                "reminders": .array(reminders.map { .object(["status": .string($0.status.rawValue), "due": .string($0.due)]) }),
                "change": outcome.billReminder.map { .string("\($0.value)") } ?? .null,
                "statusesAfter": .array(made.map { .string($0.status.rawValue) }),
            ]))
        }
        return Vectors(
            name: "bill-reminders",
            rule: "BillReminders.direction(from:to:) and follow(_:from:actions:today:calendar:), run by AssetActions.update",
            source: "ios/DosarCuSina/Services/Subscriptions/BillReminders.swift",
            shape: "directDebitBefore: whether the bank paid the subscription's bills before the edit (null when never said), directDebitAfter: after it, today: the edit's day, reminders: its Factura de plătit deadlines, each its status and due day; change: what happened to them (paused, resumed, null for nothing), statusesAfter: each one's status after the edit, in order.",
            cases: written
        )
    }
}
