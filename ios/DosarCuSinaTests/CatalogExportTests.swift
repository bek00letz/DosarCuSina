import Foundation
import Testing
@testable import DosarCuSina

/// The built-in catalog (`BuiltInTemplates`), written to `shared/catalog/` as data, so the
/// Android app reads the same categories and never keeps a catalog of its own
/// (docs/ANDROID_PLAN.md, "How parity is kept", item 1). Six files, which
/// `shared/catalog/README.md` describes:
///
/// - `templates.json`: every built-in's definition, in the catalog's order and in the shape a
///   backup's `data/templates.json` gives it (shared/schemas/dosar-v3.md, "Template"), without
///   the household's choices (its place, whether it shows, its lock, its box, its times);
/// - `catalog.json`: what a backup doesn't carry: the catalog's version, each built-in's
///   defaults (on the binder, locked), and the keys earlier catalogs had (`replacedKeys`,
///   `retiredKeys`, `replacedFieldKeys`);
/// - `keys.json`: the built-in field, deadline and category keys code names
///   (`BuiltInFieldKeys.swift`, `SubscriptionFields`, `BuiltInTemplates.Key`);
/// - `ownCategories.json`: what a category of one's own is made of besides the answers to its
///   switches (`CategorySwitches`): the pockets it starts with, each way of counting a service
///   with its counter field and its service deadline, and „Recuperate” (`LostRecordsStep`);
/// - `household.json`: the household's own deadlines (`HouseholdRules.blueprints`);
/// - `documents.json`: what a personal document can be (`DocumentType`): its types, their
///   variants and the names they give, and the rules declared on them as data.
///
/// Fresh or failing, as `CopyMatrixTests` keeps docs/COPY_MATRIX.md: the test writes the files
/// again and fails when what is committed differs. A run that finds them out of date leaves
/// them made afresh in `TEST_RUNNER_CATALOG_OUT` (`tests/run_tests.sh` sets it to the run's
/// results, so a failed run on GitHub keeps them in its `test-results` as `catalog/`).
@Suite("Catalog export")
struct CatalogExportTests {
    /// The repository's root.
    static var repository: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The committed catalog.
    static var folder: URL { repository.appending(path: "shared/catalog") }

    static let writtenBy = "ios/DosarCuSinaTests/CatalogExportTests.swift"

    static let regenerate = """
    is out of date with the built-in catalog (BuiltInTemplates). Bring shared/catalog up to date: \
    a failed run on GitHub keeps the files made afresh in its test-results artifact, catalog/ \
    (copy them over shared/catalog/), or TEST_RUNNER_CATALOG_WRITE=1 ./tests/run_tests.sh \
    (or run CatalogExportTests in Xcode with CATALOG_WRITE=1 in the scheme's environment); review \
    the diff and commit it, then run the Android tests (./gradlew :catalog:test :archive:test in \
    android/), which read the same files.
    """

    static var writes: Bool { ProcessInfo.processInfo.environment["CATALOG_WRITE"] == "1" }

