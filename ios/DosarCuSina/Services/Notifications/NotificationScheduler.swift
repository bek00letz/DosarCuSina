import Foundation
import UserNotifications
import SwiftData

// MARK: - Deep Link Notification Extension

extension Notification.Name {
    public static let dosarCuSinaOpenEventDeepLink = Notification.Name("DosarCuSinaOpenEventDeepLink")
}

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

/// Fallback notification center for CLI / headless test execution where no app bundle exists.
public final class StandaloneNotificationCenter: UserNotificationCenterProtocol, @unchecked Sendable {
    private var requests: [UNNotificationRequest] = []
    public init() {}
    public func add(_ request: UNNotificationRequest) async throws { requests.append(request) }
    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
    public func getPendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
}

/// Native notification scheduling and alert lifecycle engine using `UNUserNotificationCenter`.
///
/// Features:
/// - Reminder offsets: -30 days, -7 days, -1 day, and 0 days (due date), automatically pruning past offsets.
/// - Schedules triggers precisely at 09:00 AM local time.
/// - Time-Sensitive delivery (`.timeSensitive`) for -1d and 0d deadline alerts to break through Focus modes.
/// - Registers interactive notification category `"LIFECYCLE_EVENT_CATEGORY"` with:
///   - `"ACTION_RESOLVE"`: "Am rezolvat" (resolves event and automatically spawns next cycle on recurring cadence)
///   - `"ACTION_SNOOZE_3D"`: "Amână 3 zile" (postpones alert by 3 days)
/// - Deep linking via `dosarcusina://event/<uuid>`.
public final class NotificationScheduler: Sendable {
    
    // MARK: - Constants
    
    public static let categoryIdentifier = "LIFECYCLE_EVENT_CATEGORY"
    public static let actionResolveIdentifier = "ACTION_RESOLVE"
    public static let actionSnooze3DIdentifier = "ACTION_SNOOZE_3D"
    public static let deepLinkScheme = "dosarcusina"
    
    /// Default reminder offsets in days relative to due date: -30d, -7d, -1d, and 0d (due date).
    public static let defaultOffsets: [Int] = [-30, -7, -1, 0]
    
    // MARK: - Deep Link State
    
    private static let deepLinkLock = NSLock()
    private static nonisolated(unsafe) var _activeDeepLinkEventId: UUID?
    
    public static var activeDeepLinkEventId: UUID? {
        get {
            deepLinkLock.lock()
            defer { deepLinkLock.unlock() }
            return _activeDeepLinkEventId
        }
        set {
            deepLinkLock.lock()
            defer { deepLinkLock.unlock() }
            _activeDeepLinkEventId = newValue
        }
    }
    
    // MARK: - Properties
    
    public static func safeDefaultCenter() -> any UserNotificationCenterProtocol {
        if Bundle.main.bundleIdentifier != nil {
            return UNUserNotificationCenter.current()
        }
        return StandaloneNotificationCenter()
    }
    
    public static let shared = NotificationScheduler()
    
    private let center: any UserNotificationCenterProtocol
    
