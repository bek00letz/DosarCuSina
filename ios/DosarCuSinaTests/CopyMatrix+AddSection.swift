import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Adaugă o secțiune" in `docs/COPY_MATRIX.md`: what each step says to each category, from what
/// the category declares (`AddSectionForm`) and the words every category shares
/// (`AddSectionWording`). Beside it, the rules the matrix makes checkable.
extension CopyMatrixTests {
    /// One row of what the flow says to a category: where, the words, and whether the category
    /// declares them itself (its name, its line, its fields, its deadlines) or the flow says them.
    /// The rules on words read only the flow's: a category's own fields may well name a brand.
    struct AddSectionRow {
        var place: String
        var words: String
        var isCategoryOwn: Bool
    }

    /// The moment the matrix plans deadlines at: whether one is ticked depends only on whether
    /// its first date is worked out, never on the day, but the plan is made on a set one.
    nonisolated static let addSectionNow = Date(timeIntervalSince1970: 1_800_000_000)

    /// A deadline's subtitle on one line of a table.
    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: AddSectionWording.lineBreak, with: " / ")
    }

    /// When a deadline the category has isn't offered with nothing typed: the field and the
    /// choices that bring it.
    static func condition(_ condition: BlueprintCondition, in definition: TemplateDefinition) -> String {
        let field = definition.allFields.first { $0.key == condition.field }
        let options = field?.options?.filter { condition.oneOf.contains($0.key) }.map(\.label) ?? condition.oneOf
        return "offered only when \(field?.label ?? condition.field) is " + options.map { "„\($0)”" }.joined(separator: " or ")
    }

    /// What each step says to one category, with nothing typed yet.
    @MainActor
    static func addSectionRows(_ definition: TemplateDefinition, actions: AssetActions) -> [AddSectionRow] {
        let form = AddSectionForm(definition)
        let option = form.option
        var rows: [AddSectionRow] = []

        let offered: String
        switch option.group {
        case .shortlist?: offered = "in „\(AddSectionWording.shortlistHeader)”"
        case .others?: offered = "in „\(AddSectionWording.othersHeader)”"
        case nil: offered = "(not offered: added from its parent section's page)"
        }
        rows.append(AddSectionRow(place: "Its option in the catalog",
                                  words: [option.title, option.summary].compactMap { $0 }.joined(separator: " — ") + " · " + offered,
                                  isCategoryOwn: true))

        rows.append(AddSectionRow(place: "The essentials' header", words: form.header, isCategoryOwn: true))
        let prompt = AddSectionModel.suggestedName(values: FieldValues(), definition: definition)
        rows.append(AddSectionRow(place: "The name, before anything is typed", words: "\(AddSectionWording.name), „\(prompt)”", isCategoryOwn: true))
        rows.append(AddSectionRow(place: "Under the name", words: form.nameFootnote, isCategoryOwn: false))
        if form.essentialFields.isEmpty {
            rows.append(AddSectionRow(place: "What it asks", words: "(nothing) — \(form.detailsLater ?? "")", isCategoryOwn: false))
        } else {
            rows.append(AddSectionRow(place: "What it asks", words: form.essentialFields.map(\.label).joined(separator: " · "), isCategoryOwn: true))
        }
        if form.asksHolder {
            rows.append(AddSectionRow(place: "Whose it is (added on its own, with people in the binder)",
                                      words: "\(AddSectionWording.holderTitle) — \(AddSectionWording.holderFootnote)", isCategoryOwn: false))
        }
        if let role = form.belongsTo {
            rows.append(AddSectionRow(place: "Where it goes (added on its own, with some in the binder)",
                                      words: "\(BelongingWording.fieldTitle(role)) — \(BelongingWording.fieldFootnote(role))", isCategoryOwn: false))
        }

        let planned = actions.plannedObligations(for: definition, values: FieldValues())
        rows.append(AddSectionRow(place: "The essentials' button", words: form.essentialsAction(offersDeadlines: !planned.isEmpty), isCategoryOwn: false))
        guard !definition.blueprints.isEmpty else { return rows }

        for blueprint in definition.blueprints {
            let subtitle = oneLine(AddSectionForm.deadlineSubtitle(blueprint, values: FieldValues()))
            let state: String
            if let plan = planned.first(where: { $0.blueprint.key == blueprint.key }) {
                state = plan.isSelected ? "ticked" : (plan.asksFirstDate ? "unticked, its date asked" : "unticked")
            } else if let condition = blueprint.appliesWhen {
                state = Self.condition(condition, in: definition)
            } else {
                state = "not offered"
            }
            rows.append(AddSectionRow(place: "A deadline: \(blueprint.title)", words: "\(subtitle) — (\(state))", isCategoryOwn: true))
        }
        if let note = form.laterNote(for: planned) {
            rows.append(AddSectionRow(place: "Under the deadlines", words: note, isCategoryOwn: false))
        }
        if !planned.isEmpty {
            rows.append(AddSectionRow(place: "The deadlines' button", words: AddSectionWording.add, isCategoryOwn: false))
        }
        return rows
    }

    /// The flow's frame, the same for every category.
    static var addSectionSharedRows: [(String, String)] {
        let pockets = CustomSectionDraft.offeredPockets.map { "\($0.title): \(AddSectionWording.pocketExplanation($0))" }
        return [
            ("The catalog's title", AddSectionWording.catalogTitle),
            ("Its groups", "\(AddSectionWording.shortlistHeader) · \(AddSectionWording.othersHeader)"),
            ("A category of one's own", "\(AddSectionWording.customOption) — \(AddSectionWording.customOptionHint)"),
            ("Its step (its questions are `CustomCategoryForm`'s)", "\(AddSectionWording.customTitle) — \(AddSectionWording.next)"),
            ("The first version's step (off, `CustomSectionStep.offersPocketList`)",
             "\(AddSectionWording.customName), „\(AddSectionWording.customNamePrompt)” · \(AddSectionWording.customKeeps): " + pockets.joined(separator: " · ")),
            ("The essentials' title", AddSectionWording.essentialsTitle),
            ("The deadlines' title", "\(AddSectionWording.deadlinesTitle) — \(AddSectionWording.deadlinesIntro)"),
            ("A ticked deadline asks", AddSectionWording.nextDate),
            ("Finishing without a category", AddSectionWording.noCategory),
        ]
    }

    /// "## Adding a section" of `docs/COPY_MATRIX.md`: the words every category shares, then each
    /// category's.
    @MainActor
    static func addSectionSection(_ categories: [Category]) throws -> String {
        let actions = AssetActions(context: try makeContext(), now: { addSectionNow })
        var out = "## Adding a section\n\n### What every category shares\n\n" + table(addSectionSharedRows) + "\n"
        for category in categories {
            let rows = addSectionRows(category.definition, actions: actions).map { ($0.place, $0.words) }
            out += "\n### \(category.title)\n\n" + table(rows) + "\n"
        }
        return out
    }
}

