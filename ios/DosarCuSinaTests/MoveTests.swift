import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Mută la…")
struct MoveTests {
    private struct Household {
        let context: ModelContext
        let actions: AssetActions
        let corina: Asset
        let ion: Asset
        let card: Asset
        let flat: Asset
        let house: Asset
        let tenancy: Asset
    }

    private func household() throws -> Household {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let store = TemplateStore(context: context)
        let member = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let home = try #require(try store.template(forKey: BuiltInTemplates.Key.home))
        let tenancy = try #require(try store.template(forKey: BuiltInTemplates.Key.tenancy))
        let corina = try actions.create(name: "Manole Corina", template: member, values: FieldValues())
        let ion = try actions.create(name: "Popescu Ion", template: member, values: FieldValues())
        let card = try actions.create(name: "Carte de identitate – Manole Corina", template: documents,
                                      values: FieldValues(["document.type": .text(DocumentType.idCard)]), parent: corina)
        let flat = try actions.create(name: "Apartament", template: home, values: FieldValues())
        let house = try actions.create(name: "Casa de la țară", template: home, values: FieldValues())
        let rent = try actions.create(name: "Chiriaș etaj 2", template: tenancy, values: FieldValues(), parent: flat)
        return Household(context: context, actions: actions, corina: corina, ion: ion, card: card, flat: flat, house: house, tenancy: rent)
    }

    @Test func destinationsAreTheOtherParentsOfTheSameKind() throws {
        let h = try household()
        let all = try h.context.fetch(FetchDescriptor<Asset>())
        #expect(AssetActions.moveDestinations(for: h.card, among: all).map(\.name) == ["Popescu Ion"])
        #expect(AssetActions.moveDestinations(for: h.tenancy, among: all).map(\.name) == ["Casa de la țară"])
        #expect(AssetActions.offersNewMember(for: h.card))
        #expect(!AssetActions.offersNewMember(for: h.tenancy))
        #expect(AssetActions.parentTemplateKey(for: h.flat) == nil, "A top-level home has nowhere to move")
    }

    @Test func movingADocumentFilesItUnderTheOtherPersonAndRenamesIt() throws {
        let h = try household()
        let proposed = AssetActions.renamedForHolder(h.card, newHolder: h.ion.name)
        #expect(proposed == "Carte de identitate – Popescu Ion")
        let receipt = try h.actions.move(h.card, to: .asset(h.ion.id), renamingTo: proposed)
        #expect(h.card.parent?.id == h.ion.id)
        #expect(h.card.name == "Carte de identitate – Popescu Ion")
        #expect(!h.context.hasChanges, "Saved in one step")

        try receipt.undo()
        #expect(h.card.parent?.id == h.corina.id)
        #expect(h.card.name == "Carte de identitate – Manole Corina")
    }

    @Test func keepingTheNameMovesOnly() throws {
        let h = try household()
        try h.actions.move(h.tenancy, to: .asset(h.house.id))
        #expect(h.tenancy.parent?.id == h.house.id)
        #expect(h.tenancy.name == "Chiriaș etaj 2")
    }

    @Test func aNameThePersonChoseIsNeverRewritten() {
        #expect(DocumentNaming.renamed("Buletinul vechi", from: "Manole Corina", to: "Popescu Ion") == nil)
        #expect(DocumentNaming.renamed("Pașaport – manole corina", from: "Manole Corina", to: "Popescu Ion") == "Pașaport – Popescu Ion")
        #expect(DocumentNaming.renamed("Pașaport – Popescu Ion", from: "Popescu Ion", to: "Popescu Ion") == nil)
        #expect(DocumentNaming.name(document: "Cazier judiciar", holder: "Manole Corina") == "Cazier judiciar – Manole Corina")
    }

    @Test func aNewPersonAndTheMoveAreOneStepAndUndoRemovesThePerson() throws {
        let h = try household()
        let receipt = try h.actions.move(h.card, to: .newMember(name: "Manole Ana"), renamingTo: "Carte de identitate – Manole Ana")
        let ana = try #require(h.card.parent)
        #expect(ana.name == "Manole Ana")
        #expect(ana.templateKey == BuiltInTemplates.Key.member)

        try receipt.undo()
        let names = try h.context.fetch(FetchDescriptor<Asset>()).map(\.name)
        #expect(!names.contains("Manole Ana"))
        #expect(h.card.parent?.id == h.corina.id)
    }

    @Test func aFailedMoveLeavesEverythingAsItWas() throws {
        let h = try household()
        UnitOfWork.failNextCommitForTesting(CocoaError(.fileWriteOutOfSpace), in: h.context)
        #expect(throws: (any Error).self) {
            try h.actions.move(h.card, to: .newMember(name: "Manole Ana"), renamingTo: "Carte de identitate – Manole Ana")
        }
        let names = try h.context.fetch(FetchDescriptor<Asset>()).map(\.name)
        #expect(!names.contains("Manole Ana"))
        #expect(h.card.parent?.id == h.corina.id)
        #expect(h.card.name == "Carte de identitate – Manole Corina")
    }

    @Test func aNewPersonNeedsAName() throws {
        let h = try household()
        #expect(throws: AssetActionError.missingName) { try h.actions.move(h.card, to: .newMember(name: "  ")) }
    }
}
