// path: ios/DosarCuSina/Views/Example/ExampleBox.swift
let isLocked = template.map(vault.isLocked) ?? false
let showsPicture = !(template.map { vault.isLocked($0) } ?? false)