@MainActor
@Suite("Copy matrix: adding a section")
struct AddSectionCopyRulesTests {
    /// The actions the rules plan deadlines with, on the set moment the matrix uses.
    static func actions() throws -> AssetActions {
        AssetActions(context: try makeContext(), now: { CopyMatrixTests.addSectionNow })
    }

    /// The words the flow says to a category, folded, without the category's own.
    static func flowTokens(_ rows: [CopyMatrixTests.AddSectionRow]) -> Set<String> {
        CopyMatrixTests.tokens(rows.filter { !$0.isCategoryOwn }.map(\.words).joined(separator: " "))
    }

    @Test("No step says empty words")
    func noEmptyWords() throws {
        for (place, words) in CopyMatrixTests.addSectionSharedRows {
            #expect(!words.isEmpty && !words.contains("— —") && !words.contains("„”"), "\(place)")
        }
        let actions = try Self.actions()
        for category in try CopyMatrixTests.categories() {
            for row in CopyMatrixTests.addSectionRows(category.definition, actions: actions) {
                let words = row.words.trimmingCharacters(in: .whitespaces)
                #expect(!words.isEmpty && !words.contains("— —") && !words.contains("„”") && !words.hasPrefix("—") && !words.hasSuffix("—"),
                        "\(category.title): \(row.place) „\(row.words)”")
            }
        }
    }

    @Test("Vehicle words only for a vehicle's category, a doctor's and a vet's only for health and pets")
    func wordsStayWithTheirCategories() throws {
        let actions = try Self.actions()
        for category in try CopyMatrixTests.categories() {
            let tokens = Self.flowTokens(CopyMatrixTests.addSectionRows(category.definition, actions: actions))
            let kind = category.definition.behavior.visit
            if kind != .service {
                #expect(tokens.isDisjoint(with: CopyMatrixTests.vehicleWords), "\(category.title): \(tokens.intersection(CopyMatrixTests.vehicleWords).sorted())")
            }
            if kind != .doctor && kind != .vet {
                #expect(tokens.isDisjoint(with: CopyMatrixTests.careWords), "\(category.title): \(tokens.intersection(CopyMatrixTests.careWords).sorted())")
            }
        }
    }

    @Test("No empty list: a deadlines step only where the category has deadlines, the button adds otherwise")
    func noEmptyList() throws {
        let actions = try Self.actions()
        for category in try CopyMatrixTests.categories() {
            let definition = category.definition
            let form = AddSectionForm(definition)
            let planned = actions.plannedObligations(for: definition, values: FieldValues())
            #expect(Set(planned.map(\.blueprint.key)).isSubset(of: Set(definition.blueprints.map(\.key))), "\(category.title)")
            if definition.blueprints.isEmpty {
                #expect(planned.isEmpty, "\(category.title)")
                #expect(form.essentialsAction(offersDeadlines: false) == AddSectionWording.add, "\(category.title): no deadlines, so it adds")
            }
            #expect(form.laterNote(for: planned) == nil || planned.contains(where: \.asksFirstDate), "\(category.title): a note on dates only under some that ask one")
            let rows = CopyMatrixTests.addSectionRows(definition, actions: actions)
            #expect(rows.contains { $0.place.hasPrefix("A deadline: ") } == !definition.blueprints.isEmpty, "\(category.title)")
            #expect(rows.allSatisfy { !$0.place.hasPrefix("A deadline: ") || $0.place.count > "A deadline: ".count }, "\(category.title): a deadline with no title")
            if !form.essentialFields.isEmpty {
                #expect(form.essentialFields.allSatisfy { !$0.label.isEmpty }, "\(category.title): an essential field with no label")
            }
        }
    }

    @Test("The name's example comes from what a category declares, and fits it")
    func nameExampleFollowsTheCategory() throws {
        for category in try CopyMatrixTests.categories() {
            let behavior = category.definition.behavior
            let form = AddSectionForm(category.definition)
            let namingRoles: [CategoryBehavior.Role] = [.personalDocument, .holder, .subscription]
            let declaresOne = behavior.sectionNoun != nil || behavior.role.map { namingRoles.contains($0) } == true
            #expect((form.nameExample != nil) == declaresOne, "\(category.title)")
            if let example = form.nameExample {
                #expect(form.nameFootnote.contains(example), "\(category.title)")
            } else {
                #expect(form.nameFootnote == AddSectionWording.nameFootnoteWithoutExample, "\(category.title)")
            }
        }
        // A category of one's own that keeps bills plays a home, but isn't one: no flat's example.
        var withBills = CustomSectionDraft()
        withBills.name = "Barca"
        withBills.switches = CategorySwitches(hasDocuments: false, hasBills: true)
        #expect(AddSectionForm(withBills.definition(key: CustomSectionDraft.draftKey)).nameExample == nil)
    }

    @Test("A new section's name, before anything is typed and when left empty, is one of it, never the category's plural")
    func aSectionIsNamedAsOneThing() throws {
        for category in try CopyMatrixTests.categories() {
            let definition = category.definition
            let prompt = AddSectionModel.suggestedName(values: FieldValues(), definition: definition)
            #expect(prompt == definition.sectionName, "\(category.title): „\(prompt)”")
            if definition.key.hasPrefix(TemplateDefinition.customKeyPrefix) {
                #expect(prompt == definition.name, "\(category.title): a category of one's own is named as one thing already")
            } else {
                #expect(definition.behavior.singular != nil, "\(category.title) declares what one section is called")
                #expect(prompt != definition.name, "\(category.title): „\(prompt)” is the category's own name")
            }
        }
        #expect(BuiltInTemplates.purchase.sectionName == "Produsul", "An empty Garanții section is a product, not „Garanții”")
        #expect(BuiltInTemplates.vehicle.behavior.singular?.gender == .feminine)
        #expect(BuiltInTemplates.gender(ofSectionIn: BuiltInTemplates.Key.subscription) == .masculineOrNeuter, "„Păstrezi … ca al tău?” for a subscription")
    }

    @Test("A photo is offered for a deadline left for later only where a photo sets it")
    func laterNoteSaysAPhotoOnlyWhereOneSetsIt() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, now: { CopyMatrixTests.addSectionNow })
        let store = TemplateStore(context: context)
        let car = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle)).definition
        let carPlan = actions.plannedObligations(for: car, values: FieldValues())
        #expect(AddSectionForm(car).laterNote(for: carPlan) == AddSectionWording.datesLaterOrFromAPhoto, "An ITP report sets the ITP")
        let health = try #require(try store.template(forKey: BuiltInTemplates.Key.health)).definition
        let healthPlan = actions.plannedObligations(for: health, values: FieldValues())
        if healthPlan.contains(where: \.asksFirstDate) {
            #expect(AddSectionForm(health).laterNote(for: healthPlan) == AddSectionWording.datesLater, "No photo sets a vaccine's booster")
        }
    }
}