    public init(center: (any UserNotificationCenterProtocol)? = nil) {
        self.center = center ?? Self.safeDefaultCenter()
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
            
            // Time-Sensitive interruption level for critical -1d and 0d deadline breaches
            content.interruptionLevel = (normalizedOffset >= -1) ? .timeSensitive : .active
            
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
        content.interruptionLevel = .timeSensitive
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
    
    // MARK: - Action Handling with Recurring Rollover
    
    /// Handles interactive notification banner actions (`"ACTION_RESOLVE"`, `"ACTION_SNOOZE_3D"`, or default tap).
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
            // Cancel all pending notifications for this event
            await cancelReminders(forEventId: eventId)
            
            // Mark completed in database if context is provided
            if let context = modelContext {
                let descriptor = FetchDescriptor<LifecycleEvent>(
                    predicate: #Predicate<LifecycleEvent> { $0.id == eventId }
                )
                if let event = try context.fetch(descriptor).first {
                    event.isCompleted = true
                    event.completedDate = Date()
                    
                    // Automatic Recurring Rollover:
                    // If cadenceDays is set and > 0, spawn the next cycle's LifecycleEvent
                    if let cadence = event.cadenceDays, cadence > 0 {
                        let nextDueDate = Calendar.current.date(byAdding: .day, value: cadence, to: event.dueDate)
                            ?? event.dueDate.addingTimeInterval(Double(cadence) * 86400)
                        
                        let nextEvent = LifecycleEvent(
                            title: event.title,
                            eventDescription: event.eventDescription,
                            dueDate: nextDueDate,
                            cost: event.cost,
                            currency: event.currency,
                            provider: event.provider,
                            policyOrContractNumber: event.policyOrContractNumber,
                            coverageType: event.coverageType,
                            bonusMalusClass: event.bonusMalusClass,
                            mileageAtEvent: nil,
                            serviceLocation: event.serviceLocation,
                            insuredCoverageAmount: event.insuredCoverageAmount,
                            franchiseAmount: event.franchiseAmount,
                            startDate: event.dueDate,
                            isAutoRenew: event.isAutoRenew,
                            cadenceDays: event.cadenceDays,
                            cadenceMetricInterval: event.cadenceMetricInterval,
                            metricTriggerValue: event.metricTriggerValue,
                            reminderOffsetDays: event.reminderOffsetDays
                        )
                        nextEvent.asset = event.asset
                        context.insert(nextEvent)
                        
                        // Schedule reminders for the newly spawned recurring cycle
                        _ = try? await scheduleReminders(for: nextEvent)
                    }
                    
                    try context.save()
                    WidgetDataSyncService.shared.sync(context: context)
                }
            }
            
        case Self.actionSnooze3DIdentifier:
            if let context = modelContext {
                let descriptor = FetchDescriptor<LifecycleEvent>(
                    predicate: #Predicate<LifecycleEvent> { $0.id == eventId }
                )
                if let event = try context.fetch(descriptor).first {
                    try await snoozeReminder(for: event, days: 3)
                    WidgetDataSyncService.shared.sync(context: context)
                }
            }
            
        case UNNotificationDefaultActionIdentifier:
            // Tapping notification directly: activate deep-link navigation
            Self.activeDeepLinkEventId = eventId
            let deepLinkURL = URL(string: "\(Self.deepLinkScheme)://event/\(eventId.uuidString)")
            NotificationCenter.default.post(
                name: .dosarCuSinaOpenEventDeepLink,
                object: nil,
                userInfo: [
                    "eventId": eventId,
                    "eventIdString": eventId.uuidString,
                    "url": deepLinkURL as Any
                ]
            )
            
        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate Implementation

/// Native UNUserNotificationCenter delegate providing foreground presentation,
/// interactive action dispatching with recurring rollover, and deep-link routing.
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    
    public static let shared = NotificationDelegate()
    
    private let containerLock = NSLock()
    private nonisolated(unsafe) var _modelContainer: ModelContainer?
    
    public var modelContainer: ModelContainer? {
        get {
            containerLock.lock()
            defer { containerLock.unlock() }
            return _modelContainer
        }
        set {
            containerLock.lock()
            defer { containerLock.unlock() }
            _modelContainer = newValue
        }
    }
    
    public override init() {
        super.init()
    }
    
    /// Displays notification banners, sounds, and badges even while the app is active in foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
    
    /// Handles user taps on notifications and interactive actions ("Am rezolvat", "Amână 3 zile").
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        Task { @MainActor in
            let context: ModelContext?
            if let container = self.modelContainer {
                context = container.mainContext
            } else {
                context = nil
            }
            
            try? await NotificationScheduler.shared.handleActionResponse(
                actionIdentifier: actionIdentifier,
                userInfo: userInfo,
                modelContext: context
            )
            
            completionHandler()
        }
    }
}
