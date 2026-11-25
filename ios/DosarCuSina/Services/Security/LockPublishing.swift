import Foundation
import SwiftData

/// Sends up the locks this device chose before locking travelled (database version 19), once:
/// each category this device keeps locked by its own choice, whose record says it was never
/// locked anywhere, gets when this device locked it, or now when that isn't known
/// (`CategoryTemplate.lockedEverywhereAt`). Then every other device, a new one included, keeps it
/// locked until it is opened there (`SectionLocks.isLocked`). The app's own step: it gives no
/// change time. A lock chosen from now on travels as it is made (`CategoryTemplate.setLock`).
@MainActor
enum LockPublishing {
    /// Returns whether any lock was sent up.
    @discardableResult
    static func publish(in context: ModelContext, now: Date = Date()) throws -> Bool {
        let locks = SectionLocks.of(context.container)
        let unsent = try TemplateStore(context: context).all().filter { template in
            template.lockedEverywhereAt == nil && locks.lockedHere(template.key)?.locked == true
        }
        guard !unsent.isEmpty else { return false }
        try UnitOfWork.perform(in: context, origin: .app) {
            for template in unsent { template.lockedEverywhereAt = locks.lockedHere(template.key)?.at ?? now }
            try UnitOfWork.save(context)
        }
        return true
    }
}
