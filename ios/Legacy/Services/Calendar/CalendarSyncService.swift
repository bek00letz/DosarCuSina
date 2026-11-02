import Foundation
import EventKit

// MARK: - EventStore Protocol

/// Abstraction protocol for `EKEventStore` to allow testability without
/// requiring interactive system authorization or device calendar modifications.
public protocol EventStoreProtocol: AnyObject, Sendable {
    func event(withIdentifier identifier: String) -> EKEvent?
    func calendarItem(withIdentifier identifier: String) -> EKCalendarItem?
    
    func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws
    func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws
    
    func save(_ reminder: EKReminder, commit: Bool) throws
    func remove(_ reminder: EKReminder, commit: Bool) throws
    
    var defaultCalendarForNewEvents: EKCalendar? { get }
    func defaultCalendarForNewReminders() -> EKCalendar?
    
    func createEvent() -> EKEvent
    func createReminder() -> EKReminder
    
    func requestCalendarAccess() async throws -> Bool
    func requestRemindersAccess() async throws -> Bool
}

// MARK: - EKEventStore Conformance

extension EKEventStore: EventStoreProtocol, @retroactive @unchecked Sendable {
    public func createEvent() -> EKEvent {
        EKEvent(eventStore: self)
    }
    
    public func createReminder() -> EKReminder {
        EKReminder(eventStore: self)
    }
    
    public func requestCalendarAccess() async throws -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return try await requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    public func requestRemindersAccess() async throws -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return try await requestFullAccessToReminders()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
}

// MARK: - CalendarSyncService

/// Native EventKit synchronization bridge for Apple Calendar (`EKEvent`) and Apple Reminders (`EKReminder`).
///
/// Features:
/// - Bidirectional sync of `LifecycleEvent` obligations to the user's Apple Calendar.
/// - Sets precise 09:00 AM local time morning start and 1-hour event duration.
/// - Rich obligation notes containing formatted cost, provider, policy/contract number, and deep-link URL.
/// - Configures dual warning alarms at -7 days (-604,800s) and -1 day (-86,400s).
/// - Syncs to Apple Reminders with alarms and due date components.
/// - Protocol-based architecture (`EventStoreProtocol`) allowing 100% deterministic unit testing.
public final class CalendarSyncService: Sendable {
    
    public static let shared = CalendarSyncService()
    
    public let store: any EventStoreProtocol
    
    public init(store: any EventStoreProtocol = EKEventStore()) {
        self.store = store
    }
    
    // MARK: - Notes Builder
    
    /// Formats structured metadata into the notes field of calendar events and reminders.
    public static func buildNotes(for event: LifecycleEvent) -> String {
        var parts: [String] = []
        parts.append("Dosar cu Șină — Detalii Obligație:")
        
        if let cost = event.cost {
            let formattedCost = String(format: "%.2f", cost)
            parts.append("Cost: \(formattedCost) \(event.currency)")
        }
        
        if let provider = event.provider, !provider.isEmpty {
            parts.append("Furnizor: \(provider)")
        }
        
        if let policy = event.policyOrContractNumber, !policy.isEmpty {
            parts.append("Poliță / Contract: \(policy)")
        }
        
        if let coverage = event.coverageType, !coverage.isEmpty {
            parts.append("Tip acoperire: \(coverage)")
        }
        
        if let desc = event.eventDescription, !desc.isEmpty {
            parts.append("Descriere: \(desc)")
        }
        
        parts.append("Deschide în Dosar cu Șină: dosarcusina://event/\(event.id.uuidString)")
        return parts.joined(separator: "\n")
    }
    
    // MARK: - Calendar Synchronization
    
