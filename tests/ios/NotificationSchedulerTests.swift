import Foundation
import UserNotifications

// MARK: - Mock Notification Center

public final class MockNotificationCenter: UserNotificationCenterProtocol, @unchecked Sendable {
    public var addedRequests: [UNNotificationRequest] = []
    public var removedIdentifierBatches: [[String]] = []
    public var registeredCategories: Set<UNNotificationCategory> = []
    public var authorizationRequested = false
    public var authorizationResult = true
    
    public init() {}
    
    public func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }
    
    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifierBatches.append(identifiers)
        addedRequests.removeAll { identifiers.contains($0.identifier) }
    }
    
    public func getPendingNotificationRequests() async -> [UNNotificationRequest] {
        return addedRequests
    }
    
    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategories = categories
    }
    
    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequested = true
        return authorizationResult
    }
}

// MARK: - Test Suite

/// Comprehensive unit test suite for `NotificationScheduler`.
///
/// Verifies:
/// 1. Offset calculation rules (-30d, -7d, -1d, 0d) and normalization of positive offsets.
/// 2. Strict past-offset pruning (offsets in the past relative to referenceDate return nil).
/// 3. Fixed 09:00 AM local morning trigger time components (hour 9, minute 0, second 0).
/// 4. Interactive category registration (`LIFECYCLE_EVENT_CATEGORY`) with `ACTION_RESOLVE` and `ACTION_SNOOZE_3D`.
/// 5. Deterministic notification identifier generation: `"{eventId}_offset_{offset}"` and `"{eventId}_snooze"`.
/// 6. End-to-end reminder scheduling with mock notification center.
/// 7. Automatic cancellation when events are completed.
/// 8. Snooze reminder calculation (+3 days morning alert).
public final class NotificationSchedulerTests: Sendable {
    
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()
    
