import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Insurance policies: each cover in its own fields, policies never taken for bills,
/// and a corrected kind bringing its deadline along.
@Suite("Policies")
@MainActor
struct PolicyFilingTests {

    private func car(_ context: ModelContext) throws -> (Asset, TemplateDefinition) {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
        return (car, template.definition)
    }

    @Test func aCascoPolicyFillsTheCascoFieldsNotRCAs() throws {
        let context = try makeContext()
        let (_, vehicle) = try car(context)
        let casco = vehicle.blueprints.first { $0.key == BuiltInBlueprints.vehicleCASCO }
        let rca = vehicle.blueprints.first { $0.key == BuiltInBlueprints.vehicleRCA }
        #expect(CaptureMapping.fieldKey(for: .policyNumber, kind: .insurancePolicy, in: vehicle, deadline: casco) == VehicleFields.cascoPolicyNumber)
        #expect(CaptureMapping.fieldKey(for: .claimsPhone, kind: .insurancePolicy, in: vehicle, deadline: casco) == VehicleFields.cascoClaimsPhone)
        #expect(CaptureMapping.fieldKey(for: .provider, kind: .insurancePolicy, in: vehicle, deadline: casco) == VehicleFields.cascoInsurer)
        #expect(CaptureMapping.fieldKey(for: .policyNumber, kind: .rcaPolicy, in: vehicle, deadline: rca) == VehicleFields.policyNumber)
        #expect(CaptureMapping.fieldKey(for: .policyNumber, kind: .insurancePolicy, in: vehicle, deadline: nil) == nil, "A policy without its deadline here never fills RCA's fields")
        #expect(CaptureMapping.fieldKey(for: .expiryDate, kind: .rcaPolicy, in: vehicle, deadline: rca) == nil, "The policy's end is the deadline's own day")
    }

