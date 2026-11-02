import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A household with an electronic identity card (two PIN codes, filed in Acte,
/// which is locked by default) under a person, ready to export and bring back.
@MainActor
struct BackupHousehold {
    let container: ModelContainer
    let context: ModelContext
    let sealer: SecretSealer
    let actions: AssetActions
    let person: Asset
    let card: Asset

    static let pin = "0000"

    init() throws {
        container = try makeInMemoryContainer()
        context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        sealer = SecretSealer.ephemeral()
        actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") }, sealer: sealer)
        let store = TemplateStore(context: context)
        let member = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        person = try actions.create(name: "Manole Corina", template: member, values: FieldValues())
        card = try actions.create(
            name: "Carte de identitate – Manole Corina",
            template: documents,
            values: FieldValues([
                DocumentType.typeFieldKey: .text(DocumentType.idCard),
                DocumentType.variantFieldKey: .text(DocumentType.Variant.idCardElectronic),
                "document.pinAuthentication": .text(Self.pin),
            ]),
            parent: person
        )
    }

    var service: DossierArchiveService { DossierArchiveService(container: container, calendar: .bucharest) }

    /// This household's own backup, decoded.
    func package() throws -> DossierV3.Package {
        try DossierArchiveReader.read(try service.exportData(exportedAt: noon("2026-11-02")))
    }

    func template(_ key: String) throws -> CategoryTemplate {
        try #require(try ModelContext(container).fetch(FetchDescriptor<CategoryTemplate>()).first { $0.key == key })
    }

    func asset(_ id: UUID) throws -> Asset {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first)
    }
}

/// Every way an archive could try to rewrite a built-in category.
enum BuiltInRewrite: String, CaseIterable, Sendable {
    case newerVersionFromTheFuture
    case markedAsTheArchivesOwn
    case pinFieldsAsPlainText
    case lockTurnedOff
    case fieldsRemoved
    case renamedWithOtherReminders
    case allAtOnce

    func apply(to template: inout DossierV3.Template) {
        let all = self == .allAtOnce
        if all || self == .newerVersionFromTheFuture {
            template.version = 999
            template.updatedAt = noon("2099-01-01")
        }
        if all || self == .markedAsTheArchivesOwn { template.isBuiltIn = false }
        if all || self == .pinFieldsAsPlainText {
            for s in template.sections.indices {
                for f in template.sections[s].fields.indices where template.sections[s].fields[f].type == .secret {
                    template.sections[s].fields[f].type = .text
                    template.sections[s].fields[f].isSensitive = false
                }
            }
        }
        if all || self == .lockTurnedOff { template.isSensitive = false }
        if all || self == .fieldsRemoved { template.sections = [] }
        if all || self == .renamedWithOtherReminders {
            template.name = "Altceva"
            template.blueprints = []
        }
        // Every rewrite claims to be the newest edit, so a merge would take it if it could.
        template.updatedAt = max(template.updatedAt, noon("2099-01-01"))
    }
}

@MainActor
@Suite("Backups never change what the app defines")
struct BackupRulesTests {
    @Test(arguments: [ArchiveImportMode.merge, .replace], BuiltInRewrite.allCases)
    func builtInCategoriesAlwaysComeFromTheApp(mode: ArchiveImportMode, rewrite: BuiltInRewrite) throws {
        let household = try BackupHousehold()
        var package = try household.package()
        let index = try #require(package.templates.firstIndex { $0.key == BuiltInTemplates.Key.documents })
        rewrite.apply(to: &package.templates[index])

        try household.service.importPackage(package, mode: mode)

        let documents = try household.template(BuiltInTemplates.Key.documents)
        let catalog = BuiltInTemplates.documents
        #expect(documents.isBuiltIn)
        #expect(documents.builtInVersion == catalog.version)
        #expect(documents.name == catalog.name)
        #expect(documents.sections == catalog.sections)
        #expect(documents.blueprints == catalog.blueprints)
        #expect(documents.definition.field("document.pinAuthentication")?.type == .secret)
        #expect(documents.isSensitive, "The lock this phone had stays on")
        #expect(documents.updatedAt <= Date(), "No record's last change is later than now")

        // The PIN this phone keeps for the card is still there and still opens.
        let card = try household.asset(household.card.id)
        let sealed = try #require(card.value("document.pinAuthentication")?.textValue)
        #expect(try household.sealer.open(sealed) == BackupHousehold.pin)

        // And launching again changes nothing more.
        #expect(try !TemplateStore(context: ModelContext(household.container)).installBuiltIns())
    }