    private static func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }
    
    // MARK: - 1. Offset Calculation Rules (-30d, -7d, -1d, 0d)
    
    public static func testOffsetCalculationRules() throws {
        // Due Date: December 1, 2026 12:00:00 UTC
        let dueDate = makeDate(year: 2026, month: 12, day: 1, hour: 12)
        // Reference Date: October 15, 2026 (47 days before due date)
        let referenceDate = makeDate(year: 2026, month: 10, day: 15, hour: 12)
        
        // Offset -30 days -> November 1, 2026 09:00:00
        guard let trigger30 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: -30,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Trigger for -30d should not be nil", file: #file, line: #line)
        }
        let comp30 = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: trigger30)
        try assertEqual(comp30.year, 2026, "Year should be 2026")
        try assertEqual(comp30.month, 11, "Month should be November")
        try assertEqual(comp30.day, 1, "Nov 1 is 30 days before Dec 1")
        try assertEqual(comp30.hour, 9, "Trigger hour must be 09:00 AM")
        try assertEqual(comp30.minute, 0, "Trigger minute must be 00")
        try assertEqual(comp30.second, 0, "Trigger second must be 00")
        
        // Offset -7 days -> November 24, 2026 09:00:00
        guard let trigger7 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: -7,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Trigger for -7d should not be nil", file: #file, line: #line)
        }
        let comp7 = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: trigger7)
        try assertEqual(comp7.month, 11, "Month should be November")
        try assertEqual(comp7.day, 24, "Nov 24 is 7 days before Dec 1")
        try assertEqual(comp7.hour, 9, "09:00 AM trigger hour")
        
        // Offset -1 day -> November 30, 2026 09:00:00
        guard let trigger1 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: -1,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Trigger for -1d should not be nil", file: #file, line: #line)
        }
        let comp1 = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: trigger1)
        try assertEqual(comp1.month, 11, "Month should be November")
        try assertEqual(comp1.day, 30, "Nov 30 is 1 day before Dec 1")
        try assertEqual(comp1.hour, 9, "09:00 AM trigger hour")
        
        // Offset 0 days -> December 1, 2026 09:00:00 (due date morning alert)
        guard let trigger0 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: 0,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Trigger for 0d should not be nil", file: #file, line: #line)
        }
        let comp0 = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: trigger0)
        try assertEqual(comp0.month, 12, "Month should be December")
        try assertEqual(comp0.day, 1, "Dec 1 is due date")
        try assertEqual(comp0.hour, 9, "09:00 AM trigger hour")
        
        // Positive offset normalization test: positive 30 means 30 days before due date (-30)
        guard let triggerPos30 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: 30,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Positive 30 should normalize to -30d", file: #file, line: #line)
        }
        try assertEqual(triggerPos30, trigger30, "Positive offset 30 must produce identical date to -30")
    }
    
    // MARK: - 2. Past-Offset Pruning
    
    public static func testPastOffsetPruning() throws {
        // Due Date: December 1, 2026 12:00:00 UTC
        let dueDate = makeDate(year: 2026, month: 12, day: 1, hour: 12)
        // Reference Date: November 15, 2026 (16 days before due date)
        let referenceDate = makeDate(year: 2026, month: 11, day: 15, hour: 12)
        
        // Offset -30d lands on Nov 1, which is BEFORE Nov 15 referenceDate -> MUST be pruned (return nil)
        let trigger30 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: -30,
            referenceDate: referenceDate,
            calendar: calendar
        )
        try assertNil(trigger30, "Past trigger -30d (Nov 1 < Nov 15) must be pruned and return nil")
        
        // Offset -7d lands on Nov 24, which is AFTER Nov 15 referenceDate -> MUST be kept
        let trigger7 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: -7,
            referenceDate: referenceDate,
            calendar: calendar
        )
        try assertNotNil(trigger7, "Future trigger -7d (Nov 24 > Nov 15) must be scheduled")
        
        // Offset -1d and 0d must also be kept
        let trigger1 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: -1,
            referenceDate: referenceDate,
            calendar: calendar
        )
        try assertNotNil(trigger1, "Future trigger -1d must be scheduled")
        
        let trigger0 = NotificationScheduler.calculateTriggerDate(
            dueDate: dueDate,
            offsetDays: 0,
            referenceDate: referenceDate,
            calendar: calendar
        )
        try assertNotNil(trigger0, "Future trigger 0d must be scheduled")
        
        // Overdue event: referenceDate is Dec 5, 2026 (after due date)
        let overdueRef = makeDate(year: 2026, month: 12, day: 5, hour: 12)
        for offset in [-30, -7, -1, 0] {
            let overdueTrigger = NotificationScheduler.calculateTriggerDate(
                dueDate: dueDate,
                offsetDays: offset,
                referenceDate: overdueRef,
                calendar: calendar
            )
            try assertNil(overdueTrigger, "All offsets for overdue events must be pruned")
        }
    }
    
    // MARK: - 3. Fixed 09:00 AM Trigger Components
    
    public static func testFixed0900AMMorningTriggerComponents() throws {
        let referenceDate = makeDate(year: 2026, month: 1, day: 1, hour: 0)
        let dueDates = [
            makeDate(year: 2026, month: 2, day: 15, hour: 23),
            makeDate(year: 2026, month: 7, day: 1, hour: 6),
            makeDate(year: 2026, month: 12, day: 31, hour: 18)
        ]
        
        for due in dueDates {
            for offset in [-30, -14, -7, -3, -1, 0] {
                if let trigger = NotificationScheduler.calculateTriggerDate(
                    dueDate: due,
                    offsetDays: offset,
                    referenceDate: referenceDate,
                    calendar: calendar
                ) {
                    let comp = calendar.dateComponents([.hour, .minute, .second], from: trigger)
                    try assertEqual(comp.hour, 9, "Trigger hour must strictly be 9")
                    try assertEqual(comp.minute, 0, "Trigger minute must strictly be 0")
                    try assertEqual(comp.second, 0, "Trigger second must strictly be 0")
                }
            }
        }
    }
    
    // MARK: - 4. Interactive Category Actions Registration
    
    public static func testInteractiveCategoryActionsRegistration() throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        scheduler.registerCategories()
        
        try assertEqual(mockCenter.registeredCategories.count, 1, "Exactly 1 category should be registered")
        guard let category = mockCenter.registeredCategories.first else {
            throw TestAssertionError(message: "Category should exist", file: #file, line: #line)
        }
        
        try assertEqual(category.identifier, NotificationScheduler.categoryIdentifier, "Category identifier must be LIFECYCLE_EVENT_CATEGORY")
        try assertEqual(category.actions.count, 2, "Must register 2 interactive actions")
        
        let actionIds = category.actions.map { $0.identifier }
        try assertTrue(actionIds.contains(NotificationScheduler.actionResolveIdentifier), "Must contain ACTION_RESOLVE")
        try assertTrue(actionIds.contains(NotificationScheduler.actionSnooze3DIdentifier), "Must contain ACTION_SNOOZE_3D")
        
        // Verify action titles & options
        let resolveAction = category.actions.first { $0.identifier == NotificationScheduler.actionResolveIdentifier }
        try assertNotNil(resolveAction, "Resolve action exists")
        try assertEqual(resolveAction?.title, "Am rezolvat", "Resolve action Romanian title")
        try assertTrue(resolveAction?.options.contains(.authenticationRequired) == true, "Resolve requires authentication")
        
        let snoozeAction = category.actions.first { $0.identifier == NotificationScheduler.actionSnooze3DIdentifier }
        try assertNotNil(snoozeAction, "Snooze action exists")
        try assertEqual(snoozeAction?.title, "Amână 3 zile", "Snooze action Romanian title")
    }
    
    // MARK: - 5. Deterministic Identifier Generation
    
    public static func testNotificationIdentifierGeneration() throws {
        let eventId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        
        let id30 = NotificationScheduler.notificationIdentifier(eventId: eventId, offset: -30)
        try assertEqual(id30, "E621E1F8-C36C-495A-93FC-0C247A3E6E5F_offset_-30", "Offset -30 identifier")
        
        let id7 = NotificationScheduler.notificationIdentifier(eventId: eventId, offset: -7)
        try assertEqual(id7, "E621E1F8-C36C-495A-93FC-0C247A3E6E5F_offset_-7", "Offset -7 identifier")
        
        let id0 = NotificationScheduler.notificationIdentifier(eventId: eventId, offset: 0)
        try assertEqual(id0, "E621E1F8-C36C-495A-93FC-0C247A3E6E5F_offset_0", "Offset 0 identifier")
        
        let idSnooze = NotificationScheduler.snoozeIdentifier(eventId: eventId)
        try assertEqual(idSnooze, "E621E1F8-C36C-495A-93FC-0C247A3E6E5F_snooze", "Snooze identifier")
    }
    
    // MARK: - 6. End-to-End Scheduling & Cancellation with Mock
    
    public static func testScheduleAndCancelReminders() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        let eventId = UUID()
        let dueDate = makeDate(year: 2026, month: 12, day: 1, hour: 12)
        let referenceDate = makeDate(year: 2026, month: 10, day: 15, hour: 12) // 47 days before due
        
        let event = LifecycleEvent(
            id: eventId,
            title: "Verificare Tehnică Periodică (ITP)",
            dueDate: dueDate,
            reminderOffsetDays: [-30, -7, -1, 0]
        )
        
        // Schedule reminders
        let scheduledIds = try await scheduler.scheduleReminders(
            for: event,
            referenceDate: referenceDate,
            calendar: calendar
        )
        
        try assertEqual(scheduledIds.count, 4, "Should schedule 4 reminders (-30, -7, -1, 0)")
        try assertEqual(mockCenter.addedRequests.count, 4, "4 notification requests added to center")
        
        // Verify request details
        for req in mockCenter.addedRequests {
            try assertEqual(req.content.categoryIdentifier, NotificationScheduler.categoryIdentifier, "Category identifier match")
            try assertEqual(req.content.userInfo["eventId"] as? String, eventId.uuidString, "EventId in userInfo")
            try assertNotNil(req.trigger, "Trigger must be set")
        }
        
        // Cancel reminders
        await scheduler.cancelReminders(forEventId: eventId)
        try assertTrue(mockCenter.removedIdentifierBatches.count >= 1, "Should invoke removePendingNotificationRequests")
    }
    
    // MARK: - 7. Pruning Partial Offsets During Schedule
    
    public static func testScheduleReminders_PartialPastOffsetsPruned() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        let eventId = UUID()
        let dueDate = makeDate(year: 2026, month: 12, day: 1, hour: 12)
        // Reference date is Nov 15: -30d (Nov 1) is past, -7d (Nov 24), -1d, 0d are future
        let referenceDate = makeDate(year: 2026, month: 11, day: 15, hour: 12)
        
        let event = LifecycleEvent(
            id: eventId,
            title: "Rovinietă Anuală",
            dueDate: dueDate,
            reminderOffsetDays: [-30, -7, -1, 0]
        )
        
        let scheduledIds = try await scheduler.scheduleReminders(
            for: event,
            referenceDate: referenceDate,
            calendar: calendar
        )
        
        try assertEqual(scheduledIds.count, 3, "Only 3 reminders should be scheduled (-30d pruned)")
        try assertFalse(scheduledIds.contains("\(eventId.uuidString)_offset_-30"), "-30d offset must be pruned")
        try assertTrue(scheduledIds.contains("\(eventId.uuidString)_offset_-7"), "-7d offset must be present")
        try assertTrue(scheduledIds.contains("\(eventId.uuidString)_offset_-1"), "-1d offset must be present")
        try assertTrue(scheduledIds.contains("\(eventId.uuidString)_offset_0"), "0d offset must be present")
    }
    
    // MARK: - 8. Completed Event Behavior
    
    public static func testCompletedEventSchedulesNothing() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        let event = LifecycleEvent(
            id: UUID(),
            title: "Asigurare RCA",
            dueDate: makeDate(year: 2026, month: 12, day: 1),
            isCompleted: true // Completed
        )
        
        let scheduled = try await scheduler.scheduleReminders(for: event)
        try assertEqual(scheduled.count, 0, "Completed event must not schedule any notifications")
        try assertEqual(mockCenter.addedRequests.count, 0, "No requests added for completed event")
    }
    
    // MARK: - 9. Snooze Reminders (+3 Days)
    
    public static func testSnoozeReminder() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        let eventId = UUID()
        let referenceDate = makeDate(year: 2026, month: 11, day: 1, hour: 10)
        let event = LifecycleEvent(
            id: eventId,
            title: "Revizie Centrală",
            dueDate: makeDate(year: 2026, month: 11, day: 1)
        )
        
        let snoozeId = try await scheduler.snoozeReminder(
            for: event,
            days: 3,
            referenceDate: referenceDate,
            calendar: calendar
        )
        
        try assertEqual(snoozeId, "\(eventId.uuidString)_snooze", "Snooze identifier pattern")
        try assertEqual(mockCenter.addedRequests.count, 1, "Snooze request added")
        
        let request = mockCenter.addedRequests.first!
        try assertEqual(request.identifier, snoozeId, "Request identifier match")
        try assertEqual(request.content.categoryIdentifier, NotificationScheduler.categoryIdentifier, "Category match")
        try assertEqual(request.content.userInfo["isSnooze"] as? Bool, true, "isSnooze userInfo flag")
    }
    
    // MARK: - Runner
    
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let syncTests: [(String, () throws -> Void)] = [
            ("testOffsetCalculationRules", testOffsetCalculationRules),
            ("testPastOffsetPruning", testPastOffsetPruning),
            ("testFixed0900AMMorningTriggerComponents", testFixed0900AMMorningTriggerComponents),
            ("testInteractiveCategoryActionsRegistration", testInteractiveCategoryActionsRegistration),
            ("testNotificationIdentifierGeneration", testNotificationIdentifierGeneration)
        ]
        
        for (name, test) in syncTests {
            do {
                try test()
                passed += 1
            } catch let error as TestAssertionError {
                failed += 1
                failures.append(TestFailure(testName: name, message: error.message, file: error.file, line: error.line))
            } catch {
                failed += 1
                failures.append(TestFailure(testName: name, message: "\(error)", file: #file, line: #line))
            }
        }
        
        let asyncTests: [(String, () async throws -> Void)] = [
            ("testScheduleAndCancelReminders", testScheduleAndCancelReminders),
            ("testScheduleReminders_PartialPastOffsetsPruned", testScheduleReminders_PartialPastOffsetsPruned),
            ("testCompletedEventSchedulesNothing", testCompletedEventSchedulesNothing),
            ("testSnoozeReminder", testSnoozeReminder)
        ]
        
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for (name, test) in asyncTests {
                do {
                    try await test()
                    passed += 1
                } catch let error as TestAssertionError {
                    failed += 1
                    failures.append(TestFailure(testName: name, message: error.message, file: error.file, line: error.line))
                } catch {
                    failed += 1
                    failures.append(TestFailure(testName: name, message: "\(error)", file: #file, line: #line))
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "NotificationSchedulerTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
