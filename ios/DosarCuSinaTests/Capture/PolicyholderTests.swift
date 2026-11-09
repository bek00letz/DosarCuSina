import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A policy's bonus-malus class belongs to the person it insures, never to a car: kept on
/// them when the household knows them, shown on the policy's page and the claim screen read
/// from them, and the review says where it goes or why it doesn't. Every value is a placeholder.
@MainActor
@Suite("Bonus-malus and the policyholder")
struct PolicyholderTests {

    // MARK: The scale

    @Test("The scale is the official one, worst to best: M8 to M1, B0, B1 to B8")
    func scale() {
        #expect(BonusMalusClass.printed == ["M8", "M7", "M6", "M5", "M4", "M3", "M2", "M1", "B0", "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8"])
        #expect(BonusMalusClass.key(for: "b6") == "bonusMalus.b6")
        #expect(BonusMalusClass.key(for: "bonusMalus.m2") == "bonusMalus.m2")
        #expect(BonusMalusClass.key(for: "B9") == nil)
        #expect(BonusMalusClass.label(for: "bonusMalus.b6") == "B6")
        #expect(Set(BonusMalusClass.options.map(\.key)).count == 17, "Stable keys, one per class")
    }

    // MARK: The catalog

    @Test("The class is a field of the person, and the RCA names who it insures")
    func catalog() throws {
        let member = BuiltInTemplates.member
        let field = try #require(member.field(MemberFields.bonusMalus))
        #expect(field.type == .choice)
        #expect(field.options?.map(\.key) == BonusMalusClass.all)
        let vehicle = BuiltInTemplates.vehicle
        #expect(!vehicle.allFields.contains { $0.options?.contains { $0.key.hasPrefix("bonusMalus.") } == true }, "Never on a car")
        let rca = try #require(vehicle.blueprints.first { $0.key == BuiltInBlueprints.vehicleRCA })
        #expect(rca.facts?.policyholder == VehicleFields.policyholder)
        #expect(vehicle.field(VehicleFields.policyholder) != nil)
        #expect(vehicle.blueprints.first { $0.key == BuiltInBlueprints.vehicleCASCO }?.facts?.policyholder == nil)
    }

    @Test("An install from before gets the person's class field, and keeps its people")
    func upgrade() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        var older = BuiltInTemplates.member
        older.version = 13
        older.sections = []
        try store.installBuiltIns(catalog: BuiltInTemplates.all.filter { $0.key != BuiltInTemplates.Key.member } + [older])
        let installed = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        #expect(installed.definition.field(MemberFields.bonusMalus) == nil)
        let ana = try AssetActions(context: context).create(name: "Ana Exemplu", template: installed, values: FieldValues())

