import SwiftUI
import SwiftData
import UserNotifications

@main
struct DosarCuSinaApp: App {
    public static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Asset.self,
            LifecycleEvent.self,
            DocumentAttachment.self,
            DynamicField.self,
            ServiceItem.self,
            MeasurementLog.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var sharedModelContainer: ModelContainer {
        Self.sharedModelContainer
    }
    
    public init() {
        let container = Self.sharedModelContainer
        
        // 1. Configure Notification Delegate & ModelContainer Link
        NotificationDelegate.shared.modelContainer = container
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // 2. Register Interactive Action Categories ("Am rezolvat", "Amână 3 zile")
        NotificationScheduler.shared.registerCategories()
        
        // 3. Initial Widget Data Snapshot Sync to App Group container
        WidgetDataSyncService.shared.sync(container: container)
    }

    @AppStorage("didSeedInitialDemoData") private var didSeedInitialDemoData: Bool = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    if !didSeedInitialDemoData {
                        DemoDataSeeder.seedInitialDataIfNeeded(context: sharedModelContainer.mainContext)
                        didSeedInitialDemoData = true
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == NotificationScheduler.deepLinkScheme else { return }
        if url.host == "event",
           let uuidString = url.pathComponents.dropFirst().first,
           let uuid = UUID(uuidString: uuidString) {
            NotificationScheduler.activeDeepLinkEventId = uuid
            NotificationCenter.default.post(
                name: .dosarCuSinaOpenEventDeepLink,
                object: nil,
                userInfo: [
                    "eventId": uuid,
                    "eventIdString": uuidString,
                    "url": url
                ]
            )
        }
    }
}
