import Foundation
import Testing
@testable import DosarCuSina

/// What the situation checklists say, run over households chosen to bite and written to
/// `shared/test-vectors/readiness/`, one file per rule: the checklists themselves
/// (`ReadinessEngine.checklist`, with the trip's candidates and whether it reads a locked
/// category), what a traveller carries by citizenship and region (`TravelRules`), the
/// citizenships (`Citizenship`) and the trips kept on the phone (`TripPlanStore`). The Android
/// app's tests read the same files and must give the same answers (docs/ANDROID_PLAN.md, "How
/// parity is kept"). Every sentence is written as its kind (`ReadinessWords`: the case and what it
/// is about), never as text: the words are compared through the copy matrix.
///
/// Nothing here depends on the machine: the days are fixed, "today" is fixed, and the calendar
/// is the app's in a fixed time zone. Placeholder data only: made-up people, plates like
/// `B-123-ABC`, the made-up CNP with county code 99.
@Suite("Readiness vectors")
struct ReadinessVectorsTests {
    static var folder: URL { CatalogExportTests.repository.appending(path: "shared/test-vectors/readiness") }

    static let regenerate = """
    is out of date with the readiness checks. Bring shared/test-vectors/readiness up to date: \
    TEST_RUNNER_READINESS_VECTORS_WRITE=1 ./tests/run_tests.sh (or run ReadinessVectorsTests in Xcode with \
    READINESS_VECTORS_WRITE=1 in the scheme's environment), review the diff, run scripts/privacy-check.sh on it \
    and commit it, then run the Android tests (./gradlew :core:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    static let calendar = Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest") ?? .gmt)
    static let today = CalendarDay("2027-04-01")

    @Test("shared/test-vectors/readiness is up to date with the readiness checks")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["READINESS_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try Self.render(file)
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
        }
        let names = Set(files.map { "\($0.name).json" })
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && !names.contains(stale) {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
    }

    static func all() throws -> [Vectors] {
        try [checklists(), requirements(), citizenships(), trips()]
    }

    static func render(_ file: Vectors) throws -> String {
        let document: JSONValue = .object([
            "rule": .string(file.rule),
            "source": .string(file.source),
            "shape": .string(file.shape),
            "writtenBy": "ios/DosarCuSinaTests/ReadinessVectorsTests.swift",
            "cases": .array(file.cases),
        ])
        return String(decoding: try MachineText.jsonEncoder(.readable).encode(document), as: UTF8.self) + "\n"
    }

    // MARK: Writing what the engine says

    static func id(_ uuid: UUID?) -> JSONValue { uuid.map { .string($0.uuidString) } ?? .null }
    static func day(_ day: CalendarDay?) -> JSONValue { day.map { .string($0.isoString) } ?? .null }
    static func text(_ text: String?) -> JSONValue { text.map(JSONValue.string) ?? .null }
    static func strings(_ values: some Sequence<String>) -> JSONValue { .array(values.map(JSONValue.string)) }

    static func money(_ money: Money) throws -> JSONValue {
        try ValueVectorsTests.json(try ValueVectorsTests.compact(money))
    }

    /// A sentence as its kind: the case's name, and what it is about, in order.
    static func words(_ words: ReadinessWords) throws -> JSONValue {
        guard let child = Mirror(reflecting: words).children.first, let phrase = child.label else {
            return .object(["phrase": .string(String(describing: words)), "arguments": .array([])])
        }
        let payload = Mirror(reflecting: child.value)
        let values: [Any] = payload.displayStyle == .tuple ? payload.children.map(\.value) : [child.value]
        return .object(["phrase": .string(phrase), "arguments": .array(try values.map(argument))])
    }

    struct UnknownArgument: Error { let value: String }

    static func argument(_ value: Any) throws -> JSONValue {
        switch value {
        case let day as CalendarDay: .object(["day": .string(day.isoString)])
        case let number as Int: .object(["number": .int(number)])
        case let text as String: .object(["text": .string(text)])
        case let amount as Money: .object(["money": try money(amount)])
        default: throw UnknownArgument(value: String(describing: value))
        }
    }

    struct UnknownRoute: Error { let route: String }

    static func action(_ action: ReadinessAction?) throws -> JSONValue {
        guard let action else { return .null }
        switch action {
        case .open(let route):
            switch route {
            case .asset(let asset): return .object(["open": .object(["section": Self.id(asset)])])
            case .obligation(let deadline): return .object(["open": .object(["deadline": Self.id(deadline)])])
            default: throw UnknownRoute(route: String(describing: route))
            }
        case .addPersonalDocument(let holder): return .object(["addPersonalDocument": id(holder)])
        case .addDocument(let asset): return .object(["addDocument": id(asset)])
        case .addDeadline(let asset, let blueprint): return .object(["addDeadline": .object(["section": id(asset), "blueprint": .string(blueprint)])])
        case .editSection(let asset): return .object(["editSection": id(asset)])
        case .chooseCitizenship(let holder): return .object(["chooseCitizenship": id(holder)])
        }
    }

    static func status(_ status: ReadinessStatus) -> JSONValue { .string(String(describing: status)) }

    static func item(_ item: ReadinessItem) throws -> JSONValue {
        .object([
            "id": .string(item.id),
            "status": status(item.status),
            "need": .string(item.need == .optional ? "optional" : "required"),
            "title": try words(item.titleWords),
            "detail": try words(item.detailWords),
            "action": try action(item.action),
        ])
    }

    static func policy(_ policy: ReadinessPolicy?) throws -> JSONValue {
        guard let policy else { return .null }
        return .object([
            "blueprintKey": .string(policy.blueprintKey),
            "title": .string(policy.title),
            "whenToUse": try policy.whenToUseWords.map(words) ?? .null,
            "insurer": text(policy.insurer),
            "policyNumber": text(policy.policyNumber),
            "claimsPhone": text(policy.claimsPhone),
            "deadlineID": id(policy.deadlineID),
            "validUntil": day(policy.validUntil),
            "policyholderClass": text(policy.policyholderClass),
        ])
    }

    static func checklist(_ checklist: ReadinessChecklist) throws -> JSONValue {
        .object([
            "groups": .array(try checklist.groups.map { group in
                .object([
                    "id": .string(group.id),
                    "title": try words(group.titleWords),
                    "symbol": .string(group.symbol),
                    "items": .array(try group.items.map(item)),
                ])
            }),
            "items": strings(checklist.items.map(\.id)),
            "policy": try policy(checklist.policy),
            "policyOptions": .array(try checklist.policyOptions.map(policy)),
            "attentionCount": .int(checklist.attentionCount),
            "missingCount": .int(checklist.missingCount),
            "isAllReady": .bool(checklist.isAllReady),
        ])
    }

    // MARK: Writing what the engine reads

    /// One section of the household, with its values as the case writes them.
    struct Section {
        var asset: ReadinessAsset
        var values: [String: FieldValue]
    }

    static func value(_ value: FieldValue) -> JSONValue {
        switch value {
        case .text(let text): .object(["text": .string(text)])
        case .date(let day): .object(["date": .string(day.isoString)])
        case .choices(let keys): .object(["choices": strings(keys)])
        default: .null
        }
    }

    static func obligation(_ obligation: ReadinessObligation) throws -> JSONValue {
        .object([
            "id": id(obligation.id),
            "due": day(obligation.due),
            "lastDone": day(obligation.lastDone),
            "lastCycleDue": day(obligation.lastCycleDue),
            "reference": text(obligation.reference),
            "title": .string(obligation.title),
            "kind": .string(obligation.kind.rawValue),
            "amount": try obligation.amount.map(money) ?? .null,
        ])
    }

    static func section(_ section: Section) throws -> JSONValue {
        let asset = section.asset
        return .object([
            "id": id(asset.id),
            "name": .string(asset.name),
            "templateKey": .string(asset.templateKey),
            "role": text(asset.role?.rawValue),
            "parentId": id(asset.parentId),
            "isSensitive": .bool(asset.isSensitive),
            "wasReplaced": .bool(asset.wasReplaced),
            "values": .object(section.values.mapValues(value)),
            "obligations": .object(try asset.obligations.mapValues(obligation)),
            "otherObligations": .array(try asset.otherObligations.map(obligation)),
            "historyCount": .int(asset.historyCount),
            "documentKinds": strings(asset.documentKinds.map(\.rawValue)),
            "facts": .array(asset.facts.map { entry in
                .object([
                    "blueprintKey": .string(entry.blueprintKey),
                    "title": .string(entry.title),
                    "fields": .object(Dictionary(entry.facts.fields.map { ($0.role.rawValue, JSONValue.string($0.field)) },
                                                 uniquingKeysWith: { first, _ in first })),
                ])
            }),
        ])
    }

    static func traveller(_ traveller: TripTraveller) -> JSONValue {
        switch traveller {
        case .member(let id): .object(["member": Self.id(id)])
        case .unfiled: .string("unfiled")
        }
    }

    /// A trip, with its id unless it was made anew (a default trip's is new each time).
    static func plan(_ plan: TripPlan, withID: Bool = true) -> JSONValue {
        var fields: [String: JSONValue] = [
            "start": day(plan.start),
            "end": day(plan.end),
            "region": .string(plan.region.rawValue),
            "destination": .string(plan.destination),
            "travellers": .array(plan.travellers.sorted { $0.key < $1.key }.map(traveller)),
            "vehicles": strings(plan.vehicles.map(\.uuidString).sorted()),
            "pets": strings(plan.pets.map(\.uuidString).sorted()),
        ]
        if withID { fields["id"] = id(plan.id) }
        return .object(fields)
    }

    // MARK: A household

    static func uuid(_ n: Int) -> UUID {
        let digits = String(n)
        return UUID(uuidString: "00000000-feed-4ace-beef-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits) ?? UUID()
    }

    static func member(_ n: Int, _ name: String, citizenship: FieldValue? = nil, bonusMalus: String? = nil) -> Section {
        var values: [String: FieldValue] = [:]
        if let citizenship { values[MemberFields.citizenship] = citizenship }
        if let bonusMalus { values[MemberFields.bonusMalus] = .text(bonusMalus) }
        return Section(asset: ReadinessAsset(id: uuid(n), name: name, templateKey: BuiltInTemplates.Key.member, role: .holder,
                                             values: FieldValues(values)), values: values)
    }

    static func document(_ n: Int, _ type: String, expires: String?, holder: Int?, nationality: String? = nil, variant: String? = nil,
                         plate: String? = nil, wasReplaced: Bool = false, isSensitive: Bool = false, name: String? = nil) -> Section {
        var values: [String: FieldValue] = [DocumentType.typeFieldKey: .text(type)]
        if let expires { values[DocumentFields.expiry] = .date(CalendarDay(expires)) }
        if let nationality { values[DocumentFields.nationality] = .text(nationality) }
        if let variant { values[DocumentType.variantFieldKey] = .text(variant) }
        if let plate { values[DocumentFields.vehiclePlate] = .text(plate) }
        return Section(asset: ReadinessAsset(id: uuid(n), name: name ?? DocumentType.label(for: type) ?? type, templateKey: BuiltInTemplates.Key.documents,
                                             role: .personalDocument, parentId: holder.map(uuid), isSensitive: isSensitive, wasReplaced: wasReplaced,
                                             values: FieldValues(values)), values: values)
    }

    struct Due {
        var key: String
        var due: String
        var lastDone: String? = nil
        var lastCycleDue: String? = nil
        var reference: String? = nil
    }

    static func deadlines(_ dues: [Due], ids from: Int, template: TemplateDefinition) -> [String: ReadinessObligation] {
        var obligations: [String: ReadinessObligation] = [:]
        for (index, due) in dues.enumerated() {
            let blueprint = template.blueprints.first { $0.key == due.key }
            obligations[due.key] = ReadinessObligation(id: uuid(from + index), due: CalendarDay(due.due), lastDone: due.lastDone.map { CalendarDay($0) },
                                                       lastCycleDue: due.lastCycleDue.map { CalendarDay($0) }, reference: due.reference,
                                                       title: blueprint?.title ?? due.key, kind: blueprint?.kind ?? .routine)
        }
        return obligations
    }

    static func car(_ n: Int, _ name: String = "VW Golf 2018", values: [String: FieldValue] = [:], dues: [Due] = [], historyCount: Int = 0,
                    documentKinds: [DocumentKind] = [], other: [ReadinessObligation] = [], isSensitive: Bool = false) -> Section {
        Section(asset: ReadinessAsset(id: uuid(n), name: name, templateKey: BuiltInTemplates.Key.vehicle, isSensitive: isSensitive, values: FieldValues(values),
                                      obligations: deadlines(dues, ids: n * 10, template: BuiltInTemplates.vehicle), otherObligations: other,
                                      historyCount: historyCount, documentKinds: documentKinds, facts: ReadinessFacts.of(BuiltInTemplates.vehicle)),
                values: values)
    }

    static func home(_ n: Int, values: [String: FieldValue] = [:], dues: [Due] = [], documentKinds: [DocumentKind] = []) -> Section {
        Section(asset: ReadinessAsset(id: uuid(n), name: "Apartament", templateKey: BuiltInTemplates.Key.home, role: .home, values: FieldValues(values),
                                      obligations: deadlines(dues, ids: n * 10, template: BuiltInTemplates.home), documentKinds: documentKinds,
                                      facts: ReadinessFacts.of(BuiltInTemplates.home)),
                values: values)
    }

    static func pet(_ n: Int, _ name: String, passport: String? = nil, dues: [Due] = []) -> Section {
        var values: [String: FieldValue] = [:]
        if let passport { values[PetFields.passport] = .text(passport) }
        return Section(asset: ReadinessAsset(id: uuid(n), name: name, templateKey: BuiltInTemplates.Key.pet, values: FieldValues(values),
                                             obligations: deadlines(dues, ids: n * 10, template: BuiltInTemplates.pet)),
                       values: values)
    }

    static func healthProfile(_ n: Int, holder: Int?, euCard: String) -> Section {
        let health = BuiltInTemplates.all.first { $0.key == BuiltInTemplates.Key.health }
        let obligations = health.map { deadlines([Due(key: BuiltInBlueprints.healthEUCard, due: euCard)], ids: n * 10, template: $0) } ?? [:]
        return Section(asset: ReadinessAsset(id: uuid(n), name: "Sănătate", templateKey: BuiltInTemplates.Key.health, parentId: holder.map(uuid),
                                             obligations: obligations), values: [:])
    }

    static func trip(_ start: String, _ end: String, _ region: TripPlan.Region, travellers: [TripTraveller], vehicles: [Int] = [], pets: [Int] = [],
                     destination: String = "") -> TripPlan {
        TripPlan(id: uuid(999), start: CalendarDay(start), end: CalendarDay(end), region: region, destination: destination,
                 travellers: Set(travellers), vehicles: Set(vehicles.map(uuid)), pets: Set(pets.map(uuid)))
    }

    static func person(_ n: Int) -> TripTraveller { .member(uuid(n)) }

    // MARK: The checklists

    typealias Case = (name: String, scenario: ReadinessScenario, sections: [Section])

    static var romanian: FieldValue { .choices([Citizenship.romania]) }

    static func checklistCases() -> [Case] {
        let ana = member(1, "Ana Popescu", citizenship: romanian)
        let cardOnly = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1)]
        let cardEndingSoon = [ana, document(2, DocumentType.idCard, expires: "2027-07-01", holder: 1)]
        let thirdCountry = [member(3, "Ion Rusu", citizenship: .choices([Citizenship.key("MD")])),
                            document(4, DocumentType.passport, expires: "2031-01-01", holder: 3),
                            document(5, DocumentType.residencePermit, expires: "2028-02-01", holder: 3)]
        let passportInMargin = [member(3, "Ion Rusu", citizenship: .choices([Citizenship.key("MD")])),
                                document(4, DocumentType.passport, expires: "2027-09-01", holder: 3),
                                document(5, DocumentType.residencePermit, expires: "2028-02-01", holder: 3)]
        let cutoffDuringTrip = [ana, document(6, DocumentType.passport, expires: "2027-11-05", holder: 1)]
        let twoCitizenships = [member(7, "Elena Ciobanu", citizenship: .choices([Citizenship.romania, Citizenship.key("MD")])),
                               document(8, DocumentType.idCard, expires: "2030-01-01", holder: 7),
                               document(9, DocumentType.passport, expires: "2031-01-01", holder: 7, nationality: "MDA")]
        let replaced = [member(10, "Mihai Ionescu"),
                        document(11, DocumentType.idCard, expires: "2030-01-01", holder: 10, nationality: "ROU", wasReplaced: true)]
        let simpleCard = [ana, document(12, DocumentType.idCard, expires: "2030-01-01", holder: 1, variant: DocumentType.Variant.idCardSimple,
                                        name: "Carte de identitate simplă")]
        let withoutChip = [ana, document(13, DocumentType.idCard, expires: "2033-01-01", holder: 1, variant: DocumentType.Variant.idCardWithoutChip)]
        let unfiled = [document(14, DocumentType.passport, expires: "2031-01-01", holder: nil),
                       document(15, DocumentType.idCard, expires: nil, holder: nil, name: "Buletin vechi")]
        let unknown = [member(16, "Radu Pop"), document(17, DocumentType.idCard, expires: "2030-01-01", holder: 16)]
        let healthCard = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1), healthProfile(18, holder: 1, euCard: "2027-05-05")]
        let healthCardDocument = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1),
                                  document(19, DocumentType.euHealthCard, expires: "2029-01-01", holder: 1)]
        let driving = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1),
                       document(20, DocumentType.drivingLicence, expires: "2027-05-05", holder: 1),
                       document(21, DocumentType.greenCard, expires: "2028-01-01", holder: 1, plate: "CJ-99-XYZ"),
                       car(22, values: [VehicleFields.plate: .text("B-123-ABC")],
                           dues: [Due(key: BuiltInBlueprints.vehicleRCA, due: "2027-12-01"), Due(key: BuiltInBlueprints.vehicleITP, due: "2027-05-06"),
                                  Due(key: BuiltInBlueprints.vehicleVignette, due: "2027-05-07")])]
        let bareCar = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1), car(23, "Dacia Logan 2015")]
        let expiredCar = [ana, car(24, values: [VehicleFields.plate: .text("B-123-ABC")],
                                   dues: [Due(key: BuiltInBlueprints.vehicleRCA, due: "2027-03-01"), Due(key: BuiltInBlueprints.vehicleITP, due: "2027-03-15"),
                                          Due(key: BuiltInBlueprints.vehicleVignette, due: "2027-03-20")]),
                          document(25, DocumentType.greenCard, expires: "2028-01-01", holder: 1, plate: "B 123 ABC")]
        let pets = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1),
                    pet(30, "PawPaw", passport: "RO-0000", dues: [Due(key: BuiltInBlueprints.petRabies, due: "2028-04-25", lastDone: "2027-04-25", lastCycleDue: "2027-04-30")]),
                    pet(31, "Miți", dues: [Due(key: BuiltInBlueprints.petRabies, due: "2028-04-20", lastDone: "2027-04-20", lastCycleDue: "2027-03-01")]),
                    pet(32, "Rex", passport: "RO-0001", dues: [Due(key: BuiltInBlueprints.petRabies, due: "2028-04-22", lastDone: "2027-04-22")]),
                    pet(33, "Bubu", passport: "RO-0002", dues: [Due(key: BuiltInBlueprints.petRabies, due: "2027-05-06")]),
                    pet(34, "Tom")]
        let locked = [ana, document(2, DocumentType.idCard, expires: "2030-06-01", holder: 1, isSensitive: true)]

        let seller = member(40, "Ana Popescu", bonusMalus: BonusMalusClass.storedKey("B6"))
        let soldCar = car(41, values: [VehicleFields.civ: .text("J000000"), VehicleFields.vin: .text("WVWZZZ1KZ8W000000")],
                          dues: [Due(key: BuiltInBlueprints.vehicleITP, due: "2028-01-01"), Due(key: BuiltInBlueprints.vehicleRCA, due: "2027-03-01"),
                                 Due(key: BuiltInBlueprints.vehicleCASCO, due: "2027-12-01")],
                          historyCount: 3, documentKinds: [.invoice],
                          other: [ReadinessObligation(id: uuid(415), due: CalendarDay("2027-03-31"), title: "Impozit local", kind: .tax,
                                                      amount: Money(450, currency: "RON")),
                                  ReadinessObligation(id: uuid(416), due: CalendarDay("2027-04-01"), title: "Rată leasing", kind: .payment),
                                  ReadinessObligation(id: uuid(417), due: CalendarDay("2027-04-02"), title: "Parcare", kind: .payment),
                                  ReadinessObligation(id: uuid(418), due: CalendarDay("2027-09-01"), title: "", kind: .insurance)])
        let insuredCar = car(42, values: [VehicleFields.insurer: .text("Asigurator Exemplu S.A."), VehicleFields.claimsPhone: .text("021 000 0000"),
                                          VehicleFields.policyholder: .text("Ana Popescu")],
                             dues: [Due(key: BuiltInBlueprints.vehicleRCA, due: "2027-12-01", reference: "RO/00/A00/AA000000"),
                                    Due(key: BuiltInBlueprints.vehicleCASCO, due: "2027-03-01")],
                             documentKinds: [.policy])
        let homeWithPolicy = home(43, values: [HomeFields.policyNumber: .text("PAD000000"), HomeFields.optionalInsurer: .text("Asigurator Exemplu S.A.")],
                                  dues: [Due(key: BuiltInBlueprints.homePAD, due: "2027-10-01")])

        return [
            ("An EU citizen with an identity card, in the EU", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)])), cardOnly),
            ("An EU citizen with an identity card, in Moldova", .trip(trip("2027-05-03", "2027-05-10", .moldovaAndWesternBalkans, travellers: [person(1)])), cardOnly),
            ("An identity card not valid three months after a trip to Moldova", .trip(trip("2027-05-03", "2027-05-10", .moldovaAndWesternBalkans, travellers: [person(1)])),
             cardEndingSoon),
            ("An identity card that ends during an EU trip", .trip(trip("2027-06-25", "2027-07-05", .europeanUnion, travellers: [person(1)])), cardEndingSoon),
            ("An EU citizen with an identity card only, outside the EU", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(1)])), cardOnly),
            ("A non-EU citizen with a passport and a residence permit, in the EU", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(3)])),
             thirdCountry),
            ("A non-EU citizen, outside the EU", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(3)])), thirdCountry),
            ("A passport already within its six months, outside the EU", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(3)])),
             passportInMargin),
            ("A passport whose six months start during the trip", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(1)])), cutoffDuringTrip),
            ("A passport within its six months, in the EU", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)])), cutoffDuringTrip),
            ("Two citizenships, in the EU", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(7)])), twoCitizenships),
            ("Two citizenships, in Moldova", .trip(trip("2027-05-03", "2027-05-10", .moldovaAndWesternBalkans, travellers: [person(7)])), twoCitizenships),
            ("Two citizenships, outside the EU", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(7)])), twoCitizenships),
            ("A replaced identity card still says the citizenship, and is never picked", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(10)])),
             replaced),
            ("The simple identity card is no travel document", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)])), simpleCard),
            ("An identity card without a chip, after August 2031", .trip(trip("2031-08-01", "2031-08-10", .europeanUnion, travellers: [person(1)])), withoutChip),
            ("Documents filed under no one", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [.unfiled])), unfiled),
            ("No citizenship known, in the EU", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(16)])), unknown),
            ("No citizenship known, outside the EU", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(16)])), unknown),
            ("A health card that ends during the trip is only suggested", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)])), healthCard),
            ("A health card filed as a document", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)])), healthCardDocument),
            ("Driving: what ends during the trip", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)], vehicles: [22])), driving),
            ("Driving a car the binder knows nothing of", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(1)], vehicles: [23])), bareCar),
            ("Driving with everything expired", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)], vehicles: [24])), expiredCar),
            ("Pets and their rabies vaccines", .trip(trip("2027-05-03", "2027-05-10", .outsideEU, travellers: [person(1)], pets: [30, 31, 32, 33, 34])), pets),
            ("A locked identity card", .trip(trip("2027-05-03", "2027-05-10", .europeanUnion, travellers: [person(1)])), locked),
            ("Selling a car with its papers", .sellingVehicle(assetId: uuid(41)), [seller, soldCar]),
            ("Selling a car with no papers", .sellingVehicle(assetId: uuid(23)), bareCar),
            ("A claim with its papers", .insuranceClaim(assetId: uuid(42)), [seller, insuredCar]),
            ("A claim on another policy, asked for", .insuranceClaim(assetId: uuid(42), blueprintKey: BuiltInBlueprints.vehicleCASCO), [seller, insuredCar]),
            ("A claim with no papers", .insuranceClaim(assetId: uuid(23)), bareCar),
            ("A claim on a home", .insuranceClaim(assetId: uuid(43)), [homeWithPolicy]),
            ("A claim on a home, the optional policy asked for", .insuranceClaim(assetId: uuid(43), blueprintKey: BuiltInBlueprints.homeInsurance), [homeWithPolicy]),
            ("A claim on a section that isn't there", .insuranceClaim(assetId: uuid(98)), [homeWithPolicy]),
        ]
    }

    static func scenario(_ scenario: ReadinessScenario) -> JSONValue {
        switch scenario {
        case .trip(let trip): .object(["trip": plan(trip)])
        case .sellingVehicle(let id): .object(["sale": Self.id(id)])
        case .insuranceClaim(let id, let blueprint): .object(["claim": .object(["section": Self.id(id), "blueprint": text(blueprint)])])
        }
    }

    static func route(_ scenario: ReadinessScenario) -> ReadinessRoute {
        switch scenario {
        case .trip: .trip(holderID: nil)
        case .sellingVehicle(let id): .sale(assetID: id)
        case .insuranceClaim(let id, _): .claim(assetID: id)
        }
    }

    static func checklists() throws -> Vectors {
        let cases = try checklistCases().map { name, scenario, sections -> JSONValue in
            let assets = sections.map(\.asset)
            let candidates = ReadinessEngine.tripCandidates(in: assets)
            return .object([
                "name": .string(name),
                "today": day(today),
                "scenario": Self.scenario(scenario),
                "sections": .array(try sections.map(section)),
                "checklist": try checklist(ReadinessEngine.checklist(scenario, assets: assets, today: today, calendar: calendar)),
                "readsLocked": .bool(ReadinessEngine.readsSensitive(route(scenario), assets: assets)),
                "candidates": .object([
                    "travellers": .array(try candidates.travellers.map { .object(["traveller": traveller($0.traveller), "name": try words($0.words)]) }),
                    "vehicles": .array(candidates.vehicles.map { .object(["id": id($0.id), "name": .string($0.name)]) }),
                    "pets": .array(candidates.pets.map { .object(["id": id($0.id), "name": .string($0.name)]) }),
                ]),
                "defaultTripFrom": id(uuid(1)),
                "defaultTrip": plan(ReadinessEngine.defaultTrip(start: CalendarDay("2027-05-03"), end: CalendarDay("2027-05-10"),
                                                                holderID: uuid(1), assets: assets), withID: false),
            ])
        }
        return Vectors(
            name: "checklists", rule: "ReadinessEngine.checklist, tripCandidates, defaultTrip and readsSensitive",
            source: "ios/DosarCuSina/Services/Readiness/ReadinessEngine.swift",
            shape: "cases[].sections are what the store fills (a value is {text}, {date} or {choices}; facts name a field by role); scenario is "
                + "{trip}, {sale: id} or {claim: {section, blueprint}}; checklist is the answer: its groups with their items (each sentence a "
                + "ReadinessWords kind: its phrase and arguments, each {day}, {number}, {text} or {money}), every item's id problems first, a "
                + "claim's policy and the policies it could go to, and the counts; readsLocked is readsSensitive for the scenario's route "
                + "(a trip's for the household); candidates and defaultTrip (from defaultTripFrom, 3 to 10 May 2027) are read from the same sections; "
                + "today is fixed; a defaultTrip is written without its id, which is new each time",
            cases: cases
        )
    }

    // MARK: What a traveller carries

    static func requirements() throws -> Vectors {
        let citizenships: [String?] = [nil, Citizenship.romania, Citizenship.key("MD"), Citizenship.key("DE"), Citizenship.key("CH"),
                                       Citizenship.key("NO"), Citizenship.key("GB"), Citizenship.stateless, "country.ZZ", "Română"]
        let cases = citizenships.map { citizenship -> JSONValue in
            .object([
                "citizenship": text(citizenship),
                "group": .string(Citizenship.group(of: citizenship).rawValue),
                "regions": .object(Dictionary(TripPlan.Region.allCases.map { region in
                    (region.rawValue, JSONValue.array(TravelRules.requirements(forCitizenship: citizenship, in: region).map(TravelExportTests.requirement)))
                }, uniquingKeysWith: { first, _ in first })),
            ])
        }
        return Vectors(
            name: "requirements", rule: "TravelRules.requirements(forCitizenship:in:)",
            source: "ios/DosarCuSina/Services/Readiness/TravelRules.swift",
            shape: "cases[].citizenship (a stored key, or null when not known) is read into its group, and in each region the requirements a "
                + "traveller of it carries, each as shared/travel/rules.json writes one",
            cases: cases
        )
    }

    // MARK: Citizenships

    static func citizenships() throws -> Vectors {
        var cases: [JSONValue] = []
        for nationality in ["ROU", "Română / ROU", "rou", "Romana", "România", "D", "Germania / D", "GBN", "MDA", "Moldovan", "Republica Moldova",
                            "country.MD", "XXA", "Apatrid", "RKS", "", "   ", "Atlantis", "ROU / MDA"] {
            cases.append(.object(["rule": "key(forNationality:)", "text": .string(nationality),
                                  "key": text(Citizenship.key(forNationality: nationality))]))
        }
        let people: [(String, FieldValue?)] = [
            ("a list", .choices([Citizenship.key("MD"), Citizenship.romania, Citizenship.romania])),
            ("one key kept as text by an earlier version", .text(Citizenship.romania)),
            ("a name kept as text", .text("Moldova")),
            ("keys this build doesn't know", .choices(["country.ZZ", Citizenship.stateless])),
            ("nothing", nil),
        ]
        let documents: [[String: FieldValue]] = [
            [DocumentFields.nationality: .text("MDA")],
            [DocumentFields.nationality: .text("Română / ROU")],
            [DocumentFields.nationality: .text("Atlantis")],
            [:],
        ]
        for (name, kept) in people {
            let person = FieldValues(kept.map { [MemberFields.citizenship: $0] } ?? [:])
            cases.append(.object([
                "rule": "kept(in:), of(person:documents:)", "name": .string(name),
                "person": kept.map(value) ?? .null,
                "documents": .array(documents.map { .object($0.mapValues(value)) }),
                "kept": strings(Citizenship.kept(in: person)),
                "of": strings(Citizenship.of(person: person, documents: documents.map(FieldValues.init))),
                "ofWithoutDocuments": strings(Citizenship.of(person: person, documents: [])),
            ]))
        }
        for document in documents {
            cases.append(.object(["rule": "printed(on:)", "document": .object(document.mapValues(value)),
                                  "key": text(Citizenship.printed(on: FieldValues(document)))]))
        }
        let keeping: [(String, [String], FieldValue?)] = [
            ("a new list, put in order", [Citizenship.key("MD"), Citizenship.romania], .text(Citizenship.romania)),
            ("the same list", [Citizenship.romania, Citizenship.key("MD")], .choices([Citizenship.key("MD"), Citizenship.romania])),
            ("the list it keeps, given out of order", [Citizenship.key("MD"), Citizenship.romania], .choices([Citizenship.key("MD"), Citizenship.romania])),
            ("nothing to keep", [], .text(Citizenship.romania)),
            ("onto no citizenship", [Citizenship.stateless, Citizenship.key("DE"), Citizenship.key("DE")], nil),
        ]
        for (name, list, kept) in keeping {
            let person = FieldValues(kept.map { [MemberFields.citizenship: $0] } ?? [:])
            let result = Citizenship.keeping(list, in: person)
            cases.append(.object([
                "rule": "keeping(_:in:)", "name": .string(name), "citizenships": strings(list),
                "person": kept.map(value) ?? .null,
                "kept": result.map { $0[MemberFields.citizenship].map(value) ?? .null } ?? .null,
            ]))
        }
        return Vectors(
            name: "citizenship", rule: "Citizenship: key(forNationality:), kept(in:), of(person:documents:), printed(on:), keeping(_:in:)",
            source: "ios/DosarCuSina/Models/Fields/Citizenship.swift",
            shape: "cases[] by rule: key(forNationality:) reads text into a stored key or null; kept and of read a person's member.citizenship "
                + "value (null for none) and their documents' document.nationality; printed(on:) one document's; keeping gives the person's new "
                + "member.citizenship value, or null when nothing changes",
            cases: cases
        )
    }

    // MARK: Trips kept on the phone

    static func trips() throws -> Vectors {
        let ana = TripTraveller.member(uuid(1))
        func kept(_ n: Int, _ start: String, _ end: String, destination: String = "", region: TripPlan.Region = .europeanUnion) -> TripPlan {
            TripPlan(id: uuid(n), start: CalendarDay(start), end: CalendarDay(end), region: region, destination: destination, travellers: [ana])
        }
        let summer = kept(201, "2027-07-01", "2027-07-14", destination: "Grecia")
        let weekend = kept(202, "2027-04-10", "2027-04-12", destination: "Sibiu")
        let over = kept(203, "2027-03-20", "2027-03-31", destination: "Viena")
        let endsToday = kept(204, "2027-03-28", "2027-04-01")
        let sameDays = kept(200, "2027-07-01", "2027-07-14", destination: "Creta")
        let private1 = kept(205, "2027-05-01", "2027-05-03", destination: "Grecia, CNP 1800101990006")
        let single = kept(206, "2027-06-01", "2027-06-05", destination: "Londra", region: .outsideEU)
        let changed = kept(201, "2027-07-02", "2027-07-15", destination: "Grecia", region: .outsideEU)

        var cases: [JSONValue] = []
        let loads: [(String, [TripPlan], TripPlan?)] = [
            ("trips ahead, kept the soonest first", [summer, weekend], nil),
            ("a trip that is over is forgotten; one that ends today is kept", [summer, over, endsToday], nil),
            ("the same days are told apart by id", [summer, sameDays], nil),
            ("a destination search couldn't keep is forgotten", [private1], nil),
            ("the one trip of before is brought across", [weekend], single),
            ("the one trip of before, already in the list", [weekend, single], single),
            ("nothing kept", [], nil),
            ("everything over", [over], nil),
        ]
        for (name, stored, before) in loads {
            let store = try Self.store(stored, single: before)
            let loaded = store.store.load(today: today)
            let data = store.defaults.data(forKey: TripPlanStore.key)
            let rewrote = data != store.written || store.defaults.object(forKey: TripPlanStore.singleTripKey) == nil && before != nil
            cases.append(.object([
                "rule": "load(today:)", "name": .string(name), "today": day(today),
                "stored": .array(stored.map { plan($0) }), "single": before.map { plan($0) } ?? .null,
                "kept": .array(loaded.map { plan($0) }), "writes": .bool(rewrote),
            ]))
        }
        let saves: [(String, [TripPlan], TripPlan)] = [
            ("a new trip", [summer], weekend),
            ("a trip changed, by its id", [summer, weekend], changed),
            ("a destination search couldn't keep", [summer], private1),
        ]
        for (name, stored, saved) in saves {
            let store = try Self.store(stored, single: nil)
            store.store.save(saved)
            let after = try store.defaults.data(forKey: TripPlanStore.key).map { try MachineText.jsonDecoder().decode([TripPlan].self, from: $0) } ?? []
            cases.append(.object([
                "rule": "save(_:)", "name": .string(name), "stored": .array(stored.map { plan($0) }), "saved": plan(saved),
                "kept": .array(after.map { plan($0) }),
            ]))
        }
        for (name, stored, removed) in [("a trip forgotten by its id", [summer, weekend], summer.id), ("an id not kept", [summer], uuid(299))] {
            let store = try Self.store(stored, single: nil)
            store.store.remove(removed)
            let after = try store.defaults.data(forKey: TripPlanStore.key).map { try MachineText.jsonDecoder().decode([TripPlan].self, from: $0) } ?? []
            cases.append(.object([
                "rule": "remove(_:)", "name": .string(name), "stored": .array(stored.map { plan($0) }), "removed": id(removed),
                "kept": .array(after.map { plan($0) }),
            ]))
        }
        for plan in [summer, over, endsToday, kept(207, "2027-05-10", "2027-05-01"), kept(208, "2027-04-01", "2027-04-01")] {
            cases.append(.object([
                "rule": "isValid, isOver(by:)", "plan": Self.plan(plan), "today": day(today),
                "isValid": .bool(plan.isValid), "isOver": .bool(plan.isOver(by: today)),
            ]))
        }
        return Vectors(
            name: "trips", rule: "TripPlanStore: load(today:), save(_:), remove(_:); TripPlan.isValid and isOver(by:)",
            source: "ios/DosarCuSina/Services/Readiness/TripPlanStore.swift, ReadinessModels.swift",
            shape: "cases[] by rule: load reads the trips kept (stored, and the one trip kept before there could be several, single) into the "
                + "trips still ahead, the soonest first, each destination remembered only as search would (SearchPrivacy.mayRemember); writes "
                + "says whether loading writes the list again; save and remove give the list kept after",
            cases: cases
        )
    }

    struct Store {
        var store: TripPlanStore
        var defaults: UserDefaults
        var written: Data?
    }

    struct NoDefaults: Error {}

    /// A store over defaults of its own, holding `stored` and, when given, the one trip of before.
    static func store(_ stored: [TripPlan], single: TripPlan?) throws -> Store {
        let suite = "ReadinessVectorsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw NoDefaults() }
        defaults.removePersistentDomain(forName: suite)
        let data = stored.isEmpty ? nil : try MachineText.jsonEncoder().encode(stored)
        if let data { defaults.set(data, forKey: TripPlanStore.key) }
        if let single { defaults.set(try MachineText.jsonEncoder().encode(single), forKey: TripPlanStore.singleTripKey) }
        nonisolated(unsafe) let shared = defaults
        return Store(store: TripPlanStore(defaults: { shared }), defaults: defaults, written: data)
    }
}