    @Test(arguments: [ArchiveImportMode.merge, .replace])
    func replacingOrMergingKeepsThePinsThisPhoneHas(mode: ArchiveImportMode) throws {
        let household = try BackupHousehold()
        let data = try household.service.exportData(exportedAt: noon("2026-11-02"))
        #expect(data.range(of: Data(SecretSealer.prefix.utf8)) == nil, "The backup carries no code")
        // The backup's copy is the newer one, so a merge takes its values too.
        household.card.updatedAt = noon("2026-10-01")
        try household.context.save()

        try household.service.importArchive(data, mode: mode)

        let card = try household.asset(household.card.id)
        let sealed = try #require(card.value("document.pinAuthentication")?.textValue)
        #expect(try household.sealer.open(sealed) == BackupHousehold.pin)
    }

    @Test(arguments: [ArchiveImportMode.merge, .replace])
    func aLockIsNeverMadeWeaker(mode: ArchiveImportMode) throws {
        let household = try BackupHousehold()
        let store = TemplateStore(context: household.context)
        let notebook = try store.createCustom(
            name: "Caiet", symbol: "book", tint: .gray,
            sections: [FieldSection(key: "main", title: "Caiet", fields: [
                FieldDefinition(key: "custom.code", label: "Cod", type: .secret, isSensitive: true),
            ])],
            isSensitive: true
        )
        var package = try household.package()
        let index = try #require(package.templates.firstIndex { $0.key == notebook.key })
        package.templates[index].isSensitive = false
        package.templates[index].sections[0].fields[0].type = .text
        package.templates[index].sections[0].fields[0].isSensitive = false
        package.templates[index].updatedAt = noon("2099-01-01")

        try household.service.importPackage(package, mode: mode)

        let imported = try household.template(notebook.key)
        #expect(imported.isSensitive)
        #expect(imported.definition.field("custom.code")?.type == .secret)
        #expect(imported.definition.field("custom.code")?.isSensitive == true)
    }

    @Test func aLockFromTheArchiveIsKept() throws {
        let household = try BackupHousehold()
        var package = try household.package()
        let index = try #require(package.templates.firstIndex { $0.key == BuiltInTemplates.Key.vehicle })
        package.templates[index].isSensitive = true
        package.templates[index].updatedAt = Date()
        try household.service.importPackage(package, mode: .merge)
        #expect(try household.template(BuiltInTemplates.Key.vehicle).isSensitive)
    }

    @Test(arguments: [ArchiveImportMode.merge, .replace])
    func sectionsFiledUnderEachOtherStayVisible(mode: ArchiveImportMode) throws {
        let household = try BackupHousehold()
        var package = try household.package()
        let personIndex = try #require(package.assets.firstIndex { $0.id == DossierV3.id(household.person.id) })
        let cardIndex = try #require(package.assets.firstIndex { $0.id == DossierV3.id(household.card.id) })
        // Each says it is filed under the other.
        package.assets[personIndex].parentId = DossierV3.id(household.card.id) as String
        for i in [personIndex, cardIndex] { package.assets[i].updatedAt = noon("2026-11-03") }

        let result = try household.service.importPackage(package, mode: mode)

        #expect(result.movedToTop == 1)
        let assets = try ModelContext(household.container).fetch(FetchDescriptor<Asset>())
        for asset in assets {
            var seen: Set<UUID> = []
            var current: Asset? = asset
            while let next = current {
                #expect(seen.insert(next.id).inserted, "Nothing is filed under itself")
                current = next.parent
            }
        }
        #expect(assets.contains { $0.parent == nil }, "Something is at the top of the binder")
    }