    @Test("The cover is read once, as whole words")
    func theCoverIsReadAsWholeWords() {
        #expect(InsuranceCover.read(in: "Poliță CASCO nr. 123") == InsuranceCover.casco)
        #expect(InsuranceCover.read(in: "Asigurare PAD pentru locuință") == InsuranceCover.pad)
        #expect(InsuranceCover.read(in: "Padding și Padina", among: [InsuranceCover.pad]) == nil, "Part of a word is not a cover")
        #expect(InsuranceCover.read(in: "Răspundere civilă auto") == InsuranceCover.rca)
        #expect(InsuranceCover.read(in: "Răspundere civilă auto", among: CaptureDocumentKind.insurancePolicy.profile.covers) == nil,
                "Another policy is never an RCA: that is a kind of its own")
        #expect(InsuranceCover.key(for: "CASCO") == InsuranceCover.casco)
        #expect(InsuranceCover.key(for: "Facultativă") == InsuranceCover.home)
    }

    @Test func aPolicyMentioningDigitalIsNotADigiBill() {
        let analysis = CaptureAnalyzer().analyze(text: """
        POLIȚĂ DE ASIGURARE OBLIGATORIE RCA
        Răspundere civilă auto
        Asigurător: Exemplu Asigurări S.A., România
        Semnătură digitală
        Nr. înmatriculare B 123 ABC
        Valabilă de la 01.11.2026 până la 31.10.2027
        """, referenceDate: Date(timeIntervalSince1970: 1_793_577_600))
        #expect(analysis.kind == .rcaPolicy)
        #expect(RomanianUtilityParser.shared.detectProvider(in: "SEMNATURA DIGITALA ROMANIA") == .general)
        #expect(RomanianUtilityParser.shared.detectProvider(in: "DIGI ROMANIA S.A. FACTURA") == .digi)
    }

    /// The text of an RCA policy, as the phone read it.
    private static let policyText = """
        POLIȚĂ DE ASIGURARE OBLIGATORIE RCA
        Asigurător: Exemplu Asigurări S.A.
        Seria RO/00/X Nr. 000000000
        Nr. înmatriculare B 123 ABC
        Valabilă de la 01.11.2026 până la 31.10.2027
        Total de plată: 1.150,00 lei
        """

    /// The policy as a phone that took it for a bill would hand it to the review: the
    /// bill's fields, but the policy's own text kept for reading again.
    private func readAsABill() -> CaptureResult {
        let today = Date(timeIntervalSince1970: 1_793_577_600) // 2 November 2026
        let due = CaptureDay(year: 2026, month: 11, day: 20)!
        return CaptureResult(
            kind: .utilityInvoice, kindConfidence: 0.7,
            fields: [CaptureField(key: .dueDate, value: .day(due), confidence: 0.6, tier: .heuristic)],
            suggestions: [], reminder: nil, recognizedText: Self.policyText, barcodes: [], document: nil, notices: [],
            source: CaptureReadingSource(text: Self.policyText, pages: [], barcodes: [], referenceDate: today,
                                         modelFields: [], aiFields: nil, isSinglePhoto: false)
        )
    }

    @Test func correctingTheKindReadsThePageAgainAsThatKind() throws {
        let context = try makeContext()
        let (car, _) = try car(context)
        let review = CaptureReview(result: readAsABill(), assets: [car], context: context)
        #expect(review.blueprintKey == SubscriptionFields.billBlueprint, "A bill sets its own deadline")

        let corrected = review.choosingKind(.rcaPolicy, assets: [car], context: context)
        #expect(corrected.kind == .rcaPolicy)
        #expect(corrected.blueprintKey == "vehicle.rca")
        #expect(!corrected.remindsToPay, "Not a bill any more")
        let expiry = try #require(CaptureDay(year: 2027, month: 10, day: 31))
        #expect(corrected.value(.expiryDate) == .day(expiry), "The policy's own expiry, read from its text")
        #expect(corrected.reminderDay == CaptureMapping.calendarDay(expiry))
        #expect(corrected.value(.dueDate) == nil, "The bill's payment date doesn't stay on a policy")
    }

    @Test func correctingTheKindKeepsWhatThePersonTyped() throws {
        let context = try makeContext()
        let (car, _) = try car(context)
        var review = CaptureReview(result: readAsABill(), assets: [car], context: context)
        review.title = "Polița mașinii"
        if let index = review.fields.firstIndex(where: { $0.key == .dueDate }) { review.fields[index].confirm(nil) }
        let corrected = review.choosingKind(.rcaPolicy, assets: [car], context: context)
        #expect(corrected.title == "Polița mașinii")
        #expect(corrected.kindAlternatives.allSatisfy { $0.value != .rcaPolicy })
        // A later reading doesn't take the person's kind away.
        let again = CaptureReview(result: readAsABill(), assets: [car], context: context).carryingEdits(from: corrected, assets: [car])
        #expect(again.kind == .rcaPolicy)
    }

    @Test func anExpectedFieldThatWasntReadCanBeAdded() throws {
        let context = try makeContext()
        let (car, _) = try car(context)
        // A bill's reading of a page with no dates on it.
        let bare = CaptureResult(kind: .utilityInvoice, kindConfidence: 0.7, fields: [], suggestions: [], reminder: nil,
                                 recognizedText: "", barcodes: [], document: nil, notices: [])
        var review = CaptureReview(result: bare, assets: [car], context: context).choosingKind(.rcaPolicy, assets: [car], context: context)
        #expect(review.addableKeys.contains(.expiryDate))
        #expect(!review.addableKeys.contains(.dueDate), "Only what this kind carries")
        review.addField(.expiryDate)
        let expiry = try #require(CaptureDay(year: 2027, month: 10, day: 31))
        let index = try #require(review.fields.firstIndex { $0.key == .expiryDate })
        review.fields[index].confirm(.day(expiry))
        #expect(!review.addableKeys.contains(.expiryDate))
        #expect(review.reminderDay == CaptureMapping.calendarDay(expiry))
    }
}
