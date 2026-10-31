import Foundation
import UserNotifications
import SwiftData

/// Abstraction protocol for UNUserNotificationCenter to allow mock testing.
public protocol UserNotificationCenterProtocol: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func getPendingNotificationRequests() async -> [UNNotificationRequest]
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

// Default conformance for system UNUserNotificationCenter
extension UNUserNotificationCenter: UserNotificationCenterProtocol {
    public func getPendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            self.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}

/// Native notification scheduling and alert lifecycle engine using `UNUserNotificationCenter`.
///
/// Features:
/// - Reminder offsets: -30 days, -7 days, -1 day, and 0 days (due date), automatically pruning past offsets.
/// - Schedules triggers precisely at 09:00 AM local time.
/// - Registers interactive notification category `"LIFECYCLE_EVENT_CATEGORY"` with:
///   - `"ACTION_RESOLVE"`: "Am rezolvat" (resolves event)
///   - `"ACTION_SNOOZE_3D"`: "Amână 3 zile" (postpones alert by 3 days)
/// - Methods to schedule, cancel, reschedule, and snooze reminders for `LifecycleEvent`.
public final class NotificationScheduler: Sendable {
    
    // MARK: - Constants
    
    public static let categoryIdentifier = "LIFECYCLE_EVENT_CATEGORY"
    public static let actionResolveIdentifier = "ACTION_RESOLVE"
    public static let actionSnooze3DIdentifier = "ACTION_SNOOZE_3D"
    
    /// Default reminder offsets in days relative to due date: -30d, -7d, -1d, and 0d (due date).
    public static let defaultOffsets: [Int] = [-30, -7, -1, 0]
    
    // MARK: - Properties
    
    public static let shared = NotificationScheduler()
    
    private let center: any UserNotificationCenterProtocol
    
    public init(center: any UserNotificationCenterProtocol = UNUserNotificationCenter.current()) {
        self.center = center
    }
    
    // MARK: - Permission & Category Registration
    
    /// Requests notification permissions for alerts, badges, and sounds.
    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        return try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
    
    /// Registers the interactive notification category and action buttons.
    public func registerCategories() {
        let resolveAction = UNNotificationAction(
            identifier: Self.actionResolveIdentifier,
            title: "Am rezolvat",
            options: [.authenticationRequired]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: Self.actionSnooze3DIdentifier,
            title: "Amână 3 zile",
            options: []
        )
        
        let lifecycleCategory = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [resolveAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([lifecycleCategory])
    }
    
    // MARK: - Identifier Generation
    
    /// Builds a deterministic notification request identifier.
    public static func notificationIdentifier(eventId: UUID, offset: Int) -> String {
        return "\(eventId.uuidString)_offset_\(offset)"
    }
    
    /// Builds a notification request identifier for snoozed reminders.
    public static func snoozeIdentifier(eventId: UUID) -> String {
        return "\(eventId.uuidString)_snooze"
    }
    
    // MARK: - Trigger Date Calculation
    
    /// Calculates the precise 09:00 AM local time trigger date for a given offset.
    ///
    /// Prunes offsets that have already elapsed relative to `referenceDate`.
    ///
    /// - Parameters:
    ///   - dueDate: The event due date.
    ///   - offsetDays: The reminder offset in days (e.g. -30, -7, -1, 0, or positive 30, 7, 1).
    ///   - referenceDate: Reference time used to prune past triggers (defaults to `Date()`).
    ///   - calendar: Calendar used for date calculations.
    /// - Returns: A valid future `Date` set to 09:00:00 local time, or `nil` if in the past.
    public static func calculateTriggerDate(
        dueDate: Date,
        offsetDays: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        // Normalize offset: if positive 30, it represents 30 days before dueDate (-30)
        let daysToAdd = offsetDays > 0 ? -offsetDays : offsetDays
        
        guard let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: dueDate) else {
            return nil
        }
        
        var components = calendar.dateComponents(
            [.year, .month, .day, .timeZone],
            from: targetDate
        )
        components.hour = 9
        components.minute = 0
        components.second = 0
        
        guard let triggerDate = calendar.date(from: components) else {
            return nil
        }
        
        // Strict pruning of past triggers
        guard triggerDate > referenceDate else {
            return nil
        }
        
        return triggerDate
    }
    
    // MARK: - Reminder Scheduling
    
