import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Contract tests over every kind of document and every category: what the kind
/// profiles, the field table and the blueprints name exists, and the review's reminder
/// line says exactly what saving does.
@Suite("Kinds and categories")
@MainActor
struct CaptureKindProfileTests {

    // MARK: Every kind

    @Test func everyKindHasExactlyOneProfile() {
        let kinds = CaptureKindProfile.all.map(\.kind)
        #expect(Set(kinds) == Set(CaptureDocumentKind.allCases))
        #expect(kinds.count == CaptureDocumentKind.allCases.count)
    }

    @Test("Every kind names real catalog keys", arguments: CaptureDocumentKind.allCases)
    func everyKindNamesRealCatalogKeys(kind: CaptureDocumentKind) throws {
        let profile = kind.profile
        if let key = profile.templateKey {
            let template = try #require(BuiltInTemplates.definition(for: key), "\(kind): \(key) is a built-in category")
            if let blueprint = profile.blueprintKey {
                #expect(template.blueprints.contains { $0.key == blueprint }, "\(kind): \(blueprint) is one of \(key)'s deadlines")
            }
        }
        for cover in profile.covers {
            let deadline = try #require(profile.deadline(cover: cover), "\(kind): \(cover) has a deadline")
            let template = try #require(BuiltInTemplates.definition(for: deadline.templateKey))
            let blueprint = try #require(template.blueprints.first { $0.key == deadline.blueprintKey }, "\(cover): \(deadline.blueprintKey)")
            #expect(blueprint.facts != nil, "A policy's deadline says where its facts go")
            #expect(InsuranceCover.options.contains { $0.key == cover })
        }
        if let type = profile.documentType {
            #expect(DocumentType.options.contains { $0.key == type })
            #expect(profile.title == DocumentType.label(for: type), "A personal document is called what its type is called")
        }
        if let field = profile.deadlineField {
            #expect(profile.expectedKeys.contains(field), "\(kind): the AI provider is asked for the day the deadline follows")
        }
        #expect(!profile.title.isEmpty)
        #expect(Set(profile.expectedKeys).count == profile.expectedKeys.count, "\(kind): no field asked for twice")
    }

    @Test("The deadline's day lands where its blueprint looks", arguments: CaptureDocumentKind.allCases)
    func theDeadlineDayLandsWhereItsBlueprintLooks(kind: CaptureDocumentKind) throws {
        let profile = kind.profile
        let covers = profile.covers.isEmpty ? [nil] : profile.covers.map(Optional.some)
        for cover in covers {
            guard let deadline = profile.deadline(cover: cover), let field = profile.deadlineField else { continue }
            let template = try #require(BuiltInTemplates.definition(for: deadline.templateKey))
            let blueprint = try #require(template.blueprints.first { $0.key == deadline.blueprintKey })
            let lands = CaptureMapping.fieldKey(for: field, kind: kind, in: template, deadline: blueprint)
            if blueprint.isFieldDriven {
                #expect(lands == blueprint.drivingField, "\(kind): the day fills the field \(deadline.blueprintKey) follows")
            } else {
                #expect(lands == nil, "\(kind): \(deadline.blueprintKey) keeps its own day, off the section")
            }
        }
    }

    @Test func everyFieldTheTableNamesExists() {
        let fields = Set(BuiltInTemplates.all.flatMap { $0.allFields.map(\.key) })
        for (key, candidates) in CaptureMapping.candidates {
            for candidate in candidates {
                #expect(fields.contains(candidate), "\(key.rawValue) → \(candidate) is a built-in field")
            }
        }
    }

    // MARK: Every category

    @Test("Every blueprint's facts are fields of its category", arguments: BuiltInTemplates.all.map(\.key))
    func everyBlueprintsFactsAreFields(templateKey: String) throws {
        let template = try #require(BuiltInTemplates.definition(for: templateKey))
        for blueprint in template.blueprints {
            for (role, field) in blueprint.facts?.fields ?? [] {
                #expect(template.field(field) != nil, "\(blueprint.key).\(role.rawValue) → \(field)")
            }
            if let field = blueprint.drivingField {
                #expect(template.field(field) != nil, "\(blueprint.key) follows \(field)")
            }
        }
    }

