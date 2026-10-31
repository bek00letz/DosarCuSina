import Foundation
import SwiftData

@Model
public final class LifecycleEvent {
    public var id: UUID
    public var title: String
    public var eventDescription: String?
    public var dueDate: Date
    public var completedDate: Date?
    public var isCompleted: Bool
    
    // Financial tracking
    public var cost: Double?
    public var currency: String
    
    // Cadence & Recurrence
    public var cadenceDays: Int?
    public var cadenceMetricInterval: Double?
    public var metricTriggerValue: Double?
    public var reminderOffsetDays: [Int]
    
    public var createdAt: Date
    
    public var asset: Asset?
    
    @Relationship(deleteRule: .cascade, inverse: \DocumentAttachment.event)
    public var attachments: [DocumentAttachment] = []
    
    public init(
        id: UUID = UUID(),
        title: String,
        eventDescription: String? = nil,
        dueDate: Date,
        completedDate: Date? = nil,
        isCompleted: Bool = false,
        cost: Double? = nil,
        currency: String = "RON",
        cadenceDays: Int? = nil,
        cadenceMetricInterval: Double? = nil,
        metricTriggerValue: Double? = nil,
        reminderOffsetDays: [Int] = [30, 7, 1],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.eventDescription = eventDescription
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.isCompleted = isCompleted
        self.cost = cost
        self.currency = currency
        self.cadenceDays = cadenceDays
        self.cadenceMetricInterval = cadenceMetricInterval
        self.metricTriggerValue = metricTriggerValue
        self.reminderOffsetDays = reminderOffsetDays
        self.createdAt = createdAt
    }
    
    // MARK: - Computed Properties
    
    public var daysRemaining: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDue = calendar.startOfDay(for: dueDate)
        let components = calendar.dateComponents([.day], from: startOfToday, to: startOfDue)
        return components.day ?? 0
    }
    
    public var isOverdue: Bool {
        !isCompleted && daysRemaining < 0
    }
    
    public var isUrgent: Bool {
        !isCompleted && daysRemaining >= 0 && daysRemaining <= 7
    }
    
    public var statusBadgeText: String {
        if isCompleted {
            return "Rezolvat"
        } else if daysRemaining < 0 {
            return "Expirat de \(abs(daysRemaining))z"
        } else if daysRemaining == 0 {
            return "Azi"
        } else if daysRemaining == 1 {
            return "Mâine"
        } else {
            return "\(daysRemaining) zile rămase"
        }
    }
}
