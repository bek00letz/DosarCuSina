// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
// A category that hasn't arrived yet stays locked: never isSensitive ?? false.
let isLocked = vault.isLocked(asset, template: templates.first)
let isSensitive = asset.isSensitive(among: templates)
let keyIsLocked = CategoryTemplate.isSensitive(key: key, among: templates, in: context.container)
// A deadline of the whole household has no section, so no lock.
let pageIsLocked = obligation.asset.map { vault.isLocked($0, template: template) } ?? false
let named = vault.isLocked(sectionIsSensitive: snapshot?.isSensitive ?? true)