    @Test func aParentThatIsMissingLeavesTheSectionAtTheTop() throws {
        let household = try BackupHousehold()
        var package = try household.package()
        let cardIndex = try #require(package.assets.firstIndex { $0.id == DossierV3.id(household.card.id) })
        package.assets[cardIndex].parentId = DossierV3.id(UUID()) as String
        let target = try makeInMemoryContainer()
        let result = try DossierArchiveService(container: target, calendar: .bucharest).importPackage(package, mode: .replace)
        #expect(result.movedToTop == 1)
        let card = try #require(try ModelContext(target).fetch(FetchDescriptor<Asset>()).first { $0.name == household.card.name })
        #expect(card.parent == nil)
    }

    @Test func secretRowsNeverLeaveAndStayOnRestore() throws {
        let household = try BackupHousehold()
        try household.actions.setCustomFacts(household.person, [
            CustomFact(label: "Parolă Wi-Fi", value: "parola-exemplu", isSecret: true),
            CustomFact(label: "Număr contract apă", value: "123"),
        ])
        let kept = try #require(household.person.customFacts.first { $0.isSecret })
        #expect(SecretSealer.isSealed(kept.value), "A secret row is sealed when saved")
        #expect(kept.isSensitive)

        let data = try household.service.exportData(exportedAt: noon("2026-11-02"))
        let package = try DossierArchiveReader.read(data)
        let person = try #require(package.assets.first { $0.id == DossierV3.id(household.person.id) })
        #expect(person.customFacts?.map(\.label) == ["Număr contract apă"])
        #expect(data.range(of: Data("Parolă Wi-Fi".utf8)) == nil)

        try household.service.importArchive(data, mode: .replace)
        let restored = try household.asset(household.person.id)
        let secret = try #require(restored.customFacts.first { $0.isSecret })
        #expect(try household.sealer.open(secret.value) == "parola-exemplu")
        #expect(restored.customFacts.count == 2)
    }
}

@MainActor
@Suite("Sealed values never leave the app")
struct SealedValueTests {
    @Test func aSealedValueIsKnownByItsFormWhateverTheTemplateSays() throws {
        let sealer = SecretSealer.ephemeral()
        let sealed = try sealer.seal("0000")
        let values = FieldValues(["note": .text(sealed), "plate": .text("B-123-ABC")])

        #expect(SecretFields.stripping(values, definition: nil)["note"] == nil)
        #expect(SecretFields.stripping(values, definition: BuiltInTemplates.vehicle)["note"] == nil)
        #expect(SecretFields.stripping(values, definition: nil)["plate"] != nil)
        #expect(FieldFormatter.display(.text(sealed), as: .text) == SecretFields.mask)
        let plain = FieldDefinition(key: "note", label: "Notă", type: .text)
        #expect(FieldFormatter.display(.text(sealed), field: plain) == SecretFields.mask)
    }

    @Test func noExitCarriesASealedValueEvenUnderAFieldThatIsntSecret() throws {
        let household = try BackupHousehold()
        let sealed = try household.sealer.seal("0000")
        // A sealed value sitting in an ordinary field, as an old import could have left it.
        var values = household.card.values
        values["document.number"] = .text(sealed)
        household.card.valuesData = StoredJSON.encode(values)
        household.card.notes = "Notă \(sealed)"
        try household.context.save()

        let data = try household.service.exportData(exportedAt: noon("2026-11-02"))
        let package = try DossierArchiveReader.read(data)
        let card = try #require(package.assets.first { $0.id == DossierV3.id(household.card.id) })
        #expect(card.values["document.number"] == nil)

        let index = try SearchIndexBuilder(context: household.context).build()
        #expect(index.search(String(sealed.dropFirst(SecretSealer.prefix.count).prefix(12))).isEmpty)
    }
}

@Suite("Password-protected backups")
struct ArchiveEncryptionTests {
    let plain = Data((0..<5_000).map { UInt8($0 % 251) })

