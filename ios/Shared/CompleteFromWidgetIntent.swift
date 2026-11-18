import AppIntents
import Foundation

/// "Gata" on a widget. Compiled into the app and the widget extension; each
/// target supplies its own `WidgetCompletionHandler`:
/// - in the app it completes the obligation through `IntentEngine.perform`, the
///   same engine every other "done" from outside uses, whose pass through the
///   coordinator takes that deadline's pending and shown reminders away at once;
/// - in the widget extension, should the system still run it there, it leaves
///   the request in `WidgetCompletionQueue` for the app.
/// It runs in the app: on iOS 26 as an intent that the system runs in the app's
/// process (`LiveActivityIntent`, which starts the app in the background, no
/// Live Activity involved), from iOS 27 pinned there (`allowedExecutionTargets`).
public struct CompleteFromWidgetIntent: AppIntent, LiveActivityIntent {
    public static let title: LocalizedStringResource = "Marchează ca rezolvat"
    public static let description = IntentDescription("Bifează din widget un termen din Dosar cu Șină.")
    /// Only widgets use it; Shortcuts has `CompleteObligationIntent`.
    public static let isDiscoverable = false
    public static var supportedModes: IntentModes { .background }

    @available(iOS 27.0, *)
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Termen")
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