    /// Schedules all eligible reminder notifications for a `LifecycleEvent`.
    ///
    /// - Parameters:
    ///   - event: The lifecycle event to schedule.
    ///   - referenceDate: Reference date for pruning past triggers (defaults to `Date()`).
    ///   - calendar: Calendar instance.
    /// - Returns: The list of scheduled notification request identifiers.
    @discardableResult
    public func scheduleReminders(
        for event: LifecycleEvent,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [String] {
        // If event is already completed, ensure no pending reminders remain
        if event.isCompleted {
            await cancelReminders(forEventId: event.id)
            return []
        }
        
        // Cancel existing pending notifications for this event before rescheduling
        await cancelReminders(forEventId: event.id)
        
        // Collect offsets: use event.reminderOffsetDays plus due date (0) if not present,
        // or fallback to defaultOffsets if empty
        let rawOffsets: [Int]
        if event.reminderOffsetDays.isEmpty {
            rawOffsets = Self.defaultOffsets
        } else {
            var set = Set(event.reminderOffsetDays)
            set.insert(0) // Ensure due date alert is scheduled
            rawOffsets = Array(set)
        }
        
        var scheduledIdentifiers: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "ro_RO")
        let formattedDueDate = dateFormatter.string(from: event.dueDate)
        
        for offset in rawOffsets {
            guard let triggerDate = Self.calculateTriggerDate(
                dueDate: event.dueDate,
                offsetDays: offset,
                referenceDate: referenceDate,
                calendar: calendar
            ) else {
                // Offset has already passed: prune
                continue
            }
            
            let normalizedOffset = offset > 0 ? -offset : offset
            let identifier = Self.notificationIdentifier(eventId: event.id, offset: normalizedOffset)
            
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = Self.categoryIdentifier
            content.sound = .default
            
            // Localized Romanian notification copy
            if normalizedOffset == 0 {
                content.title = "Scadent astăzi: \(event.title)"
                if let asset = event.asset {
                    content.body = "Pentru \(asset.name). Marchează ca rezolvat sau amână din notificare."
                } else {
                    content.body = "Termenul limită este astăzi. Verifică detaliile în Dosar cu Șină."
                }
            } else if normalizedOffset == -1 {
                content.title = "Scadent mâine: \(event.title)"
                if let asset = event.asset {
                    content.body = "Pentru \(asset.name). Termen: \(formattedDueDate)."
                } else {
                    content.body = "Termenul limită este mâine. Verifică detaliile în Dosar cu Șină."
                }
            } else {
                let days = abs(normalizedOffset)
                content.title = "Expiră în \(days) zile: \(event.title)"
                if let asset = event.asset {
                    content.body = "Pentru \(asset.name). Termen: \(formattedDueDate)."
                } else {
                    content.body = "Ai o scadență programată pe \(formattedDueDate)."
                }
            }
            
            content.userInfo = [
                "eventId": event.id.uuidString,
                "assetId": event.asset?.id.uuidString ?? "",
                "eventTitle": event.title,
                "offsetDays": normalizedOffset
            ]
            
            let triggerComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: triggerDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            try await center.add(request)
            scheduledIdentifiers.append(identifier)
        }
        
        return scheduledIdentifiers
    }
    
    /// Cancels all pending notifications associated with an event.
    public func cancelReminders(for event: LifecycleEvent) async {
        await cancelReminders(forEventId: event.id)
    }
    
    /// Cancels all pending notifications matching an event's UUID.
    public func cancelReminders(forEventId eventId: UUID) async {
        let prefix = eventId.uuidString
        let pending = await center.getPendingNotificationRequests()
        let matchingIdentifiers = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix(prefix) }
        
        if !matchingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: matchingIdentifiers)
        }
    }
    
    /// Reschedules reminders for an event (cancels existing and schedules fresh).
    @discardableResult
    public func rescheduleReminders(
        for event: LifecycleEvent,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [String] {
        return try await scheduleReminders(for: event, referenceDate: referenceDate, calendar: calendar)
    }
    
    /// Snoozes reminder alerts for a specific event by a given number of days (default 3 days).
    @discardableResult
    public func snoozeReminder(
        for event: LifecycleEvent,
        days: Int = 3,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> String {
        let identifier = Self.snoozeIdentifier(eventId: event.id)
        
        // Remove any previous snooze notification
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        guard let targetDay = calendar.date(byAdding: .day, value: days, to: referenceDate) else {
            throw NSError(domain: "DosarCuSina.NotificationScheduler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not calculate snooze date"])
        }
        
        var components = calendar.dateComponents([.year, .month, .day, .timeZone], from: targetDay)
        components.hour = 9
        components.minute = 0
        components.second = 0
        
        guard let triggerDate = calendar.date(from: components) else {
            throw NSError(domain: "DosarCuSina.NotificationScheduler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid snooze trigger date"])
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Reminder amânat: \(event.title)"
        if let asset = event.asset {
            content.body = "Pentru \(asset.name). Notificarea a fost amânată cu \(days) zile."
        } else {
            content.body = "Notificarea a fost amânată cu \(days) zile."
        }
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        content.userInfo = [
            "eventId": event.id.uuidString,
            "assetId": event.asset?.id.uuidString ?? "",
            "eventTitle": event.title,
            "isSnooze": true
        ]
        
        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try await center.add(request)
        return identifier
    }
    
    // MARK: - Action Handling
    
    /// Handles interactive notification banner actions (`"ACTION_RESOLVE"`, `"ACTION_SNOOZE_3D"`).
    public func handleActionResponse(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any],
        modelContext: ModelContext? = nil
    ) async throws {
        guard let eventIdString = userInfo["eventId"] as? String,
              let eventId = UUID(uuidString: eventIdString) else {
            return
        }
        
        switch actionIdentifier {
        case Self.actionResolveIdentifier:
            // Cancel all notifications for this event
            await cancelReminders(forEventId: eventId)
            
            // Mark completed in database if context is provided
            if let context = modelContext {
                let descriptor = FetchDescriptor<LifecycleEvent>(
                    predicate: #Predicate<LifecycleEvent> { $0.id == eventId }
                )
                if let event = try context.fetch(descriptor).first {
                    event.isCompleted = true
                    event.completedDate = Date()
                    try context.save()
                }
            }
            
        case Self.actionSnooze3DIdentifier:
            if let context = modelContext {
                let descriptor = FetchDescriptor<LifecycleEvent>(
                    predicate: #Predicate<LifecycleEvent> { $0.id == eventId }
                )
                if let event = try context.fetch(descriptor).first {
                    try await snoozeReminder(for: event, days: 3)
                }
            }
            
        default:
            break
        }
    }
}
