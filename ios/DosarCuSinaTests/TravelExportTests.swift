import Foundation
import Testing
@testable import DosarCuSina

/// What a traveller carries, written to `shared/travel/` as data, so the Android app's trip
/// check reads the same rules and never keeps a country, a document rule or a key of its own
/// (docs/ANDROID_PLAN.md, "How parity is kept", item 1). Three files, which
/// `shared/travel/README.md` describes:
///
/// - `rules.json`: what each citizenship group carries in each region (`TravelRules`), the
///   citizenships whose identity card a region takes, with where the rule comes from, where the
///   health card and the visa are checked, and the keys the readiness checks read;
/// - `countries.json`: the countries a person can be a citizen of (`Citizenship`), in the
///   choice's order, with their codes, their Romanian names, what documents print for them and
///   whether their citizens move freely in the EU;
/// - `documents.json`: the document types (`DocumentType`) as the checks read them, with their
///   travel data: the travel margin, the kinds that are no travel document, the last day a
///   kind is good for travel.
///
/// Fresh or failing, as `CatalogExportTests` keeps `shared/catalog/`: a run that finds the files
/// out of date leaves them made afresh in `TEST_RUNNER_TRAVEL_OUT` (`tests/run_tests.sh` sets it
/// to the run's results, so a failed run on GitHub keeps them in its `test-results` as `travel/`).
@Suite("Travel export")
struct TravelExportTests {
    static var folder: URL { CatalogExportTests.repository.appending(path: "shared/travel") }

    static let writtenBy = "ios/DosarCuSinaTests/TravelExportTests.swift"

    static let regenerate = """
    is out of date with the travel rules (TravelRules, Citizenship, DocumentType). Bring shared/travel up to date: \
    a failed run on GitHub keeps the files made afresh in its test-results artifact, travel/ (copy them over \
    shared/travel/), or TEST_RUNNER_TRAVEL_WRITE=1 ./tests/run_tests.sh (or run TravelExportTests in Xcode with \
    TRAVEL_WRITE=1 in the scheme's environment); review the diff and commit it, then run the Android tests \
    (./gradlew :core:test :catalog:test in android/), which read the same files.
    """

    static var writes: Bool { ProcessInfo.processInfo.environment["TRAVEL_WRITE"] == "1" }

    static var outOfDateGoesTo: URL? {
        ProcessInfo.processInfo.environment["TRAVEL_OUT"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
    }

    @Test("shared/travel is up to date with the travel rules")
    func travelIsUpToDate() throws {
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
            Issue.record(Comment(rawValue: "shared/travel/\(name) " + Self.regenerate))
        }
    }

    @Test("Every requirement a table uses is written, and every group and region has its row")
    func everyRuleIsWritten() {
        for group in Citizenship.Group.allCases {
            for region in TripPlan.Region.allCases {
                #expect(TravelRules.table[group]?[region] != nil, "\(group) in \(region)")
            }
        }
        for requirement in TravelRules.table.values.flatMap(\.values).flatMap({ $0 }) + TravelRules.identityCards.values.map(\.requirement) {
            #expect(TravelRules.allRequirements.contains(requirement))
        }
    }

    @Test("The countries are the citizenship field's choice, in its order")
    func countriesAreTheChoice() {
        let member = BuiltInTemplates.all.first { $0.key == BuiltInTemplates.Key.member }
        let field = member?.sections.flatMap(\.fields).first { $0.key == MemberFields.citizenship }
        #expect(field?.options?.map(\.key) == Citizenship.options.map(\.key))
    }

    // MARK: The files

    static func files() throws -> [String: String] {
        [
            "rules.json": try render(rules()),
            "countries.json": try render(countries()),
            "documents.json": try render(documents()),
        ]
    }

    static func render(_ value: JSONValue) throws -> String {
        String(decoding: try MachineText.jsonEncoder(.readable).encode(value), as: UTF8.self) + "\n"
    }

    static func strings(_ values: some Sequence<String>) -> JSONValue { .array(values.map(JSONValue.string)) }

    static func requirement(_ requirement: TravelRequirement) -> JSONValue {
        .object([
            "need": .string(requirement.need.rawValue),
            "accepted": strings(requirement.accepted),
            "countsTravelCutoff": .bool(requirement.countsTravelCutoff),
            "monthsValidAfterReturn": .int(requirement.monthsValidAfterReturn),
        ])
    }