    @Test func opensOnlyWithItsPassword() throws {
        let sealed = try ArchiveEncryption.encrypt(plain, password: "parola-exemplu", iterations: 1_000, chunkSize: 1_024)
        #expect(ArchiveEncryption.isEncrypted(sealed))
        #expect(sealed.range(of: plain.prefix(64)) == nil)
        #expect(try ArchiveEncryption.decrypt(sealed, password: "parola-exemplu") == plain)
        #expect(throws: ArchiveEncryption.Failure.wrongPassword) { try ArchiveEncryption.decrypt(sealed, password: "alta-parola") }
    }

    @Test func refusesAnyChangeReorderingOrCut() throws {
        let sealed = try ArchiveEncryption.encrypt(plain, password: "parola-exemplu", iterations: 1_000, chunkSize: 1_024)
        var flipped = sealed
        flipped[flipped.count - 30] ^= 0x01
        #expect(throws: ArchiveEncryption.Failure.wrongPassword) { try ArchiveEncryption.decrypt(flipped, password: "parola-exemplu") }

        let chunk = 1_024 + ArchiveEncryption.tagSize
        let cut = sealed.prefix(ArchiveEncryption.headerSize + 2 * chunk)
        #expect(throws: ArchiveEncryption.Failure.wrongPassword) { try ArchiveEncryption.decrypt(Data(cut), password: "parola-exemplu") }

        var header = sealed
        header[ArchiveEncryption.magic.count + 2] ^= 0x01 // iterations
        #expect(throws: (any Error).self) { try ArchiveEncryption.decrypt(header, password: "parola-exemplu") }
    }

    @Test func emptyAndExactChunkSizesRoundTrip() throws {
        for size in [0, 1, 1_024, 2_048, 2_049] {
            let data = Data(repeating: 7, count: size)
            let sealed = try ArchiveEncryption.encrypt(data, password: "parola-exemplu", iterations: 1_000, chunkSize: 1_024)
            #expect(try ArchiveEncryption.decrypt(sealed, password: "parola-exemplu") == data)
        }
    }

    @Test func readsFromASliceOfABiggerBuffer() throws {
        let sealed = try ArchiveEncryption.encrypt(plain, password: "parola-exemplu", iterations: 1_000, chunkSize: 1_024)
        let padded = Data([9, 9, 9]) + sealed
        #expect(try ArchiveEncryption.decrypt(padded.dropFirst(3), password: "parola-exemplu") == plain)
    }

    @MainActor
    @Test func aProtectedBackupAsksForItsPasswordAndRestores() async throws {
        let household = try BackupHousehold()
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try await household.service.export(to: directory, password: "parola-exemplu", exportedAt: noon("2026-11-02"))
        let data = try Data(contentsOf: url)
        #expect(DossierArchiveReader.isPasswordProtected(data))
        #expect(throws: ArchiveError.needsPassword) { try DossierArchiveReader.read(data) }
        #expect(throws: ArchiveError.wrongPassword) { try DossierArchiveReader.read(data, password: "alta-parola") }

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: .bucharest).importArchive(data, password: "parola-exemplu", mode: .replace)
        #expect(try ModelContext(target).fetch(FetchDescriptor<Asset>()).contains { $0.name == household.card.name })
    }

    @Test func aPasswordNeedsEightCharactersTypedTheSameTwice() {
        #expect(!BackupPasswordRule(password: "scurta", repeated: "scurta").isReady)
        #expect(!BackupPasswordRule(password: "parola-exemplu", repeated: "parola-exemplo").isReady)
        #expect(BackupPasswordRule(password: "parola-exemplu", repeated: "parola-exemplu").isReady)
    }
}

@Suite("Zip reader and writer limits")
struct ZipLimitTests {
    @Test func readsAnArchiveThatIsASliceOfABiggerBuffer() throws {
        let zip = try DosarZipEngine.createArchive(entries: [.init(path: "a.txt", data: Data("Dosar".utf8))])
        let padded = Data(repeating: 0, count: 17) + zip
        let entries = try DosarZipEngine.unpackArchive(padded.dropFirst(17))
        #expect(entries.map(\.path) == ["a.txt"])
        #expect(entries.first?.data == Data("Dosar".utf8))
    }

