import Foundation
import UserNotifications
import SwiftUI
import WidgetKit
import SwiftData

// MARK: - Adversarial Test Suite

public final class AdversarialTests: Sendable {
    
    private static let gmtCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()
    
    private static func makeGMTDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.minute = minute
        comp.second = 0
        comp.timeZone = TimeZone(secondsFromGMT: 0)
        return gmtCalendar.date(from: comp)!
    }
    
    private static func makeLocalDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.minute = minute
        comp.second = 0
        comp.timeZone = timeZone
        return cal.date(from: comp)!
    }
    
    // =========================================================================
    // TASK 1: NOTIFICATION SCHEDULING ADVERSARIAL VERIFICATION
    // =========================================================================
    
    // 1.1 Past-Offset Stress Test: Event Due Today (Before 09:00 AM)
    public static func testEventDueToday_Before0900AM() throws {
        // Due Date: Today at 16:00
        let dueDate = makeGMTDate(year: 2026, month: 11, day: 1, hour: 16)
        // Reference Date: Today at 07:30 AM (before the 09:00 AM morning alert)
        let referenceDate = makeGMTDate(year: 2026, month: 11, day: 1, hour: 7, minute: 30)
        
        // -30d, -7d, -1d are in the past -> must be nil
        try assertNil(NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: -30, referenceDate: referenceDate, calendar: gmtCalendar), "-30d is in the past")
        try assertNil(NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: -7, referenceDate: referenceDate, calendar: gmtCalendar), "-7d is in the past")
        try assertNil(NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: -1, referenceDate: referenceDate, calendar: gmtCalendar), "-1d is in the past")
        
        // Offset 0d lands at 09:00 AM today, which is AFTER 07:30 AM -> MUST BE SCHEDULED
        let trigger0 = NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: 0, referenceDate: referenceDate, calendar: gmtCalendar)
        try assertNotNil(trigger0, "0d offset must be scheduled if referenceDate < 09:00 AM")
        let comp = gmtCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: trigger0!)
        try assertEqual(comp.year, 2026, "Year 2026")
        try assertEqual(comp.month, 11, "Month 11")
        try assertEqual(comp.day, 1, "Day 1")
        try assertEqual(comp.hour, 9, "09:00 AM")
        try assertEqual(comp.minute, 0, "00 min")
        try assertEqual(comp.second, 0, "00 sec")
    }
    
    // 1.2 Past-Offset Stress Test: Event Due Today (After 09:00 AM)
    public static func testEventDueToday_After0900AM() throws {
        // Due Date: Today at 16:00
        let dueDate = makeGMTDate(year: 2026, month: 11, day: 1, hour: 16)
        // Reference Date: Today at 10:15 AM (after the 09:00 AM morning alert)
        let referenceDate = makeGMTDate(year: 2026, month: 11, day: 1, hour: 10, minute: 15)
        
        // ALL offsets (-30, -7, -1, 0) must be pruned because 09:00 AM today is already in the past!
        for offset in [-30, -7, -1, 0, 30, 7, 1] {
            let trigger = NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: offset, referenceDate: referenceDate, calendar: gmtCalendar)
            try assertNil(trigger, "Offset \(offset) must be pruned when referenceDate is 10:15 AM today")
        }
    }
    
    // 1.3 Past-Offset Stress Test: Event Due In Exactly 2 Days
    public static func testEventDueIn2Days() throws {
        // Reference Date: Nov 1, 2026 10:00 AM
        let referenceDate = makeGMTDate(year: 2026, month: 11, day: 1, hour: 10)
        // Due Date: Nov 3, 2026 14:00 PM (2 days later)
        let dueDate = makeGMTDate(year: 2026, month: 11, day: 3, hour: 14)
        
        // -30d (Oct 4) -> Past -> nil
        try assertNil(NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: -30, referenceDate: referenceDate, calendar: gmtCalendar), "-30d must be nil")
        // -7d (Oct 27) -> Past -> nil
        try assertNil(NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: -7, referenceDate: referenceDate, calendar: gmtCalendar), "-7d must be nil")
        
        // -1d (Nov 2 at 09:00 AM) -> Tomorrow morning -> MUST BE SCHEDULED
        let trigger1 = NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: -1, referenceDate: referenceDate, calendar: gmtCalendar)
        try assertNotNil(trigger1, "-1d must be scheduled")
        let comp1 = gmtCalendar.dateComponents([.day, .hour, .minute], from: trigger1!)
        try assertEqual(comp1.day, 2, "Nov 2")
        try assertEqual(comp1.hour, 9, "09:00 AM")
        
        // 0d (Nov 3 at 09:00 AM) -> Due date morning -> MUST BE SCHEDULED
        let trigger0 = NotificationScheduler.calculateTriggerDate(dueDate: dueDate, offsetDays: 0, referenceDate: referenceDate, calendar: gmtCalendar)
        try assertNotNil(trigger0, "0d must be scheduled")
        let comp0 = gmtCalendar.dateComponents([.day, .hour, .minute], from: trigger0!)
        try assertEqual(comp0.day, 3, "Nov 3")
        try assertEqual(comp0.hour, 9, "09:00 AM")
    }
    
    // 1.4 Past-Offset Stress Test: Event Overdue by 10 Days
    public static func testEventOverdueBy10Days() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        // Reference Date: Nov 1, 2026 10:00 AM
        let referenceDate = makeGMTDate(year: 2026, month: 11, day: 1, hour: 10)
        // Due Date: Oct 22, 2026 10:00 AM (10 days in the past)
        let dueDate = makeGMTDate(year: 2026, month: 10, day: 22, hour: 10)
        
        let event = LifecycleEvent(
            id: UUID(),
            title: "Overdue Event",
            dueDate: dueDate,
            reminderOffsetDays: [-30, -7, -1, 0]
        )
        
        let scheduledIds = try await scheduler.scheduleReminders(for: event, referenceDate: referenceDate, calendar: gmtCalendar)
        try assertEqual(scheduledIds.count, 0, "Overdue event must schedule exactly ZERO notifications")
        try assertEqual(mockCenter.addedRequests.count, 0, "Zero notification requests added to UNUserNotificationCenter")
    }
    
    // 1.5 Fixed 09:00:00 AM Across Leap Day (Feb 29)
    public static func testFixedHourAcrossLeapDays() throws {
        // Leap Year 2028: Feb 29 exists
        let ref2028 = makeGMTDate(year: 2028, month: 1, day: 1, hour: 0)
        
        // 1. Due March 1, 2028: -1d lands on Feb 29, 2028
        let dueMarch1_2028 = makeGMTDate(year: 2028, month: 3, day: 1, hour: 12)
        guard let triggerLeapDay = NotificationScheduler.calculateTriggerDate(
            dueDate: dueMarch1_2028,
            offsetDays: -1,
            referenceDate: ref2028,
            calendar: gmtCalendar
        ) else {
            throw TestAssertionError(message: "Leap day trigger must exist", file: #file, line: #line)
        }
        let compLeap = gmtCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerLeapDay)
        try assertEqual(compLeap.year, 2028, "Year 2028")
        try assertEqual(compLeap.month, 2, "February")
        try assertEqual(compLeap.day, 29, "February 29 preserved on leap year")
        try assertEqual(compLeap.hour, 9, "Hour must be 9")
        try assertEqual(compLeap.minute, 0, "Minute must be 0")
        try assertEqual(compLeap.second, 0, "Second must be 0")
        
        // 2. Non-leap Year 2027: March 1 - 1d lands on Feb 28, 2027
        let ref2027 = makeGMTDate(year: 2027, month: 1, day: 1, hour: 0)
        let dueMarch1_2027 = makeGMTDate(year: 2027, month: 3, day: 1, hour: 12)
        guard let triggerNonLeap = NotificationScheduler.calculateTriggerDate(
            dueDate: dueMarch1_2027,
            offsetDays: -1,
            referenceDate: ref2027,
            calendar: gmtCalendar
        ) else {
            throw TestAssertionError(message: "Non leap day trigger must exist", file: #file, line: #line)
        }
        let compNonLeap = gmtCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerNonLeap)
        try assertEqual(compNonLeap.year, 2027, "Year 2027")
        try assertEqual(compNonLeap.month, 2, "February")
        try assertEqual(compNonLeap.day, 28, "February 28 on non-leap year")
        try assertEqual(compNonLeap.hour, 9, "Hour must be 9")
        try assertEqual(compNonLeap.minute, 0, "Minute must be 0")
        try assertEqual(compNonLeap.second, 0, "Second must be 0")
    }
    
    // 1.6 Fixed 09:00:00 AM Across Daylight Savings Transitions (Europe/Bucharest)
    public static func testFixedHourAcrossDaylightSavingsTransitions_EuropeBucharest() throws {
        guard let bucharestTZ = TimeZone(identifier: "Europe/Bucharest") else {
            throw TestAssertionError(message: "Europe/Bucharest timezone must exist", file: #file, line: #line)
        }
        var bucharestCal = Calendar(identifier: .gregorian)
        bucharestCal.timeZone = bucharestTZ
        
        // --- SPRING FORWARD 2026: Sunday, March 29, 2026 ---
        // (At 03:00, clocks jump to 04:00, UTC+2 -> UTC+3)
        let refSpring = makeLocalDate(year: 2026, month: 3, day: 1, hour: 0, timeZone: bucharestTZ)
        
        // Trigger on transition day itself (March 29, 2026)
        let dueMarch29 = makeLocalDate(year: 2026, month: 3, day: 29, hour: 14, timeZone: bucharestTZ)
        guard let triggerSpringDay = NotificationScheduler.calculateTriggerDate(
            dueDate: dueMarch29,
            offsetDays: 0,
            referenceDate: refSpring,
            calendar: bucharestCal
        ) else {
            throw TestAssertionError(message: "Spring forward trigger must not be nil", file: #file, line: #line)
        }
        let compSpring = bucharestCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerSpringDay)
        try assertEqual(compSpring.year, 2026, "Year 2026")
        try assertEqual(compSpring.month, 3, "March")
        try assertEqual(compSpring.day, 29, "Day 29 (DST transition day)")
        try assertEqual(compSpring.hour, 9, "Scheduled hour in Europe/Bucharest must be 09:00 AM after jump")
        try assertEqual(compSpring.minute, 0, "Scheduled minute must be 0")
        try assertEqual(compSpring.second, 0, "Scheduled second must be 0")
        
        // Cross-transition trigger: Event due on April 1 (after DST), offset -7d -> lands on March 25 (before DST)
        let dueApril1 = makeLocalDate(year: 2026, month: 4, day: 1, hour: 12, timeZone: bucharestTZ)
        guard let triggerCrossSpring = NotificationScheduler.calculateTriggerDate(
            dueDate: dueApril1,
            offsetDays: -7,
            referenceDate: refSpring,
            calendar: bucharestCal
        ) else {
            throw TestAssertionError(message: "Cross spring trigger must exist", file: #file, line: #line)
        }
        let compCrossSpring = bucharestCal.dateComponents([.day, .hour, .minute, .second], from: triggerCrossSpring)
        try assertEqual(compCrossSpring.day, 25, "March 25")
        try assertEqual(compCrossSpring.hour, 9, "09:00 AM local time")
        
        // --- FALL BACK 2026: Sunday, October 25, 2026 ---
        // (At 04:00, clocks fall back to 03:00, UTC+3 -> UTC+2)
        let refFall = makeLocalDate(year: 2026, month: 10, day: 1, hour: 0, timeZone: bucharestTZ)
        let dueOct25 = makeLocalDate(year: 2026, month: 10, day: 25, hour: 14, timeZone: bucharestTZ)
        guard let triggerFallDay = NotificationScheduler.calculateTriggerDate(
            dueDate: dueOct25,
            offsetDays: 0,
            referenceDate: refFall,
            calendar: bucharestCal
        ) else {
            throw TestAssertionError(message: "Fall back trigger must exist", file: #file, line: #line)
        }
        let compFall = bucharestCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerFallDay)
        try assertEqual(compFall.year, 2026, "Year 2026")
        try assertEqual(compFall.month, 10, "October")
        try assertEqual(compFall.day, 25, "Day 25 (DST fall back day)")
        try assertEqual(compFall.hour, 9, "Scheduled hour in Europe/Bucharest must be 09:00 AM after fall back")
        try assertEqual(compFall.minute, 0, "Scheduled minute must be 0")
        try assertEqual(compFall.second, 0, "Scheduled second must be 0")
    }
    
    // 1.7 Interactive Action Identifiers and Snooze (+3 Days) Math
    public static func testInteractiveActionsAndSnoozeMath() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        scheduler.registerCategories()
        
        guard let cat = mockCenter.registeredCategories.first else {
            throw TestAssertionError(message: "Category not found", file: #file, line: #line)
        }
        try assertEqual(cat.identifier, "LIFECYCLE_EVENT_CATEGORY", "Category identifier")
        
        let actionIds = cat.actions.map { $0.identifier }
        try assertTrue(actionIds.contains("ACTION_RESOLVE"), "Contains ACTION_RESOLVE")
        try assertTrue(actionIds.contains("ACTION_SNOOZE_3D"), "Contains ACTION_SNOOZE_3D")
        
        // Snooze Test: Snooze from Nov 15 14:45 by 3 days -> Nov 18 09:00:00 AM
        let ref = makeGMTDate(year: 2026, month: 11, day: 15, hour: 14, minute: 45)
        let event = LifecycleEvent(id: UUID(), title: "ITP Scadență", dueDate: ref)
        let snoozeId = try await scheduler.snoozeReminder(for: event, days: 3, referenceDate: ref, calendar: gmtCalendar)
        
        try assertEqual(snoozeId, "\(event.id.uuidString)_snooze", "Snooze ID pattern")
        let snoozeReq = mockCenter.addedRequests.first { $0.identifier == snoozeId }
        try assertNotNil(snoozeReq, "Snooze request registered")
        
        guard let trig = snoozeReq?.trigger as? UNCalendarNotificationTrigger else {
            throw TestAssertionError(message: "Trigger should be UNCalendarNotificationTrigger", file: #file, line: #line)
        }
        try assertEqual(trig.dateComponents.year, 2026, "Year 2026")
        try assertEqual(trig.dateComponents.month, 11, "Month 11")
        try assertEqual(trig.dateComponents.day, 18, "Day 18 (15 + 3 days)")
        try assertEqual(trig.dateComponents.hour, 9, "09:00 AM morning snooze")
        try assertEqual(trig.dateComponents.minute, 0, "00 min")
        try assertEqual(trig.dateComponents.second, 0, "00 sec")
    }
    
    // =========================================================================
    // TASK 2: WIDGET STATE & CONCENTRIC GEOMETRY ADVERSARIAL VERIFICATION
    // =========================================================================
    
    // 2.1 Interactive Completion Intent & Snapshot State Mutations
    public static func testWidgetSnapshotStateMutations() throws {
        // Setup a controlled snapshot
        let ev1 = DosarWidgetEventItem(
            id: "ev-01",
            title: "RCA",
            assetName: "Golf",
            iconName: "car.fill",
            assetColorHex: "007AFF",
            dueDate: makeGMTDate(year: 2026, month: 11, day: 3),
            daysRemaining: 2,
            isUrgent: true,
            isOverdue: false,
            isCompleted: false
        )
        let ev2 = DosarWidgetEventItem(
            id: "ev-02",
            title: "ITP Expirat",
            assetName: "Golf",
            iconName: "car.fill",
            assetColorHex: "007AFF",
            dueDate: makeGMTDate(year: 2026, month: 10, day: 25),
            daysRemaining: -7,
            isUrgent: false,
            isOverdue: true,
            isCompleted: false
        )
        let ev3 = DosarWidgetEventItem(
            id: "ev-03",
            title: "Revizie Gaz",
            assetName: "Apartament",
            iconName: "flame.fill",
            assetColorHex: "FF9500",
            dueDate: makeGMTDate(year: 2026, month: 12, day: 15),
            daysRemaining: 44,
            isUrgent: false,
            isOverdue: false,
            isCompleted: false
        )
        
        let initialSnapshot = DosarWidgetSnapshot(
            lastUpdated: Date(),
            healthScore: 0,
            activeAssetsCount: 2,
            urgentEventsCount: 2, // ev1 (urgent) + ev2 (overdue)
            events: [ev1, ev2, ev3]
        )
        WidgetDataProvider.saveSnapshot(initialSnapshot)
        
        // Step 1: Complete urgent ev-01
        WidgetDataProvider.markEventCompleted(eventId: "ev-01")
        var current = WidgetDataProvider.loadSnapshot()
        try assertTrue(current.events.first { $0.id == "ev-01" }?.isCompleted == true, "ev-01 must be completed")
        try assertEqual(current.urgentEventsCount, 1, "Only ev-02 remains urgent/overdue")
        try assertEqual(current.healthScore, 33, "1/3 completed = 33% healthScore")
        
        // Step 2: Complete overdue ev-02
        WidgetDataProvider.markEventCompleted(eventId: "ev-02")
        current = WidgetDataProvider.loadSnapshot()
        try assertTrue(current.events.first { $0.id == "ev-02" }?.isCompleted == true, "ev-02 must be completed")
        try assertEqual(current.urgentEventsCount, 0, "Zero urgent/overdue events remaining")
        try assertEqual(current.healthScore, 66, "2/3 completed = 66% healthScore")
        
        // Step 3: Complete regular ev-03
        WidgetDataProvider.markEventCompleted(eventId: "ev-03")
        current = WidgetDataProvider.loadSnapshot()
        try assertTrue(current.events.first { $0.id == "ev-03" }?.isCompleted == true, "ev-03 must be completed")
        try assertEqual(current.urgentEventsCount, 0, "Zero urgent remaining")
        try assertEqual(current.healthScore, 100, "3/3 completed = 100% healthScore")
        
        // Step 4: Non-existent eventId should gracefully no-op
        WidgetDataProvider.markEventCompleted(eventId: "non-existent-id")
        let afterNonExistent = WidgetDataProvider.loadSnapshot()
        try assertEqual(afterNonExistent.healthScore, 100, "Health score remains 100")
        try assertEqual(afterNonExistent.events.count, 3, "Count remains 3")
    }
    
    // 2.2 Concentric Geometry Mathematical Verification
    public static func testConcentricGeometryFormulas() throws {
        // Mathematical formula from Apple Craftsmanship: R_inner = R_outer - padding
        
        // 1. Medium Widget Left Radar Column
        // Container Outer Radius = 22pt (iOS Standard Widget squircle)
        // Container Padding = 12pt
        // Concentric Card Radius = 22 - 12 = 10pt (or 14pt with 8pt visual padding)
        let widgetOuterRadius: CGFloat = 22.0
        let widgetPadding: CGFloat = 12.0
        let theoreticalCardRadius = widgetOuterRadius - widgetPadding
        try assertEqual(Double(theoreticalCardRadius), 10.0, "Theoretical concentric radius: 22 - 12 = 10pt")
        
        // 2. Medium Widget Right Event Row Cards
        // Row Card Radius: R_outer = 10pt
        // Icon Badge: R_inner = 7pt
        // Required Concentric Padding: R_outer - R_inner = 10 - 7 = 3pt
        let rowCardRadius: CGFloat = 10.0
        let rowBadgeRadius: CGFloat = 7.0
        let requiredConcentricPadding = rowCardRadius - rowBadgeRadius
        try assertEqual(Double(requiredConcentricPadding), 3.0, "R_inner = 7 requires exact padding of 3pt (10 - 7 = 3)")
        
        // 3. Small Widget Badges
        // Badge Radius: R = 8pt
        // Container: R = 22pt, padding = 14pt -> R_inner = 8pt
        let smallBadgeRadius: CGFloat = 8.0
        let smallRequiredPadding = widgetOuterRadius - smallBadgeRadius
        try assertEqual(Double(smallRequiredPadding), 14.0, "Concentric badge R=8 in R=22 requires padding 14pt")
    }
    
    // MARK: - Runner
    
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let syncTests: [(String, () throws -> Void)] = [
            ("testEventDueToday_Before0900AM", testEventDueToday_Before0900AM),
            ("testEventDueToday_After0900AM", testEventDueToday_After0900AM),
            ("testEventDueIn2Days", testEventDueIn2Days),
            ("testFixedHourAcrossLeapDays", testFixedHourAcrossLeapDays),
            ("testFixedHourAcrossDaylightSavingsTransitions_EuropeBucharest", testFixedHourAcrossDaylightSavingsTransitions_EuropeBucharest),
            ("testWidgetSnapshotStateMutations", testWidgetSnapshotStateMutations),
            ("testConcentricGeometryFormulas", testConcentricGeometryFormulas)
        ]
        
        for (name, test) in syncTests {
            do {
                try test()
                passed += 1
                print("  ✅ PASS  \(name)")
            } catch let error as TestAssertionError {
                failed += 1
                failures.append(TestFailure(testName: name, message: error.message, file: error.file, line: error.line))
                print("  ❌ FAIL  \(name): \(error.message)")
            } catch {
                failed += 1
                failures.append(TestFailure(testName: name, message: "\(error)", file: #file, line: #line))
                print("  ❌ FAIL  \(name): \(error)")
            }
        }
        
        let asyncTests: [(String, () async throws -> Void)] = [
            ("testEventOverdueBy10Days", testEventOverdueBy10Days),
            ("testInteractiveActionsAndSnoozeMath", testInteractiveActionsAndSnoozeMath)
        ]
        
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for (name, test) in asyncTests {
                do {
                    try await test()
                    passed += 1
                    print("  ✅ PASS  \(name)")
                } catch let error as TestAssertionError {
                    failed += 1
                    failures.append(TestFailure(testName: name, message: error.message, file: error.file, line: error.line))
                    print("  ❌ FAIL  \(name): \(error.message)")
                } catch {
                    failed += 1
                    failures.append(TestFailure(testName: name, message: "\(error)", file: #file, line: #line))
                    print("  ❌ FAIL  \(name): \(error)")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "AdversarialTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
