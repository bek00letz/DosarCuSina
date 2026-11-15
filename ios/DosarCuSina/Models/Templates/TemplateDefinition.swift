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

/// Whether a category's sections each get a box on the Dosar grid or share one. The catalog
/// says which a category starts with (`CategoryBehavior.defaultGrouping`); the person can choose
/// the other for each category (`CategoryTemplate.chosenGrouping`). Raw values are part of the
/// `.dosar` contract.
public enum BoxGrouping: String, Codable, Sendable, CaseIterable {
    /// One box per section: the car, the other car.
    case separate
    /// One box for all of the category's sections, which opens to their list ("Mașini").
    case grouped

    /// The one rule for what the person is offered for a category: the other choice, or nil.
    /// Grouping is offered once its sections have boxes of their own and it has two or more;
    /// splitting a grouped box again is always offered, so there is always a way back.
    public static func offer(for behavior: CategoryBehavior, now current: BoxGrouping, sections: Int) -> BoxGrouping? {
        guard behavior.offersGrouping else { return nil }
        if current == .grouped { return .separate }
        return sections >= 2 ? .grouped : nil
    }
}

/// What a category's sections are called when they are counted ("3 mașini"), as data, so the
/// count of a grouped box reads in the category's own words. A category without one, or with
/// one from a newer version, counts them as sections ("3 secțiuni"). Raw values are part of the
/// `.dosar` contract; the words are in `BoxStatus.count(_:of:)`.
public enum SectionNoun: String, Codable, Sendable, CaseIterable {
    case car, home, pet, bike, plant, espressoMachine
}

/// What a category does in the binder, as data, so a custom category can behave like
/// Acte or Garanții and no screen asks which built-in it is. Raw values are part of the
/// `.dosar` contract; a value from a newer version reads as the default, the one that hides
/// nothing (a box per section, a plain list, no part), and stays stored as it was written
/// until the person changes it (`CategoryTemplate.behavior`, through `KeptObject`).
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
    /// Whether its sections start in one box or one each, when its box is `perSection`; nil reads
    /// as `.separate`. The person's choice for the category wins (`CategoryTemplate.grouping`).
    public var defaultGrouping: BoxGrouping?
    /// What its sections are called when counted ("3 plante"); nil counts them as sections.
    public var sectionNoun: SectionNoun?
    /// Its sections may be filed under a section of the category that plays this part, or stand
    /// on their own: a subscription under a home or a phone plan alone, a plant on a home's sill
    /// or on its own. "Mută la…" offers the sections that play it, and standing on its own.
    public var mayBelongTo: Role?
    /// A new section goes under the household's only section of the `mayBelongTo` part by itself
    /// (the only home); with none or several it stands on its own until the person moves it.
    public var goesUnderTheOnlyOne: Bool
    /// How its visits read and what they are ("Am fost la service"); nil reads as
    /// `VisitWording.standard`. Read it through `visitWording`.
    public var visit: VisitWording?
    /// Its option in "Adaugă o secțiune", one thing rather than the category ("Mașină",
    /// not "Mașini"); nil shows the category's name. Read it through `offerTitle(name:)`.
    public var offerTitle: String?
    /// Its place among the ones most households start with ("Cele mai des folosite"),
    /// from 1; nil lists it with the other ready-made ones.
    public var shortlistOrder: Int?

    public init(box: Box = .perSection, listing: Listing = .plain, role: Role? = nil, parentPocket: SectionPocket? = nil, addedOnlyUnderParent: Bool = false,
                defaultGrouping: BoxGrouping? = nil, sectionNoun: SectionNoun? = nil, mayBelongTo: Role? = nil, goesUnderTheOnlyOne: Bool = false,
                visit: VisitWording? = nil, offerTitle: String? = nil, shortlistOrder: Int? = nil) {
        self.box = box
        self.listing = listing
        self.role = role
        self.parentPocket = parentPocket
        self.addedOnlyUnderParent = addedOnlyUnderParent
        self.defaultGrouping = defaultGrouping
        self.sectionNoun = sectionNoun
        self.mayBelongTo = mayBelongTo
        self.goesUnderTheOnlyOne = goesUnderTheOnlyOne
        self.visit = visit
        self.offerTitle = offerTitle
        self.shortlistOrder = shortlistOrder
    }

    /// Any category the person makes: a box per section, a plain list.
    public static let standard = CategoryBehavior()

    /// Whether its sections get boxes of their own on the Dosar grid.
    public var hasSectionBoxes: Bool { box == .perSection }

    /// Whether the person can choose between one box per section and one box for them all: only
    /// a category whose sections have boxes of their own. A category with one box (Acte) or none
    /// (tenants) keeps it.
    public var offersGrouping: Bool { hasSectionBoxes }

    /// How its visits read: its own wording, else the standard one.
    public var visitWording: VisitWording { visit ?? .standard }

    /// Its option's title in "Adaugă o secțiune": its own, else the category's `name`.
    public func offerTitle(name: String) -> String {
        guard let offerTitle, !offerTitle.isEmpty else { return name }
        return offerTitle
    }

    private enum CodingKeys: String, CodingKey {
        case box, listing, role, parentPocket, addedOnlyUnderParent, defaultGrouping, sectionNoun, mayBelongTo, goesUnderTheOnlyOne, visit, offerTitle, shortlistOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = (try? c.decodeIfPresent(String.self, forKey: .box)).flatMap { $0.flatMap(Box.init(rawValue:)) } ?? .perSection
        listing = (try? c.decodeIfPresent(String.self, forKey: .listing)).flatMap { $0.flatMap(Listing.init(rawValue:)) } ?? .plain
        role = (try? c.decodeIfPresent(String.self, forKey: .role)).flatMap { $0.flatMap(Role.init(rawValue:)) }
        parentPocket = (try? c.decodeIfPresent(String.self, forKey: .parentPocket)).flatMap { $0.flatMap(SectionPocket.init(rawValue:)) }
        addedOnlyUnderParent = (try? c.decodeIfPresent(Bool.self, forKey: .addedOnlyUnderParent)).flatMap { $0 } ?? false
        defaultGrouping = (try? c.decodeIfPresent(String.self, forKey: .defaultGrouping)).flatMap { $0.flatMap(BoxGrouping.init(rawValue:)) }
        sectionNoun = (try? c.decodeIfPresent(String.self, forKey: .sectionNoun)).flatMap { $0.flatMap(SectionNoun.init(rawValue:)) }
        mayBelongTo = (try? c.decodeIfPresent(String.self, forKey: .mayBelongTo)).flatMap { $0.flatMap(Role.init(rawValue:)) }
        goesUnderTheOnlyOne = (try? c.decodeIfPresent(Bool.self, forKey: .goesUnderTheOnlyOne)).flatMap { $0 } ?? false
        visit = (try? c.decodeIfPresent(VisitWording.self, forKey: .visit)).flatMap { $0 }
        offerTitle = (try? c.decodeIfPresent(String.self, forKey: .offerTitle)).flatMap { $0 }
        shortlistOrder = (try? c.decodeIfPresent(Int.self, forKey: .shortlistOrder)).flatMap { $0 }
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
    public static let builtInCatalogVersion = 17

    public static let customKeyPrefix = "custom."

    public static func newCustomKey() -> String {
        customKeyPrefix + UUID().uuidString.lowercased()
    }
}
