// path: ios/DosarCuSina/Services/Example/ExampleReader.swift
/// Reads on a context of its own; never ModelContext(container) here.
func read(_ container: ModelContainer, into context: ModelContext) throws -> Int {
    let own = PersistenceController.context(in: container) // not ModelContext(container)
    own.autosaveEnabled = false
    return try own.fetchCount(FetchDescriptor<Asset>())
}
let container = try PersistenceController.makeContainer(inMemory: true)
