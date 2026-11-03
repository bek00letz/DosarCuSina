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

/// What a category does in the binder, as data, so a custom category can behave like
/// Acte or Garanții and no screen asks which built-in it is. Raw values are part of the
/// `.dosar` contract; a value from a newer version reads as the default.
public struct CategoryBehavior: Hashable, Sendable, Codable {
    /// How the category shows on the Dosar grid.
    public enum Box: String, Codable, Sendable {
        /// One box per top-level section: the car, the flat, PawPaw.
        case perSection
        /// One box for the whole category, which gathers many small records: Acte, Garanții, Abonamente.
        case wholeCategory
        /// No box: its sections live inside another one (tenants in a home, people in Acte).
        case insideOther
    }

    /// What the category's own page lists.
    public enum Listing: String, Codable, Sendable {
        case plain
        /// Grouped by the person they belong to (Acte).
        case byHolder
        /// Still covered first, then the ones whose warranty ended (Garanții).
        case byWarranty
        /// With what they cost a month (Abonamente).
        case byMonthlyCost
    }

    /// The part a category plays for other categories.
    public enum Role: String, Codable, Sendable {
        /// A person things are filed under: their personal documents (a household member).
        case holder
        /// A personal document of a holder: an identity card, a passport.
        case personalDocument
        /// An ongoing contract that bills and contracts file into.
        case subscription
        /// A place the ongoing contracts tied to an address live under (a home).
        case home
    }

    public var box: Box
    public var listing: Listing
    public var role: Role?
    /// The pocket of a parent's page its sections show in (tenants, products, subscriptions).
    public var parentPocket: SectionPocket?
    /// Its sections are only added under another section, never on their own (a tenancy).
    public var addedOnlyUnderParent: Bool

    public init(box: Box = .perSection, listing: Listing = .plain, role: Role? = nil, parentPocket: SectionPocket? = nil, addedOnlyUnderParent: Bool = false) {
        self.box = box
        self.listing = listing
        self.role = role
        self.parentPocket = parentPocket
        self.addedOnlyUnderParent = addedOnlyUnderParent
    }

    /// Any category the person makes: a box per section, a plain list.
    public static let standard = CategoryBehavior()

    /// Whether its sections get boxes of their own on the Dosar grid.
    public var hasSectionBoxes: Bool { box == .perSection }

    private enum CodingKeys: String, CodingKey { case box, listing, role, parentPocket, addedOnlyUnderParent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = (try? c.decodeIfPresent(String.self, forKey: .box)).flatMap { $0.flatMap(Box.init(rawValue:)) } ?? .perSection
        listing = (try? c.decodeIfPresent(String.self, forKey: .listing)).flatMap { $0.flatMap(Listing.init(rawValue:)) } ?? .plain
        role = (try? c.decodeIfPresent(String.self, forKey: .role)).flatMap { $0.flatMap(Role.init(rawValue:)) }
        parentPocket = (try? c.decodeIfPresent(String.self, forKey: .parentPocket)).flatMap { $0.flatMap(SectionPocket.init(rawValue:)) }
        addedOnlyUnderParent = (try? c.decodeIfPresent(Bool.self, forKey: .addedOnlyUnderParent)).flatMap { $0 } ?? false
    }
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
    /// What the category does in the binder: its box, its list, its part for other categories.
    public var behavior: CategoryBehavior
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
        behavior: CategoryBehavior = .standard,
        version: Int = TemplateDefinition.builtInCatalogVersion
    ) {
        self.behavior = behavior
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
    public static let builtInCatalogVersion = 13

    public static let customKeyPrefix = "custom."

    public static func newCustomKey() -> String {
        customKeyPrefix + UUID().uuidString.lowercased()
    }
}
