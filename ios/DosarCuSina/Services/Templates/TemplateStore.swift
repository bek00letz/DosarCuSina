import Foundation
import SwiftData

public enum TemplateStoreError: LocalizedError, Equatable {
    /// The category still has assets; move or delete them first.
    case inUse(assetCount: Int)
    case builtInCannotBeDeleted

    public var errorDescription: String? {
        switch self {
        case .inUse(let count):
            return String(localized: "Categoria are încă \(count) active. Mută-le sau șterge-le mai întâi.", comment: "Shown when deleting a category that still has assets")
        case .builtInCannotBeDeleted:
            return String(localized: "Categoriile incluse nu se pot șterge, dar le poți ascunde de pe ecranul principal.")
        }
    }
}

/// The single place that creates, upgrades, orders and deletes category templates.
@MainActor
public struct TemplateStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Installs built-in templates that are missing and upgrades installed ones
    /// whose catalog version is newer, keeping household preferences (order,
    /// visibility, Face ID). Also removes duplicate built-ins that a sync merge
    /// may have produced. Saves only when something changed.
    @discardableResult
    public func installBuiltIns(catalog: [TemplateDefinition] = BuiltInTemplates.all) throws -> Bool {
        var changed = false
        let existing = try context.fetch(FetchDescriptor<CategoryTemplate>(sortBy: [SortDescriptor(\.createdAt)]))
        var byKey: [String: CategoryTemplate] = [:]
        for template in existing {
            if template.isBuiltIn, byKey[template.key] != nil {
                context.delete(template)
                changed = true
            } else if byKey[template.key] == nil {
                byKey[template.key] = template
            }
        }
        var nextOrder = (existing.map(\.homeOrder).max() ?? -1) + 1
        for definition in catalog {
            if let installed = byKey[definition.key] {
                if installed.isBuiltIn, installed.builtInVersion < definition.version {
                    installed.apply(definition)
                    changed = true
                }
            } else {
                context.insert(CategoryTemplate(definition: definition, isBuiltIn: true, homeOrder: nextOrder))
                nextOrder += 1
                changed = true
            }
        }
        if changed { try save() }
        return changed
    }

    /// All templates in home order.
    public func all() throws -> [CategoryTemplate] {
        try context.fetch(FetchDescriptor<CategoryTemplate>(sortBy: [SortDescriptor(\.homeOrder), SortDescriptor(\.createdAt)]))
    }

    public func template(forKey key: String) throws -> CategoryTemplate? {
        var descriptor = FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Templates keyed by `key`, for looking up many assets at once.
    public func templatesByKey() throws -> [String: CategoryTemplate] {
        var result: [String: CategoryTemplate] = [:]
        for template in try all() where result[template.key] == nil {
            result[template.key] = template
        }
        return result
    }

    @discardableResult
    public func createCustom(
        name: String,
        symbol: String,
        tint: TemplateTint,
        sections: [FieldSection],
        blueprints: [ObligationBlueprint] = [],
        isSensitive: Bool = false
    ) throws -> CategoryTemplate {
        let definition = TemplateDefinition(
            key: TemplateDefinition.newCustomKey(),
            name: name,
            symbol: symbol,
            tint: tint,
            isSensitiveByDefault: isSensitive,
            sections: sections,
            blueprints: blueprints
        )
        let order = ((try all()).map(\.homeOrder).max() ?? -1) + 1
        let template = CategoryTemplate(definition: definition, isBuiltIn: false, homeOrder: order)
        context.insert(template)
        try save()
        return template
    }

    /// Replaces a custom template's definition. Built-ins only take preference changes.
    public func update(_ template: CategoryTemplate, with definition: TemplateDefinition) throws {
        if template.isBuiltIn {
            template.isOnHome = definition.isOnHomeByDefault
            template.isSensitive = definition.isSensitiveByDefault
        } else {
            template.apply(definition)
            template.isOnHome = definition.isOnHomeByDefault
            template.isSensitive = definition.isSensitiveByDefault
        }
        template.updatedAt = Date()
        try save()
    }

    public func delete(_ template: CategoryTemplate) throws {
        guard !template.isBuiltIn else { throw TemplateStoreError.builtInCannotBeDeleted }
        let key = template.key
        let count = try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == key }))
        guard count == 0 else { throw TemplateStoreError.inUse(assetCount: count) }
        context.delete(template)
        try save()
    }

    /// Reorders templates the way `List.onMove` reports it.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        var ordered = try all()
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in ordered.enumerated() where template.homeOrder != index {
            template.homeOrder = index
        }
        try save()
    }

    public func setOnHome(_ template: CategoryTemplate, _ isOnHome: Bool) throws {
        template.isOnHome = isOnHome
        try save()
    }

    public func setSensitive(_ template: CategoryTemplate, _ isSensitive: Bool) throws {
        template.isSensitive = isSensitive
        try save()
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