        #expect(try store.installBuiltIns())
        #expect(installed.builtInVersion == TemplateDefinition.builtInCatalogVersion)
        #expect(installed.definition.field(MemberFields.bonusMalus) != nil)
        #expect(ana.templateKey == BuiltInTemplates.Key.member)
        #expect(try store.installBuiltIns() == false, "Upgraded once")
    }

    // MARK: Reading who it insures

    static let policyText = """
    CONTRACT DE ASIGURARE DE RĂSPUNDERE CIVILĂ AUTO RCA Seria RO/00/X00/XX nr. 123456789
    Proprietar: EXEMPLU ANA MARIA
    C.U.I. / C.N.P. Proprietar: 1800101990006 Nr. înmatriculare/înregistrare: B 123 ABC
    Prima de asigurare 1234.56 LEI, Clasă Bonus-Malus: B6
    """

    @Test("A policy names who it insures; their CNP is read only to find them")
    func reading() throws {
        let fields = PolicyholderReader.fields(in: CaptureText(Self.policyText))
        #expect(fields.first { $0.key == .policyholder }?.value.text == "Exemplu Ana Maria")
        let number = try #require(fields.first { $0.key == .policyholderPersonalNumber })
        #expect(number.value.text == "1800101990006")
        #expect(number.sourceText == nil, "Its line is never kept to show")
        #expect(!CaptureMapping.isShownInReview(.policyholderPersonalNumber, among: [.policyholderPersonalNumber]))
        #expect(CaptureDocumentKind.rcaPolicy.allows(.policyholder))
        #expect(CaptureDocumentKind.rcaPolicy.allows(.bonusMalusClass))
        #expect(!CaptureDocumentKind.utilityInvoice.allows(.policyholderPersonalNumber))
        #expect(!CaptureDocumentKind.serviceInvoice.allows(.bonusMalusClass))
        #expect(!CloudSchema(kind: .rcaPolicy).fields.contains { $0.key == .policyholderPersonalNumber }, "Never asked of the AI provider")
        #expect(CaptureMapping.candidates[.policyholderPersonalNumber] == nil, "Never filed")

        let analysis = CaptureAnalyzer().analyze(text: Self.policyText, as: .rcaPolicy)
        #expect(analysis.fields.first { $0.key == .policyholder }?.value.text == "Exemplu Ana Maria")
        #expect(analysis.fields.first { $0.key == .bonusMalusClass }?.value.text == "B6")
    }

    @Test("The person is found by their CNP first, else by name")
    func matching() {
        let ana = Policyholders.Person(id: UUID(), name: "Ana", personalNumbers: ["1800101990006"], bonusMalus: "bonusMalus.b6")
        let ion = Policyholders.Person(id: UUID(), name: "Ion Exemplu", personalNumbers: [], bonusMalus: nil)
        #expect(Policyholders.person(named: "Exemplu Ana Maria", personalNumber: "1800101990006", among: [ana, ion])?.id == ana.id)
        #expect(Policyholders.person(named: "EXEMPLU ION", personalNumber: nil, among: [ana, ion])?.id == ion.id)
        #expect(Policyholders.person(named: "Popescu Maria", personalNumber: nil, among: [ana, ion]) == nil)
        #expect(Policyholders.bonusMalus(ofPolicyholder: "Ana", among: [ana, ion]) == "B6")
        #expect(Policyholders.bonusMalus(ofPolicyholder: "Ion Exemplu", among: [ana, ion]) == nil, "No class known")
    }

    // MARK: Filing

    private struct Household {
        let context: ModelContext
        let car: Asset
        let rca: Obligation
        let member: Asset
    }

    private func household(memberName: String = "Exemplu Ana Maria", memberCNP: String? = nil) throws -> Household {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        let members = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let actions = AssetActions(context: context)
        let car = try actions.create(name: "VW Golf 2018", template: vehicle, values: FieldValues())
        let member = try actions.create(name: memberName, template: members, values: FieldValues())
        if let memberCNP, let documents = try store.template(forKey: BuiltInTemplates.Key.documents) {
            var values = FieldValues()
            values[DocumentFields.personalNumber] = .text(memberCNP)
            _ = try actions.create(name: "Carte de identitate", template: documents, values: values, parent: member)
        }
        let blueprint = try #require(vehicle.definition.blueprints.first { $0.key == BuiltInBlueprints.vehicleRCA })
        let rca = try ObligationActions(context: context).create(from: blueprint, for: car, firstDue: CalendarDay(Date()).adding(days: 20, calendar: .current))
        return Household(context: context, car: car, rca: rca, member: member)
    }

    private func policy(holder: String?, number: String? = nil) -> CaptureResult {
        let expiry = CaptureDay(date: Calendar.current.date(byAdding: .day, value: 375, to: Date())!)
        var fields = [
            CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .policyNumber, value: .text("RO/00/X00/XX 123456789"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .bonusMalusClass, value: .text("B6"), confidence: 0.8, tier: .heuristic),
        ]
        if let holder { fields.append(CaptureField(key: .policyholder, value: .text(holder), confidence: 0.8, tier: .heuristic)) }
        if let number { fields.append(CaptureField(key: .policyholderPersonalNumber, value: .text(number), confidence: 0.97, tier: .deterministic)) }
        return CaptureResult(kind: .rcaPolicy, kindConfidence: 0.95, fields: fields, suggestions: [], reminder: nil,
                             recognizedText: "POLIȚĂ RCA", barcodes: [], document: nil, notices: [])
    }

    private func save(_ result: CaptureResult, in house: Household) async throws -> CaptureFilingPlan {
        var review = CaptureReview(result: result, assets: [house.car, house.member], context: house.context)
        review.destination = .asset(house.car.id)
        let filer = CaptureFiler(context: house.context, store: CaptureDocumentStore())
        let plan = try filer.plan(for: review)
        _ = try await filer.save(review)
        return plan
    }

    @Test("The class goes to the person the policy insures, never to the car, and the RCA's page reads it from them")
    func keptOnThePerson() async throws {
        let house = try household()
        let plan = try await save(policy(holder: "Exemplu Ana Maria"), in: house)
        #expect(plan.bonusMalus == .keep(classKey: "bonusMalus.b6", memberID: house.member.id, memberName: "Exemplu Ana Maria"))
        #expect(house.member.value(MemberFields.bonusMalus) == .text("bonusMalus.b6"))
        #expect(house.car.value(VehicleFields.policyholder) == .text("Exemplu Ana Maria"))
        #expect(!house.car.values.contains { _, value in value.textValue?.hasPrefix("bonusMalus.") == true }, "Never stored on the car")

        // Shown on the deadline page and the claim screen, read from the person.
        let templates = try TemplateStore(context: house.context).templatesByKey()
        let facts = DeadlineFacts.of(house.rca, template: templates[BuiltInTemplates.Key.vehicle]?.definition)
        #expect(Policyholders.bonusMalus(ofPolicyholder: facts.policyholder, among: Policyholders.people(in: house.context)) == "B6")
        let snapshot = ReadinessAsset.make(from: try house.context.fetch(FetchDescriptor<Asset>()), templates: templates)
        let claim = ReadinessEngine.checklist(.insuranceClaim(assetId: house.car.id, blueprintKey: BuiltInBlueprints.vehicleRCA), assets: snapshot)
        #expect(claim.policy?.policyholderClass == "B6")

        // A new class on the person shows everywhere, with nothing to update on the car.
        try AssetActions(context: house.context).update(house.member, name: house.member.name,
                                                       values: { var v = house.member.values; v[MemberFields.bonusMalus] = .text("bonusMalus.b7"); return v }(),
                                                       notes: nil)
        #expect(Policyholders.bonusMalus(ofPolicyholder: facts.policyholder, among: Policyholders.people(in: house.context)) == "B7")
    }

    @Test("Found by the CNP on their documents, the person is named as the household knows them")
    func foundByPersonalNumber() async throws {
        let house = try household(memberName: "Ana", memberCNP: "1800101990006")
        let plan = try await save(policy(holder: "Exemplu Ana Maria", number: "1800101990006"), in: house)
        #expect(plan.bonusMalus == .keep(classKey: "bonusMalus.b6", memberID: house.member.id, memberName: "Ana"))
        #expect(house.member.value(MemberFields.bonusMalus) == .text("bonusMalus.b6"))
        #expect(house.car.value(VehicleFields.policyholder) == .text("Ana"), "So the page finds her by name")
    }

    @Test("Nobody in the household, or no name on the policy: the class isn't kept, and the review says why")
    func notKept() async throws {
        let house = try household()
        let plan = try await save(policy(holder: "Popescu Maria"), in: house)
        #expect(plan.bonusMalus == .notInHousehold(name: "Popescu Maria"))
        #expect(house.member.value(MemberFields.bonusMalus) == nil)

        let other = try household()
        let unnamed = try await save(policy(holder: nil), in: other)
        #expect(unnamed.bonusMalus == .noPolicyholder)
        #expect(other.member.value(MemberFields.bonusMalus) == nil)
    }

    @Test("A new RCA through Am rezolvat keeps the class on the person too")
    func throughCompletion() async throws {
        let house = try household()
        _ = try await CaptureFiler(context: house.context).file(.completion(.init(
            obligation: house.rca, date: Date(), cost: nil, document: policy(holder: "Exemplu Ana Maria"))))
        #expect(house.member.value(MemberFields.bonusMalus) == .text("bonusMalus.b6"))
        #expect(house.car.value(VehicleFields.policyholder) == .text("Exemplu Ana Maria"))
    }
}
