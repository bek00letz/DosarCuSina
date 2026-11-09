import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A home keeps its mandatory policy (PAD) and its optional one apart, like a car's RCA and
/// CASCO: each deadline names its own insurer, policy number and claims phone. Facts an
/// earlier version kept together move only with the owner's OK.
@MainActor
@Suite("A home's two policies")
struct HomePoliciesTests {
    private func facts(_ key: String) throws -> BlueprintFacts {
        try #require(BuiltInTemplates.home.blueprints.first { $0.key == key }?.facts)
    }

    @Test func padAndTheOptionalPolicyKeepTheirOwnFacts() throws {
        let pad = try facts(BuiltInBlueprints.homePAD)
        let optional = try facts(BuiltInBlueprints.homeInsurance)
        let fields = Set(BuiltInTemplates.home.allFields.map(\.key))
        // Who a policy insures is named only on a car's RCA, whose class it shows.
        #expect(pad.policyholder == nil && optional.policyholder == nil, "A home policy names no policyholder")
        for role in BlueprintFactRole.allCases where role != .policyholder {
            let padField = try #require(pad.field(for: role))
            let optionalField = try #require(optional.field(for: role))
            #expect(padField != optionalField, "\(role): never shared")
            #expect(fields.contains(padField) && fields.contains(optionalField), "\(role): both are fields of a home")
        }
        #expect(pad.policyNumber == HomeFields.policyNumber, "PAD keeps the fields a home had")
        #expect(optional.policyNumber == HomeFields.optionalPolicyNumber)
    }

    @Test func eachCoverFilesIntoItsOwnDeadline() {
        let profile = CaptureKindProfile.of(.insurancePolicy)
        #expect(profile.deadline(cover: InsuranceCover.pad)?.blueprintKey == BuiltInBlueprints.homePAD)
        #expect(profile.deadline(cover: InsuranceCover.home)?.blueprintKey == BuiltInBlueprints.homeInsurance)
    }

    // MARK: The repair

    private struct Home {
        let context: ModelContext
        let asset: Asset
        let repairs: DataRepairs
    }

    private func home(deadlines: [String], paper: String? = nil, optionalNumber: String? = nil) throws -> Home {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        var values = FieldValues()
        values[HomeFields.insurer] = .text("Exemplu Asigurări S.A.")
        values[HomeFields.policyNumber] = .text("LOC-000001")
        values[HomeFields.claimsPhone] = .text("0210000004")
        if let optionalNumber { values[HomeFields.optionalPolicyNumber] = .text(optionalNumber) }
        let calendar = Calendar.bucharest
        let today = CalendarDay(noon("2026-11-03"), calendar: calendar)
        let asset = try AssetActions(context: context, calendar: calendar, now: { noon("2026-11-03") })
            .create(name: "Apartament", template: template, values: values)
        for key in deadlines {
            let blueprint = try #require(template.blueprints.first { $0.key == key })
            _ = try HouseholdMutations.makeObligation(from: blueprint, for: asset, firstDue: CalendarDay("2027-05-31"), today: today, calendar: calendar, in: context)
        }
        if let paper {
            let policy = Attachment(fileName: "locuinta.pdf", contentType: "com.adobe.pdf", data: Data("z".utf8), kind: .policy)
            policy.extractedText = paper
            context.insert(policy)
            policy.asset = asset
        }
        try UnitOfWork.save(context)
        let ledger = DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "home-policies-\(UUID().uuidString)")))
        return Home(context: context, asset: asset, repairs: DataRepairs(context: context, calendar: calendar, ledger: ledger))
    }

    private func found(_ home: Home) throws -> [DataRepairFinding] {
        try home.repairs.detect().filter { $0.step == .homePolicySets }
    }

    @Test func factsOfAnOptionalPolicyMoveWhenTheOwnerSaysSo() throws {
        let home = try home(deadlines: [BuiltInBlueprints.homeInsurance])
        let list = try found(home)
        #expect(list.map(\.message) == [
            "La Apartament, „LOC-000001” e de la asigurarea facultativă, dar stă la PAD. O mut la asigurarea facultativă, cu asigurătorul și telefonul de daune?",
        ])
        #expect(home.asset.value(HomeFields.policyNumber) == .text("LOC-000001"), "Nothing moves before the owner says so")

        try home.repairs.apply(list)
        #expect(home.asset.value(HomeFields.optionalInsurer) == .text("Exemplu Asigurări S.A."))
        #expect(home.asset.value(HomeFields.optionalPolicyNumber) == .text("LOC-000001"))
        #expect(home.asset.value(HomeFields.optionalClaimsPhone) == .text("0210000004"))
        #expect(home.asset.value(HomeFields.insurer) == nil)
        #expect(home.asset.value(HomeFields.policyNumber) == nil)
        #expect(home.asset.value(HomeFields.claimsPhone) == nil)
        #expect(try found(home).isEmpty, "Applied once, not found again")
    }

    @Test func factsOfAPADStayWhereTheyAre() throws {
        #expect(try found(home(deadlines: [BuiltInBlueprints.homePAD])).isEmpty)
        // A paper that carries the number and names PAD says so, whatever deadlines run.
        let paper = "POLIȚĂ DE ASIGURARE OBLIGATORIE A LOCUINȚEI (PAD)\nSeria LOC nr. LOC-000001"
        #expect(try found(home(deadlines: [BuiltInBlueprints.homePAD, BuiltInBlueprints.homeInsurance], paper: paper)).isEmpty)
    }

    @Test func aPaperThatIsNotPADSaysItIsTheOptionalOne() throws {
        let paper = "POLIȚĂ DE ASIGURARE FACULTATIVĂ A LOCUINȚEI\nNr. LOC-000001"
        let list = try found(home(deadlines: [BuiltInBlueprints.homePAD, BuiltInBlueprints.homeInsurance], paper: paper))
        #expect(list.count == 1)
        #expect(list.first?.message.hasPrefix("La Apartament, „LOC-000001” e de la asigurarea facultativă") == true)
    }

    @Test func whenTheCoverCantBeToldTheOwnerChecks() throws {
        for deadlines in [[], [BuiltInBlueprints.homePAD, BuiltInBlueprints.homeInsurance]] {
            let home = try home(deadlines: deadlines)
            let list = try found(home)
            #expect(list.map(\.message) == [
                "Verifică asigurarea de la Apartament: „LOC-000001” stă la PAD și nu-mi dau seama dacă e PAD sau asigurarea facultativă. E cea facultativă? O mut acolo, cu asigurătorul și telefonul de daune.",
            ])
            // "Lasă așa" keeps them as PAD's and isn't asked again.
            home.repairs.dismiss(list)
            #expect(try found(home).isEmpty)
            #expect(home.asset.value(HomeFields.policyNumber) == .text("LOC-000001"))
        }
    }

    @Test func aHomeThatAlreadyKeepsThemApartIsLeftAlone() throws {
        #expect(try found(home(deadlines: [BuiltInBlueprints.homeInsurance], optionalNumber: "LOC-000002")).isEmpty)
    }
}
