import AppIntents
import Foundation

/// "Gata" on a widget. Compiled into the app and the widget extension; each
/// target supplies its own `WidgetCompletionHandler`:
/// - in the app it completes the obligation through `ObligationActions`, the
///   same engine every other "done" button uses;
/// - in the widget extension (iOS 26, where the system runs it there) it leaves
///   the request in `WidgetCompletionQueue` for the app.
/// From iOS 27 the intent is pinned to the app, so the engine runs right away.
public struct CompleteFromWidgetIntent: AppIntent {
    public static let title: LocalizedStringResource = "Marchează ca rezolvat"
    public static let description = IntentDescription("Bifează din widget o obligație din Dosar cu Șină.")
    /// Only widgets use it; Shortcuts has `CompleteObligationIntent`.
    public static let isDiscoverable = false
    public static var supportedModes: IntentModes { .background }

    @available(iOS 27.0, *)
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Obligație")
    public var obligationID: String

    @Parameter(title: "Termen")
    public var dueDay: String

    public init() {}

    public init(obligationID: UUID, dueDay: String) {
        self.obligationID = obligationID.uuidString
        self.dueDay = dueDay
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: obligationID) else { return .result() }
        await WidgetCompletionHandler.handle(WidgetCompletion(obligationId: id, dueDay: dueDay))
        return .result()
    }
}