    @Test func eachPartIsPlayedByOneBuiltInCategory() {
        let roles = BuiltInTemplates.all.compactMap(\.behavior.role)
        #expect(Set(roles).count == roles.count)
        for role in [CategoryBehavior.Role.holder, .personalDocument, .subscription, .home] {
            #expect(roles.contains(role), "\(role.rawValue) has a category")
        }
        // A pocket that gathers a category is shown by some category.
        let pockets = Set(BuiltInTemplates.all.flatMap(\.pockets))
        for template in BuiltInTemplates.all {
            if let pocket = template.behavior.parentPocket { #expect(pockets.contains(pocket)) }
        }
    }

    @Test func aCategoryOfOnesOwnCanBehaveLikeABuiltIn() throws {
        let context = try makeContext()
        let custom = try TemplateStore(context: context).createCustom(name: "Unelte", symbol: "hammer", pockets: [.keyFacts])
        #expect(custom.behavior == .standard)
        custom.behavior = CategoryBehavior(box: .wholeCategory, listing: .byWarranty)
        let order = BinderLayout.defaultOrder(
            templates: [.init(key: custom.key, homeOrder: 0, isOnHome: true, box: custom.behavior.box)],
            assets: [.init(id: UUID(), templateKey: custom.key, isTopLevel: true, createdAt: .now)]
        )
        #expect(order == [.category(custom.key), .agenda], "One box for the whole category, like Garanții")
        #expect(StoredJSON.decode(CategoryBehavior.self, from: Data(#"{"box":"somethingNew","listing":"byHolder"}"#.utf8))
                == CategoryBehavior(listing: .byHolder), "A value from a newer version reads as the default")
    }

    // MARK: The review says what saving does

    private static let today = CalendarDay("2026-11-02")