    @Test func refusesMoreFilesThanAZipCanDescribe() {
        let entries = (0...Int(UInt16.max)).map { DosarZipEngine.Entry(path: "f\($0)", data: Data()) }
        #expect(throws: DosarZipEngine.ZipError.tooLargeToWrite) { try DosarZipEngine.createArchive(entries: entries) }
    }

    @Test func datesOutsideWhatAZipCanHoldAreWrittenAtItsEnds() throws {
        let far = Calendar.bucharest.date(from: DateComponents(year: 2200, month: 5, day: 1))!
        let early = Calendar.bucharest.date(from: DateComponents(year: 1970, month: 1, day: 1))!
        let zip = try DosarZipEngine.createArchive(entries: [
            .init(path: "far.txt", data: Data("a".utf8), modifiedDate: far),
            .init(path: "early.txt", data: Data("b".utf8), modifiedDate: early),
        ])
        let entries = try DosarZipEngine.unpackArchive(zip)
        let years = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, Calendar.current.component(.year, from: $0.modifiedDate)) })
        #expect(years["far.txt"] == 2107)
        #expect(years["early.txt"] == 1980)
    }
}

@MainActor
@Suite("Backups ask first")
struct BackupFlowTests {
    private func flow(_ household: BackupHousehold, _ outcome: FakeAuthenticator.Outcome, appLock: Bool = false) -> (BackupFlow, FakeAuthenticator, URL) {
        let authenticator = FakeAuthenticator(outcome)
        let vault = BiometricVaultManager(authenticator: authenticator, appLockEnabled: { appLock }, observesAppLifecycle: false)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (BackupFlow(container: household.container, vault: vault, workDirectory: directory, inbox: directory.appending(path: "Inbox")), authenticator, directory)
    }

    @Test func exportingNeedsFaceIDWhileASectionIsLocked() async throws {
        let household = try BackupHousehold()
        let (refused, refusedPrompts, refusedDirectory) = flow(household, .cancel)
        await refused.export(password: nil)
        #expect(refusedPrompts.prompts == 1)
        #expect(refused.exportURL == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: refusedDirectory.path(percentEncoded: false)).isEmpty, "Nothing is written")

        let (allowed, allowedPrompts, _) = flow(household, .succeed)
        await allowed.export(password: nil)
        #expect(allowedPrompts.prompts == 1)
        let url = try #require(allowed.exportURL)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        allowed.finishSharing()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), "The shared file goes once sharing ends")
    }

    @Test func withNoLockOnNothingIsAsked() async throws {
        let household = try BackupHousehold()
        for template in try household.context.fetch(FetchDescriptor<CategoryTemplate>()) { template.isSensitive = false }
        try household.context.save()
        let (flow, prompts, _) = flow(household, .cancel)
        await flow.export(password: nil)
        #expect(prompts.prompts == 0)
        #expect(flow.exportURL != nil)
    }

    @Test func theAppLockAloneAlsoAsks() async throws {
        let household = try BackupHousehold()
        for template in try household.context.fetch(FetchDescriptor<CategoryTemplate>()) { template.isSensitive = false }
        try household.context.save()
        let (flow, prompts, _) = flow(household, .fail, appLock: true)
        await flow.export(password: nil)
        #expect(prompts.prompts == 1)
        #expect(flow.exportURL == nil)
    }

