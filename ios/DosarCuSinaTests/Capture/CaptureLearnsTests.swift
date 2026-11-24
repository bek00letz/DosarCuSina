import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Capture learns from what the person saved: what an issuer prints where, so its next paper is
/// read on the phone alone. Placeholder firm, codes and amounts only.
@Suite("Capture learns from what was saved")
@MainActor
struct CaptureLearnsTests {

    /// A language model that answers what it is given: the person's AI provider reading a page.
    final class AnsweringModel: CaptureSemanticExtracting, @unchecked Sendable {
        let tier: CaptureTier = .cloudModel
        let fields: [CaptureField]
        init(_ fields: [CaptureField]) { self.fields = fields }
        func availability() -> CaptureModelAvailability { .available }
        func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
            SemanticExtraction(kind: .utilityInvoice, fields: fields)
        }
    }

    /// A gas bill whose due date is printed under a label the phone's tables don't have, and a later
    /// date (the next reading) that the phone takes for the day to pay by when nothing labels one.
    static func bill(issued: String, due: String, nextReading: String, total: String) -> String {
        """
        ENGIE Romania S.A.
        CUI: RO12345674
        FACTURĂ GAZE NATURALE
        Seria EXM nr. 0000001
        Data emiterii: \(issued)
        Ultima zi de plată: \(due)
        Următoarea citire: \(nextReading)
        Cod client: 1000000000
        Total de plată: \(total) lei
        """
    }

    static let firstBill = bill(issued: "01.11.2026", due: "15.12.2026", nextReading: "20.12.2026", total: "123,45")
    static let secondBill = bill(issued: "01.12.2026", due: "14.01.2027", nextReading: "21.01.2027", total: "98,10")

    private func engine(cloud: AnsweringModel? = nil) -> CaptureEngine {
        CaptureEngine(analyzer: .standard(), recognizer: CaptureEngineTests.FixedRecognizer(text: ""), normalizer: nil,
                      onDeviceModel: nil, cloudModel: cloud, store: nil)
    }

    private func read(_ text: String, on iso: String, cloud: AnsweringModel? = nil, lessons: LessonBook = .empty) async throws -> CaptureResult {
        try await engine(cloud: cloud).capture(CaptureRequest(.text(text), options: CaptureOptions(
            useOnDeviceModel: false, useCloudModel: cloud != nil, storeDocument: false, referenceDate: noon(iso), lessons: lessons)))
    }

    private func household() throws -> ModelContext {
        let context = try makeContext()
        var values = FieldValues()
        values["home.address"] = .text("Strada Exemplu nr. 1")
        let homes = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        _ = try AssetActions(context: context).create(name: "Apartament", template: homes, values: values)
        return context
    }

    private func save(_ result: CaptureResult, in context: ModelContext, on iso: String,
                      edit: (inout CaptureReview) -> Void = { _ in }) async throws -> CaptureFiler.Outcome {
        var review = CaptureReview(result: result, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        edit(&review)
        let date = noon(iso)
        return try await CaptureFiler(context: context, calendar: .bucharest, now: { date }).save(review)
    }

    /// The person saved the day the bill says, whoever read it.
    private func confirm(_ key: CaptureFieldKey, _ value: CaptureValue, in review: inout CaptureReview) {
        if let index = review.fields.firstIndex(where: { $0.key == key }) {
            review.fields[index].confirm(value)
        } else {
            review.fields.append(CaptureReview.Field(key: key, value: value, confidence: 1, sourceText: nil, tier: .deterministic, isEdited: true))
        }
    }

    // MARK: The loop

    @Test("A bill the phone misread, saved once, teaches it to read the next bill of that issuer by itself")
    func theNextBillIsReadOnThePhone() async throws {
        let context = try household()
        let due = CaptureValue.day(CalendarDay("2026-12-15"))
        // The phone alone takes the next reading's day for the day to pay by.
        let alone = try await read(Self.firstBill, on: "2026-11-02")
        #expect(alone.field(.dueDate)?.value != due, "Tiers 1–2 miss this layout's due date")

        // The person's AI provider reads it; the person checks it and saves.
        let model = AnsweringModel([CaptureField(key: .dueDate, value: due, confidence: 0.9, sourceText: nil, tier: .cloudModel)])
        let first = try await read(Self.firstBill, on: "2026-11-02", cloud: model)
        _ = try await save(first, in: context, on: "2026-11-02") { confirm(.dueDate, due, in: &$0) }

        let lessons = try IssuerLessons(context: context).book()
        #expect(lessons.lessons == [CaptureLesson(issuer: IssuerKey(rawValue: "cui:12345674"), kind: .utilityInvoice, field: .dueDate,
                                                  label: "Ultima zi de plată")])

        // The next bill of the same firm, on the phone alone: no model, nothing sent.
        let second = try await read(Self.secondBill, on: "2026-12-02", lessons: lessons)
        #expect(second.field(.dueDate)?.value == .day(CalendarDay("2027-01-14")), "Read from the lesson alone")
        #expect(second.field(.dueDate)?.tier == .heuristic, "The phone's own reader read it")
        #expect(!second.readWithCloudModel)
        // Without the lesson, the same page still reads as before.
        let without = try await read(Self.secondBill, on: "2026-12-02")
        #expect(without.field(.dueDate)?.value != .day(CalendarDay("2027-01-14")))
    }

    @Test("A lesson keeps the category its paper was filed in, worked out as the pure learner does")
    func aLessonKeepsItsCategory() async throws {
        let context = try household()
        let due = CaptureValue.day(CalendarDay("2026-12-15"))
        let first = try await read(Self.firstBill, on: "2026-11-02")
        var review = CaptureReview(result: first, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        confirm(.dueDate, due, in: &review)
        let worked = await CaptureFiler.lessons(taughtBy: .review(review), household: [])
        let pure = CaptureLessonLearner.lessons(from: try #require(first.source), saved: .init(kind: review.kind, values: review.valuesByKey))
        #expect(worked == pure, "Away from the main thread, the same lessons")
        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        let kept = try context.fetch(FetchDescriptor<IssuerLesson>())
        #expect(kept.count == 1)
        #expect(kept.first?.categoryKey == outcome.asset?.templateKey)
        #expect(kept.first?.categoryKey == BuiltInTemplates.Key.subscription)
    }

    @Test("An issuer learned of only from a locked category's papers is protected in Settings; one with no category is while any lock is on")
    func lockedCategoriesLessonsAreProtected() throws {
        let context = try makeContext()
        let bills = IssuerLesson(CaptureLesson(issuer: IssuerKey(rawValue: "cui:12345674"), kind: .utilityInvoice, field: .dueDate, label: "Ultima zi de plată"),
                                 issuerName: "ENGIE Romania S.A.", categoryKey: BuiltInTemplates.Key.subscription)
        let clinic = IssuerLesson(CaptureLesson(issuer: IssuerKey(rawValue: "name:CLINICAEXEMPLU"), kind: .medicalResult, field: .issueDate, label: "Data recoltării"),
                                  issuerName: "Clinica Exemplu SRL", categoryKey: BuiltInTemplates.Key.health)
        let older = IssuerLesson(CaptureLesson(issuer: IssuerKey(rawValue: "name:FIRMAEXEMPLU"), kind: .serviceInvoice, field: .total, label: "Suma datorată"),
                                 issuerName: "Firma Exemplu SRL")
        for lesson in [bills, clinic, older] { context.insert(lesson) }
        try context.save()
        let locks = BinderLocks.read(in: context)
        #expect(locks.lockedKeys.contains(BuiltInTemplates.Key.health), "Sănătate is locked as the catalog starts it")
        let issuers = Dictionary(IssuerLessons.issuers(try context.fetch(FetchDescriptor<IssuerLesson>()), locks: locks).map { ($0.name, $0.isProtected) },
                                 uniquingKeysWith: { first, _ in first })
        #expect(issuers["ENGIE Romania S.A."] == false)
        #expect(issuers["Clinica Exemplu SRL"] == true)
        #expect(issuers["Firma Exemplu SRL"] == true, "Not known where it was learned: kept behind the locks")
    }

    @Test("Anulează takes a filing's lessons back with it")
    func undoTakesTheLessonsBack() async throws {
        let context = try household()
        let due = CaptureValue.day(CalendarDay("2026-12-15"))
        let first = try await read(Self.firstBill, on: "2026-11-02")
        let outcome = try await save(first, in: context, on: "2026-11-02") { confirm(.dueDate, due, in: &$0) }
        #expect(try IssuerLessons(context: context).book().lessons.count == 1)
        try #require(outcome.receipt).undo()
        #expect(try IssuerLessons(context: context).book().isEmpty)
    }

    @Test("Nothing is learned from what the phone already read right")
    func nothingWhenThePhoneWasRight() throws {
        let source = Self.source(Self.firstBill, on: "2026-11-02")
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [
            .issueDate: .day(CalendarDay("2026-11-01")), .total: .money(Money(Decimal(string: "123.45")!, currency: "RON")),
        ])
        #expect(CaptureLessonLearner.lessons(from: source, saved: saved) == nil)
    }

    // MARK: Evidence that points one way

    @Test("A value printed next to two different labels teaches nothing")
    func twoLabelsTeachNothing() throws {
        let text = Self.firstBill + "\nData limită: 15.12.2026"
        let source = Self.source(text, on: "2026-11-02")
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: .day(CalendarDay("2026-12-15"))])
        #expect(CaptureLessonLearner.lessons(from: source, saved: saved) == nil)
    }

    @Test("A label two papers give two different values is no lesson, and the one kept goes")
    func aContradictedLabelGoes() throws {
        let issuer = IssuerKey(rawValue: "cui:12345674")
        let earlier = CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .issueDate, label: "Ultima zi de plată")
        let source = Self.source(Self.firstBill, on: "2026-11-02", lessons: LessonBook([earlier]))
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [
            .issueDate: .day(CalendarDay("2026-11-01")), .dueDate: .day(CalendarDay("2026-12-15")),
        ])
        let outcome = try #require(CaptureLessonLearner.lessons(from: source, saved: saved))
        #expect(outcome.learned.isEmpty)
        #expect(outcome.forgotten == [earlier])
    }

    @Test("A label with digits, or longer than four words, is never a lesson")
    func labelsWithDigitsAreRefused() throws {
        let text = Self.firstBill.replacingOccurrences(of: "Ultima zi de plată:", with: "Termen 30 zile:")
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: .day(CalendarDay("2026-12-15"))])
        #expect(CaptureLessonLearner.lessons(from: Self.source(text, on: "2026-11-02"), saved: saved) == nil)
        let long = Self.firstBill.replacingOccurrences(of: "Ultima zi de plată:", with: "Vă rugăm să plătiți factura până pe")
        #expect(CaptureLessonLearner.lessons(from: Self.source(long, on: "2026-11-02"), saved: saved) == nil)

        let day = CaptureValue.day(CalendarDay("2026-12-15"))
        #expect(CaptureLessonLearner.accepts("Ultima zi de plată", value: day, personal: []))
        #expect(!CaptureLessonLearner.accepts("Index 1.8.0", value: day, personal: []))
        #expect(!CaptureLessonLearner.accepts("Card 4111 1111 1111 1111", value: day, personal: []))
        #expect(!CaptureLessonLearner.accepts("CNP 1800101990006", value: day, personal: []))
        #expect(!CaptureLessonLearner.accepts("Data la care trebuie plătită factura", value: day, personal: []))
    }

    @Test("A label holding a value of the person's is never a lesson")
    func labelsWithPersonalValuesAreRefused() throws {
        let text = Self.firstBill.replacingOccurrences(of: "Ultima zi de plată:", with: "Exemplu Ion plătește:")
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [
            .dueDate: .day(CalendarDay("2026-12-15")), .policyholder: .text("Ion Exemplu"),
        ])
        #expect(CaptureLessonLearner.lessons(from: Self.source(text, on: "2026-11-02"), saved: saved) == nil)
        let day = CaptureValue.day(CalendarDay("2026-12-15"))
        #expect(!CaptureLessonLearner.accepts("Titular Exemplu", value: day, personal: CaptureLessonLearner.personalWords(in: [.policyholder: .text("Ion Exemplu")])))
        #expect(!CaptureLessonLearner.accepts("Cod EXM", value: .text("EXM"), personal: []), "Never the value itself")
        #expect(CaptureLessonLearner.personalWords(in: [.provider: .text("ENGIE Romania S.A.")]).isEmpty, "The issuer's own name is its words")
    }

    @Test("A label holding what the binder keeps of the household, anywhere in it, is never a lesson")
    func labelsWithTheHouseholdsValuesAreRefused() throws {
        let text = Self.firstBill.replacingOccurrences(of: "Ultima zi de plată:", with: "Termen Exemplu:")
        let due = CaptureValue.day(CalendarDay("2026-12-15"))
        let alone = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: due])
        #expect(CaptureLessonLearner.lessons(from: Self.source(text, on: "2026-11-02"), saved: alone)?.learned.map(\.label) == ["Termen Exemplu"],
                "An issuer's own words are learned")
        let household = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: due],
                                                   household: CaptureLessonLearner.words(of: ["Ion Exemplu"]))
        #expect(CaptureLessonLearner.lessons(from: Self.source(text, on: "2026-11-02"), saved: household) == nil,
                "A person's name the binder keeps, though this paper's values don't hold it")
    }

    @Test("The binder's people, homes' addresses and plates are the household's words, by the field's type")
    func householdValuesComeFromTheBinder() throws {
        let context = try household()
        context.insert(Asset(name: "Ion Exemplu", templateKey: BuiltInTemplates.Key.member))
        var car = FieldValues()
        car[VehicleFields.plate] = .text("B-123-ABC")
        car[VehicleFields.make] = .text("Volkswagen")
        context.insert(Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle, values: car))
        let words = try HouseholdValues.words(in: context)
        #expect(words.isSuperset(of: ["ion", "exemplu", "strada", "abc"]))
        #expect(!words.contains("volkswagen"), "A make names no one")
        #expect(!words.contains("apartament"), "A home's name is no address")
    }

    @Test("A proper name the page prints in its buyer's block is never a lesson")
    func buyerBlockNamesAreRefused() throws {
        let due = CaptureValue.day(CalendarDay("2026-12-15"))
        let saved = CaptureLessonLearner.Saved(kind: .utilityInvoice, values: [.dueDate: due])
        let labelled = Self.firstBill.replacingOccurrences(of: "Ultima zi de plată:", with: "Termen Exempluescu:")
        #expect(CaptureLessonLearner.lessons(from: Self.source(labelled, on: "2026-11-02"), saved: saved)?.learned.isEmpty == false)
        let withBuyer = labelled.replacingOccurrences(of: "FACTURĂ GAZE NATURALE", with: "FACTURĂ GAZE NATURALE\nClient: Ion Exempluescu")
        #expect(CaptureLessonLearner.lessons(from: Self.source(withBuyer, on: "2026-11-02"), saved: saved) == nil)
        let names = CaptureLessonLearner.buyerBlockNames(in: CaptureText(withBuyer), kind: .utilityInvoice)
        #expect(names.isSuperset(of: ["ion", "exempluescu"]))
        #expect(!names.contains("client") && !names.contains("emiterii"), "A label's words are no one's name")
    }

    @Test("A personal document teaches nothing")
    func personalDocumentsTeachNothing() {
        #expect(!CaptureDocumentKind.identityCard.profile.learnsIssuerLabels)
        #expect(!CaptureDocumentKind.vehicleRegistration.profile.learnsIssuerLabels)
        #expect(CaptureDocumentKind.utilityInvoice.profile.learnsIssuerLabels)
    }

    // MARK: Reading with lessons

    @Test("A learned label is taught only for its issuer, apart from the kind's own table")
    func learnedLabelsAreTaughtForTheirIssuer() {
        let issuer = IssuerKey(rawValue: "cui:12345674")
        let book = LessonBook([CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .total, label: "Suma datorată")])
        let profile = CaptureDocumentKind.utilityInvoice.profile
        let taught = book.teaching(profile, issuer: issuer)
        #expect(taught.learnedLabels.map(\.0) == [.total])
        #expect(taught.learnedLabels.first?.1 == ["suma datorata"])
        #expect(taught.labels(for: .total) == profile.labels(for: .total), "The kind's readers keep the kind's own table; lessons are read by position")
        #expect(book.teaching(profile, issuer: IssuerKey(rawValue: "cui:98765438")).learnedLabels.isEmpty)
        #expect(book.teaching(CaptureDocumentKind.rcaPolicy.profile, issuer: issuer).learnedLabels.isEmpty, "Another kind of paper")
    }

    @Test("A label learned of an issuer never beats what the kind's own table reads; it fills only what the table misses")
    func aLearnedLabelFillsWhatTheTableMisses() {
        let issuer = IssuerKey(rawValue: "cui:12345674")
        let book = LessonBook([CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .total, label: "Sold curent")])
        let page = """
            ENGIE Romania S.A.
            CUI: RO12345674
            FACTURĂ GAZE NATURALE
            Data emiterii: 01.12.2026
            Sold curent: 5,00 lei
            Total de plată: 98,10 lei
            """
        func total(_ text: String) -> CaptureValue? {
            CaptureAnalyzer.standard().learning(book).analyze(text: text, referenceDate: noon("2026-12-02")).fields.first { $0.key == .total }?.value
        }
        #expect(total(page) == .money(Money(Decimal(string: "98.10")!, currency: "RON")), "„Total de plată” is the kind's own: it stands")
        let missing = page.replacingOccurrences(of: "\nTotal de plată: 98,10 lei", with: "")
        #expect(total(missing) == .money(Money(Decimal(string: "5.00")!, currency: "RON")), "Where the table reads nothing, the lesson reads it")

        let read = CaptureField(key: .total, value: .money(Money(Decimal(string: "98.10")!, currency: "RON")), confidence: 0.8,
                                sourceText: "Total de plată: 98,10 lei", tier: .heuristic)
        let learned = CaptureField(key: .total, value: .money(Money(5, currency: "RON")), confidence: LessonBook.readingConfidence,
                                   sourceText: "Sold curent: 5,00 lei", tier: .heuristic)
        let own = CaptureDocumentKind.utilityInvoice.profile.wordings(of: .total)
        #expect(!ReadingArbiter.admitsLearned(learned, over: read, ownLabels: own))
        #expect(ReadingArbiter.admitsLearned(learned, over: nil, ownLabels: own))
        let guess = CaptureField(key: .total, value: .money(Money(7, currency: "RON")), confidence: 0.4, sourceText: "Consum 7,00 lei", tier: .heuristic)
        #expect(ReadingArbiter.admitsLearned(learned, over: guess, ownLabels: own), "A guess without the kind's label is weighed as any reading")
    }

    @Test func aLessonHasTheSameIDOnEveryDevice() {
        let issuer = IssuerKey(rawValue: "cui:12345674")
        let due = CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .dueDate, label: "Ultima zi de plată")
        #expect(due.id == CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .dueDate, label: "ULTIMA ZI DE PLATA").id)
        #expect(due.id != CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .issueDate, label: "Ultima zi de plată").id)
        #expect(IssuerLesson(due, issuerName: "ENGIE Romania S.A.").id == due.id)
    }

    // MARK: Two devices

    @Test("Two devices' lessons meet: the same lesson is one, agreeing ones are all kept, contradicting ones go")
    func twoDevicesLessonsMeet() throws {
        let context = try makeContext()
        let issuer = IssuerKey(rawValue: "cui:12345674")
        let due = CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .dueDate, label: "Ultima zi de plată")
        let total = CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .total, label: "Suma datorată")
        let issued = CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .issueDate, label: "Emisă pe")
        let otherIssued = CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .dueDate, label: "Emisă pe")
        // This phone learned two lessons; the other device learned one of them, one more, and one
        // that gives a label of this phone's to another value. Each copy is its own device's.
        let phone = [IssuerLesson(due, issuerName: "ENGIE Romania S.A."), IssuerLesson(issued, issuerName: "ENGIE Romania S.A.")]
        let other = [IssuerLesson(due, issuerName: "ENGIE Romania"), IssuerLesson(total, issuerName: "ENGIE Romania"),
                     IssuerLesson(otherIssued, issuerName: "ENGIE Romania")]
        for record in phone + other { context.insert(record) }
        try UnitOfWork.save(context)
        #expect(Set((phone + other).map(\.copyID)).count == 5, "Every copy is named by the device that made it")

        try RecordsMeet.join(in: context)
        try IssuerLessons.settle(in: context)

        let kept = try context.fetch(FetchDescriptor<IssuerLesson>())
        #expect(kept.count == 2)
        #expect(Set(try IssuerLessons(context: context).book().lessons) == [due, total], "The union of what agrees")
        // Joining again changes nothing, the same on every device.
        #expect(try !RecordsMeet.join(in: context))
        #expect(try !IssuerLessons.settle(in: context))
    }

    // MARK: Settings

    @Test("Settings lists each issuer once, with its labels, and forgetting one can be taken back")
    func settingsListsAndForgets() throws {
        let context = try makeContext()
        let issuer = IssuerKey(rawValue: "cui:12345674")
        context.insert(IssuerLesson(CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .dueDate, label: "Ultima zi de plată"), issuerName: "ENGIE Romania S.A."))
        context.insert(IssuerLesson(CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .total, label: "Suma datorată"), issuerName: "ENGIE Romania S.A."))
        let unread = IssuerLesson(CaptureLesson(issuer: issuer, kind: .other, field: .total, label: "Suma"), issuerName: "ENGIE Romania S.A.")
        unread.kindRaw = "aKindFromANewerBuild"
        context.insert(unread)
        try UnitOfWork.save(context)

        let issuers = IssuerLessons.issuers(try context.fetch(FetchDescriptor<IssuerLesson>()))
        #expect(issuers.map(\.name) == ["ENGIE Romania S.A."])
        #expect(issuers.first?.lessons.count == 2, "What a newer build wrote stays, unread")
        #expect(IssuerWording.status(issuers: 0) == "Nimic încă")

        let receipt = try IssuerLessons(context: context).forget(issuer)
        #expect(try context.fetchCount(FetchDescriptor<IssuerLesson>()) == 0)
        try receipt.undo()
        #expect(try context.fetchCount(FetchDescriptor<IssuerLesson>()) == 3)
    }

    // MARK: Database version 16

    @Test func versionSixteenOnlyAddsTheLessons() throws {
        let fifteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV15.models))
        let sixteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV16.models))
        for (entity, hash) in fifteen.entityVersionHashesByName {
            #expect(sixteen.entityVersionHashesByName[entity] == hash, "\(entity) is as version 15 shipped it")
        }
        #expect(Set(sixteen.entitiesByName.keys).subtracting(fifteen.entitiesByName.keys) == ["IssuerLesson"])
        let lessons = try #require(sixteen.entitiesByName["IssuerLesson"])
        #expect(lessons.relationshipsByName.isEmpty)
        for (name, attribute) in lessons.attributesByName {
            #expect(attribute.isOptional || attribute.defaultValue != nil, "IssuerLesson.\(name) may be empty or has a default, as CloudKit needs")
        }
        // The frozen version 15 is version 14 with the person's choice of boxes, nothing more.
        let fourteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV14.models))
        for (entity, description) in fifteen.entitiesByName {
            let added = Set(description.attributesByName.keys).subtracting(fourteen.entitiesByName[entity]?.attributesByName.keys.map { $0 } ?? [])
            #expect(added == (entity == "CategoryTemplate" ? ["boxGroupingRaw"] : []), "\(entity)")
        }
    }

    @Test func aStoreFromVersionFifteenOpensWithEverythingAsItWasAndNothingLearned() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v15.store")
        let edited = noon("2026-10-01")

        // Written by version 15: the cars' category, grouped, and a car with a firm.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV15.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let cars = DosarSchemaV15.CategoryTemplate(key: BuiltInTemplates.Key.vehicle)
            cars.isBuiltIn = true
            cars.boxGroupingRaw = BoxGrouping.grouped.rawValue
            cars.updatedAt = edited
            let car = DosarSchemaV15.Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
            let firm = DosarSchemaV15.Provider(name: "Service Exemplu SRL")
            for model in [cars, car, firm] as [any PersistentModel] { context.insert(model) }
            firm.assets = [car]
            try context.save()
        }

        let context = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let cars = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first)
        #expect(cars.chosenGrouping == .grouped)
        #expect(cars.updatedAt == edited, "An upgrade isn't a change")
        #expect(try context.fetch(FetchDescriptor<Asset>()).first?.providers?.first?.name == "Service Exemplu SRL")
        #expect(try context.fetchCount(FetchDescriptor<IssuerLesson>()) == 0, "Nothing is learned until a paper is saved")
    }

    // MARK: Database version 17

    @Test func versionSeventeenOnlyAddsTheLessonsCategory() throws {
        let sixteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV16.models))
        let seventeen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV17.models))
        for (entity, hash) in sixteen.entityVersionHashesByName where entity != "IssuerLesson" {
            #expect(seventeen.entityVersionHashesByName[entity] == hash, "\(entity) is as version 16 shipped it")
        }
        #expect(Set(seventeen.entitiesByName.keys) == Set(sixteen.entitiesByName.keys))
        let before = try #require(sixteen.entitiesByName["IssuerLesson"]), after = try #require(seventeen.entitiesByName["IssuerLesson"])
        #expect(Set(after.attributesByName.keys).subtracting(before.attributesByName.keys) == ["categoryKey"])
        #expect(after.attributesByName["categoryKey"]?.isOptional == true, "Optional, as CloudKit needs")
    }

    @Test func aStoreFromVersionSixteenKeepsItsLessonsWithNoCategory() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v16.store")
        let lesson = CaptureLesson(issuer: IssuerKey(rawValue: "cui:12345674"), kind: .utilityInvoice, field: .dueDate, label: "Ultima zi de plată")
        do {
            let schema = Schema(versionedSchema: DosarSchemaV16.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let record = DosarSchemaV16.IssuerLesson()
            record.id = lesson.id
            record.issuerKey = lesson.issuer.rawValue
            record.issuerName = "ENGIE Romania S.A."
            record.kindRaw = lesson.kind.rawValue
            record.fieldKey = lesson.field.rawValue
            record.label = lesson.label
            context.insert(record)
            try context.save()
        }
        let context = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let kept = try context.fetch(FetchDescriptor<IssuerLesson>())
        #expect(kept.map(\.lesson) == [lesson])
        #expect(kept.first?.categoryKey == nil, "Where it was learned isn't known")
    }

    // MARK: Helpers

    /// What the phone read of `text`, as a capture keeps it.
    static func source(_ text: String, on iso: String, lessons: LessonBook = .empty) -> CaptureReadingSource {
        CaptureReadingSource(text: text, pages: [], barcodes: [], referenceDate: noon(iso), modelFields: [], aiFields: nil,
                             isSinglePhoto: false, lessons: lessons)
    }
}
