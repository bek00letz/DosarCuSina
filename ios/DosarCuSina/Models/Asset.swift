import Foundation
import SwiftData
import SwiftUI

@Model
public final class Asset {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var categoryRaw: String
    public var iconName: String
    public var accentColorHex: String
    
    // Telemetry (for vehicles, bikes, boats, equipment)
    public var currentMetricValue: Double?
    public var metricUnit: String?
    
    public var createdAt: Date
    public var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \LifecycleEvent.asset)
    public var events: [LifecycleEvent] = []
    
    @Relationship(deleteRule: .cascade, inverse: \DocumentAttachment.asset)
    public var attachments: [DocumentAttachment] = []
    
    @Relationship(deleteRule: .cascade)
    public var dynamicFields: [DynamicField] = []
    
    public var category: AssetCategory {
        get { AssetCategory(rawValue: categoryRaw) ?? .custom }
        set { categoryRaw = newValue.rawValue }
    }
    
    public var accentColor: Color {
        Color(hex: accentColorHex) ?? category.defaultColor
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        category: AssetCategory = .home,
        iconName: String? = nil,
        accentColorHex: String? = nil,
        currentMetricValue: Double? = nil,
        metricUnit: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.categoryRaw = category.rawValue
        self.iconName = iconName ?? category.systemIcon
        self.accentColorHex = accentColorHex ?? "007AFF"
        self.currentMetricValue = currentMetricValue
        self.metricUnit = metricUnit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Helper Metrics
    
    public var pendingEventsCount: Int {
        events.filter { !$0.isCompleted }.count
    }
    
    public var urgentEventsCount: Int {
        events.filter { $0.isUrgent || $0.isOverdue }.count
    }
    
    public var nextUpcomingEvent: LifecycleEvent? {
        events
            .filter { !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }
    
    public var totalCostThisYear: Double {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        return events
            .filter {
                guard let cost = $0.cost, cost > 0 else { return false }
                let eventYear = calendar.component(.year, from: $0.dueDate)
                return eventYear == currentYear
            }
            .compactMap { $0.cost }
            .reduce(0, +)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}
