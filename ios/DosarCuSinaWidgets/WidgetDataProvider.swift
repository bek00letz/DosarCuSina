import Foundation
import WidgetKit
import SwiftUI

// MARK: - Color Hex Utility for WidgetKit
extension Color {
    public init?(widgetHex: String) {
        var hexSanitized = widgetHex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Widget Event Data Item
public struct DosarWidgetEventItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let assetName: String
    public let iconName: String
    public let assetColorHex: String
    public let dueDate: Date
    public let daysRemaining: Int
    public let isUrgent: Bool
    public let isOverdue: Bool
    public var isCompleted: Bool
    public let cost: Double?
    public let currency: String
    
    public init(
        id: String,
        title: String,
        assetName: String,
        iconName: String,
        assetColorHex: String,
        dueDate: Date,
        daysRemaining: Int,
        isUrgent: Bool,
        isOverdue: Bool,
        isCompleted: Bool = false,
        cost: Double? = nil,
        currency: String = "RON"
    ) {
        self.id = id
        self.title = title
        self.assetName = assetName
        self.iconName = iconName
        self.assetColorHex = assetColorHex
        self.dueDate = dueDate
        self.daysRemaining = daysRemaining
        self.isUrgent = isUrgent
        self.isOverdue = isOverdue
        self.isCompleted = isCompleted
        self.cost = cost
        self.currency = currency
    }
    
    public var badgeText: String {
        if isCompleted {
            return "Rezolvat"
        } else if daysRemaining < 0 {
            return "Expirat \(abs(daysRemaining))z"
        } else if daysRemaining == 0 {
            return "Azi"
        } else if daysRemaining == 1 {
            return "Mâine"
        } else {
            return "\(daysRemaining)z"
        }
    }
    
    public var urgencyColorHex: String {
        if isCompleted {
            return "34C759" // Green
        } else if isOverdue {
            return "FF3B30" // Red
        } else if isUrgent {
            return "FF9500" // Orange
        } else {
            return "007AFF" // System Blue
        }
    }
}

// MARK: - Widget Snapshot Data
public struct DosarWidgetSnapshot: Codable, Sendable {
    public var lastUpdated: Date
    public var healthScore: Int
    public var activeAssetsCount: Int
    public var urgentEventsCount: Int
    public var events: [DosarWidgetEventItem]
    
    public init(
        lastUpdated: Date = Date(),
        healthScore: Int = 88,
        activeAssetsCount: Int = 4,
        urgentEventsCount: Int = 1,
        events: [DosarWidgetEventItem] = []
    ) {
        self.lastUpdated = lastUpdated
        self.healthScore = healthScore
        self.activeAssetsCount = activeAssetsCount
        self.urgentEventsCount = urgentEventsCount
        self.events = events
    }
}

// MARK: - Widget Timeline Entry
public struct DosarWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    public let assetName: String
    public let eventTitle: String
    public let daysRemaining: Int
    public let isUrgent: Bool
    public let isOverdue: Bool
    public let iconName: String
    public let assetColorHex: String
    public let healthScore: Int
    public let activeAssetsCount: Int
    public let urgentEventsCount: Int
    public let upcomingEvents: [DosarWidgetEventItem]
    public let nearestEventId: String
    public let statusText: String
    
    public init(
        date: Date,
        assetName: String,
        eventTitle: String,
        daysRemaining: Int,
        isUrgent: Bool,
        isOverdue: Bool,
        iconName: String,
        assetColorHex: String,
        healthScore: Int,
        activeAssetsCount: Int,
        urgentEventsCount: Int,
        upcomingEvents: [DosarWidgetEventItem],
        nearestEventId: String,
        statusText: String
    ) {
        self.date = date
        self.assetName = assetName
        self.eventTitle = eventTitle
        self.daysRemaining = daysRemaining
        self.isUrgent = isUrgent
        self.isOverdue = isOverdue
        self.iconName = iconName
        self.assetColorHex = assetColorHex
        self.healthScore = healthScore
        self.activeAssetsCount = activeAssetsCount
        self.urgentEventsCount = urgentEventsCount
        self.upcomingEvents = upcomingEvents
        self.nearestEventId = nearestEventId
        self.statusText = statusText
    }
}

// MARK: - Widget Data Provider
public final class WidgetDataProvider: Sendable {
    public static let shared = WidgetDataProvider()
    public static let appGroupID = "group.com.ar.dosarcusina.shared"
    public static let snapshotFileName = "dosar_widget_snapshot.json"
    
