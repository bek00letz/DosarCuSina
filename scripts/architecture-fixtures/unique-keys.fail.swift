// path: ios/DosarCuSina/Services/Example/ExampleRepairs.swift
let providers = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Provider>()).map { ($0.id, $0) })
var group = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.id) })
