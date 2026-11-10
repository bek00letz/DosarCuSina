import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Identity documents from the review to the binder: named after their holder, filed
/// under the household member they belong to, with everything read kept on the
/// document and nothing personal in search. Names are placeholders or the public
/// specimen's; the CNP is fabricated with county code 99 and a valid control digit.
@Suite("Identity documents, filed by person")
@MainActor
struct IdentityFilingTests {

    private func field(_ key: CaptureFieldKey, _ value: CaptureValue, confidence: Double = 0.8, tier: CaptureTier = .heuristic) -> CaptureField {
        CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: tier)
    }

    private var cardFields: [CaptureField] {
        [
            field(.surname, .text("MANOLE")),
            field(.givenNames, .text("CORINA IOANA")),
            field(.holderName, .text("CORINA IOANA MANOLE")),
            field(.personalNumber, .text("2900520990015"), confidence: 0.97, tier: .deterministic),
            field(.birthDate, .day(CalendarDay(printedYear: 1990, month: 5, day: 20)!), confidence: 0.97, tier: .deterministic),
            field(.sex, .text("F"), confidence: 0.97, tier: .deterministic),
            field(.nationality, .text("ROU")),
            field(.documentNumber, .text("SP1236343")),
            field(.expiryDate, .day(CalendarDay(printedYear: 2035, month: 4, day: 6)!)),
        ]
    }

    private func card(notices: [CaptureNotice] = []) -> CaptureResult {
        let routing = CaptureRouter.route(kind: .identityCard, kindConfidence: 0.95, fields: cardFields)
        return CaptureResult(kind: .identityCard, kindConfidence: 0.95, fields: cardFields, suggestions: routing.suggestions,
                             reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: notices)
    }

    @Test("Named after the holder, surname first, in title case with diacritics")
    func titleNamesTheHolder() throws {
        let review = CaptureReview(result: card(), assets: [], context: try makeContext())
        #expect(review.title == "Carte de identitate – Manole Corina Ioana")
        #expect(CaptureMapping.titleCased("ȘTEFĂNESCU ION-ANDREI") == "Ștefănescu Ion-Andrei")
        #expect(CaptureMapping.titleCased("o’BRIEN  ana") == "O’Brien Ana")
    }

    @Test("Everything read is shown, in order, with distinct labels")
    func reviewShowsPersonalFields() throws {
        let review = CaptureReview(result: card(), assets: [], context: try makeContext())
        #expect(review.visibleFields.map(\.key) == [.surname, .givenNames, .personalNumber, .birthDate, .sex, .nationality, .documentNumber, .expiryDate])
        #expect(CaptureMapping.label(for: .surname) == "Nume de familie")
        #expect(review.visibleFields.allSatisfy { !$0.needsCheck })
    }

    @Test("Members match in any order, without case or diacritics")
    func memberMatching() {
        let ana = UUID(), corina = UUID(), other = UUID()
        let members = [(id: other, name: "Ion Exemplu"), (id: ana, name: "Ana Manole"), (id: corina, name: "corina mănole")]
        #expect(CaptureMapping.matchingMember(holderSurname: "MANOLE", holderName: "Manole Corina Ioana", among: members) == corina)
        #expect(CaptureMapping.matchingMember(holderSurname: "MANOLE", holderName: "Manole Corina Ioana", among: [(id: ana, name: "Ana Manole")]) == nil)
        #expect(CaptureMapping.matchingMember(holderSurname: "MANOLE", holderName: "Manole Corina Ioana", among: [(id: other, name: "IOANA CORINA MANOLE")]) == other)
        // Two equally partial matches: no guess.
        #expect(CaptureMapping.matchingMember(holderSurname: "MANOLE", holderName: "Manole Corina Ioana",
                                              among: [(id: ana, name: "Corina Manole"), (id: other, name: "Ioana Manole")]) == nil)
    }

    @Test("No matching member: a new one named after the holder, the card filed under them")
    func newMemberForTheHolder() async throws {
        let context = try makeContext()
        let review = CaptureReview(result: card(), assets: [], context: context)
        #expect(review.destination == .newAsset(templateKey: BuiltInTemplates.Key.member))
        #expect(review.newAssetName == "Manole Corina Ioana")

        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        let document = try #require(outcome.asset)
        #expect(document.templateKey == BuiltInTemplates.Key.documents)
        #expect(document.name == "Carte de identitate – Manole Corina Ioana")
        #expect(document.parent?.name == "Manole Corina Ioana")
        #expect(document.parent?.templateKey == BuiltInTemplates.Key.member)
        #expect(document.value("document.personalNumber") == .text("2900520990015"))
        #expect(document.value("document.birthDate") == .date(CalendarDay("1990-05-20")))
        #expect(document.value("document.sex") == .text("F"))
        #expect(document.value("document.nationality") == .text("ROU"))
        #expect(document.value("document.number") == .text("SP1236343"))
        #expect(document.value("document.type") == .text(DocumentType.idCard))
        #expect(document.activeObligations.contains { $0.blueprintKey == "document.renew" })

        let groups = try DocumentHolders.groups(in: context)
        #expect(groups.first { $0.holder?.name == "Manole Corina Ioana" }?.documents.map(\.id) == [document.id])
    }

    @Test("A matching member gets the card")
    func existingMember() async throws {
        let context = try makeContext()
        let memberTemplate = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.member))
        let member = try AssetActions(context: context).create(name: "Corina Manole", template: memberTemplate, values: FieldValues())
        let review = CaptureReview(result: card(), assets: [member], context: context)
        #expect(review.destination == .asset(member.id))

        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        #expect(outcome.asset?.parent?.id == member.id)
        #expect(outcome.asset?.templateKey == BuiltInTemplates.Key.documents)
    }

    @Test("Personal values and the text read off an identity document stay out of search")
    func nothingPersonalInSearch() async throws {
        let context = try makeContext()
        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            .save(CaptureReview(result: card(), assets: [], context: context))
        let document = try #require(outcome.asset)
        try AttachmentActions(context: context).file(
            DocumentDraft(title: document.name, fileName: "Carte de identitate.heic", kind: .identity, extractedText: "CNP / PIN 2900520990015\n20.05.1990"),
            asset: document
        )
        let index = try SearchIndexBuilder(context: context).build()
        #expect(index.search("2900520990015").isEmpty)
        #expect(index.search("SP1236343").isEmpty)
        #expect(index.search("20.05.1990").isEmpty)
        #expect(!index.search("Manole").isEmpty)
    }

    @Test("Reading again with the back keeps what the person changed")
    func readingAgainKeepsEdits() throws {
        let context = try makeContext()
        var before = CaptureReview(result: card(notices: [.identityBackMissing]), assets: [], context: context)
        #expect(before.asksForBackPage)
        let index = try #require(before.fields.firstIndex { $0.key == .nationality })
        before.fields[index].confirm(.text("Română"))
        before.title = "Buletinul Corinei"

        var withZone = cardFields
        withZone.removeAll { $0.key == .documentNumber || $0.key == .nationality }
        withZone.append(field(.documentNumber, .text("SP1236344"), confidence: 0.99, tier: .deterministic))
        withZone.append(field(.nationality, .text("ROU"), confidence: 0.95, tier: .deterministic))
        let routing = CaptureRouter.route(kind: .identityCard, kindConfidence: 0.98, fields: withZone)
        let after = CaptureReview(result: CaptureResult(kind: .identityCard, kindConfidence: 0.98, fields: withZone, suggestions: routing.suggestions,
                                                        reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: []),
                                  assets: [], context: context).carryingEdits(from: before, assets: [])
        #expect(after.value(.nationality) == .text("Română"))
        #expect(after.value(.documentNumber) == .text("SP1236344"))
        #expect(after.title == "Buletinul Corinei")
        #expect(!after.asksForBackPage)
    }

    @Test("A checked zone value that disagrees with the person's edit is offered, never applied")
    func zoneValueIsOfferedBesideAnEdit() throws {
        let context = try makeContext()
        var before = CaptureReview(result: card(notices: [.identityBackMissing]), assets: [], context: context)
        let number = try #require(before.fields.firstIndex { $0.key == .documentNumber })
        before.fields[number].confirm(.text("SP1236345"))
        let surname = try #require(before.fields.firstIndex { $0.key == .surname })
        before.fields[surname].confirm(.text("MANOLE"))   // typed, but the same as the zone

        var withZone = cardFields.filter { $0.key != .documentNumber && $0.key != .expiryDate }
        let zone = CaptureField.machineReadableSource
        withZone.append(CaptureField(key: .documentNumber, value: .text("SP1236343"), confidence: 0.99, sourceText: zone, tier: .deterministic))
        withZone.append(CaptureField(key: .expiryDate, value: .day(CalendarDay(printedYear: 2035, month: 4, day: 7)!), confidence: 0.99, sourceText: zone, tier: .deterministic))
        let routing = CaptureRouter.route(kind: .identityCard, kindConfidence: 0.98, fields: withZone)
        var after = CaptureReview(result: CaptureResult(kind: .identityCard, kindConfidence: 0.98, fields: withZone, suggestions: routing.suggestions,
                                                        reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: []),
                                  assets: [], context: context).carryingEdits(from: before, assets: [])

        let edited = try #require(after.fields.first { $0.key == .documentNumber })
        #expect(edited.value == .text("SP1236345"), "The person's value stays")
        let zoneValue = CaptureAlternative(CaptureValue.text("SP1236343"), source: .checked(machineReadable: true))
        #expect(edited.alternatives == [zoneValue], "The zone's value is offered beside it")
        #expect(after.fields.first { $0.key == .surname }?.alternatives.isEmpty == true, "Nothing to offer when they agree")
        // A field they didn't touch takes the zone's value.
        #expect(after.value(.expiryDate) == .day(CalendarDay(printedYear: 2035, month: 4, day: 7)!))
        #expect(after.fields.first { $0.key == .expiryDate }?.alternatives.isEmpty == true)

        let index = try #require(after.fields.firstIndex { $0.key == .documentNumber })
        after.fields[index].use(zoneValue)
        #expect(after.value(.documentNumber) == .text("SP1236343"))
        #expect(after.fields[index].alternatives.isEmpty, "Their own typed value isn't offered back")
        #expect(!after.fields[index].needsCheck)
    }
}
