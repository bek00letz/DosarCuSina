// path: ios/DosarCuSina/Services/Example/ExampleReader.swift
let container = try ModelContainer(for: schema, configurations: [configuration])
let context = ModelContext(container)
container.mainContext.autosaveEnabled = true
