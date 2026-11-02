import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

// MARK: - Assertion helpers kept from the first test harness

// The cadence and parser suites were written against these helpers. They now
// record Swift Testing issues at the caller's location. They are `throws` only
// so the existing `try assert…` call sites stay unchanged.

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(actual == expected, Comment(rawValue: message), sourceLocation: sourceLocation)
}

func assertAlmostEqual(_ actual: Double, _ expected: Double, accuracy: Double = 0.001, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(abs(actual - expected) <= accuracy, Comment(rawValue: "\(message) (\(actual) vs \(expected))"), sourceLocation: sourceLocation)
}

func assertTrue(_ condition: Bool, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(condition, Comment(rawValue: message), sourceLocation: sourceLocation)
}

func assertFalse(_ condition: Bool, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(!condition, Comment(rawValue: message), sourceLocation: sourceLocation)
}

func assertNil<T>(_ value: T?, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(value == nil, Comment(rawValue: message), sourceLocation: sourceLocation)
}

func assertNotNil<T>(_ value: T?, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(value != nil, Comment(rawValue: message), sourceLocation: sourceLocation)
}

/// Thrown by the older suites to stop a test early; Swift Testing reports it as a failure.
struct TestAssertionError: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int

    var description: String { "\(message) at \(file):\(line)" }
}

// MARK: - Fixtures

extension Calendar {
    /// Gregorian in Bucharest, the time zone the app's rules are written for.
    static var bucharest: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest") ?? .gmt
        calendar.locale = Locale(identifier: "ro_RO")
        return calendar
    }
}

extension CalendarDay {
    /// `CalendarDay("2026-11-02")` in tests.
    init(_ iso: String) {
        self = CalendarDay(isoString: iso) ?? CalendarDay(year: 1970, month: 1, day: 1)
    }
}

/// A fixed clock for tests: noon on `day` in Bucharest.
func noon(_ iso: String, calendar: Calendar = .bucharest) -> Date {
    CalendarDay(iso).noonDate(in: calendar)
}

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try PersistenceController.makeContainer(inMemory: true)
}

/// A context with the built-in categories installed.
@MainActor
func makeContext() throws -> ModelContext {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    try TemplateStore(context: context).installBuiltIns()
    return context
}

/// Snapshot for pure-function tests.
func snapshot(
    _ title: String = "Obligație",
    kind: ObligationKind = .routine,
    due: String,
    status: ObligationStatus = .active,
    asset: (UUID, String)? = nil,
    offsets: [Int]? = nil,
    consequence: Consequence? = nil,
    grace: Int? = nil,
    snoozedUntil: Date? = nil,
    cost: Money? = nil,
    isSensitive: Bool = false,
    isExample: Bool = false
) -> ObligationSnapshot {
    ObligationSnapshot(
        title: title,
        kind: kind,
        status: status,
        dueDay: CalendarDay(due),
        snoozedUntil: snoozedUntil,
        reminders: ReminderProfile(
            leadDays: offsets ?? kind.defaultProfile.leadDays,
            consequence: consequence ?? kind.defaultProfile.consequence,
            graceDays: grace ?? kind.defaultProfile.graceDays
        ),
        estimatedCost: cost,
        assetId: asset?.0,
        assetName: asset?.1,
        isSensitive: isSensitive,
        isExample: isExample
    )
}
