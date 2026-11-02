import Foundation
import WidgetKit

/// The widget extension's side of `CompleteFromWidgetIntent`.
///
/// The extension can't open the household database, so it leaves the request
/// for the app (which completes it through `ObligationActions` the next time it
/// runs) and reloads the widgets, which hide the item straight away.
enum WidgetCompletionHandler {
    static func handle(_ completion: WidgetCompletion) async {
        WidgetCompletionQueue.shared()?.enqueue(completion)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
