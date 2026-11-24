#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Writes the binder's whole data layout to iCloud's development environment, in development
/// builds only, so it can be deployed to production with nothing missing.
///
/// iCloud learns a record's fields from the records a build uploads, so its development layout
/// holds only what a development build happened to write: a field no one has filled in yet
/// isn't there, and once the layout is deployed, a phone that writes it fails to sync. Apple's
/// answer is `initializeCloudKitSchema`, run on the same model SwiftData mirrors, against a
/// store of its own that is removed afterwards. The `DosarCuSina (iCloud layout)` scheme
/// launches the app with `-DosarPrepareCloudKitSchema` on a device signed into iCloud; the app
/// then opens the binder on the phone alone (`PersistenceController.syncIsBuiltIn`) and shows
/// only this step (`CloudKitSchemaSetupView`). Run it once before each deployment to production.
enum CloudKitSchemaSetup {
    /// The launch argument that asks for it.
    nonisolated static let argument = "-DosarPrepareCloudKitSchema"

    /// Whether this launch is for it; never in a release build.
    nonisolated static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// How it went: done, or the error iCloud gave, in its own terms (domain and code) for
    /// whoever runs it to look up.
    enum Outcome: Equatable, Sendable {
        case done
        case failed(String)
    }

    /// The model iCloud is given: exactly the entities of the schema the app stores, and nothing else.
    nonisolated static func managedObjectModel() -> NSManagedObjectModel? {
        NSManagedObjectModel.makeManagedObjectModel(for: CurrentSchema.models)
    }

    /// Uploads the layout, away from the main thread, and removes the store it used.
    static func run() async -> Outcome {
        await Task.detached(priority: .userInitiated) { upload() }.value
    }

    private nonisolated static func upload() -> Outcome {
        guard let model = managedObjectModel() else { return .failed("No model for the schema") }
        let folder = FileManager.default.temporaryDirectory.appending(path: "CloudKitSchema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let description = NSPersistentStoreDescription(url: folder.appending(path: "Schema.store"))
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: PersistenceController.cloudKitContainer)
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: (any Error)?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            return .done
        } catch {
            let error = error as NSError
            return .failed("\(error.domain) \(error.code)")
        }
    }
}
#endif