    /// Syncs or updates a `LifecycleEvent` into Apple Calendar via `EventStoreProtocol`.
    @discardableResult
    public func syncToCalendar(
        event: LifecycleEvent,
        in store: any EventStoreProtocol
    ) async throws -> String {
        let ekEvent: EKEvent
        if let existingId = event.calendarEventIdentifier,
           let existingEvent = store.event(withIdentifier: existingId) {
            ekEvent = existingEvent
        } else {
            ekEvent = store.createEvent()
            if let defaultCal = store.defaultCalendarForNewEvents {
                ekEvent.calendar = defaultCal
            }
        }
        
        // Title formatting: "[Event Title] — [Asset Name]"
        let assetName = event.asset?.name ?? "Dosar cu Șină"
        ekEvent.title = "\(event.title) — \(assetName)"
        
        // 09:00 AM local morning alert
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .timeZone], from: event.dueDate)
        components.hour = 9
        components.minute = 0
        components.second = 0
        let start = calendar.date(from: components) ?? event.dueDate
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        
        ekEvent.startDate = start
        ekEvent.endDate = end
        ekEvent.isAllDay = false
        
        ekEvent.notes = Self.buildNotes(for: event)
        ekEvent.url = URL(string: "dosarcusina://event/\(event.id.uuidString)")
        
        // Dual alarms: -7 days and -1 day
        ekEvent.alarms = [
            EKAlarm(relativeOffset: -7 * 86400),
            EKAlarm(relativeOffset: -1 * 86400)
        ]
        
        try store.save(ekEvent, span: .thisEvent, commit: true)
        
        let identifier = ekEvent.eventIdentifier ?? event.calendarEventIdentifier ?? "event_\(event.id.uuidString)"
        event.calendarEventIdentifier = identifier
        return identifier
    }
    
    /// Overload accepting concrete `EKEventStore` directly.
    @discardableResult
    public func syncToCalendar(
        event: LifecycleEvent,
        in store: EKEventStore
    ) async throws -> String {
        try await syncToCalendar(event: event, in: store as any EventStoreProtocol)
    }
    
    /// Convenience method using the default store instance.
    @discardableResult
    public func syncToCalendar(event: LifecycleEvent) async throws -> String {
        try await syncToCalendar(event: event, in: store)
    }
    
    // MARK: - Reminders Synchronization
    
    /// Syncs or updates a `LifecycleEvent` into Apple Reminders via `EventStoreProtocol`.
    @discardableResult
    public func syncToReminders(
        event: LifecycleEvent,
        in store: any EventStoreProtocol
    ) async throws -> String {
        let reminder: EKReminder
        if let existingId = event.reminderItemIdentifier,
           let existingItem = store.calendarItem(withIdentifier: existingId) as? EKReminder {
            reminder = existingItem
        } else {
            reminder = store.createReminder()
            if let defaultCal = store.defaultCalendarForNewReminders() {
                reminder.calendar = defaultCal
            }
        }
        
        let assetName = event.asset?.name ?? "Dosar cu Șină"
        reminder.title = "\(event.title) — \(assetName)"
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: event.dueDate)
        components.hour = 9
        components.minute = 0
        reminder.dueDateComponents = components
        
        reminder.notes = Self.buildNotes(for: event)
        reminder.url = URL(string: "dosarcusina://event/\(event.id.uuidString)")
        
        reminder.alarms = [
            EKAlarm(relativeOffset: -7 * 86400),
            EKAlarm(relativeOffset: -1 * 86400)
        ]
        
        try store.save(reminder, commit: true)
        
        let identifier = reminder.calendarItemIdentifier
        event.reminderItemIdentifier = identifier
        return identifier
    }
    
    /// Overload accepting concrete `EKEventStore` directly.
    @discardableResult
    public func syncToReminders(
        event: LifecycleEvent,
        in store: EKEventStore
    ) async throws -> String {
        try await syncToReminders(event: event, in: store as any EventStoreProtocol)
    }
    
    /// Convenience method using the default store instance.
    @discardableResult
    public func syncToReminders(event: LifecycleEvent) async throws -> String {
        try await syncToReminders(event: event, in: store)
    }
    
    // MARK: - Removal
    
    /// Removes an event from Calendar using its identifier.
    public func removeFromCalendar(
        identifier: String,
        in store: any EventStoreProtocol
    ) async throws {
        guard !identifier.isEmpty else { return }
        if let ekEvent = store.event(withIdentifier: identifier) {
            try store.remove(ekEvent, span: .thisEvent, commit: true)
        }
    }
    
    public func removeFromCalendar(
        identifier: String,
        in store: EKEventStore
    ) async throws {
        try await removeFromCalendar(identifier: identifier, in: store as any EventStoreProtocol)
    }
    
    public func removeFromCalendar(identifier: String) async throws {
        try await removeFromCalendar(identifier: identifier, in: store)
    }
    
    /// Removes a reminder using its identifier.
    public func removeFromReminders(
        identifier: String,
        in store: any EventStoreProtocol
    ) async throws {
        guard !identifier.isEmpty else { return }
        if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            try store.remove(reminder, commit: true)
        }
    }
    
    public func removeFromReminders(
        identifier: String,
        in store: EKEventStore
    ) async throws {
        try await removeFromReminders(identifier: identifier, in: store as any EventStoreProtocol)
    }
    
    public func removeFromReminders(identifier: String) async throws {
        try await removeFromReminders(identifier: identifier, in: store)
    }
    
    // MARK: - Authorization Helpers
    
    public var hasCalendarAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }
    
    public var hasRemindersAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }
    
    public func requestCalendarAccess() async -> Bool {
        do {
            return try await store.requestCalendarAccess()
        } catch {
            return false
        }
    }
    
    public func requestRemindersAccess() async -> Bool {
        do {
            return try await store.requestRemindersAccess()
        } catch {
            return false
        }
    }
}
