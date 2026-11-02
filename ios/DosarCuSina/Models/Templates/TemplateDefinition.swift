import Foundation

/// Which hero layout the asset screen uses for a template. Mainstay categories
/// get a purpose-built hero; everything else uses `standard`, built from field roles.
///
/// Raw values are part of the `.dosar` contract.
public enum HeroStyle: String, Codable, CaseIterable, Sendable {
    /// Plate badge, make, model, year and odometer.
    case vehicle
    /// Address and the meter-reading window.
    case home
    /// Expiry ring and "valid until".
    case document
    /// Photo, age and weight trend.
    case pet
    /// Name, identifier and the next obligation.
    case standard
}

/// A named accent for a category. Screens map it to a semantic color; storing a
/// name keeps dark mode and contrast in the design system, not in the data.
///
/// Raw values are part of the `.dosar` contract.
public enum TemplateTint: String, Codable, CaseIterable, Sendable {
    case blue, orange, pink, brown, indigo, teal, purple, green, red, yellow, mint, cyan, gray
}

/// The plain description of a category template: what the built-in catalog
/// declares, what `.dosar` archives carry, and what `CategoryTemplate` stores.
public struct TemplateDefinition: Hashable, Sendable, Codable, Identifiable {
    /// Stable key: `vehicle`, `home`, … for built-ins, `custom.<uuid>` for user templates.
    public var key: String
    public var name: String
    /// One line shown when picking a template.
    public var summary: String?
    public var symbol: String
    public var tint: TemplateTint
    public var heroStyle: HeroStyle
    /// Whether new installs show this category on the home screen.
    public var isOnHomeByDefault: Bool
    /// Whether the category asks for Face ID by default.
    public var isSensitiveByDefault: Bool
    public var sections: [FieldSection]
    public var blueprints: [ObligationBlueprint]
    /// Parts and jobs the history can track for assets of this category.
    public var components: [ComponentDefinition]
    /// The pockets a section page of this category shows, in the global order.
    public var pockets: [SectionPocket]
    /// Bumped when a built-in definition changes, so installed copies get upgraded.
    public var version: Int

    public var id: String { key }

    public init(
        key: String,
        name: String,
        summary: String? = nil,
        symbol: String,
        tint: TemplateTint,
        heroStyle: HeroStyle = .standard,
        isOnHomeByDefault: Bool = true,
        isSensitiveByDefault: Bool = false,
        sections: [FieldSection],
        blueprints: [ObligationBlueprint] = [],
        components: [ComponentDefinition] = [],
        pockets: [SectionPocket] = SectionPocket.standard,
        version: Int = TemplateDefinition.builtInCatalogVersion
    ) {
        self.components = components
        self.pockets = SectionPocket.ordered(pockets)
        self.key = key
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.tint = tint
        self.heroStyle = heroStyle
        self.isOnHomeByDefault = isOnHomeByDefault
        self.isSensitiveByDefault = isSensitiveByDefault
        self.sections = sections
        self.blueprints = blueprints
        self.version = version
    }

    public var allFields: [FieldDefinition] { sections.flatMap(\.fields) }

    public func field(_ key: String) -> FieldDefinition? {
        allFields.first { $0.key == key }
    }

    public func fields(withRole role: FieldRole) -> [FieldDefinition] {
        allFields.filter { $0.role == role }
    }

    public func field(withRole role: FieldRole) -> FieldDefinition? {
        allFields.first { $0.role == role }
    }

    /// What the asset's top card shows, in order: identifiers, document numbers, then key facts.
    public var keyFactFields: [FieldDefinition] {
        let order: [FieldRole] = [.identifier, .documentNumber, .keyFact]
        return order.flatMap { fields(withRole: $0) }
    }

    /// Revision of the built-in catalog. Bump it whenever a built-in definition
    /// changes so installed copies are upgraded (preferences are kept).
    public static let builtInCatalogVersion = 2

    public static let customKeyPrefix = "custom."

    public static func newCustomKey() -> String {
        customKeyPrefix + UUID().uuidString.lowercased()
    }
}
