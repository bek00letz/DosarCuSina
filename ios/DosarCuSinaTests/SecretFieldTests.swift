import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Secret fields (PIN codes)")
struct SecretFieldTests {
    /// An obvious placeholder, never a real-looking code.
    private let pin = "0000"
    private let signingPin = "000000"

    private struct Setup {
        let container: ModelContainer
        let context: ModelContext
        let sealer: SecretSealer
        let actions: AssetActions
        let card: Asset
    }

    private func setup() throws -> Setup {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        let sealer = SecretSealer.ephemeral()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") }, sealer: sealer)
        let store = TemplateStore(context: context)
        let member = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let corina = try actions.create(name: "Manole Corina", template: member, values: FieldValues())
        let card = try actions.create(
            name: "Carte de identitate – Manole Corina",
            template: documents,
            values: FieldValues([
                DocumentType.typeFieldKey: .text(DocumentType.idCard),
                DocumentType.variantFieldKey: .text(DocumentType.Variant.idCardElectronic),
                "document.expiry": .date(CalendarDay(year: 2026, month: 11, day: 20)),
                "document.pinAuthentication": .text(pin),
                "document.pinSigning": .text(signingPin),
            ]),
            obligations: actions.plannedObligations(for: documents, values: FieldValues(["document.expiry": .date(CalendarDay(year: 2026, month: 11, day: 20))])),
            parent: corina
        )
        return Setup(container: container, context: context, sealer: sealer, actions: actions, card: card)
    }

    // MARK: Which documents have them

    @Test func onlyTheElectronicIdentityCardHasPinFields() {
        let definition = BuiltInTemplates.documents
        let secrets = SecretFields.fields(in: definition)
        #expect(secrets.map(\.label) == ["PIN pentru autentificare", "PIN pentru semnare"])
        func applying(type: String, variant: String?) -> [String] {
            var values = FieldValues([DocumentType.typeFieldKey: .text(type)])
            values[DocumentType.variantFieldKey] = variant.map(FieldValue.text)
            return secrets.filter { $0.applies(to: values) }.map(\.key)
        }
        #expect(applying(type: DocumentType.idCard, variant: DocumentType.Variant.idCardElectronic).count == 2)
        #expect(applying(type: DocumentType.idCard, variant: DocumentType.Variant.idCardWithoutChip).isEmpty)
        #expect(applying(type: DocumentType.idCard, variant: nil).isEmpty)
    }

    @Test func aBankCardIsNeverOfferedAPinField() {
        let secrets = SecretFields.fields(in: BuiltInTemplates.documents)
        for variant in [nil] + DocumentType.variants(of: DocumentType.bankCard).map(\.key) as [String?] {
            var values = FieldValues([DocumentType.typeFieldKey: .text(DocumentType.bankCard)])
            values[DocumentType.variantFieldKey] = variant.map(FieldValue.text)
            #expect(secrets.allSatisfy { !$0.applies(to: values) })
        }
    }

    // MARK: Kept sealed

    @Test func aPinIsSealedWhenSavedAndOpensWithThePhonesKey() throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        #expect(SecretSealer.isSealed(stored))
        #expect(!stored.contains(pin))
        #expect(try s.sealer.open(stored) == pin)
        #expect(FieldFormatter.display(.text(stored), as: .secret) == SecretFields.mask, "No general path shows a secret")

