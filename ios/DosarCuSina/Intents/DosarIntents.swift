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

    /// Whether its day is shown: not while the whole app is locked.
    let showsDay: Bool

    public var displayRepresentation: DisplayRepresentation {
        // Nothing of the binder while the app is locked, its due day included.
        guard showsDay else { return DisplayRepresentation(title: "\(title)") }
        let due = DosarFormat.dayMonth(dueDay)
        if let assetName {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(assetName) · \(due)")
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(due)")
    }

    /// The deadline as Siri and Shortcuts may show it, by the rule every outside surface follows
    /// (`SearchPrivacy`): a locked category's in generic words, and every one generic, its day
    /// left out, while the whole app is locked. The id and the cycle stay, so a shortcut that
    /// holds it still finds it, and the app opens it after Face ID.
    init(_ snapshot: ObligationSnapshot, appLockEnabled: Bool) {
        let listsAnything = SearchPrivacy.outsideListsAnything(appLockEnabled: appLockEnabled)
        let named = listsAnything && !snapshot.isSensitive
        self.id = snapshot.id
        self.showsDay = listsAnything
        self.title = named ? snapshot.title : String(localized: "Scadență protejată")
        self.assetName = named ? snapshot.assetName : nil
        self.dueDay = snapshot.dueDay
    }
}

public struct ObligationQuery: EntityQuery {
    public init() {}

    /// The deadlines a shortcut holds, by id. While the app is locked they come back generic
    /// (`ObligationEntity.init(_:appLockEnabled:)`), so a saved shortcut still runs and opens the
    /// app, which asks for Face ID.
    public func entities(for identifiers: [UUID]) async throws -> [ObligationEntity] {
        try await MainActor.run {
            let wanted = Set(identifiers)
            let locked = IntentStore.appLockEnabled
            return try IntentStore.snapshots().filter { wanted.contains($0.id) }.map { ObligationEntity($0, appLockEnabled: locked) }
        }
    }

    /// What needs attention, in the Radar's order. Nothing while the app is locked: as in the
    /// iPhone's search, a locked app lists nothing of the binder outside it
    /// (`SearchPrivacy.outsideListsAnything`).
    public func suggestedEntities() async throws -> [ObligationEntity] {
        try await MainActor.run {
            let locked = IntentStore.appLockEnabled
            guard SearchPrivacy.outsideListsAnything(appLockEnabled: locked) else { return [] }
            let digest = AttentionModel.digest(try IntentStore.snapshots())
            return (digest.now + digest.soon.flatMap(\.entries)).prefix(10).map { ObligationEntity($0.obligation, appLockEnabled: locked) }
        }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case storeUnavailable
    case notFound
    case appLocked
    /// A deadline of a locked category, not closed: Face ID wasn't given, or couldn't be asked.
    case protectedDeadline
    /// A deadline whose closing asks a new day or a new document, which only the app asks.
    case closesInTheApp

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: return "Datele nu pot fi deschise acum. Deschide aplicația și încearcă din nou."
        case .notFound: return "Obligația nu mai e activă. Poate ai bifat-o deja."
        case .appLocked: return "Dosar cu Șină e protejat cu Face ID. Deschide aplicația ca să vezi termenele."
        case .protectedDeadline: return "Termenul e într-o categorie protejată. Deschide-l în Dosar cu Șină și confirmă cu Face ID ca să-l bifezi."
        case .closesInTheApp: return "Termenul cere o dată nouă sau actul nou. Deschide-l în Dosar cu Șină și apasă „Am rezolvat” ca să-l bifezi."
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
        try ObligationSnapshot.fetchForOutside(in: PersistenceController.context(in: container()))
    }

    /// Whether the whole app is locked on this device.
    static var appLockEnabled: Bool { AppPreferences.shared.appLockEnabled }

    /// With the app lock on, intents that read or change deadlines open the app,
    /// which asks for Face ID, instead of answering.
    static var opensAppInstead: Bool { appLockEnabled }
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
        // Closing that asks a new day or a new document happens in the app's "Am rezolvat"
        // (`IntentEngine.needsTheApp`, the one rule): the shortcut continues there.
        if try await MainActor.run(body: { try IntentEngine.needsTheApp(request, in: container.mainContext) }) {
            let cycle = obligation.dueDay
            await MainActor.run { AppNavigator.shared.open(.completion(id, cycle: cycle)) }
            guard systemContext.currentMode.canContinueInForeground else { throw IntentError.closesInTheApp }
            throw needsToContinueInForegroundError("Deschide Dosar cu Șină ca să termini de bifat.", alwaysConfirm: false)
        }
        // A deadline of a locked category closes only after Face ID, which the app asks
        // (`IntentEngine.perform`, the one rule): the shortcut continues there.
        if try await MainActor.run(body: { try IntentEngine.asksFaceID(request, in: container.mainContext) }) {
            guard systemContext.currentMode.canContinueInForeground else { throw IntentError.protectedDeadline }
            try await continueInForeground("Deschide Dosar cu Șină ca să confirmi cu Face ID.", alwaysConfirm: false)
        }
        let outcome = try await IntentEngine.perform(request, container: container)
        switch outcome {
        case .leftForTheApp:
            // Its page, to finish there.
            await MainActor.run { AppNavigator.shared.open(.obligation(id)) }
            throw IntentError.protectedDeadline
        case .needsTheApp:
            // Changed meanwhile into one that asks: its "Am rezolvat", to finish there.
            let cycle = obligation.dueDay
            await MainActor.run { AppNavigator.shared.open(.completion(id, cycle: cycle)) }
            throw IntentError.closesInTheApp
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
                let when = WhenWording.phrase(entry.urgency, daysRemaining: entry.daysRemaining)
                return String(localized: "\(title), \(when)", comment: "Siri: a deadline and when it is due, e.g. 'ITP, în 5 zile'.")
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
