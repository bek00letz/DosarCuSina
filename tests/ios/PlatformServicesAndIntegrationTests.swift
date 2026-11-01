import Foundation
import UserNotifications
import SwiftData
import EventKit

// MARK: - Mock Event Store for Calendar & Reminders

public final class MockEventStore: EventStoreProtocol, @unchecked Sendable {
    public var events: [String: EKEvent] = [:]
    public var reminders: [String: EKReminder] = [:]
    
    public var savedEvents: [EKEvent] = []
    public var removedEvents: [EKEvent] = []
    public var savedReminders: [EKReminder] = []
    public var removedReminders: [EKReminder] = []
    
    public var defaultCalendarForNewEvents: EKCalendar?
    public var defaultCalendarForNewRemindersVal: EKCalendar?
    
    public var calendarAccessGranted = true
    public var remindersAccessGranted = true
    
    private let innerStore = EKEventStore()
    
    public init() {}
    
    public func event(withIdentifier identifier: String) -> EKEvent? {
        return events[identifier] ?? savedEvents.first
    }
    
    public func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
        return reminders[identifier]
    }
    
    public func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        savedEvents.append(event)
        let identifier = event.eventIdentifier ?? "mock_event"
        events[identifier] = event
    }
    
    public func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        removedEvents.append(event)
        events.removeAll()
    }
    
    public func save(_ reminder: EKReminder, commit: Bool) throws {
        savedReminders.append(reminder)
        let identifier = reminder.calendarItemIdentifier
        reminders[identifier] = reminder
    }
    
    public func remove(_ reminder: EKReminder, commit: Bool) throws {
        removedReminders.append(reminder)
        reminders.removeValue(forKey: reminder.calendarItemIdentifier)
    }
    
    public func defaultCalendarForNewReminders() -> EKCalendar? {
        return defaultCalendarForNewRemindersVal
    }
    
    public func createEvent() -> EKEvent {
        return EKEvent(eventStore: innerStore)
    }
    
    public func createReminder() -> EKReminder {
        return EKReminder(eventStore: innerStore)
    }
    
    public func requestCalendarAccess() async throws -> Bool {
        return calendarAccessGranted
    }
    
    public func requestRemindersAccess() async throws -> Bool {
        return remindersAccessGranted
    }
}

// MARK: - Test Suite

public final class PlatformServicesAndIntegrationTests: Sendable {
    
    private static let gmtCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()
    
