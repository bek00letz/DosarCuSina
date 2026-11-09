import Foundation
import SwiftData

extension DosarSchemaV8 {
    /// A category of assets (Car, Home, a user's own "Bikes") and its field and
    /// obligation definitions, plus this household's preferences for it.
    ///
    /// Built-in categories are installed from `BuiltInTemplates` and upgraded by
    /// `builtInVersion`; custom categories are created by the person. Both sync
    /// and travel in `.dosar` archives the same way.
    @Model
    public final class CategoryTemplate {
        public var key: String = ""
        public var name: String = ""
        public var summary: String?
        public var symbol: String = "square.grid.2x2"
        public var tintRaw: String = TemplateTint.gray.rawValue
        public var heroStyleRaw: String = HeroStyle.standard.rawValue
        public var isBuiltIn: Bool = false
        /// Definition version installed from the catalog (0 for custom templates).
        public var builtInVersion: Int = 0

        // Household preferences
        public var homeOrder: Int = 0
        public var isOnHome: Bool = true
        /// Ask for Face ID before showing assets of this category.
        public var isSensitive: Bool = false

        /// JSON `[FieldSection]`.
        public var sectionsData: Data?
        /// JSON `[ObligationBlueprint]`.
        public var blueprintsData: Data?
        /// JSON `[ComponentDefinition]`.
        public var componentsData: Data?
        /// `SectionPocket` raw values.
        public var pocketsRaw: [String] = SectionPocket.standard.map(\.rawValue)
        /// JSON `CategoryBehavior`: its box, its list, its part for other categories.
        /// Nil for a category from before version 3, which behaves as `standard`.
        public var behaviorData: Data?

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public init(definition: TemplateDefinition, isBuiltIn: Bool, homeOrder: Int) {
            self.key = definition.key
            self.isBuiltIn = isBuiltIn
            self.homeOrder = homeOrder
            self.isOnHome = definition.isOnHomeByDefault
            self.isSensitive = definition.isSensitiveByDefault
            apply(definition)
        }

        /// Replaces the definition (name, look, fields, blueprints) and keeps household preferences.
        public func apply(_ definition: TemplateDefinition) {
            name = definition.name
            summary = definition.summary
            symbol = definition.symbol
            tintRaw = definition.tint.rawValue
            heroStyleRaw = definition.heroStyle.rawValue
            sectionsData = StoredJSON.encode(definition.sections)
            blueprintsData = StoredJSON.encode(definition.blueprints)
            componentsData = StoredJSON.encode(definition.components)
            pocketsRaw = definition.pockets.map(\.rawValue)
            behaviorData = definition.behavior == .standard ? nil : StoredJSON.encode(definition.behavior)
            builtInVersion = isBuiltIn ? definition.version : 0
            updatedAt = Date()
        }

        /// What the category does in the binder.
        public var behavior: CategoryBehavior {
            get { StoredJSON.decode(CategoryBehavior.self, from: behaviorData) ?? .standard }
            set { behaviorData = newValue == .standard ? nil : StoredJSON.encode(newValue); updatedAt = Date() }
        }

        public var tint: TemplateTint {
            get { TemplateTint(rawValue: tintRaw) ?? .gray }
            set { tintRaw = newValue.rawValue }
        }

        public var heroStyle: HeroStyle {
            get { HeroStyle(rawValue: heroStyleRaw) ?? .standard }
            set { heroStyleRaw = newValue.rawValue }
        }

        public var sections: [FieldSection] {
            get { StoredJSON.decode([FieldSection].self, from: sectionsData) ?? [] }
            set { sectionsData = StoredJSON.encode(newValue); updatedAt = Date() }
        }

        public var blueprints: [ObligationBlueprint] {
            get { StoredJSON.decode([ObligationBlueprint].self, from: blueprintsData) ?? [] }
            set { blueprintsData = StoredJSON.encode(newValue); updatedAt = Date() }
        }

        public var components: [ComponentDefinition] {
            get { StoredJSON.decode([ComponentDefinition].self, from: componentsData) ?? [] }
            set { componentsData = StoredJSON.encode(newValue); updatedAt = Date() }
        }

        /// The pockets a section page shows, in the global order.
        public var pockets: [SectionPocket] {
            get { SectionPocket.ordered(pocketsRaw.compactMap(SectionPocket.init(rawValue:))) }
            set { pocketsRaw = SectionPocket.ordered(newValue).map(\.rawValue); updatedAt = Date() }
        }

        public var isCustom: Bool { !isBuiltIn }

        /// The plain definition, as archives and the catalog describe it.
        public var definition: TemplateDefinition {
            TemplateDefinition(
                key: key,
                name: name,
                summary: summary,
                symbol: symbol,
                tint: tint,
                heroStyle: heroStyle,
                isOnHomeByDefault: isOnHome,
                isSensitiveByDefault: isSensitive,
                sections: sections,
                blueprints: blueprints,
                components: components,
                pockets: pockets,
                behavior: behavior,
                version: builtInVersion
            )
        }
    }
}
