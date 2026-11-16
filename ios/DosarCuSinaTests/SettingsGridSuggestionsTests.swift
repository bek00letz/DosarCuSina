import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Settings as a short list of pages, examples removed on the binder, empty category boxes
/// folded into the add box that names them, and suggestions kept out of the repair list.
@MainActor
@Suite("Settings pages, the binder's add box and suggestions")
struct SettingsGridSuggestionsTests {
    let calendar = Calendar.bucharest

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func add(_ name: String, _ key: String, under parent: Asset? = nil, isExample: Bool = false, in context: ModelContext) throws -> Asset {
        try AssetActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
            .create(name: name, template: try template(key, in: context), values: FieldValues(), parent: parent, isExample: isExample)
    }

    private func ledger() throws -> DataRepairLedger {
        DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "suggestions-\(UUID().uuidString)")))
    }

    // MARK: Settings

    @Test func everyLinkLandsOnItsPage() {
        let expected: [SettingsSection: SettingsPage] = [
            .notifications: .notifications, .privacy: .protection, .categories: .dosarScreen, .backup: .iCloudAndBackups,
            .examples: .examples, .repairs: .repairs, .ai: .ai, .about: .about,
        ]
        for section in SettingsSection.allCases {
            #expect(SettingsPage.path(for: section) == expected[section].map { [$0] }, "\(section) opens its page over the list")
        }
        #expect(SettingsPage.path(for: nil).isEmpty, "Without a link, the list")
        #expect(DeepLink.route(from: URL(string: "dosarcusina://settings/ai")!) == .settings(.ai))
        #expect(ShellRouting.plan(for: .settings(.repairs)).sheet == .settings(.repairs), "The repair prompt's Arată-mi opens the list's page")
    }

    @Test func theListIsShortAndShowsExamplesOnlyWhileThereAreSome() {
        #expect(SettingsPage.listed(hasExamples: false) == [.notifications, .protection, .dosarScreen, .iCloudAndBackups, .ai, .repairs, .about])
        #expect(SettingsPage.listed(hasExamples: true).contains(.examples))
        #expect(SettingsPage.groups(hasExamples: false).flatMap { $0 } == SettingsPage.listed(hasExamples: false), "Every page in one group, in order")
        #expect(SettingsPage.groups(hasExamples: true).flatMap { $0 } == SettingsPage.listed(hasExamples: true))
        #expect(Set(SettingsPage.allCases.map(\.title)).count == SettingsPage.allCases.count)
        #expect(SettingsPage.iCloudAndBackups.title == "iCloud și copii de siguranță", "Backups are copii de siguranță everywhere")
        #expect(SettingsPage.ai.title == "Citire cu AI")
        #expect(SettingsPage.repairs.title == "De corectat", "The repair list: De verificat is only the share inbox")
    }

    @Test func eachRowSaysHowItStandsInWords() {
        #expect(SettingsStatus.notifications(.authorized, minuteOfDay: 9 * 60) == "Pornite, la 09:00")
        #expect(SettingsStatus.notifications(.denied, minuteOfDay: 9 * 60) == "Oprite din Setările telefonului")
        #expect(SettingsStatus.notifications(.notDetermined, minuteOfDay: 9 * 60) == "Nu ai ales încă")

        #expect(SettingsStatus.protection(appLock: false, lockedCategories: 2, biometryName: "Face ID", needsChoosingAgain: false) == "Face ID pentru 2 categorii")
        #expect(SettingsStatus.protection(appLock: false, lockedCategories: 1, biometryName: "Face ID", needsChoosingAgain: false) == "Face ID pentru o categorie")
        #expect(SettingsStatus.protection(appLock: false, lockedCategories: 20, biometryName: "Face ID", needsChoosingAgain: false) == "Face ID pentru 20 de categorii")
        #expect(SettingsStatus.protection(appLock: true, lockedCategories: 2, biometryName: "Face ID", needsChoosingAgain: false) == "Toată aplicația cere Face ID")
        #expect(SettingsStatus.protection(appLock: false, lockedCategories: 0, biometryName: "Touch ID", needsChoosingAgain: false) == "Oprită")
        #expect(SettingsStatus.protection(appLock: false, lockedCategories: 0, biometryName: "Face ID", needsChoosingAgain: true) == "Totul cere Face ID până alegi din nou",
                "Locks that couldn't be read stay on, and the row says so")

        #expect(SettingsStatus.dosarScreen(hiddenCategories: 0) == "Toate categoriile se văd")
        #expect(SettingsStatus.dosarScreen(hiddenCategories: 1) == "O categorie ascunsă")
        #expect(SettingsStatus.dosarScreen(hiddenCategories: 3) == "3 categorii ascunse")

        #expect(SettingsStatus.iCloud(sync: .on, health: .upToDate(.now), isStopping: false) == "Totul e sincronizat")
        #expect(SettingsStatus.iCloud(sync: .noAccount, health: nil, isStopping: false) == "Nu ești conectat la iCloud")
        #expect(SettingsStatus.iCloud(sync: .off, health: nil, isStopping: false) == "Doar pe telefon")
        #expect(SettingsStatus.iCloud(sync: .notInThisBuild, health: nil, isStopping: false) == "Doar pe telefon")
        #expect(SettingsStatus.iCloud(sync: .waitingForExamples, health: nil, isStopping: false) == "Pe telefon, cât sunt exemple")

        #expect(SettingsStatus.ai(readyWith: nil) == "Oprită, citesc pe telefon")
        #expect(SettingsStatus.ai(readyWith: .gemini) == AIProvider.gemini.name)

        #expect(SettingsStatus.repairs(0) == "Nimic de corectat")
        #expect(SettingsStatus.repairs(1) == "Un lucru de corectat")
        #expect(SettingsStatus.repairs(3) == "3 lucruri de corectat")
    }

    // MARK: Examples, removed where they are

    @Test func theBinderRemovesExamplesWithTheUndo() throws {
        let context = try makeContext()
        let car = try add("VW Golf 2018", BuiltInTemplates.Key.vehicle, in: context)
        _ = try add("Apartament Exemplu", BuiltInTemplates.Key.home, isExample: true, in: context)
        let before = try context.fetch(FetchDescriptor<Asset>())
        #expect(ExampleRemoval.isOffered(assets: before))

        let toast = try ExampleRemoval.remove(in: context)
        let after = try context.fetch(FetchDescriptor<Asset>())
        #expect(!ExampleRemoval.isOffered(assets: after), "Once they are gone, the binder offers nothing")
        #expect(after.map(\.id) == [car.id], "What the person made stays")

        try #require(toast.receipt).undo()
        #expect(ExampleRemoval.isOffered(assets: try context.fetch(FetchDescriptor<Asset>())), "Anulează brings them back")
    }

    // MARK: The binder

    private func layout(_ context: ModelContext, contacts: Bool = false) throws -> (order: [BinderBoxID], line: String?) {
        let templates = try TemplateStore(context: context).all()
        let infos = templates.map { BinderLayout.TemplateInfo($0) }
        let assets = try context.fetch(FetchDescriptor<Asset>()).map(BinderLayout.AssetInfo.init)
        let order = BinderLayout.defaultOrder(templates: infos, assets: assets, hasContacts: contacts)
        let names = BinderLayout.addBoxNames(offered: SectionOffers(templates).inOrder.map { BinderLayout.TemplateInfo($0) }, templates: infos, assets: assets)
        return (order, BinderLayout.addBoxLine(names))
    }

    @Test func emptyCategoryBoxesFoldIntoTheAddBoxWhichNamesThem() throws {
        let context = try makeContext()
        let car = try add("VW Golf 2018", BuiltInTemplates.Key.vehicle, in: context)
        let first = try layout(context)
        #expect(first.order == [.asset(car.id)], "No Acte, Garanții, Abonamente or Agendă while they hold nothing")
        #expect(first.line == "Acte, Garanții, Abonamente, Locuințe…", "The add box still shows what the binder can hold")

        _ = try add("Espressor Exemplu", BuiltInTemplates.Key.purchase, in: context)
        let second = try layout(context, contacts: true)
        #expect(second.order.contains(.category(BuiltInTemplates.Key.purchase)), "Garanții gets its box as soon as it holds something")
        #expect(second.order.last == .agenda, "Agendă comes back with its first contact")
        #expect(second.line?.contains("Garanții") == false)
        #expect(second.line?.hasPrefix("Acte, Abonamente") == true)

        _ = try add("Persoană Exemplu", BuiltInTemplates.Key.member, in: context)
        #expect(try layout(context).order.contains(.category(BuiltInTemplates.Key.documents)), "Acte holds the household's people")
    }

    @Test func theAddBoxNamesOnlyWhatCanBeAddedOnItsOwnAndStopsAtFour() {
        let templates: [BinderLayout.TemplateInfo] = [
            .init(key: "a", homeOrder: 0, isOnHome: true, name: "Mașini"),
            .init(key: "b", homeOrder: 1, isOnHome: true, box: .wholeCategory, name: "Garanții"),
            .init(key: "c", homeOrder: 2, isOnHome: true, box: .insideOther, name: "Chiriași"),
            .init(key: "d", homeOrder: 3, isOnHome: false, name: "Biciclete"),
            .init(key: "e", homeOrder: 4, isOnHome: true, name: "Animale"),
            .init(key: "f", homeOrder: 5, isOnHome: true, name: "Plante"),
            .init(key: "g", homeOrder: 6, isOnHome: true, name: "Espressoare"),
            .init(key: "h", homeOrder: 7, isOnHome: true, name: "Altele"),
        ]
        let names = BinderLayout.addBoxNames(offered: templates, templates: templates, assets: [])
        #expect(names.names == ["Garanții", "Mașini", "Animale", "Plante"], "A folded box first; never one that lives inside another, never a hidden one")
        #expect(names.more)
        #expect(BinderLayout.addBoxLine(names) == "Garanții, Mașini, Animale, Plante…")
        #expect(BinderLayout.addBoxLine(([], false)) == nil, "Nothing left to name: just „Adaugă o secțiune”")
        #expect(BinderLayout.addBoxLine((["Acte"], false)) == "Acte")
    }

    // MARK: Where grouping is offered

    @Test func groupingIsOfferedOnTheBoxAndAMenuOfOneShowsItsItem() throws {
        let context = try makeContext()
        let first = try add("VW Golf 2018", BuiltInTemplates.Key.vehicle, in: context)
        _ = try add("Dacia Logan 2020", BuiltInTemplates.Key.vehicle, in: context)
        let model = BinderBoxes(templates: try TemplateStore(context: context).all(), assets: try context.fetch(FetchDescriptor<Asset>()),
                                providerCount: 0, vault: .shared, context: context)
        let box = try #require(model.box(for: .asset(first.id)))
        #expect(box.groupingOffer == .grouped, "The box's press-and-hold menu offers one box for both")
        #expect(try template(BuiltInTemplates.Key.vehicle, in: context).groupingOffer(sections: 2) == .grouped,
                "Setări › Ecranul Dosar reads the same rule")

        #expect(DSMoreActionsLayout(count: 0) == .nothing)
        #expect(DSMoreActionsLayout(count: 1) == .direct, "A single item shows as itself")
        #expect(DSMoreActionsLayout(count: 2) == .menu)
    }

    // MARK: Suggestions

    @Test func onlyThePlantStepIsASuggestion() {
        #expect(DataRepairs.steps.filter { $0.isSuggestion }.map { type(of: $0).id } == [.sectionsIntoTheirHome])
        #expect(DataRepairs.step(.sectionsIntoTheirHome).applyTitle == "Mută")
        #expect(DataRepairs.step(.counterOutliers).applyTitle == "Corectează")
    }

    @Test func suggestionsWaitInDinTimpNotInTheRepairListOrItsPrompt() throws {
        let context = try makeContext()
        _ = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        _ = try add("Ferigă", BuiltInTemplates.Key.plants, in: context)
        let ledger = try ledger()
        let center = DataRepairCenter(ledger: ledger)
        try center.refresh(in: context, announce: true)
        #expect(!center.pending.contains { $0.step == .sectionsIntoTheirHome }, "Not in the repair list")
        #expect(!center.announcement.contains { $0.step == .sectionsIntoTheirHome }, "Never the launch prompt")
        #expect(center.suggestions.map(\.step) == [.sectionsIntoTheirHome])

        let note = try #require(AttentionModel.suggestionNote(count: center.suggestions.count, topics: center.suggestionTopics))
        #expect(note.opens == .suggestions)
        #expect(note.title == "O sugestie pentru dosar")
        #expect(note.detail == "Ce ține de altă secțiune. Nu schimb nimic fără tine.")
        #expect(!note.detail.contains("Ferigă"), "The note names nothing a locked section wouldn't")
        #expect(note.expectedDay == nil)

        let bill = AttentionNote(opens: .section(UUID()), title: "Factura de la ENGIE n-a venit luna asta", detail: "", expectedDay: CalendarDay("2026-11-02"))
        #expect(AttentionModel.calmNotes(missingBills: [bill], suggestions: note) == [bill, note], "Bills first, the suggestions last")
        #expect(AttentionModel.suggestionNote(count: 0, topics: []) == nil)
        #expect(AttentionModel.suggestionNote(count: 3, topics: ["Ce stă într-o locuință"])?.title == "3 sugestii pentru dosar")

        // "Lasă așa" is kept by the same stored ids, so nothing is asked twice.
        try center.dismiss(center.suggestions, in: context)
        #expect(center.suggestions.isEmpty)
        let later = DataRepairCenter(ledger: ledger)
        try later.refresh(in: context, announce: true)
        #expect(later.suggestions.isEmpty)
    }

    @Test func applyingASuggestionMovesThePlantAndTheNoteGoes() throws {
        let context = try makeContext()
        let flat = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        let fern = try add("Ferigă", BuiltInTemplates.Key.plants, in: context)
        let center = DataRepairCenter(ledger: try ledger())
        try center.refresh(in: context, announce: false)
        try center.apply(center.suggestions, in: context)
        #expect(fern.parent?.id == flat.id)
        #expect(center.suggestions.isEmpty)
        #expect(AttentionModel.suggestionNote(count: center.suggestions.count, topics: center.suggestionTopics) == nil)
    }
}
