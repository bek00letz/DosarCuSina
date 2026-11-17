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

/// What one section of a category is called, as one thing rather than the category („Mașina”,
/// not „Mașini”), and the gender of that noun, for the words that agree with it („Dacă o
/// păstrezi” for a car). A new section's name before anything is typed, and the name it gets
/// when the person leaves it empty, are this (`AddSectionModel.suggestedName`), never the
/// category's name. A built-in declares it (`CategoryBehavior.singular`, with no default); a
/// category of one's own is named as one thing already („Barca, Rulota, Pianul”), so its
/// sections take its name (`TemplateDefinition.sectionName`) and no gender is guessed for it:
/// what agrees with a section's gender is only ever said of a built-in's. Part of the `.dosar` contract:
/// `{"name": "Mașina", "gender": "feminine"}`.
public struct SectionSingular: Codable, Hashable, Sendable {
    /// One section, with its article, as a name in the binder: „Mașina”, „Actul”.
    public var name: String
    public var gender: GrammaticalGender

    public init(_ name: String, _ gender: GrammaticalGender) {
        self.name = name
        self.gender = gender
    }

    private enum CodingKeys: String, CodingKey { case name, gender }

    /// A gender this build doesn't know (from a newer one) reads as Romanian's default for a
    /// thing and keeps the name; the stored text stays as written (`KeptObject`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        gender = GrammaticalGender(stored: try? c.decodeIfPresent(String.self, forKey: .gender))
    }
}

/// Grammatical gender of the noun one section of a category is, for words that agree with it
/// (`SectionSingular`). Raw values are part of the `.dosar` contract.
public enum GrammaticalGender: String, Codable, Sendable, Hashable {
    /// Mașina, locuința, persoana.
    case feminine
    /// Actul, abonamentul, animalul. Romanian's default for a thing.
    case masculineOrNeuter

    /// A stored value: unknown or missing reads as Romanian's default for a thing.
    public init(stored raw: String?) {
        self = raw.flatMap(GrammaticalGender.init(rawValue:)) ?? .masculineOrNeuter
    }
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
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// A person things are filed under: their personal documents (a household member).
        case holder
        /// A personal document of a holder: an identity card, a passport.
        case personalDocument
        /// An ongoing contract that bills and contracts file into.
        case subscription
        /// A place the ongoing contracts tied to an address live under (a home).
        case home
        /// A vehicle the household keeps (a car). Catalog 18.
        case vehicle

        /// The parts another category's sections can say they belong to ("Ține de…": a home, a
        /// car, a person), in the order a category of one's own offers them. Which of them a
        /// binder offers is what its categories play (`CategorySwitches.belongingChoices`).
        public static let parents: [Role] = [.home, .vehicle, .holder]

        /// Whether sections of other categories can be filed under a section that plays it.
        public var holdsSections: Bool { Self.parents.contains(self) }
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
    /// or on its own, a category of one's own under a car ("Ține de…"). "Mută la…" offers the
    /// sections that play it, and standing on its own. On the parent's page they show in the
    /// catalog's pocket (`parentPocket`), else in a pocket of their own named after the category
    /// (`hasPocketOfItsOwn`).
    public var mayBelongTo: Role?
    /// A new section goes under the household's only section of the `mayBelongTo` part by itself
    /// (the only home); with none or several it stands on its own until the person moves it.
    public var goesUnderTheOnlyOne: Bool
    /// What its visits are, and so what the visit form asks and says (`VisitKind.shape`): a
    /// service, a job, a repair, a doctor's or a vet's visit, a note, or none. Every category says
    /// it; there is no default. A stored behaviour without one reads as none (`VisitKind(stored:)`).
    public var visit: VisitKind
    /// Its option in "Adaugă o secțiune", one thing rather than the category ("Mașină",
    /// not "Mașini"); nil shows the category's name. Read it through `offerTitle(name:)`.
    public var offerTitle: String?
    /// Its place among the ones most households start with ("Cele mai des folosite"),
    /// from 1; nil lists it with the other ready-made ones.
    public var shortlistOrder: Int?
    /// What one of its sections is called („Mașina”) and that noun's gender. Every built-in
    /// declares it (there is no default); nil for a category of one's own, whose sections take
    /// its name (`TemplateDefinition.sectionName`).
    public var singular: SectionSingular?

    public init(box: Box = .perSection, listing: Listing = .plain, role: Role? = nil, parentPocket: SectionPocket? = nil, addedOnlyUnderParent: Bool = false,
                defaultGrouping: BoxGrouping? = nil, sectionNoun: SectionNoun? = nil, mayBelongTo: Role? = nil, goesUnderTheOnlyOne: Bool = false,
                visit: VisitKind, offerTitle: String? = nil, shortlistOrder: Int? = nil, singular: SectionSingular?) {
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
        self.singular = singular
    }

    /// Any category the person makes, before its switches: a box per section, a plain list, no
    /// visits (`CategorySwitches` gives it the kind „Are revizii sau lucrări” says), its sections
    /// named after it.
    public static let standard = CategoryBehavior(visit: .none, singular: nil)

    /// Whether its sections get boxes of their own on the Dosar grid.
    public var hasSectionBoxes: Bool { box == .perSection }

    /// Whether its sections, filed under a section of the part they may belong to, show on that
    /// section's page in a pocket named after the category (`PagePocket.category`) rather than in
    /// one of the catalog's (`parentPocket`): a category of one's own that says "Ține de…".
    public var hasPocketOfItsOwn: Bool { mayBelongTo != nil && parentPocket == nil }

    /// Whether the person can choose between one box per section and one box for them all: only
    /// a category whose sections have boxes of their own. A category with one box (Acte) or none
    /// (tenants) keeps it.
    public var offersGrouping: Bool { hasSectionBoxes }

    /// Its option's title in "Adaugă o secțiune": its own, else the category's `name`.
    public func offerTitle(name: String) -> String {
        guard let offerTitle, !offerTitle.isEmpty else { return name }
        return offerTitle
    }

    private enum CodingKeys: String, CodingKey {
        case box, listing, role, parentPocket, addedOnlyUnderParent, defaultGrouping, sectionNoun, mayBelongTo, goesUnderTheOnlyOne, visit, offerTitle, shortlistOrder,
             singular
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
        visit = VisitKind(stored: (try? c.decodeIfPresent(JSONValue.self, forKey: .visit)).flatMap { $0 })
        offerTitle = (try? c.decodeIfPresent(String.self, forKey: .offerTitle)).flatMap { $0 }
        shortlistOrder = (try? c.decodeIfPresent(Int.self, forKey: .shortlistOrder)).flatMap { $0 }
        singular = (try? c.decodeIfPresent(SectionSingular.self, forKey: .singular)).flatMap { $0 }
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
        behavior: CategoryBehavior,
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

    /// What one of its sections is called: what a built-in declares, else (a category of one's
    /// own, named as one thing already) the category's name.
    public var sectionName: String {
        if let singular = behavior.singular, !singular.name.isEmpty { return singular.name }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
    public static let builtInCatalogVersion = 24

    public static let customKeyPrefix = "custom."

    public static func newCustomKey() -> String {
        customKeyPrefix + UUID().uuidString.lowercased()
    }
}
