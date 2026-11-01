import Foundation
import AppIntents
import SwiftData

// MARK: - SwiftData Store Accessor for Intents

@MainActor
final class DosarDataStore {
    static let shared = DosarDataStore()
    
    private var container: ModelContainer?
    
    private init() {
        let schema = Schema([
            Asset.self,
            LifecycleEvent.self,
            DocumentAttachment.self,
            DynamicField.self,
            ServiceItem.self,
            MeasurementLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.container = try? ModelContainer(for: schema, configurations: [config])
    }
    
    /// Fetches all uncompleted events due within the next N days.
    func fetchUpcomingEvents(days: Int = 30) -> [LifecycleEvent] {
        guard let container = container else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LifecycleEvent>(
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        guard let allEvents = try? context.fetch(descriptor) else { return [] }
        
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: days, to: startOfToday) else { return [] }
        
        return allEvents.filter { event in
            !event.isCompleted && event.dueDate >= startOfToday && event.dueDate <= endDate
        }
    }
    
    /// Finds vehicle ITP and inspection deadlines.
    func fetchVehicleITPEvents() -> [(event: LifecycleEvent, asset: Asset)] {
        guard let container = container else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Asset>()
        guard let allAssets = try? context.fetch(descriptor) else { return [] }
        
        var results: [(event: LifecycleEvent, asset: Asset)] = []
        
        for asset in allAssets where asset.category == .vehicle {
            for event in asset.events where !event.isCompleted {
                let lower = event.title.lowercased()
                if lower.contains("itp") || lower.contains("inspec") || lower.contains("rca") {
                    results.append((event: event, asset: asset))
                }
            }
        }
        
        return results.sorted { $0.event.dueDate < $1.event.dueDate }
    }
    
    /// Marks an event as resolved by its UUID, rolling over if recurring.
    func completeEvent(id: UUID) -> Bool {
        guard let container = container else { return false }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LifecycleEvent>(
            predicate: #Predicate<LifecycleEvent> { $0.id == id }
        )
        guard let event = try? context.fetch(descriptor).first else { return false }
        
        if let cadence = event.cadenceDays, cadence > 0 {
            event.dueDate = CadenceCalculator.calculateNextDueDate(from: event.dueDate, cadenceDays: cadence)
            event.isCompleted = false
            event.completedDate = nil
        } else {
            event.isCompleted = true
            event.completedDate = Date()
        }
        
        try? context.save()
        return true
    }
}

// MARK: - Intent: Check Expiring Events

/// App Intent answering: "Ce îmi expiră luna asta?"
public struct CheckExpiringEventsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Verifică expirări luna aceasta"
    public static var description = IntentDescription("Afișează scadențele și obligațiile programate în următoarele 30 de zile.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let responseText: String = await MainActor.run {
            let events = DosarDataStore.shared.fetchUpcomingEvents(days: 30)
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            dateFormatter.locale = Locale(identifier: "ro_RO")
            
            if events.isEmpty {
                return "Totul este la zi! Nu ai nicio scadență programată în următoarele 30 de zile în Dosar cu Șină."
            } else if events.count == 1 {
                let event = events[0]
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: event.dueDate)).day ?? 0
                let dateStr = dateFormatter.string(from: event.dueDate)
                let assetInfo = event.asset != nil ? " pentru \(event.asset!.name)" : ""
                
                if days == 0 {
                    return "Ai o scadență chiar astăzi: \(event.title)\(assetInfo)."
                } else if days == 1 {
                    return "Ai o scadență mâine: \(event.title)\(assetInfo), pe \(dateStr)."
                } else {
                    return "Ai o scadență în următoarele 30 de zile: \(event.title)\(assetInfo), pe \(dateStr), peste \(days) zile."
                }
            } else {
                let summaryItems = events.prefix(4).map { event -> String in
                    let dateStr = dateFormatter.string(from: event.dueDate)
                    let assetPart = event.asset != nil ? " (\(event.asset!.name))" : ""
                    return "\(event.title)\(assetPart) pe \(dateStr)"
                }
                let joinedList = summaryItems.joined(separator: ", ")
                let remainingCount = events.count - summaryItems.count
                let extra = remainingCount > 0 ? " și încă \(remainingCount) altele." : "."
                return "Ai \(events.count) scadențe în următoarele 30 de zile: \(joinedList)\(extra)"
            }
        }
        
        return .result(value: responseText, dialog: IntentDialog(stringLiteral: responseText))
    }
}

