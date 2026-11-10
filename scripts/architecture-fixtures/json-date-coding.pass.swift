// path: ios/DosarCuSina/Services/Example/ExampleStore.swift
// A comment may name dateEncodingStrategy.
let data = try MachineText.jsonEncoder().encode(items)
let items = try MachineText.jsonDecoder().decode([Item].self, from: data)
let archive = MachineText.jsonEncoder(.readable)