    /// Where a run that finds the files out of date leaves them as they should be.
    static var outOfDateGoesTo: URL? {
        ProcessInfo.processInfo.environment["CATALOG_OUT"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
    }

    @Test("shared/catalog is up to date with the built-in catalog")
    func catalogIsUpToDate() throws {
        let files = try Self.files()
        let manager = FileManager.default
        if Self.writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var outOfDate: [String] = []
        for (name, fresh) in files.sorted(by: { $0.key < $1.key }) {
            let url = Self.folder.appending(path: name)
            if Self.writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if committed != fresh { outOfDate.append(name) }
        }
        // A file nothing writes any more goes, so Android never reads an old catalog.
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && files[stale] == nil {
            if Self.writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by nothing any more and " + Self.regenerate))
            }
        }
        if !outOfDate.isEmpty, let out = Self.outOfDateGoesTo {
            try manager.createDirectory(at: out, withIntermediateDirectories: true)
            for (name, fresh) in files { try fresh.write(to: out.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate {
            Issue.record(Comment(rawValue: "shared/catalog/\(name) " + Self.regenerate))
        }
    }

    @Test("keys.json names every key the code names")
    func everyNamedKeyIsExported() throws {
        // Read from the sources, so a key added there and not here fails instead of going missing.
        for (type, keys) in Self.namedKeys {
            let source = try String(contentsOf: Self.repository.appending(path: type.file), encoding: .utf8)
            let declared = try Self.staticLets(in: source, enum: type.enumName)
            #expect(!declared.isEmpty, "No keys found for \(type.name) in \(type.file)")
            #expect(Set(keys.keys) == Set(declared), "keys.json's \(type.name) lists \(keys.keys.sorted()), \(type.file) declares \(declared.sorted())")
        }
    }

    @Test("Every built-in has one version, the catalog's")
    func oneVersion() {
        for definition in BuiltInTemplates.all {
            #expect(definition.version == TemplateDefinition.builtInCatalogVersion, "\(definition.key)")
        }
    }

    // MARK: The files

    /// Every file, by name, as it is written.
    static func files() throws -> [String: String] {
        [
            "templates.json": try render(BuiltInTemplates.all.map(CatalogTemplate.init)),
            "catalog.json": try render(Catalog()),
            "keys.json": try render(Keys()),
            "ownCategories.json": try render(OwnCategories()),
            "household.json": try render(Household()),
            "documents.json": try render(Documents()),
        ]
    }

    static func render<Value: Encodable>(_ value: Value) throws -> String {
        String(decoding: try MachineText.jsonEncoder(.readable).encode(value), as: UTF8.self) + "\n"
    }

    /// A built-in as a backup writes it (`DossierArchiveWriter.template`), without the household's
    /// choices and times: the same keys, the same encodings.
    struct CatalogTemplate: Encodable {
        var key: String
        var name: String
        var summary: String?
        var symbol: String
        var tint: String
        var heroStyle: String
        var isBuiltIn = true
        var version: Int
        var sections: KeptList<FieldSection>
        var blueprints: KeptList<ObligationBlueprint>
        var components: KeptList<ComponentDefinition>
        var pockets: [String]
        var behavior: KeptObject<CategoryBehavior>?

        init(_ definition: TemplateDefinition) {
            key = definition.key
            name = definition.name
            summary = definition.summary
            symbol = definition.symbol
            tint = definition.tint.rawValue
            heroStyle = definition.heroStyle.rawValue
            version = definition.version
            sections = KeptList(definition.sections)
            blueprints = KeptList(definition.blueprints)
            components = KeptList(definition.components)
            pockets = definition.pockets.map(\.rawValue)
            behavior = KeptObject(definition.behavior).omitted { $0 == .standard }
        }
    }

    /// What a backup doesn't carry and installing the built-ins reads (`TemplateStore.installBuiltIns`).
    struct Catalog: Encodable {
        struct Category: Encodable {
            var key: String
            var isOnHomeByDefault: Bool
            var isSensitiveByDefault: Bool
        }

        var builtInVersion = TemplateDefinition.builtInCatalogVersion
        /// In the catalog's order, the one new built-ins are installed in.
        var categories = BuiltInTemplates.all.map {
            Category(key: $0.key, isOnHomeByDefault: $0.isOnHomeByDefault, isSensitiveByDefault: $0.isSensitiveByDefault)
        }
        var replacedKeys = BuiltInTemplates.replacedKeys
        var replacedFieldKeys = BuiltInTemplates.replacedFieldKeys
        var retiredKeys = BuiltInTemplates.retiredKeys.sorted()
        var writtenBy = CatalogExportTests.writtenBy
    }

    /// The keys code names, by the type that names them.
    struct Keys: Encodable {
        var keys: [String: [String: String]] = Dictionary(
            CatalogExportTests.namedKeys.map { ($0.key.name, $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        var writtenBy = CatalogExportTests.writtenBy
    }

    /// What a category of one's own is made of besides the answers to its switches
    /// (`CategorySwitches`): the pockets every new one starts with, the field section a counter
    /// goes in, and for each way a service is counted, the interval it starts at, its counter field
    /// (none for a service by time) and its service deadline at that interval. The interval the
    /// person types is laid into the deadline by `CategorySwitches.serviceBlueprint`'s rule, which
    /// Android ports; the words and the rest of the deadline come from here.
    struct OwnCategories: Encodable {
        struct Counter: Encodable {
            var counter: String
            var defaultEvery: Int
            var field: FieldDefinition?
            var service: ObligationBlueprint
        }

        var basePockets = CategorySwitches.basePockets.map(\.rawValue)
        var counterSectionKey = CategorySwitches.counterSectionKey
        /// In `CategorySwitches.Counter`'s order, the one a category's service is read in.
        var counters = CategorySwitches.Counter.allCases.map { counter in
            Counter(counter: counter.rawValue, defaultEvery: counter.defaultEvery, field: CategorySwitches.counterField(counter),
                    service: CategorySwitches.serviceBlueprint(CategorySwitches.Service(counter)))
        }
        /// „Recuperate”, the category of one's own the repair list keeps records in whose section
        /// was deleted on another device (`LostRecordsStep`): one key and one section id on every
        /// device, and on both apps, so two devices that keep records there make one.
        var recovered = Recovered()
        var writtenBy = CatalogExportTests.writtenBy
    }

    struct Recovered: Encodable {
        var key = LostRecordsStep.categoryKey
        var name = LostRecordsStep.name
        var symbol = LostRecordsStep.symbol
        var pockets = LostRecordsStep.pockets.map(\.rawValue)
        var sectionID = LostRecordsStep.sectionID
    }

    /// What a personal document can be (`DocumentType`): its types in the order they are offered,
    /// each with its label and what else it is found by; their variants, each offered only for its
    /// type, with the name the document takes when it differs from the type's (`documentName`);
    /// what a document of no type is called; and what is declared on the types as data: which keep
    /// a back (`keepsBackSide`), how long one is valid after it is issued
    /// (`validityMonthsAfterIssue`, by type or variant), how long before its expiry it stops being
    /// good for travel (`travelMargins`), which are read only on the phone and which are shared
    /// with care.
    struct Documents: Encodable {
        struct Kind: Encodable {
            var key: String
            var label: String
            var aliases: [String]
        }

        struct Variant: Encodable {
            var type: String
            var key: String
            var label: String
            var documentName: String?
        }

        var typeFieldKey = DocumentType.typeFieldKey
        var variantFieldKey = DocumentType.variantFieldKey
        var types = DocumentType.options.map { Kind(key: $0.key, label: $0.label, aliases: $0.aliases) }
        var variants = DocumentType.variants.map {
            Variant(type: $0.type, key: $0.option.key, label: $0.option.label, documentName: $0.documentName)
        }
        var unnamed = DocumentType.unnamed
        var keepsBackSide = DocumentType.keepsBackSide.sorted()
        var validityMonthsAfterIssue = DocumentType.validityMonthsAfterIssue
        var travelMargins = DocumentType.travelMargins
        var readOnPhoneOnly = DocumentType.readOnPhoneOnly.sorted()
        var sharedWithCare = DocumentType.sharedWithCare.sorted()
        var writtenBy = CatalogExportTests.writtenBy
    }

    /// The household's own deadlines (`HouseholdRules.blueprints`): what a deadline with no
    /// section is made from, as `HouseholdRules.reconcile` makes it.
    struct Household: Encodable {
        var blueprints = HouseholdRules.blueprints
        var writtenBy = CatalogExportTests.writtenBy
    }

    // MARK: The named keys

    struct KeyType: Hashable {
        /// As keys.json names it: the Swift type.
        var name: String
        /// The enum that declares them, in `file`.
        var enumName: String
        var file: String
    }

    static let fieldKeysFile = "ios/DosarCuSina/Services/Templates/BuiltInFieldKeys.swift"

    /// Every key the code names, by the constant that names it. `everyNamedKeyIsExported` checks
    /// each list against its source, both ways.
    static let namedKeys: [KeyType: [String: String]] = [
        KeyType(name: "VehicleFields", enumName: "VehicleFields", file: fieldKeysFile): [
            "plate": VehicleFields.plate, "make": VehicleFields.make, "model": VehicleFields.model, "year": VehicleFields.year,
            "vin": VehicleFields.vin, "civ": VehicleFields.civ, "odometer": VehicleFields.odometer, "usage": VehicleFields.usage,
            "insurer": VehicleFields.insurer, "policyNumber": VehicleFields.policyNumber, "claimsPhone": VehicleFields.claimsPhone,
            "policyholder": VehicleFields.policyholder, "cascoInsurer": VehicleFields.cascoInsurer,
            "cascoPolicyNumber": VehicleFields.cascoPolicyNumber, "cascoClaimsPhone": VehicleFields.cascoClaimsPhone,
            "cascoInsuredSum": VehicleFields.cascoInsuredSum,
        ],
        KeyType(name: "HomeFields", enumName: "HomeFields", file: fieldKeysFile): [
            "address": HomeFields.address, "pod": HomeFields.pod, "clc": HomeFields.clc, "insurer": HomeFields.insurer,
            "policyNumber": HomeFields.policyNumber, "claimsPhone": HomeFields.claimsPhone, "insuredSum": HomeFields.insuredSum,
            "optionalInsurer": HomeFields.optionalInsurer, "optionalPolicyNumber": HomeFields.optionalPolicyNumber,
            "optionalClaimsPhone": HomeFields.optionalClaimsPhone, "optionalInsuredSum": HomeFields.optionalInsuredSum,
        ],
        KeyType(name: "DocumentFields", enumName: "DocumentFields", file: fieldKeysFile): [
            "number": DocumentFields.number, "personalNumber": DocumentFields.personalNumber, "birthDate": DocumentFields.birthDate,
            "sex": DocumentFields.sex, "nationality": DocumentFields.nationality, "categories": DocumentFields.categories,
            "issuer": DocumentFields.issuer, "issueDate": DocumentFields.issueDate, "expiry": DocumentFields.expiry,
            "recordResult": DocumentFields.recordResult, "cardNetwork": DocumentFields.cardNetwork,
            "cardLastFour": DocumentFields.cardLastFour, "vehiclePlate": DocumentFields.vehiclePlate,
        ],
        KeyType(name: "MemberFields", enumName: "MemberFields", file: fieldKeysFile): [
            "bonusMalus": MemberFields.bonusMalus, "citizenship": MemberFields.citizenship,
        ],
        KeyType(name: "PetFields", enumName: "PetFields", file: fieldKeysFile): [
            "microchip": PetFields.microchip, "passport": PetFields.passport,
        ],
        KeyType(name: "PurchaseFieldKeys", enumName: "PurchaseFieldKeys", file: fieldKeysFile): [
            "model": PurchaseFieldKeys.model, "serial": PurchaseFieldKeys.serial,
            "warrantyMonths": PurchaseFieldKeys.warrantyMonths, "warrantyUntil": PurchaseFieldKeys.warrantyUntil,
        ],
        KeyType(name: "BuiltInBlueprints", enumName: "BuiltInBlueprints", file: fieldKeysFile): [
            "vehicleITP": BuiltInBlueprints.vehicleITP, "vehicleRCA": BuiltInBlueprints.vehicleRCA,
            "vehicleCASCO": BuiltInBlueprints.vehicleCASCO, "vehicleVignette": BuiltInBlueprints.vehicleVignette,
            "homePAD": BuiltInBlueprints.homePAD, "homeInsurance": BuiltInBlueprints.homeInsurance,
            "homeBoilerCheck": BuiltInBlueprints.homeBoilerCheck, "homeGasCheck": BuiltInBlueprints.homeGasCheck,
            "homeGasRevision": BuiltInBlueprints.homeGasRevision, "documentRenew": BuiltInBlueprints.documentRenew,
            "petRabies": BuiltInBlueprints.petRabies, "petVaccine": BuiltInBlueprints.petVaccine,
            "warrantyEnds": BuiltInBlueprints.warrantyEnds, "healthEUCard": BuiltInBlueprints.healthEUCard,
        ],
        KeyType(name: "SubscriptionFields", enumName: "SubscriptionFields", file: "ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift"): [
            "provider": SubscriptionFields.provider, "service": SubscriptionFields.service, "group": SubscriptionFields.group,
            "price": SubscriptionFields.price, "cycle": SubscriptionFields.cycle, "clientCode": SubscriptionFields.clientCode,
            "contractNumber": SubscriptionFields.contractNumber, "account": SubscriptionFields.account,
            "pod": SubscriptionFields.pod, "clc": SubscriptionFields.clc, "placeCode": SubscriptionFields.placeCode,
            "phoneNumber": SubscriptionFields.phoneNumber, "startDate": SubscriptionFields.startDate,
            "minimumMonths": SubscriptionFields.minimumMonths, "minimumUntil": SubscriptionFields.minimumUntil,
            "directDebit": SubscriptionFields.directDebit, "lastBill": SubscriptionFields.lastBill,
            "minimumEndsBlueprint": SubscriptionFields.minimumEndsBlueprint, "billBlueprint": SubscriptionFields.billBlueprint,
        ],
        KeyType(name: "BuiltInTemplates.Key", enumName: "Key", file: "ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift"): [
            "vehicle": BuiltInTemplates.Key.vehicle, "home": BuiltInTemplates.Key.home, "documents": BuiltInTemplates.Key.documents,
            "pet": BuiltInTemplates.Key.pet, "health": BuiltInTemplates.Key.health, "purchase": BuiltInTemplates.Key.purchase,
            "subscription": BuiltInTemplates.Key.subscription, "other": BuiltInTemplates.Key.other, "bike": BuiltInTemplates.Key.bike,
            "plants": BuiltInTemplates.Key.plants, "tenancy": BuiltInTemplates.Key.tenancy, "member": BuiltInTemplates.Key.member,
            "espresso": BuiltInTemplates.Key.espresso,
        ],
    ]

    struct NoSuchEnum: Error { let name: String }

    /// The names of the `static let`s an enum declares in `source`, read as text: from its
    /// `enum Name {` line to the closing brace at the same indentation.
    static func staticLets(in source: String, enum name: String) throws -> [String] {
        let lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix("enum \(name) {") }) else {
            throw NoSuchEnum(name: name)
        }
        let indent = String(lines[start].prefix { $0 == " " })
        var names: [String] = []
        for line in lines[(start + 1)...] {
            if line == indent + "}" { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["public static let ", "static let "] where trimmed.hasPrefix(prefix) {
                let rest = trimmed.dropFirst(prefix.count)
                names.append(String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }))
                break
            }
        }
        return names
    }
}
