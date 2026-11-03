import Foundation
import SwiftData

public enum TemplateStoreError: LocalizedError, Equatable {
    /// The category still has assets; move or delete them first.
    case inUse(assetCount: Int)
    case builtInCannotBeDeleted
    /// What a built-in category does is the app's; only categories of one's own have switches.
    case builtInBehaviourIsFixed

    public var errorDescription: String? {
        switch self {
        case .builtInBehaviourIsFixed:
            return String(localized: "Categoriile incluse se poartă mereu la fel. Poți schimba doar categoriile tale.", comment: "Shown when changing what a built-in category keeps.")
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

    /// Installs built-in templates that are missing and gives installed ones the
    /// catalog's definition whenever theirs is from another version or was
    /// changed into a custom one, keeping household preferences (order,
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
        changed = try retireOldBuiltIns(byKey: &byKey) || changed
        var nextOrder = (existing.map(\.homeOrder).max() ?? -1) + 1
        for definition in catalog {
            if let installed = byKey[definition.key] {
                // A built-in is always the app's own definition: a newer catalog
                // upgrades it, and one changed from outside is put back.
                if !installed.isBuiltIn || installed.builtInVersion != definition.version {
                    installed.isBuiltIn = true
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

    /// Moves assets off built-in templates an earlier catalog had: a replaced key
    /// hands its assets (with renamed field keys) to its successor; a retired key
    /// with assets becomes a custom category so nothing disappears.
    private func retireOldBuiltIns(byKey: inout [String: CategoryTemplate]) throws -> Bool {
        var changed = false
        for (oldKey, newKey) in BuiltInTemplates.replacedKeys {
            let assets = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == oldKey }))
            for asset in assets {
                var values = FieldValues()
                for (key, value) in asset.values { values[BuiltInTemplates.replacedFieldKeys[key] ?? key] = value }
                asset.templateKey = newKey
                asset.valuesData = StoredJSON.encode(values)
                changed = true
            }
            if let old = byKey.removeValue(forKey: oldKey), old.isBuiltIn {
                context.delete(old)
                changed = true
            }
        }
        for key in BuiltInTemplates.retiredKeys {
            guard let old = byKey[key], old.isBuiltIn else { continue }
            let count = try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == key }))
            if count > 0 {
                old.isBuiltIn = false
                old.builtInVersion = 0
            } else {
                context.delete(old)
                byKey.removeValue(forKey: key)
            }
            changed = true
        }
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
        try Self.templatesByKey(in: context)
    }

    /// Templates keyed by `key` on any context, such as search's own off the main
    /// thread. The first in the binder's order wins when a key repeats.
    nonisolated public static func templatesByKey(in context: ModelContext) throws -> [String: CategoryTemplate] {
        var result: [String: CategoryTemplate] = [:]
        let all = try context.fetch(FetchDescriptor<CategoryTemplate>(sortBy: [SortDescriptor(\.homeOrder), SortDescriptor(\.createdAt)]))
        for template in all where result[template.key] == nil {
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

    /// Creates a category from a name, a symbol and the pockets it should show,
    /// with no fields of its own ("Altceva…"). Facts go in Date importante as free rows.
    @discardableResult
    public func createCustom(name: String, symbol: String, pockets: [SectionPocket], tint: TemplateTint = .gray, isSensitive: Bool = false) throws -> CategoryTemplate {
        let template = try createCustom(name: name, symbol: symbol, tint: tint, sections: [], isSensitive: isSensitive)
        template.pockets = pockets
        try save()
        return template
    }

    /// Creates a category of the person's own from the few plain questions it answers
    /// (`CategorySwitches`): its pockets, its box, a counter and a service deadline.
    @discardableResult
    public func createCustom(name: String, symbol: String, switches: CategorySwitches, tint: TemplateTint = .gray, isSensitive: Bool = false) throws -> CategoryTemplate {
        var definition = switches.definition(key: TemplateDefinition.newCustomKey(), name: name, symbol: symbol, tint: tint)
        definition.isSensitiveByDefault = isSensitive
        let order = ((try all()).map(\.homeOrder).max() ?? -1) + 1
        let template = CategoryTemplate(definition: definition, isBuiltIn: false, homeOrder: order)
        context.insert(template)
        try save()
        return template
    }

    /// The deadlines a change of switches touches: the service deadlines a switch turns off
    /// (still running), the ones it turns back on (paused), and the running ones whose
    /// interval it changes. Nothing changes until the person says so
    /// (`editCustom(_:name:symbol:switches:changingDeadlines:)`).
    public struct SwitchEffects {
        /// Running deadlines whose service the change turns off.
        public var pausing: [Obligation] = []
        /// Paused deadlines whose service the change turns back on.
        public var resuming: [Obligation] = []
        /// Running deadlines that count by another interval from now on.
        public var retiming: [Obligation] = []

        public var isEmpty: Bool { pausing.isEmpty && resuming.isEmpty && retiming.isEmpty }
    }

    public func effects(of switches: CategorySwitches, on template: CategoryTemplate) throws -> SwitchEffects {
        let before = Set(template.blueprints.map(\.key).filter(CategorySwitches.isServiceBlueprint))
        let rules = Self.serviceRules(of: switches.applied(to: template.definition))
        let key = template.key
        let assets = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == key }, sortBy: [SortDescriptor(\.name)]))
        var effects = SwitchEffects()
        for obligation in assets.flatMap({ $0.obligations ?? [] }) {
            guard let blueprint = obligation.blueprintKey, CategorySwitches.isServiceBlueprint(blueprint) else { continue }
            let rule = rules[blueprint]
            if obligation.status == .active, before.contains(blueprint), rule == nil {
                effects.pausing.append(obligation)
            } else if obligation.status == .paused, rule != nil, !before.contains(blueprint) {
                effects.resuming.append(obligation)
            } else if obligation.status == .active, let rule, obligation.recurrence != rule {
                effects.retiming.append(obligation)
            }
        }
        return effects
    }

    /// Each service blueprint's rule, by key.
    private static func serviceRules(of definition: TemplateDefinition) -> [String: RecurrenceRule] {
        Dictionary(definition.blueprints.filter { CategorySwitches.isServiceBlueprint($0.key) }.map { ($0.key, $0.recurrence) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Renames a category of the person's own and changes its symbol and switches, as one
    /// step the toast can take back. Nothing filed is deleted: a pocket turned off only
    /// hides, and comes back with what it had. With `changingDeadlines`, in the same step,
    /// the service deadlines a switch turned off are paused, the paused ones it turned back
    /// on run again, and running ones (and those resumed) count by the new interval from
    /// their next cycle; their due day stays (`effects(of:on:)`).
    @discardableResult
    public func editCustom(_ template: CategoryTemplate, name: String, symbol: String, switches: CategorySwitches, changingDeadlines: Bool) throws -> UndoReceipt {
        guard !template.isBuiltIn else { throw TemplateStoreError.builtInBehaviourIsFixed }
        let effects = changingDeadlines ? try effects(of: switches, on: template) : SwitchEffects()
        return try UnitOfWork.performUndoable(in: context) {
            var definition = switches.applied(to: template.definition)
            definition.name = name
            definition.symbol = symbol
            template.apply(definition)
            let rules = Self.serviceRules(of: definition)
            let actions = ObligationActions(context: context)
            for obligation in effects.pausing { try actions.pause(obligation) }
            for obligation in effects.resuming { try actions.resume(obligation) }
            for obligation in effects.resuming + effects.retiming {
                guard let key = obligation.blueprintKey, let rule = rules[key], obligation.recurrence != rule else { continue }
                try actions.setRecurrence(obligation, rule)
            }
            try save()
        }.receipt
    }

    /// Changes which pockets a category shows.
    public func setPockets(_ template: CategoryTemplate, _ pockets: [SectionPocket]) throws {
        template.pockets = pockets
        try save()
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
        try UnitOfWork.save(context)
    }
}