    /// Every key the readiness checks read, by the Swift constant that names it (keys.json's shape).
    static let reads: [String: [String: String]] = [
        "DocumentFields": [
            "expiry": DocumentFields.expiry, "nationality": DocumentFields.nationality, "vehiclePlate": DocumentFields.vehiclePlate,
            "personalNumber": DocumentFields.personalNumber,
        ],
        "VehicleFields": ["plate": VehicleFields.plate, "civ": VehicleFields.civ, "vin": VehicleFields.vin],
        "PetFields": ["passport": PetFields.passport],
        "MemberFields": ["citizenship": MemberFields.citizenship, "bonusMalus": MemberFields.bonusMalus],
        "BuiltInBlueprints": [
            "vehicleRCA": BuiltInBlueprints.vehicleRCA, "vehicleITP": BuiltInBlueprints.vehicleITP,
            "vehicleVignette": BuiltInBlueprints.vehicleVignette, "vehicleCASCO": BuiltInBlueprints.vehicleCASCO,
            "homePAD": BuiltInBlueprints.homePAD, "homeInsurance": BuiltInBlueprints.homeInsurance,
            "petRabies": BuiltInBlueprints.petRabies, "healthEUCard": BuiltInBlueprints.healthEUCard,
        ],
        "BuiltInTemplates.Key": ["vehicle": BuiltInTemplates.Key.vehicle, "pet": BuiltInTemplates.Key.pet],
        "DocumentType": [
            "idCard": DocumentType.idCard, "passport": DocumentType.passport, "residencePermit": DocumentType.residencePermit,
            "drivingLicence": DocumentType.drivingLicence, "euHealthCard": DocumentType.euHealthCard, "greenCard": DocumentType.greenCard,
        ],
        "ObligationKind": [
            "insurance": ObligationKind.insurance.rawValue, "tax": ObligationKind.tax.rawValue, "payment": ObligationKind.payment.rawValue,
        ],
        "DocumentKind": ["invoice": DocumentKind.invoice.rawValue, "policy": DocumentKind.policy.rawValue],
        "BlueprintFactRole": Dictionary(BlueprintFactRole.allCases.map { ($0.rawValue, $0.rawValue) }, uniquingKeysWith: { first, _ in first }),
    ]

    static func rules() -> JSONValue {
        let byGroup = Citizenship.Group.allCases.map { group -> (String, JSONValue) in
            (group.rawValue, .object(Dictionary(TripPlan.Region.allCases.map { region in
                (region.rawValue, JSONValue.array(TravelRules.requirements(for: group, in: region).map(requirement)))
            }, uniquingKeysWith: { first, _ in first })))
        }
        let identityCards = TripPlan.Region.allCases.compactMap { region -> JSONValue? in
            guard let cards = TravelRules.identityCards[region] else { return nil }
            return .object([
                "region": .string(region.rawValue),
                "citizens": strings(cards.citizens.sorted()),
                "requirement": requirement(cards.requirement),
                "source": .string(cards.source),
            ])
        }
        return .object([
            "groups": strings(Citizenship.Group.allCases.map(\.rawValue)),
            "regions": strings(TripPlan.Region.allCases.map(\.rawValue)),
            "byGroup": .object(Dictionary(byGroup, uniquingKeysWith: { first, _ in first })),
            "identityCards": .array(identityCards),
            "healthCardRegions": strings(TripPlan.Region.allCases.filter { TravelRules.checksHealthCard(in: $0) }.map(\.rawValue)),
            "visaRegions": strings(TripPlan.Region.allCases.filter { TravelRules.remindsOfVisa(in: $0) }.map(\.rawValue)),
            "petRabiesWaitDays": .int(ReadinessEngine.rabiesWaitDays),
            "reads": .object(reads.mapValues { .object($0.mapValues(JSONValue.string)) }),
            "writtenBy": .string(writtenBy),
        ])
    }

    static func countries() -> JSONValue {
        let byCode = Dictionary(Citizenship.countries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let options = Citizenship.options.map { option -> JSONValue in
            var entry: [String: JSONValue] = ["key": .string(option.key), "label": .string(option.label), "aliases": strings(option.aliases)]
            if let country = byCode[option.key] {
                entry["code"] = .string(country.code)
                entry["printedCode"] = .string(country.printedCode)
                entry["otherCodes"] = strings(country.otherCodes)
                entry["movesFreely"] = .bool(country.movesFreely)
            }
            return .object(entry)
        }
        return .object([
            "keyPrefix": .string(Citizenship.key("")),
            "stateless": .string(Citizenship.stateless),
            "statelessCodes": strings(Citizenship.statelessCodes),
            "options": .array(options),
            "freeMovement": strings(Citizenship.freeMovement.sorted()),
            "writtenBy": .string(writtenBy),
        ])
    }

    static func documents() -> JSONValue {
        let types = DocumentType.options.map { option -> JSONValue in
            .object([
                "key": .string(option.key), "label": .string(option.label), "aliases": strings(option.aliases),
                "travelMarginDays": .int(DocumentType.travelMargins[option.key] ?? 0),
            ])
        }
        let variants = DocumentType.variants.map { spec -> JSONValue in
            .object([
                "type": .string(spec.type),
                "key": .string(spec.option.key),
                "travels": .bool(!TravelRules.notForTravel.contains(spec.option.key)),
                "travelEnds": TravelRules.travelEnds[spec.option.key].map { .string($0.isoString) } ?? .null,
            ])
        }
        return .object([
            "typeField": .string(DocumentType.typeFieldKey),
            "variantField": .string(DocumentType.variantFieldKey),
            "types": .array(types),
            "variants": .array(variants),
            "writtenBy": .string(writtenBy),
        ])
    }
}
