// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
// A category that hasn't arrived yet stays locked: never isSensitive ?? false.
let isLocked = vault.isLocked(asset, template: templates.first)
let isSensitive = asset.isSensitive(among: templates)
let keyIsLocked = CategoryTemplate.isSensitive(key: key, among: templates, in: context.container)
// A deadline of the whole household has no section, so no lock.
let pageIsLocked = obligation.asset.map { vault.isLocked($0, template: template) } ?? false
let named = vault.isLocked(sectionIsSensitive: snapshot?.isSensitive ?? true)
// Whether anything of the binder is locked asks every category a section names.
let covers = BinderLocks.read(in: context).anySectionLocked
let lockedKeys = BinderLocks(templates: templates, naming: sections.map(\.templateKey), in: context.container).lockedKeys
let isOpen = vault.isLocked(sectionIsSensitive: template.isSensitive)
let hidden = facts.filter { $0.isSensitive || $0.isSecret }
let chosen = assets.contains { $0.id == id && $0.isSensitive }
