import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A new household member and their first document are created in one save.
@Suite("New holder in one save")
@MainActor
struct NewHolderSaveTests {

    @Test("A new person and their document are one save: a failure leaves no orphan member")
    func newPersonIsOneSave() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let members = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let renewal = try #require(documents.blueprints.first { $0.key == "document.renew" })
        let memberKey = BuiltInTemplates.Key.member
        let before = try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == memberKey }))

        // A renewal asked for without any date to start from fails after both were inserted.
        #expect(throws: (any Error).self) {
            try AssetActions(context: context).create(
                name: "Carte de identitate – Exemplu Ion", template: documents, values: FieldValues(),
                obligations: [PlannedObligation(blueprint: renewal, firstDue: nil, isSelected: true)],
                newParent: AssetActions.NewParent(name: "Exemplu Ion", template: members)
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == memberKey })) == before)
        #expect(try context.fetch(FetchDescriptor<Asset>()).allSatisfy { $0.name != "Exemplu Ion" })

        // And when it works, both arrive together, linked.
        let document = try AssetActions(context: context).create(
            name: "Carte de identitate – Exemplu Ion", template: documents, values: FieldValues(),
            newParent: AssetActions.NewParent(name: "Exemplu Ion", template: members)
        )
        #expect(document.parent?.name == "Exemplu Ion")
        #expect(try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == memberKey })) == before + 1)
    }

    @Test("Filing to a new person whose document template is missing leaves no one behind")
    func filerLeavesNoOrphan() async throws {
        let context = try makeContext()
        let documentsKey = BuiltInTemplates.Key.documents
        for template in try context.fetch(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == documentsKey })) {
            context.delete(template)
        }
        try context.save()
        let fields = [
            CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.8, tier: .heuristic),
            CaptureField(key: .givenNames, value: .text("ION"), confidence: 0.8, tier: .heuristic),
        ]
        let review = CaptureReview(
            result: CaptureResult(kind: .identityCard, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], document: nil, notices: []),
            assets: [], context: context
        )
        #expect(review.destination == .newAsset(templateKey: BuiltInTemplates.Key.member))
        var failed = false
        do { _ = try await CaptureFiler(context: context).save(review) } catch { failed = true }
        #expect(failed)
        let memberKey = BuiltInTemplates.Key.member
        #expect(try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == memberKey })) == 0)
    }
}