        // Editing other fields keeps the sealed value as it is; a new code is sealed in turn.
        var values = s.card.values
        values["document.number"] = .text("XX000000")
        try s.actions.update(s.card, name: s.card.name, values: values, notes: nil)
        #expect(s.card.value("document.pinAuthentication")?.textValue == stored)
        values["document.pinSigning"] = .text("111111")
        try s.actions.update(s.card, name: s.card.name, values: values, notes: nil)
        let signing = try #require(s.card.value("document.pinSigning")?.textValue)
        #expect(SecretSealer.isSealed(signing))
        #expect(try s.sealer.open(signing) == "111111")
    }

    @Test func anotherPhonesKeyCannotOpenIt() throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        #expect(throws: SecretFieldError.unreadable) { try SecretSealer.ephemeral().open(stored) }
    }

    @Test func turningTheCardIntoABankCardDropsThePins() throws {
        let s = try setup()
        var values = s.card.values
        values[DocumentType.typeFieldKey] = .text(DocumentType.bankCard)
        try s.actions.update(s.card, name: s.card.name, values: values, notes: nil)
        #expect(s.card.value("document.pinAuthentication") == nil)
        #expect(s.card.value("document.pinSigning") == nil)
    }

    // MARK: Never carried outward

    @Test func searchNeverIndexesAPin() throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        let index = try SearchIndexBuilder(context: s.context).build()
        #expect(index.search(pin).isEmpty)
        #expect(index.search(signingPin).isEmpty)
        #expect(index.search("PIN pentru autentificare").isEmpty, "Not even the label")
        #expect(index.search(String(stored.dropFirst(SecretSealer.prefix.count).prefix(8))).isEmpty)
        #expect(!index.search("Manole").isEmpty, "The document itself is still found by name")
    }

    @Test func widgetsNeverCarryAPin() throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        let snapshot = WidgetFeed.make(from: try ObligationSnapshot.fetchAll(in: s.context, calendar: .bucharest),
                                       now: noon("2026-11-02"), calendar: .bucharest)
        #expect(!snapshot.items.isEmpty, "The card's renewal is there")
        let json = String(decoding: try WidgetFeed.encode(snapshot), as: UTF8.self)
        #expect(!json.contains(pin))
        #expect(!json.contains(SecretSealer.prefix))
        #expect(!json.contains(stored))
    }

    @Test func archivesCarryNoPinAndImportsHaveNone() throws {
        let s = try setup()
        let data = try DossierArchiveService(container: s.container, calendar: .bucharest).exportData()
        let package = try DossierArchiveReader.read(data)
        let exported = try #require(package.assets.first { $0.name == s.card.name })
        #expect(exported.values.value["document.pinAuthentication"] == nil)
        #expect(exported.values.value["document.pinSigning"] == nil)
        #expect(exported.values.value["document.expiry"] != nil, "Everything else travels")
        for path in package.files.paths {
            let file = try #require(try package.files.data(at: path))
            #expect(file.range(of: Data(SecretSealer.prefix.utf8)) == nil)
        }

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: .bucharest).importArchive(data, mode: .replace)
        let imported = try #require(try ModelContext(target).fetch(FetchDescriptor<Asset>()).first { $0.name == s.card.name })
        #expect(imported.value("document.pinAuthentication") == nil)
    }

    @Test func mergingABackupKeepsThePinsThisPhoneHas() throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        let data = try DossierArchiveService(container: s.container, calendar: .bucharest).exportData()
        // The backup's copy of the card is newer, so its values win; it brings no PIN and takes none away.
        s.card.updatedAt = s.card.updatedAt.addingTimeInterval(-86_400)
        try s.context.save()
        let result = try DossierArchiveService(container: s.container, calendar: .bucharest).importArchive(data, mode: .merge)
        #expect(result.updated > 0)
        let id = s.card.id
        let merged = try #require(try ModelContext(s.container).fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first)
        #expect(merged.value("document.pinAuthentication")?.textValue == stored)
    }

    // MARK: Reveal

    @Test func revealAlwaysAsksForAFreshFaceIDAndLeavesTheSessionAlone() async throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        let authenticator = FakeAuthenticator(.succeed)
        let vault = BiometricVaultManager(authenticator: authenticator, appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(await vault.unlock(reason: "Acte") == .success)
        #expect(authenticator.prompts == 1)

        let reveal = SecretReveal(vault: vault, sealer: s.sealer)
        #expect(await reveal.open(stored, reason: "Arată PIN") == .revealed(pin))
        #expect(await reveal.open(stored, reason: "Arată PIN") == .revealed(pin))
        #expect(authenticator.prompts == 3, "Every reveal asks again, even with the section open")
        #expect(vault.isSessionUnlocked, "The session is neither opened nor closed by a reveal")

        authenticator.outcome = .cancel
        #expect(await reveal.open(stored, reason: "Arată PIN") == .notAuthenticated)
        authenticator.outcome = .fail
        #expect(await reveal.open(stored, reason: "Arată PIN") == .notAuthenticated)
        #expect(vault.isSessionUnlocked)
    }

    @Test func aRevealNeverOpensALockedSession() async throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(await SecretReveal(vault: vault, sealer: s.sealer).open(stored, reason: "Arată PIN") == .revealed(pin))
        #expect(!vault.isSessionUnlocked)
        #expect(vault.isLocked(sectionIsSensitive: true))
    }

    @Test func aCodeFromAnotherPhoneSaysWhatToDo() async throws {
        let s = try setup()
        let stored = try #require(s.card.value("document.pinAuthentication")?.textValue)
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(await SecretReveal(vault: vault, sealer: .ephemeral()).open(stored, reason: "Arată PIN") == .failed(.unreadable))
    }
}
