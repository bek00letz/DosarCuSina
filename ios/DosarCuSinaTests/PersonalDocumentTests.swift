import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Adding a document for a person")
struct PersonalDocumentTests {
    private func setup() throws -> (ModelContext, Asset) {
        let context = try makeContext()
        let member = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.member))
        let corina = try AssetActions(context: context, calendar: .bucharest).create(name: "Manole Corina", template: member, values: FieldValues())
        return (context, corina)
    }

    @Test func onlyTypesWithRealVariantsHaveThem() throws {
        #expect(DocumentType.variants(of: DocumentType.criminalRecord).map(\.label) == ["Judiciar", "Fiscal", "Auto"])
        #expect(DocumentType.variants(of: DocumentType.bankCard).count == 2)
        #expect(DocumentType.variants(of: DocumentType.idCard).count == 2)
        #expect(DocumentType.variants(of: DocumentType.passport).count == 2)
        #expect(DocumentType.variants(of: DocumentType.drivingLicence).isEmpty)
        #expect(DocumentType.variants(of: DocumentType.other).isEmpty)
        let field = try #require(BuiltInTemplates.documents.field(DocumentType.variantFieldKey))
        let cazier = FieldValues([DocumentType.typeFieldKey: .text(DocumentType.criminalRecord)])
        #expect(field.applies(to: cazier))
        #expect(field.options(for: cazier).map(\.key) == DocumentType.variants(of: DocumentType.criminalRecord).map(\.key))
        #expect(!field.applies(to: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.drivingLicence)])))
    }

    @Test func theNameComesFromTheTypeVariantAndHolder() {
        var draft = PersonalDocumentDraft()
        #expect(draft.automaticName(holder: "Manole Corina") == nil)
        draft.choose(type: DocumentType.criminalRecord)
        #expect(draft.name(holder: "Manole Corina") == "Cazier – Manole Corina")
        draft.variant = DocumentType.Variant.criminalRecordFiscal
        #expect(draft.name(holder: "Manole Corina") == "Cazier fiscal – Manole Corina")
        draft.choose(type: DocumentType.idCard)
        #expect(draft.variant == nil, "A cazier's variant doesn't fit an identity card")
        draft.variant = DocumentType.Variant.idCardElectronic
        #expect(draft.name(holder: "Manole Corina") == "Carte de identitate – Manole Corina")
        draft.customName = "Buletinul nou"
        #expect(draft.name(holder: "Manole Corina") == "Buletinul nou")
    }

    @Test func savingFilesItUnderThePersonWithItsReminderInOneSave() throws {
        let (context, corina) = try setup()
        var draft = PersonalDocumentDraft()
        draft.choose(type: DocumentType.passport)
        draft.variant = DocumentType.Variant.passportTemporary
        draft.expiry = CalendarDay(year: 2027, month: 6, day: 30)

        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let line = try #require(PersonalDocumentFiling.reminderLine(draft, template: template, actions: actions,
                                                                     today: CalendarDay(year: 2026, month: 11, day: 2)))
        #expect(line.hasPrefix("Expiră pe 30 iunie 2027."))
        #expect(line.contains("Te anunț"))

        let document = try PersonalDocumentFiling.save(draft, holder: corina, context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        #expect(!context.hasChanges)
        #expect(document.parent?.id == corina.id)
        #expect(document.name == "Pașaport temporar – Manole Corina")
        #expect(document.value(DocumentType.variantFieldKey)?.textValue == DocumentType.Variant.passportTemporary)
        let renewal = try #require(document.activeObligations.first)
        #expect(renewal.blueprintKey == "document.renew")
        #expect(renewal.reminders == ReminderProfile(leadDays: [90, 0], consequence: .legal, travelMarginDays: 180),
                "The passport's profile, with its travel cut-off, not a separate step")
    }

    @Test func aDocumentWithoutAnExpiryHasNoDeadline() throws {
        let (context, corina) = try setup()
        var draft = PersonalDocumentDraft()
        draft.choose(type: DocumentType.bankCard)
        let document = try PersonalDocumentFiling.save(draft, holder: corina, context: context)
        #expect(document.activeObligations.isEmpty)
        #expect(document.name == "Card bancar – Manole Corina")
    }

    @Test func savingWithoutATypeIsRefused() throws {
        let (context, corina) = try setup()
        #expect(throws: PersonalDocumentError.missingType) { try PersonalDocumentFiling.save(PersonalDocumentDraft(), holder: corina, context: context) }
    }

    @Test func aVariantThatNoLongerFitsIsDroppedOnSave() throws {
        let (context, corina) = try setup()
        var draft = PersonalDocumentDraft()
        draft.choose(type: DocumentType.criminalRecord)
        draft.variant = DocumentType.Variant.criminalRecordDriving
        let document = try PersonalDocumentFiling.save(draft, holder: corina, context: context)
        var values = document.values
        values[DocumentType.typeFieldKey] = .text(DocumentType.drivingLicence)
        try AssetActions(context: context).update(document, name: document.name, values: values, notes: nil)
        #expect(document.value(DocumentType.variantFieldKey) == nil)
    }

    @Test func aPhotoStartedFromAPersonBecomesOneOfTheirDocuments() async throws {
        let (context, corina) = try setup()
        var review = CaptureReview(
            result: CaptureResult(kind: .other, kindConfidence: 0.6, fields: [], suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], document: nil, notices: []),
            assets: [corina], context: context
        )
        review.destination = .asset(corina.id)
        review.filesAsPersonalDocument = true
        #expect(CaptureFiler.filedTemplateKey(for: review, destinationTemplateKey: BuiltInTemplates.Key.member, templates: try TemplateStore(context: context).templatesByKey()) == BuiltInTemplates.Key.documents)

        let outcome = try await CaptureFiler(context: context).save(review)
        let document = try #require(outcome.asset)
        #expect(document.parent?.id == corina.id)
        #expect(document.templateKey == BuiltInTemplates.Key.documents)
        #expect(document.name == "Document – Manole Corina")
    }

    @Test func aPhotographedElectronicCardKnowsItsVariantSoItsPINRowsAppear() async throws {
        let (context, corina) = try setup()
        var review = CaptureReview(
            result: CaptureResult(kind: .identityCard, kindConfidence: 0.95, fields: [
                CaptureField(key: .surname, value: .text("MANOLE"), confidence: 0.8, tier: .heuristic),
                CaptureField(key: .givenNames, value: .text("CORINA"), confidence: 0.8, tier: .heuristic),
                CaptureField(key: .documentVariant, value: .text(DocumentType.Variant.idCardElectronic), confidence: 0.9, tier: .deterministic),
            ], suggestions: [], reminder: nil, recognizedText: "", barcodes: [], document: nil, notices: []),
            assets: [corina], context: context
        )
        review.destination = .asset(corina.id)
        let outcome = try await CaptureFiler(context: context).save(review)
        let document = try #require(outcome.asset)
        #expect(document.value(DocumentType.variantFieldKey) == .text(DocumentType.Variant.idCardElectronic))
    }

    @Test func theElectronicCardLayoutReportsItsVariant() {
        let analysis = CaptureAnalyzer().analyze(text: """
        ROMANIA
        CARTE DE IDENTITATE IDENTITY CARD
        Nume / Surname
        EXEMPLU
        Prenume / Given names
        ION
        CNP / PIN 1800101990006
        Nr. document / Document no.
        XY123456
        Data expirării / Date of expiry
        15.03.2032
        Semnătura titularului / Holder's signature
        """, referenceDate: Date(timeIntervalSince1970: 1_793_577_600))
        #expect(analysis.fields.first { $0.key == .documentVariant }?.value.text == DocumentType.Variant.idCardElectronic)
    }

    @Test func withoutTheFlagALoosePaperStaysOnThePerson() throws {
        let context = try makeContext()
        var review = CaptureReview(
            result: CaptureResult(kind: .other, kindConfidence: 0.6, fields: [], suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], document: nil, notices: []),
            assets: [], context: context
        )
        review.destination = .none
        #expect(CaptureFiler.filedTemplateKey(for: review, destinationTemplateKey: BuiltInTemplates.Key.member, templates: try TemplateStore(context: context).templatesByKey()) == BuiltInTemplates.Key.member)
    }
}