    public static func getSharedDirectoryURL() -> URL? {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            if FileManager.default.fileExists(atPath: groupURL.path) {
                return groupURL
            }
            do {
                try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
                return groupURL
            } catch {
                // App group directory not writable without provisioning profile, fall through to caches
            }
        }
        
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let fallbackDir = cachesURL?.appendingPathComponent("DosarCuSina", isDirectory: true)
        if let fallbackDir = fallbackDir, !FileManager.default.fileExists(atPath: fallbackDir.path) {
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        }
        return fallbackDir ?? cachesURL
    }
    
    public static func getSnapshotFileURL() -> URL? {
        guard let directory = getSharedDirectoryURL() else { return nil }
        return directory.appendingPathComponent(snapshotFileName)
    }
    
    public static func loadSnapshot() -> DosarWidgetSnapshot {
        guard let fileURL = getSnapshotFileURL(),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaultSnapshot()
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(DosarWidgetSnapshot.self, from: data)
            return snapshot
        } catch {
            return defaultSnapshot()
        }
    }
    
    public static func saveSnapshot(_ snapshot: DosarWidgetSnapshot) {
        guard let fileURL = getSnapshotFileURL() else { return }
        
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silently continue if snapshot write fails
        }
    }
    
    public static func markEventCompleted(eventId: String) {
        var snapshot = loadSnapshot()
        var updated = false
        
        for index in snapshot.events.indices {
            if snapshot.events[index].id == eventId {
                snapshot.events[index].isCompleted = true
                updated = true
                break
            }
        }
        
        if updated {
            let pendingEvents = snapshot.events.filter { !$0.isCompleted }
            let urgentCount = pendingEvents.filter { $0.isUrgent || $0.isOverdue }.count
            snapshot.urgentEventsCount = urgentCount
            
            let total = max(1, snapshot.events.count)
            let completed = snapshot.events.filter { $0.isCompleted }.count
            snapshot.healthScore = min(100, max(0, Int((Double(completed) / Double(total)) * 100)))
            snapshot.lastUpdated = Date()
            
            saveSnapshot(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    public static func defaultSnapshot() -> DosarWidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let due1 = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let due2 = calendar.date(byAdding: .day, value: 12, to: today) ?? today
        let due3 = calendar.date(byAdding: .day, value: 24, to: today) ?? today
        let due4 = calendar.date(byAdding: .day, value: 45, to: today) ?? today
        
        let event1 = DosarWidgetEventItem(
            id: "event-rca-001",
            title: "Asigurare RCA",
            assetName: "VW Golf 2018",
            iconName: "car.fill",
            assetColorHex: "007AFF",
            dueDate: due1,
            daysRemaining: 3,
            isUrgent: true,
            isOverdue: false,
            isCompleted: false,
            cost: 840.0,
            currency: "RON"
        )
        
        let event2 = DosarWidgetEventItem(
            id: "event-gaze-002",
            title: "Revizie Tehnică Gaze",
            assetName: "Apartament Pipera",
            iconName: "flame.fill",
            assetColorHex: "FF9500",
            dueDate: due2,
            daysRemaining: 12,
            isUrgent: false,
            isOverdue: false,
            isCompleted: false,
            cost: 350.0,
            currency: "RON"
        )
        
        let event3 = DosarWidgetEventItem(
            id: "event-vet-003",
            title: "Vaccin Polivalent Anual",
            assetName: "Max (Ciobănesc)",
            iconName: "pawprint.fill",
            assetColorHex: "8E5A2A",
            dueDate: due3,
            daysRemaining: 24,
            isUrgent: false,
            isOverdue: false,
            isCompleted: false,
            cost: 180.0,
            currency: "RON"
        )
        
        let event4 = DosarWidgetEventItem(
            id: "event-impozit-004",
            title: "Impozit Clădiri",
            assetName: "Apartament Pipera",
            iconName: "house.fill",
            assetColorHex: "34C759",
            dueDate: due4,
            daysRemaining: 45,
            isUrgent: false,
            isOverdue: false,
            isCompleted: false,
            cost: 260.0,
            currency: "RON"
        )
        
        return DosarWidgetSnapshot(
            lastUpdated: Date(),
            healthScore: 88,
            activeAssetsCount: 4,
            urgentEventsCount: 1,
            events: [event1, event2, event3, event4]
        )
    }
    
    public static func createEntry(from snapshot: DosarWidgetSnapshot, date: Date = Date()) -> DosarWidgetEntry {
        let activeEvents = snapshot.events.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
        let nearestEvent = activeEvents.first
        
        let assetName = nearestEvent?.assetName ?? "Dosar cu Șină"
        let eventTitle = nearestEvent?.title ?? "Toate obligațiile sunt la zi"
        let daysRemaining = nearestEvent?.daysRemaining ?? 30
        let isUrgent = nearestEvent?.isUrgent ?? false
        let isOverdue = nearestEvent?.isOverdue ?? false
        let iconName = nearestEvent?.iconName ?? "folder.fill"
        let assetColorHex = nearestEvent?.assetColorHex ?? "007AFF"
        let nearestEventId = nearestEvent?.id ?? ""
        let statusText = nearestEvent?.badgeText ?? "La zi"
        
        return DosarWidgetEntry(
            date: date,
            assetName: assetName,
            eventTitle: eventTitle,
            daysRemaining: daysRemaining,
            isUrgent: isUrgent,
            isOverdue: isOverdue,
            iconName: iconName,
            assetColorHex: assetColorHex,
            healthScore: snapshot.healthScore,
            activeAssetsCount: snapshot.activeAssetsCount,
            urgentEventsCount: snapshot.urgentEventsCount,
            upcomingEvents: activeEvents,
            nearestEventId: nearestEventId,
            statusText: statusText
        )
    }
}

// MARK: - Widget Timeline Provider
public struct DosarWidgetTimelineProvider: TimelineProvider {
    public typealias Entry = DosarWidgetEntry
    
    public init() {}
    
    public func placeholder(in context: Context) -> DosarWidgetEntry {
        let snapshot = WidgetDataProvider.defaultSnapshot()
        return WidgetDataProvider.createEntry(from: snapshot)
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (DosarWidgetEntry) -> Void) {
        let snapshot = WidgetDataProvider.loadSnapshot()
        let entry = WidgetDataProvider.createEntry(from: snapshot)
        completion(entry)
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<DosarWidgetEntry>) -> Void) {
        let snapshot = WidgetDataProvider.loadSnapshot()
        let currentDate = Date()
        let entry = WidgetDataProvider.createEntry(from: snapshot, date: currentDate)
        
        // Reload every hour or at nearest deadline
        var reloadDate = currentDate.addingTimeInterval(3600)
        if let nextDueDate = entry.upcomingEvents.first?.dueDate, nextDueDate > currentDate {
            reloadDate = min(reloadDate, nextDueDate)
        }
        
        let timeline = Timeline(entries: [entry], policy: .after(reloadDate))
        completion(timeline)
    }
}