    private func result(_ kind: CaptureDocumentKind, deadlineDay: CalendarDay?) -> CaptureResult {
        var fields: [CaptureField] = []
        func add(_ key: CaptureFieldKey, _ value: CaptureValue) {
            fields.append(CaptureField(key: key, value: value, confidence: 0.9, sourceText: nil, tier: .heuristic))
        }
        if let field = kind.profile.deadlineField, let deadlineDay,
           let day = CaptureDay(year: deadlineDay.year, month: deadlineDay.month, day: deadlineDay.day) {
            add(field, .day(day))
        }
        switch kind {
        case .fiscalReceipt, .warrantyCertificate: add(.productName, .text("Hotă Exemplu"))
        case .utilityInvoice, .contract: add(.provider, .text("ENGIE Romania S.A."))
        default: break
        }
        let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.9, fields: fields)
        return CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                             recognizedText: "", barcodes: [], document: nil, notices: [])
    }

    @Test("The reminder line names a reminder exactly when saving makes one",
          arguments: CaptureDocumentKind.allCases, [CalendarDay("2027-06-10"), CalendarDay("2026-05-10")])
    func theReminderLineMatchesWhatSavingDoes(kind: CaptureDocumentKind, day: CalendarDay) async throws {
        let context = try makeContext()
        let review = CaptureReview(result: result(kind, deadlineDay: day), assets: [], context: context)
        let templates = try TemplateStore(context: context).templatesByKey()
        let plan = CaptureFilingPlan.make(for: review, templates: templates, assets: [], today: Self.today, calendar: .bucharest)
        let preview = CaptureReminderPreview.text(for: review, plan: plan, today: Self.today)
        #expect((preview?.contains("Te anunț") ?? false) == plan.schedulesReminder, "\(kind): \(preview ?? "no line")")
        guard review.destination != .none else {
            #expect(!plan.schedulesReminder)
            return
        }

        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        let made = plan.blueprint.flatMap { blueprint in outcome.asset?.activeObligations.first { $0.blueprintKey == blueprint.key } }
        #expect((made != nil) == plan.schedulesReminder, "\(kind): saving made a deadline exactly when the plan said so")
        if let made, let deadline = plan.deadline {
            #expect(made.dueDay(in: .bucharest) == deadline.day)
            #expect(made.reminderLeadDays == deadline.reminders.leadDays, "\(kind): it reminds as the line said")
        }
    }

    @Test("A home's optional policy gets its deadline")
    func aHomePolicyGetsItsDeadline() async throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        let home = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            .create(name: "Apartament", template: template, values: FieldValues())
        let fields = [
            CaptureField(key: .provider, value: .text("Exemplu Asigurări S.A."), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .policyNumber, value: .text("LOC-000001"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .coverageType, value: .text(InsuranceCover.home), confidence: 0.7, tier: .heuristic),
            CaptureField(key: .expiryDate, value: .day(CaptureDay(year: 2027, month: 10, day: 31)!), confidence: 0.9, tier: .heuristic),
        ]
        let routing = CaptureRouter.route(kind: .insurancePolicy, kindConfidence: 0.9, fields: fields)
        var review = CaptureReview(result: CaptureResult(kind: .insurancePolicy, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions,
                                                         reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: []),
                                   assets: [home], context: context)
        review.destination = .asset(home.id)
        let filer = CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let plan = try filer.plan(for: review)
        #expect(plan.deadline?.blueprint.key == BuiltInBlueprints.homeInsurance)
        let outcome = try await filer.save(review)
        let policy = try #require(outcome.obligation)
        #expect(policy.blueprintKey == BuiltInBlueprints.homeInsurance)
        #expect(policy.dueDay(in: .bucharest) == CalendarDay("2027-10-31"))
        #expect(home.value(HomeFields.policyNumber) == .text("LOC-000001"))
        let insurer = try #require(try context.fetch(FetchDescriptor<Provider>()).first)
        #expect(insurer.name == "Exemplu Asigurări S.A.")
        #expect(insurer.has(.insurer), "An insurer becomes a firm in Agendă")
    }

    @Test("A CASCO filed on a car fills CASCO's fields and its own deadline")
    func aCascoFillsItsOwnFields() async throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values[VehicleFields.plate] = .text("B-123-ABC")
        values[VehicleFields.policyNumber] = .text("RCA-000001")
        let car = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            .create(name: "VW Golf", template: template, values: values)
        let fields = [
            CaptureField(key: .licensePlate, value: .text("B 123 ABC"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .policyNumber, value: .text("CASCO-000001"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .claimsPhone, value: .text("0210000002"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .coverageType, value: .text(InsuranceCover.casco), confidence: 0.7, tier: .heuristic),
            CaptureField(key: .expiryDate, value: .day(CaptureDay(year: 2027, month: 10, day: 31)!), confidence: 0.9, tier: .heuristic),
        ]
        let routing = CaptureRouter.route(kind: .insurancePolicy, kindConfidence: 0.9, fields: fields)
        let review = CaptureReview(result: CaptureResult(kind: .insurancePolicy, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions,
                                                         reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: []),
                                   assets: [car], context: context)
        #expect(review.destination == .asset(car.id))
        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        #expect(outcome.obligation?.blueprintKey == BuiltInBlueprints.vehicleCASCO)
        #expect(car.value(VehicleFields.cascoPolicyNumber) == .text("CASCO-000001"))
        #expect(car.value(VehicleFields.policyNumber) == .text("RCA-000001"), "RCA's number stays RCA's")
        let page = DeadlineFacts.of(try #require(outcome.obligation), template: template.definition)
        #expect(page.policyNumber == "CASCO-000001")
        #expect(page.claimsPhone != nil && page.claimsPhone == car.value(VehicleFields.cascoClaimsPhone)?.textValue)
    }

    // MARK: Sections and firms

    @Test func aFieldThatDrivesADeadlineMakesItWhenItGetsAValue() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.subscription))
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        var values = FieldValues()
        values[SubscriptionFields.provider] = .text("ENGIE Romania S.A.")
        let subscription = try actions.create(name: "Gaz", template: template, values: values)
        #expect(!subscription.activeObligations.contains { $0.blueprintKey == "subscription.contractEnd" })

        values["subscription.contractEnd"] = .date(CalendarDay("2027-03-31"))
        try actions.update(subscription, name: "Gaz", values: values, notes: nil)
        let end = try #require(subscription.activeObligations.first { $0.blueprintKey == "subscription.contractEnd" })
        #expect(end.dueDay(in: .bucharest) == CalendarDay("2027-03-31"))

        // A day that has passed makes nothing: the contract is already over.
        values["subscription.contractEnd"] = nil
        try actions.update(subscription, name: "Gaz", values: values, notes: nil)
        try ObligationActions(context: context, calendar: .bucharest).delete(end)
        values["subscription.contractEnd"] = .date(CalendarDay("2026-01-31"))
        try actions.update(subscription, name: "Gaz", values: values, notes: nil)
        #expect(!subscription.activeObligations.contains { $0.blueprintKey == "subscription.contractEnd" })
    }

    @Test func aFirmIsFoundByItsCUIFirst() throws {
        let context = try makeContext()
        let actions = ProviderActions(context: context)
        let first = try #require(try actions.findOrCreate(name: "Exemplu Asigurări S.A.", taxID: "RO 12345678", trade: .insurer))
        #expect(first.taxID == "12345678")
        let byCUI = try actions.findOrCreate(name: "EXEMPLU ASIGURARI", taxID: "12345678", trade: .insurer)
        #expect(byCUI?.id == first.id, "Another spelling, the same CUI: the same firm")
        let otherFirm = try actions.findOrCreate(name: "Exemplu Asigurări S.A.", taxID: "87654321", trade: .insurer)
        #expect(otherFirm?.id != first.id, "The same name with another CUI is another firm")
        let named = try #require(try actions.findOrCreate(name: "Service Exemplu", trade: .mechanic))
        #expect(named.taxID == nil)
        let filled = try actions.findOrCreate(name: "Service Exemplu", taxID: "11223344", trade: .mechanic)
        #expect(filled?.id == named.id)
        #expect(named.taxID == "11223344", "A firm found by name keeps the CUI it lacked")
    }

    // MARK: Repairs

    @Test func firmsWithTheSameCUIAreOfferedForMerging() throws {
        let context = try makeContext()
        let actions = ProviderActions(context: context)
        let one = try actions.create(name: "Exemplu Asigurări S.A.", trades: [.insurer])
        let two = try actions.create(name: "Asigurări Exemplu", trades: [.insurer])
        one.taxID = "12345678"
        two.taxID = "12345678"
        try UnitOfWork.save(context)
        let groups = try CaptureRepairs(context: context).duplicateProviderCandidates()
        #expect(groups.count == 1)
        #expect(Set([groups.first?.keptID] + (groups.first?.duplicateIDs ?? []).map(Optional.some)) == [one.id, two.id])
        try CaptureRepairs(context: context).mergeDuplicateProviders(groups)
        #expect(try context.fetch(FetchDescriptor<Provider>()).filter { $0.taxID == "12345678" }.count == 1)
    }

    @Test func cascoFactsInRCAFieldsMoveToCASCO() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values[VehicleFields.insurer] = .text("Exemplu Asigurări S.A.")
        values[VehicleFields.policyNumber] = .text("CAS-000123")
        values[VehicleFields.claimsPhone] = .text("0210000003")
        let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: values)
        let policy = Attachment(fileName: "casco.pdf", contentType: "com.adobe.pdf", data: Data("x".utf8), kind: .policy)
        policy.extractedText = "POLIȚĂ CASCO nr. CAS-000123, asigurare facultativă auto"
        context.insert(policy)
        policy.asset = car
        try UnitOfWork.save(context)

        let repairs = DataRepairs(context: context, calendar: .bucharest, ledger: DataRepairLedger(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let found = try repairs.detect().filter { $0.step == .cascoInRCAFields }
        #expect(found.count == 1)
        try repairs.apply(found)
        #expect(car.value(VehicleFields.cascoPolicyNumber) == .text("CAS-000123"))
        #expect(car.value(VehicleFields.cascoInsurer) == .text("Exemplu Asigurări S.A."))
        #expect(car.value(VehicleFields.cascoClaimsPhone) == .text("0210000003"))
        #expect(car.value(VehicleFields.policyNumber) == nil)
        #expect(try repairs.detect().filter { $0.step == .cascoInRCAFields }.isEmpty, "Applied once, not found again")
    }

    @Test func aHomePolicyWithoutItsDeadlineGetsOne() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        let home = try AssetActions(context: context).create(name: "Apartament", template: template, values: FieldValues())
        let year = Calendar.bucharest.component(.year, from: Date()) + 1
        let policy = Attachment(fileName: "locuinta.pdf", contentType: "com.adobe.pdf", data: Data("y".utf8), kind: .policy)
        policy.title = "Poliță locuință"
        policy.extractedText = """
            POLIȚĂ DE ASIGURARE FACULTATIVĂ A LOCUINȚEI
            Asigurător: Exemplu Asigurări S.A.
            Valabilă de la 01.06.\(year - 1) până la 31.05.\(year)
            """
        context.insert(policy)
        policy.asset = home
        try UnitOfWork.save(context)

        let repairs = DataRepairs(context: context, calendar: .bucharest, ledger: DataRepairLedger(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let found = try repairs.detect().filter { $0.step == .homePolicyWithoutDeadline }
        #expect(found.count == 1)
        try repairs.apply(found)
        let deadline = try #require(home.activeObligations.first { $0.blueprintKey == BuiltInBlueprints.homeInsurance })
        #expect(deadline.dueDay(in: .bucharest) == CalendarDay(year: year, month: 5, day: 31))
        #expect(policy.obligation?.id == deadline.id)
        #expect(try repairs.detect().filter { $0.step == .homePolicyWithoutDeadline }.isEmpty, "Applied once, not found again")
    }
}