// MARK: - Intent: Check Vehicle ITP Status

/// App Intent answering: "Când expiră ITP-ul la mașină?"
public struct CheckVehicleITPIntent: AppIntent {
    public static var title: LocalizedStringResource = "Verifică ITP mașină"
    public static var description = IntentDescription("Verifică data scadenței pentru inspecția tehnică periodică (ITP) a vehiculelor tale.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let responseText: String = await MainActor.run {
            let vehicleEvents = DosarDataStore.shared.fetchVehicleITPEvents()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            dateFormatter.locale = Locale(identifier: "ro_RO")
            
            // Filter specifically for ITP first, or fallback to any vehicle inspection
            let itpMatches = vehicleEvents.filter { $0.event.title.localizedCaseInsensitiveContains("itp") }
            let candidate = itpMatches.first ?? vehicleEvents.first
            
            if let match = candidate {
                let event = match.event
                let asset = match.asset
                let formattedDate = dateFormatter.string(from: event.dueDate)
                let daysRemaining = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: Date()),
                    to: calendar.startOfDay(for: event.dueDate)
                ).day ?? 0
                
                if daysRemaining < 0 {
                    return "Atenție: ITP-ul pentru \(asset.name) a expirat acum \(abs(daysRemaining)) zile, pe data de \(formattedDate)."
                } else if daysRemaining == 0 {
                    return "ITP-ul pentru \(asset.name) expiră astăzi!"
                } else if daysRemaining == 1 {
                    return "ITP-ul pentru \(asset.name) expiră mâine, pe data de \(formattedDate)."
                } else {
                    return "ITP-ul pentru \(asset.name) expiră pe \(formattedDate), peste \(daysRemaining) zile."
                }
            } else {
                return "Nu am găsit nicio scadență de ITP înregistrată pentru vehiculele tale în Dosar cu Șină."
            }
        }
        
        return .result(value: responseText, dialog: IntentDialog(stringLiteral: responseText))
    }
}

// MARK: - Intent: Complete Event (Interactive for Widgets & Shortcuts)

/// Interactive App Intent to mark an event as resolved.
public struct CompleteEventIntent: AppIntent {
    public static var title: LocalizedStringResource = "Marchează ca rezolvat"
    public static var description = IntentDescription("Marchează o scadență din Dosar cu Șină ca fiind completată.")
    public static var openAppWhenRun: Bool = false
    
    @Parameter(title: "ID Eveniment")
    public var eventId: String
    
    public init() {
        self.eventId = ""
    }
    
    public init(eventId: String) {
        self.eventId = eventId
    }
    
    public init(eventId: UUID) {
        self.eventId = eventId.uuidString
    }
    
    public func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: eventId) else {
            return .result()
        }
        await MainActor.run {
            _ = DosarDataStore.shared.completeEvent(id: uuid)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Registers top Romanian voice phrases and shortcuts for Siri & Spotlight.
public struct DosarShortcuts: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor = .navy
    
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckExpiringEventsIntent(),
            phrases: [
                "Ce îmi expiră luna asta în \(.applicationName)",
                "Ce expiră luna aceasta în \(.applicationName)",
                "Verifică expirări în \(.applicationName)"
            ],
            shortTitle: "Expirări luna aceasta",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: CheckVehicleITPIntent(),
            phrases: [
                "Când expiră ITP-ul la mașină în \(.applicationName)",
                "Când expiră ITP în \(.applicationName)",
                "Status ITP mașină în \(.applicationName)"
            ],
            shortTitle: "Status ITP Mașină",
            systemImageName: "car.fill"
        )
    }
}