    @Test func replacingEverythingNeedsFaceIDAndMergingDoesnt() async throws {
        let household = try BackupHousehold()
        let (owner, _, directory) = flow(household, .succeed)
        await owner.export(password: nil)
        let backup = try #require(owner.exportURL)
        let other = Asset(name: "Doar aici", templateKey: BuiltInTemplates.Key.other)
        household.context.insert(other)
        try household.context.save()

        let (refused, prompts, _) = flow(household, .cancel)
        await refused.open(backup)
        let pending = try #require(refused.pending)
        await refused.runImport(pending, mode: .replace)
        #expect(prompts.prompts == 1)
        #expect(try household.asset(other.id).name == "Doar aici", "Nothing was replaced")
        #expect(refused.pending == pending, "The backup waits as it was")

        await refused.runImport(pending, mode: .merge)
        #expect(prompts.prompts == 1, "Merging asks nothing")
        #expect(refused.resultText != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter { $0.hasPrefix("import-") }.isEmpty, "The working copy goes once read")
    }

    @Test func aFileHandedOverThroughOpenInIsRemovedOnceRead() async throws {
        let household = try BackupHousehold()
        let (flow, _, directory) = flow(household, .succeed)
        let inbox = directory.appending(path: "Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let handed = inbox.appending(path: "Dosar.dosar")
        try household.service.exportData().write(to: handed)
        let kept = directory.appending(path: "Ales din Fișiere.dosar")
        try household.service.exportData().write(to: kept)

        await flow.open(handed)
        #expect(!FileManager.default.fileExists(atPath: handed.path(percentEncoded: false)))
        let first = try #require(flow.pending)
        flow.discard(first.url)
        #expect(!FileManager.default.fileExists(atPath: first.url.path(percentEncoded: false)))
        await flow.open(kept)
        #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)), "A file picked in place is the person's own")
        flow.discard(try #require(flow.pending).url)
    }

    @Test func aProtectedBackupWaitsForItsPassword() async throws {
        let household = try BackupHousehold()
        let (flow, _, directory) = flow(household, .succeed)
        let url = try await household.service.export(to: directory, password: "parola-exemplu")
        await flow.open(url)
        #expect(flow.pending == nil)
        let file = try #require(flow.lockedFile)
        #expect(!file.wasWrong)
        await flow.unlock(file, with: "alta-parola")
        let again = try #require(flow.lockedFile)
        #expect(again.wasWrong)
        await flow.unlock(again, with: "parola-exemplu")
        let pending = try #require(flow.pending)
        flow.discard(pending.url)
    }
}

@MainActor
@Suite("The lock covers everything")
struct LockCoverTests {
    @Test func theAppLockCoversWhileTheSessionIsClosed() {
        #expect(LockCover.decide(appLockEnabled: true, anySectionLocked: false, isSessionUnlocked: false, isActive: true, isAuthenticating: false) == .lock)
        #expect(LockCover.decide(appLockEnabled: true, anySectionLocked: false, isSessionUnlocked: false, isActive: false, isAuthenticating: true) == .lock)
        #expect(LockCover.decide(appLockEnabled: true, anySectionLocked: false, isSessionUnlocked: true, isActive: true, isAuthenticating: false) == nil)
    }

    @Test func theAppSwitcherPictureIsCoveredWheneverLockedContentCouldShow() {
        // App lock on: always.
        #expect(LockCover.decide(appLockEnabled: true, anySectionLocked: false, isSessionUnlocked: true, isActive: false, isAuthenticating: false) == .privacy)
        // Only section locks, with a section open: covered.
        #expect(LockCover.decide(appLockEnabled: false, anySectionLocked: true, isSessionUnlocked: true, isActive: false, isAuthenticating: false) == .privacy)
        // Only section locks, all closed: nothing locked can be on screen.
        #expect(LockCover.decide(appLockEnabled: false, anySectionLocked: true, isSessionUnlocked: false, isActive: false, isAuthenticating: false) == nil)
        // No lock at all.
        #expect(LockCover.decide(appLockEnabled: false, anySectionLocked: false, isSessionUnlocked: true, isActive: false, isAuthenticating: false) == nil)
        // Not behind a Face ID prompt.
        #expect(LockCover.decide(appLockEnabled: false, anySectionLocked: true, isSessionUnlocked: true, isActive: false, isAuthenticating: true) == nil)
    }

    @Test func linksAndOpenedFilesWaitUntilUnlock() throws {
        let locked = Flag(true)
        let navigator = AppNavigator(isAppLocked: { locked.value })
        #expect(navigator.open(try #require(URL(string: "dosarcusina://settings/backup"))))
        #expect(navigator.consume() == nil)
        locked.value = false
        #expect(navigator.consume() == .settings(.backup))
        #expect(navigator.consume() == nil)

        locked.value = true
        let file = URL.temporaryDirectory.appending(path: "Dosar.dosar")
        #expect(navigator.open(file))
        #expect(navigator.consumeArchiveURL() == nil)
        #expect(navigator.consume() == nil)
        locked.value = false
        #expect(navigator.consumeArchiveURL() == file)
    }

    @Test func wholeBinderActionsAskEveryTimeAndLeaveTheSessionAlone() async {
        let authenticator = FakeAuthenticator(.succeed)
        let vault = BiometricVaultManager(authenticator: authenticator, appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(await vault.unlock(reason: "Acte") == .success)
        #expect(await vault.confirmWholeBinder(anySectionLocked: true, reason: "Copie") == .success)
        #expect(await vault.confirmWholeBinder(anySectionLocked: true, reason: "Copie") == .success)
        #expect(authenticator.prompts == 3, "Asked every time, even with the session open")
        #expect(vault.isSessionUnlocked)
        #expect(await vault.confirmWholeBinder(anySectionLocked: false, reason: "Copie") == .success)
        #expect(authenticator.prompts == 3, "No lock, no question")
    }
}

@MainActor
@Suite("Search keeps no personal numbers")
struct SearchPrivacyTests {
    private let cnp = "1800101990006"

    @Test func aLockedSectionsReadTextIsNeverIndexedWhateverTheKind() throws {
        let household = try BackupHousehold()
        for kind in DocumentKind.allCases {
            let attachment = Attachment(fileName: "act.pdf", contentType: "application/pdf", data: Data([1]), kind: kind)
            attachment.title = "Act \(kind.rawValue)"
            attachment.extractedText = "certificat cazier mentiune unica"
            household.context.insert(attachment)
            attachment.asset = household.card
        }
        try household.context.save()
        let index = try SearchIndexBuilder(context: household.context).build()
        #expect(index.search("mentiune").isEmpty)
        #expect(index.search("act").allSatisfy { $0.document.isSensitive }, "Titles still show, marked locked")
    }

    @Test func aDocumentOfAVisitInALockedSectionIsLockedToo() throws {
        let household = try BackupHousehold()
        let obligation = Obligation(title: "Reînnoire", kind: .routine, dueDay: CalendarDay(year: 2027, month: 1, day: 1), calendar: .bucharest)
        household.context.insert(obligation)
        obligation.asset = household.card
        let attachment = Attachment(fileName: "dovada.pdf", contentType: "application/pdf", data: Data([1]), kind: .other)
        attachment.extractedText = "textcitit"
        household.context.insert(attachment)
        attachment.obligation = obligation
        try household.context.save()
        let index = try SearchIndexBuilder(context: household.context).build()
        #expect(index.search("textcitit").isEmpty)
        #expect(index.search("dovada").allSatisfy { $0.document.isSensitive })
    }

    @Test func aCNPIsNeverIndexedAnywhere() throws {
        let household = try BackupHousehold()
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        car.notes = "Proprietar CNP \(cnp), de verificat"
        household.context.insert(car)
        let receipt = Attachment(fileName: "chitanta.pdf", contentType: "application/pdf", data: Data([1]), kind: .receipt)
        receipt.extractedText = "Client \(cnp) ENGIE Romania S.A."
        household.context.insert(receipt)
        receipt.asset = car
        try household.context.save()

        let index = try SearchIndexBuilder(context: household.context).build()
        #expect(index.search(cnp).isEmpty)
        #expect(index.search("1800101").isEmpty)
        #expect(!index.search("verificat").isEmpty, "The rest of the text is still found")
        #expect(!index.search("ENGIE").isEmpty)
    }

    @Test func recentSearchesKeepNoCNPAndNothingThatFoundLockedContent() {
        let open = SearchResult(document: SearchDocument(id: "a", kind: .asset, title: "VW Golf", subtitle: nil, route: .home, fields: []), score: 1)
        let locked = SearchResult(document: SearchDocument(id: "b", kind: .document, title: "Cazier", subtitle: nil, route: .home, fields: [], isSensitive: true), score: 1)
        #expect(SearchPrivacy.mayRemember("golf", results: [open]))
        #expect(!SearchPrivacy.mayRemember("cazier", results: [open, locked]))
        #expect(!SearchPrivacy.mayRemember(cnp, results: []))
        #expect(!SearchPrivacy.mayRemember("cnp \(cnp)", results: []))

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set([cnp, "golf"], forKey: "search.recent")
        let recent = RecentSearches(defaults: defaults)
        #expect(recent.items == ["golf"], "A CNP kept by an earlier version is dropped")
        recent.add("cazier", results: [locked])
        #expect(recent.items == ["golf"])
    }

    @Test func onlyThirteenDigitRunsCount() {
        #expect(SearchPrivacy.redacting("tel 0712345678") == "tel 0712345678")
        #expect(SearchPrivacy.redacting("cod 18001019900061") == "cod 18001019900061")
        #expect(SearchPrivacy.redacting("cnp \(cnp).") == "cnp .")
    }
}

@Suite("Codes kept as secret rows")
struct SecretRowTests {
    @Test(arguments: [
        ("Parolă Wi-Fi", true), ("Wi-Fi", true), ("Cod alarmă", true), ("Cod interfon", true), ("PIN card parcare", true),
        ("Cod client", false), ("Cod POD", false), ("Număr contract", false), ("Pinguin", false),
    ])
    func aLabelThatNamesACodeStartsAsASecret(label: String, isCode: Bool) {
        #expect(CustomFact.looksLikeCode(label) == isCode)
    }

    @Test func aSecretRowShowsOnlyItsMask() throws {
        let sealed = try SecretSealer.ephemeral().seal("0000")
        let rows = AssetFacts.factRows(FieldValues(), customFacts: [CustomFact(label: "Cod alarmă", value: sealed, isSecret: true)], template: nil)
        #expect(rows.first?.text == SecretFields.mask)
        #expect(rows.first?.sealed == sealed)
        #expect(rows.first?.isSensitive == true)
    }
}

@MainActor
@Suite("A database that can't open yet")
struct StoreOpeningTests {
    struct Locked: Error {}

    @Test func waitsForTheUnlockInsteadOfShowingRecovery() throws {
        let available = Flag(false)
        let attempts = Counter()
        let controller = PersistenceController(
            storeURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store"),
            isProtectedDataAvailable: { available.value },
            makeContainer: { _ in
                attempts.count += 1
                guard available.value else { throw Locked() }
                return try makeInMemoryContainer()
            }
        )
        guard case .waitingForUnlock = controller.state else { Issue.record("Expected to wait"); return }
        controller.startFresh()
        guard case .waitingForUnlock = controller.state else { Issue.record("Nothing is moved aside while waiting"); return }

        available.value = true
        controller.protectedDataDidBecomeAvailable()
        guard case .ready = controller.state else { Issue.record("Expected the store to open"); return }
        #expect(attempts.count == 3)
    }

    @Test func aFullPhoneIsToldApartFromAnUnreadableFile() throws {
        let full = PersistenceController(
            storeURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store"),
            isProtectedDataAvailable: { true },
            makeContainer: { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError) }
        )
        guard case .failed(.outOfSpace) = full.state else { Issue.record("Expected out of space"); return }
        let broken = PersistenceController(
            storeURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store"),
            isProtectedDataAvailable: { true },
            makeContainer: { _ in throw Locked() }
        )
        guard case .failed(.unreadable) = broken.state else { Issue.record("Expected unreadable"); return }
    }
}

/// A value a test changes while the code under test reads it.
final class Flag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

final class Counter: @unchecked Sendable {
    var count = 0
}
