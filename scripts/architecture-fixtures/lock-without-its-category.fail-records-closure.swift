// path: ios/DosarCuSina/Views/Settings/ExampleBackup.swift
let anyLocked = try context.fetch(FetchDescriptor<CategoryTemplate>()).contains { $0.isSensitive }
