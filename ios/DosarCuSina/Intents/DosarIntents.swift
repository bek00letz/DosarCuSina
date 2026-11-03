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
        let due = DosarFormat.dayMonth(dueDay)
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
    case appLocked

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: return "Datele nu pot fi deschise acum. Deschide aplicația și încearcă din nou."
        case .notFound: return "Obligația nu mai e activă. Poate ai bifat-o deja."
        case .appLocked: return "Dosar cu Șină e protejat cu Face ID. Deschide aplicația ca să vezi termenele."
        }
    }
}

/// Intents use the same database and the same engine as the app, and see only
/// what may leave the app (`ObligationSnapshot.fetchForOutside`): never examples.
@MainActor
enum IntentStore {
    static func container() throws -> ModelContainer {
        guard let container = PersistenceController.shared.container else { throw IntentError.storeUnavailable }
        return container
    }

    static func snapshots() throws -> [ObligationSnapshot] {
        try ObligationSnapshot.fetchForOutside(in: ModelContext(container()))
    }

    /// With the app lock on, intents that read or change deadlines open the app,
    /// which asks for Face ID, instead of answering.
    static var opensAppInstead: Bool { AppPreferences.shared.appLockEnabled }
}

public struct CompleteObligationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Marchează ca rezolvat"
    public static let description = IntentDescription("Bifează o obligație. Dacă se repetă, trece la următoarea scadență.")
    /// Siri asks to unlock the phone first.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Obligație")
    public var obligation: ObligationEntity

    public init() {}

    public init(obligation: ObligationEntity) {
        self.obligation = obligation
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = obligation.id
        if await MainActor.run(body: { IntentStore.opensAppInstead }) {
            await MainActor.run { AppNavigator.shared.open(.obligation(id)) }
            guard systemContext.currentMode.canContinueInForeground else { throw IntentError.appLocked }
            throw needsToContinueInForegroundError("Deschide Dosar cu Șină ca să bifezi.", alwaysConfirm: false)
        }
        // The cycle Siri resolved the deadline on: a shortcut run later never closes the next one.
        let request = OutsideRequest(obligationId: id, cycle: obligation.dueDay, action: .complete, surface: .shortcut)
        let container = try await MainActor.run { try IntentStore.container() }
        let outcome = try await IntentEngine.perform(request, container: container)
        switch outcome {
        case .skipped, .snoozed:
            throw IntentError.notFound
        case .completed(let next?):
            let date = DosarFormat.longDay(next)
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Gata. Următoarea scadență e pe \(date).")))
        case .completed(nil):
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Gata, am bifat-o.")))
        }
    }
}

public struct UpcomingObligationsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ce scadențe am"
    public static let description = IntentDescription("Spune ce obligații au nevoie de atenție acum.")
    /// Siri asks to unlock the phone first.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        if await MainActor.run(body: { IntentStore.opensAppInstead }) {
            await MainActor.run { AppNavigator.shared.open(.upcoming) }
            guard systemContext.currentMode.canContinueInForeground else { throw IntentError.appLocked }
            throw needsToContinueInForegroundError("Deschide Dosar cu Șină ca să vezi termenele.", alwaysConfirm: false)
        }
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
                default: return String(localized: "\(title), în \(DurationWording.phrase(days: entry.daysRemaining))")
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