    private static func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.minute = 0
        comp.second = 0
        comp.timeZone = TimeZone(secondsFromGMT: 0)
        return gmtCalendar.date(from: comp)!
    }
    
    // MARK: - 1. Time-Sensitive Delivery Levels
    
    public static func testTimeSensitiveDeliveryLevels() async throws {
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        
        let dueDate = makeDate(year: 2026, month: 12, day: 1, hour: 12)
        let refDate = makeDate(year: 2026, month: 10, day: 1, hour: 12) // 61 days before
        
        let event = LifecycleEvent(
            title: "Rovinietă 12 Luni",
            dueDate: dueDate,
            reminderOffsetDays: [-30, -7, -1, 0]
        )
        
        _ = try await scheduler.scheduleReminders(for: event, referenceDate: refDate, calendar: gmtCalendar)
        
        try assertEqual(mockCenter.addedRequests.count, 4, "4 notification requests scheduled")
        
        for req in mockCenter.addedRequests {
            let offset = req.content.userInfo["offsetDays"] as? Int ?? -999
            if offset >= -1 { // 0d (today) or -1d (tomorrow)
                try assertEqual(
                    req.content.interruptionLevel,
                    .timeSensitive,
                    "Offset \(offset) must be .timeSensitive to break through Focus"
                )
            } else { // -7d or -30d
                try assertEqual(
                    req.content.interruptionLevel,
                    .active,
                    "Offset \(offset) must be .active"
                )
            }
        }
    }
    
    // MARK: - 2. Recurring Rollover on ACTION_RESOLVE
    
    public static func testActionResolveRecurringRollover() async throws {
        let schema = Schema([
            Asset.self,
            LifecycleEvent.self,
            DocumentAttachment.self,
            DynamicField.self,
            ServiceItem.self,
            MeasurementLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        let asset = Asset(
            name: "Dacia Duster 2021",
            category: .vehicle,
            iconName: "car.fill",
            accentColorHex: "FF9500"
        )
        context.insert(asset)
        
        let eventDueDate = makeDate(year: 2026, month: 6, day: 15)
        let event = LifecycleEvent(
            title: "Revizie Ulei și Filtre",
            dueDate: eventDueDate,
            cost: 650.0,
            currency: "RON",
            provider: "Dacia Service",
            policyOrContractNumber: "SRV-2026-99",
            cadenceDays: 365
        )
        event.asset = asset
        context.insert(event)
        try context.save()
        
        let mockCenter = MockNotificationCenter()
        let scheduler = NotificationScheduler(center: mockCenter)
        _ = try await scheduler.scheduleReminders(for: event)
        
        // Execute ACTION_RESOLVE
        let userInfo: [AnyHashable: Any] = [
            "eventId": event.id.uuidString,
            "assetId": asset.id.uuidString
        ]
        
        try await scheduler.handleActionResponse(
            actionIdentifier: NotificationScheduler.actionResolveIdentifier,
            userInfo: userInfo,
            modelContext: context
        )
        
        // Verify original event is completed
        try assertTrue(event.isCompleted, "Original event must be marked completed")
        try assertNotNil(event.completedDate, "Completed date must be recorded")
        
        // Fetch all events for asset
        let descriptor = FetchDescriptor<LifecycleEvent>(
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        let allEvents = try context.fetch(descriptor)
        try assertEqual(allEvents.count, 2, "A new rollover event must have been automatically spawned")
        
        let nextEvent = allEvents.first { $0.id != event.id }
        try assertNotNil(nextEvent, "Next event must exist")
        try assertFalse(nextEvent!.isCompleted, "Next event must be active/uncompleted")
        try assertEqual(nextEvent!.title, "Revizie Ulei și Filtre", "Next event copies title")
        try assertEqual(nextEvent!.provider, "Dacia Service", "Next event copies provider")
        try assertEqual(nextEvent!.cost, 650.0, "Next event copies cost")
        try assertEqual(nextEvent!.cadenceDays, 365, "Next event preserves cadence")
        try assertEqual(nextEvent!.asset?.name, "Dacia Duster 2021", "Next event linked to same asset")
        
        // Verify next due date is exactly 365 days later
        let expectedNextDate = Calendar.current.date(byAdding: .day, value: 365, to: eventDueDate)!
        let diff = abs(nextEvent!.dueDate.timeIntervalSince(expectedNextDate))
        try assertTrue(diff < 60, "Next due date must be due date + cadenceDays (365 days)")
    }
    
    // MARK: - 3. Non-Recurring Event on ACTION_RESOLVE Does Not Rollover
    
    public static func testActionResolveOneOffEventNoRollover() async throws {
        let schema = Schema([
            Asset.self,
            LifecycleEvent.self,
            DocumentAttachment.self,
            DynamicField.self,
            ServiceItem.self,
            MeasurementLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        let event = LifecycleEvent(
            title: "Achiziție Manuală Birou",
            dueDate: makeDate(year: 2026, month: 7, day: 1),
            cost: 1200.0,
            cadenceDays: nil // One-off
        )
        context.insert(event)
        try context.save()
        
        let scheduler = NotificationScheduler.shared
        try await scheduler.handleActionResponse(
            actionIdentifier: NotificationScheduler.actionResolveIdentifier,
            userInfo: ["eventId": event.id.uuidString],
            modelContext: context
        )
        
        try assertTrue(event.isCompleted, "Event marked completed")
        let descriptor = FetchDescriptor<LifecycleEvent>()
        let total = try context.fetch(descriptor).count
        try assertEqual(total, 1, "No rollover event should be created when cadenceDays is nil")
    }
    
    // MARK: - 4. Deep-Link Navigation Identifier on Notification Tap
    
    public static func testDefaultActionDeepLinkNotification() async throws {
        let testEventId = UUID()
        let userInfo: [AnyHashable: Any] = ["eventId": testEventId.uuidString]
        
        var receivedNotification = false
        var receivedIdString = ""
        
        let observer = NotificationCenter.default.addObserver(
            forName: .dosarCuSinaOpenEventDeepLink,
            object: nil,
            queue: nil
        ) { notif in
            receivedNotification = true
            receivedIdString = notif.userInfo?["eventIdString"] as? String ?? ""
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        
        try await NotificationScheduler.shared.handleActionResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: userInfo
        )
        
        try assertTrue(receivedNotification, "Notification .dosarCuSinaOpenEventDeepLink must be posted")
        try assertEqual(receivedIdString, testEventId.uuidString, "EventId match in deep link payload")
        try assertEqual(NotificationScheduler.activeDeepLinkEventId, testEventId, "activeDeepLinkEventId match")
    }
    
    // MARK: - 5. CalendarSyncService Integration with MockEventStore
    
    public static func testCalendarSyncService_EventAndReminders() async throws {
        let mockStore = MockEventStore()
        let service = CalendarSyncService(store: mockStore)
        
        let dueDate = makeDate(year: 2026, month: 9, day: 20, hour: 12)
        let event = LifecycleEvent(
            title: "Inspecție ISCIR Centrală",
            dueDate: dueDate,
            cost: 350.0,
            currency: "RON",
            provider: "Engie Servicii",
            policyOrContractNumber: "ISCIR-77441"
        )
        
        // 1. Sync to Calendar
        let calId = try await service.syncToCalendar(event: event, in: mockStore)
        try assertFalse(calId.isEmpty, "Calendar identifier returned")
        try assertEqual(event.calendarEventIdentifier, calId, "Stored calendar identifier on event")
        try assertEqual(mockStore.savedEvents.count, 1, "1 event saved to store")
        
        let savedEvent = mockStore.savedEvents.first!
        try assertTrue(savedEvent.title.contains("Inspecție ISCIR Centrală"), "Title contains event name")
        try assertNotNil(savedEvent.notes, "Notes populated")
        try assertTrue(savedEvent.notes!.contains("350.00 RON"), "Notes contains formatted cost")
        try assertTrue(savedEvent.notes!.contains("Engie Servicii"), "Notes contains provider")
        try assertTrue(savedEvent.notes!.contains("dosarcusina://event/"), "Notes contains deep link")
        try assertEqual(savedEvent.alarms?.count, 2, "Must configure dual alarms (-7d, -1d)")
        
        // 2. Sync to Reminders
        let remId = try await service.syncToReminders(event: event, in: mockStore)
        try assertFalse(remId.isEmpty, "Reminder identifier returned")
        try assertEqual(event.reminderItemIdentifier, remId, "Stored reminder identifier on event")
        try assertEqual(mockStore.savedReminders.count, 1, "1 reminder saved to store")
        
        let savedReminder = mockStore.savedReminders.first!
        try assertTrue(savedReminder.title.contains("Inspecție ISCIR Centrală"), "Reminder title match")
        try assertNotNil(savedReminder.dueDateComponents, "Due date components configured")
        try assertEqual(savedReminder.dueDateComponents?.hour, 9, "09:00 AM due time")
        
        // 3. Remove operations
        try await service.removeFromCalendar(identifier: calId, in: mockStore)
        try assertEqual(mockStore.removedEvents.count, 1, "Event removed from store")
        
        try await service.removeFromReminders(identifier: remId, in: mockStore)
        try assertEqual(mockStore.removedReminders.count, 1, "Reminder removed from store")
    }
    
    // MARK: - 6. Romanian Phone Number Formatting & Quick Action URLs
    
    public static func testRomanianPhoneFormattingAndActionURLs() throws {
        // Standard mobile (using official Romanian dummy test range +40 700 000 000)
        let formatted1 = ContactFormatting.formatRomanianPhoneNumber("0700000000")
        try assertEqual(formatted1, "+40 700 000 000", "Standard mobile formatted")
        
        // Already international with +40
        let formatted2 = ContactFormatting.formatRomanianPhoneNumber("+40700001002")
        try assertEqual(formatted2, "+40 700 001 002", "+40 international mobile formatted")
        
        // Double zero prefix 0040
        let formatted3 = ContactFormatting.formatRomanianPhoneNumber("0040700123456")
        try assertEqual(formatted3, "+40 700 123 456", "0040 mobile formatted")
        
        // Dialable phone URL (tel://)
        let telURL = ContactFormatting.phoneURL(for: "0700 000 000")
        try assertNotNil(telURL, "Phone URL generated")
        try assertEqual(telURL?.absoluteString, "tel://+40700000000", "E.164 tel URL")
        
        // WhatsApp URL (https://wa.me/40700000000)
        let waURL = ContactFormatting.whatsAppURL(for: "0700 000 000")
        try assertNotNil(waURL, "WhatsApp URL generated")
        try assertEqual(waURL?.absoluteString, "https://wa.me/40700000000", "wa.me link without plus")
        
        // Email URL
        let mailURL = ContactFormatting.emailURL(for: "  mecanic@service-auto.ro  ")
        try assertNotNil(mailURL, "Email URL generated")
        try assertEqual(mailURL?.absoluteString, "mailto:mecanic@service-auto.ro", "mailto link")
        
        // Invalid email handling
        let invalidMail = ContactFormatting.emailURL(for: "not-an-email")
        try assertNil(invalidMail, "Invalid email returns nil")
    }
    
    // MARK: - 7. WidgetDataSyncService Snapshot Building & Health Scoring
    
    public static func testWidgetDataSyncServiceSnapshotCalculations() throws {
        let service = WidgetDataSyncService.shared
        let refDate = makeDate(year: 2026, month: 11, day: 1, hour: 12)
        
        // Scenario A: Zero events -> baseline 100% health
        let snapEmpty = service.buildSnapshot(from: [], assets: [], referenceDate: refDate)
        try assertEqual(snapEmpty.healthScore, 100, "Empty events baseline is 100 health")
        try assertEqual(snapEmpty.urgentEventsCount, 0, "Zero urgent events")
        try assertEqual(snapEmpty.events.count, 0, "Zero events")
        
        // Scenario B: 1 overdue (-25), 1 urgent (-5), 1 future
        let evOverdue = LifecycleEvent(
            title: "RCA Expirat",
            dueDate: makeDate(year: 2026, month: 10, day: 25) // 7 days overdue
        )
        let evUrgent = LifecycleEvent(
            title: "ITP Scadent",
            dueDate: makeDate(year: 2026, month: 11, day: 3) // 2 days remaining (urgent)
        )
        let evFuture = LifecycleEvent(
            title: "Impozit",
            dueDate: makeDate(year: 2026, month: 12, day: 31) // 60 days
        )
        
        let snapMixed = service.buildSnapshot(from: [evOverdue, evUrgent, evFuture], assets: [], referenceDate: refDate)
        // Expected score: 100 - 25 (overdue) - 5 (urgent) = 70
        try assertEqual(snapMixed.healthScore, 70, "Health score with 1 overdue and 1 urgent is 70")
        try assertEqual(snapMixed.urgentEventsCount, 2, "2 urgent events (1 overdue + 1 urgent)")
        try assertEqual(snapMixed.events.count, 3, "3 widget items mapped")
        
        // First item should be nearest due date (evOverdue)
        try assertEqual(snapMixed.events.first?.title, "RCA Expirat", "Chronologically ordered")
    }
    
    // MARK: - Runner
    
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let syncTests: [(String, () throws -> Void)] = [
            ("testRomanianPhoneFormattingAndActionURLs", testRomanianPhoneFormattingAndActionURLs),
            ("testWidgetDataSyncServiceSnapshotCalculations", testWidgetDataSyncServiceSnapshotCalculations)
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
            ("testTimeSensitiveDeliveryLevels", testTimeSensitiveDeliveryLevels),
            ("testActionResolveRecurringRollover", testActionResolveRecurringRollover),
            ("testActionResolveOneOffEventNoRollover", testActionResolveOneOffEventNoRollover),
            ("testDefaultActionDeepLinkNotification", testDefaultActionDeepLinkNotification),
            ("testCalendarSyncService_EventAndReminders", testCalendarSyncService_EventAndReminders)
        ]
        
        var isDone = false
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
            isDone = true
        }
        
        while !isDone {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "PlatformServicesAndIntegrationTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
