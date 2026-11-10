import Foundation
import SwiftData

extension AssetActions {
    /// Sets or removes the asset's photo (a pet, the car, a box on the home grid).
    /// Saves once; on failure nothing changes.
    public func setPhoto(_ asset: Asset, _ data: Data?) throws {
        asset.photoData = data
        try UnitOfWork.save(context, now: now())
    }
}
