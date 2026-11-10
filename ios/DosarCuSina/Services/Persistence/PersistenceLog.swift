import Foundation
import OSLog

/// The persistence log: where a step that saves on its own, with no one to tell (launch's
/// steps, the repair list looking again after an import), says it failed. It names the step
/// and the kind of error only, never a value of the household's.
enum PersistenceLog {
    static let logger = Logger(subsystem: "com.ar.dosarcusina.app", category: "persistence")

    /// Logs that `step` failed with `error`.
    static func failed(_ step: String, _ error: any Error) {
        logger.error("\(step, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)")
    }

    /// Runs `work`, and logs it when it fails instead of throwing. Returns whether it succeeded.
    @discardableResult
    static func attempt(_ step: String, _ work: () throws -> Void) -> Bool {
        do {
            try work()
            return true
        } catch {
            failed(step, error)
            return false
        }
    }
}
