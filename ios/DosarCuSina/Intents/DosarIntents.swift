import AppIntents
import Foundation
import SwiftData

/// An obligation as Siri, Shortcuts and widgets see it.
public struct ObligationEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Obligație")
    public static let defaultQuery = ObligationQuery()

    public let id: UUID
    public let title: String
    public let assetName: String?
    public let dueDay: CalendarDay

    public var displayRepresentation: DisplayRepresentation {
        let due = dueDay.startDate().formatted(.dateTime.day().month(.wide).locale(.dosarDefault))
        if let assetName {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(assetName) · \(due)")
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(due)")
    }

    init(_ snapshot: ObligationSnapshot) {
        self.id = snapshot.id
        self.title = snapshot.isSensitive ? String(localized: "Scadență protejată") : snapshot.title
        self.assetName = snapshot.isSensitive ? nil : snapshot.assetName
        self.dueDay = snapshot.dueDay
    }
}

public struct ObligationQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [ObligationEntity] {
        let wanted = Set(identifiers)
        return try await IntentStore.snapshots().filter { wanted.contains($0.id) }.map(ObligationEntity.init)
    }

    /// What needs attention, in the Radar's order.
    public func suggestedEntities() async throws -> [ObligationEntity] {
        let digest = AttentionModel.digest(try await IntentStore.snapshots())
        return (digest.now + digest.soon.flatMap(\.entries)).prefix(10).map { ObligationEntity($0.obligation) }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case storeUnavailable
    case notFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: return "Datele nu pot fi deschise acum. Deschide aplicația și încearcă din nou."
        case .notFound: return "Obligația nu mai există."
        }
    }
}

/// Intents use the same database and the same engine as the app.
@MainActor
enum IntentStore {
    static func container() throws -> ModelContainer {
        guard let container = PersistenceController.shared.container else { throw IntentError.storeUnavailable }
        return container
    }

    static func snapshots() throws -> [ObligationSnapshot] {
        try ObligationSnapshot.fetchAll(in: ModelContext(container()))
    }
}

public struct CompleteObligationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Marchează ca rezolvat"
    public static let description = IntentDescription("Bifează o obligație. Dacă se repetă, trece la următoarea scadență.")

    @Parameter(title: "Obligație")
    public var obligation: ObligationEntity

    public init() {}

    public init(obligation: ObligationEntity) {
        self.obligation = obligation
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = obligation.id
        let message = try await MainActor.run { () throws -> String in
            let context = try IntentStore.container().mainContext
            var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let target = try context.fetch(descriptor).first else { throw IntentError.notFound }
            try ObligationActions(context: context).complete(target)
            if target.status == .active {
                let next = target.dueDay().startDate().formatted(.dateTime.day().month(.wide).year().locale(.dosarDefault))
                return String(localized: "Gata. Următoarea scadență e pe \(next).")
            }
            return String(localized: "Gata, am bifat-o.")
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

public struct UpcomingObligationsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ce scadențe am"
    public static let description = IntentDescription("Spune ce obligații au nevoie de atenție acum.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await MainActor.run { () throws -> String in
            let digest = AttentionModel.digest(try IntentStore.snapshots())
            guard !digest.now.isEmpty else {
                return String(localized: "Nimic urgent. Totul e la zi.")
            }
            let lines = digest.now.map { entry -> String in
                let title = entry.obligation.isSensitive ? String(localized: "o scadență protejată") : entry.obligation.title
                switch entry.urgency {
                case .overdue: return String(localized: "\(title), depășit")
                case .today: return String(localized: "\(title), azi")
                default: return String(localized: "\(title), în \(entry.daysRemaining) zile")
                }
            }
            return lines.formatted(.list(type: .and).locale(.dosarDefault))
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

public struct DosarShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UpcomingObligationsIntent(),
            phrases: [
                "Ce scadențe am în \(.applicationName)",
                "Ce am de făcut în \(.applicationName)",
            ],
            shortTitle: "Scadențe",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: CompleteObligationIntent(),
            phrases: [
                "Bifează \(\.$obligation) în \(.applicationName)",
            ],
            shortTitle: "Bifează",
            systemImageName: "checkmark.circle"
        )
    }
}
