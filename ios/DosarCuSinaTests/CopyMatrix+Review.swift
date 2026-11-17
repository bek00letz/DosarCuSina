import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The capture review's part of `docs/COPY_MATRIX.md`: what its summary card and its filing
/// lines say to each kind of document, from the kind's description (`CaptureKindProfile`: its
/// title, its noun and the pronoun it takes, what its day means) and the filing plan
/// (`CaptureFilingPlan`, said by `CaptureReminderPreview`), with the words every kind shares
/// (`CaptureReviewWording`) listed once. Placeholder data only.
extension CopyMatrixTests {
    /// The day the samples are read on, and the days their deadline falls: to come, and passed.
    static let reviewToday = CalendarDay("2026-11-02")
    static let reviewDayToCome = CalendarDay("2027-06-10")
    static let reviewDayPassed = CalendarDay("2026-05-10")
    /// Sample values for the words that carry one.
    static let reviewPerson = "Exemplu Ion"
    static let reviewSubscription = "Gaze Apartament"
    static let reviewValue = "123456"
    static let reviewStatement = "Plata se face prin debit direct."
    static var reviewProvider: AIProvider { .gemini }

    /// A reading of `kind` with its deadline's day, routed the way the engine routes it.
    static func reviewResult(_ kind: CaptureDocumentKind, day: CalendarDay?, bonusMalus: String? = nil) -> CaptureResult {
        var fields: [CaptureField] = []
        func add(_ key: CaptureFieldKey, _ value: CaptureValue) {
            fields.append(CaptureField(key: key, value: value, confidence: 0.9, sourceText: nil, tier: .heuristic))
        }
        let profile = kind.profile
        if let field = profile.deadlineField, let day { add(field, .day(day)) }
        if case .product = profile.titleRule { add(.productName, .text("Hotă Exemplu")) }
        if let bonusMalus { add(.bonusMalusClass, .text(bonusMalus)) }
        if profile.filing == .subscription {
            add(.provider, .text("ENGIE Romania S.A."))
            add(.serviceKind, .text(ServiceKind.gas))
        }
        let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.9, fields: fields)
        return CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                             recognizedText: "", barcodes: [], document: nil, notices: [])
    }

    /// The reminder line for `kind`'s sample with its day on `day`, filed where the review
    /// suggests or, with `placeChosen` false, nowhere yet.
    @MainActor
    static func reminderLine(_ kind: CaptureDocumentKind, day: CalendarDay, placeChosen: Bool = true, context: ModelContext) throws -> String {
        var review = CaptureReview(result: reviewResult(kind, day: day), assets: [], context: context)
        if !placeChosen { review.destination = .none }
        if kind.profile.isBill { review.remindsToPay = true }
        let templates = try TemplateStore(context: context).templatesByKey()
        let plan = CaptureFilingPlan.make(for: review, templates: templates, assets: [], today: reviewToday, calendar: .bucharest)
        return CaptureReminderPreview.text(for: review, plan: plan, today: reviewToday) ?? "(no reminder line)"
    }

    /// What the review says to one kind of document, row by row: its kind's words and the
    /// filing lines its plan gives, never the words every kind shares (`reviewSharedRows`).
    @MainActor
    static func reviewRows(_ kind: CaptureDocumentKind, context: ModelContext) throws -> [(String, String)] {
        let profile = kind.profile
        let noun = profile.noun
        let templates = try TemplateStore(context: context).templatesByKey()
        let review = CaptureReview(result: reviewResult(kind, day: reviewDayToCome), assets: [], context: context)
        let place = CaptureReviewPlace(review: review, assets: [], templates: templates)
        var rows: [(String, String)] = [
            ("Its title", profile.title),
            ("Where it goes: the summary's heading and the picker's title", noun.wherePutWords),
            ("Where it goes, with nothing in the binder", [place.title, place.subtitle, place.newNameTitle.map { "field „\($0)”" }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")),
        ]
        if let meaning = profile.dayMeaning {
            rows.append(("What its day means", meaning.opening(sampleDay)))
            rows.append(("When it reminds, its day to come", try reminderLine(kind, day: reviewDayToCome, context: context)))
            rows.append(("Its place not chosen yet", try reminderLine(kind, day: reviewDayToCome, placeChosen: false, context: context)))
            rows.append(("Its day passed", try reminderLine(kind, day: reviewDayPassed, context: context)))
        } else {
            rows.append(("When it reminds", "(sets no deadline: no reminder line)"))
        }
        if profile.isBill {
            rows.append(("Reminded to pay it", noun.remindToPayWords))
        }
        if profile.filing == .subscription, profile.allows(.directDebit) {
            rows.append(("The bank pays it", "\(CaptureReviewWording.directDebit) — \(noun.directDebitWords(reviewStatement))"))
        }
        // The class is said only where the policy files into a deadline that keeps who it insures (a car's RCA).
        let plan = CaptureFilingPlan.make(for: review, templates: templates, assets: [], today: reviewToday, calendar: .bucharest)
        if profile.readsCover, profile.allows(.bonusMalusClass), plan.blueprint?.facts?.policyholder != nil {
            rows.append(("Its bonus-malus class", [
                CaptureReviewWording.bonusMalus(.keep(classKey: "B8", memberID: UUID(), memberName: reviewPerson)),
                CaptureReviewWording.bonusMalus(.noPolicyholder),
                CaptureReviewWording.bonusMalus(.notInHousehold(name: reviewPerson)),
            ].joined(separator: " / ")))
        }
        if profile.filing == .subscription, profile.allows(.meterIndex) {
            let day = CalendarDay("2026-10-05")
            let read = try #require(SubscriptionMeter.reading(.number(12_345), service: ServiceKind.gas, day: day))
            let estimated = try #require(SubscriptionMeter.reading(.number(12_345), basis: .text(ReadingBasis.estimated.rawValue), service: ServiceKind.gas, day: day))
            rows.append(("Its meter index", [
                CaptureFilingPlan.Meter.record(read, subscription: reviewSubscription).sentence,
                CaptureFilingPlan.Meter.record(estimated, subscription: reviewSubscription).sentence,
                CaptureFilingPlan.Meter.alreadyKept(read, subscription: reviewSubscription).sentence,
                CaptureFilingPlan.Meter.unknownService.sentence,
            ].joined(separator: " / ")))
        }
        rows.append(("Nothing read off it", noun.nothingReadWords))
        rows.append(("A value that passed its check digit", noun.printedWords(reviewValue)))
        if profile.isIdentityDocument || profile.hasMachineReadableBack {
            rows.append(("What its machine-readable code says", profile.machineReadableWords(reviewValue)))
        }
        if profile.hasMachineReadableBack {
            rows.append(("Its back", CaptureReviewWording.backPage))
        }
        rows.append(("Under „Citește mai bine”", PhoneOnlyReading.isPhoneOnly(kind)
                     ? CaptureReviewWording.cardsStayOnPhone
                     : profile.sentToProviderWords(reviewProvider.name)))
        return rows
    }

    /// The review's frame, the same for every kind.
    static var reviewSharedRows: [(String, String)] {
        typealias W = CaptureReviewWording
        let provider = reviewProvider
        return [
            ("The screen", "\(W.title) · \(W.save) · \(W.notSaved)"),
            ("From De verificat", "\(W.later) · \(W.removeFromInbox) · \(W.discardFromInbox)"),
            ("The thumbnail (VoiceOver)", "\(W.seeLarge) — \(W.seeLargeHint)"),
            ("Its kind", "\(W.notThis) · \(W.whatKind) · \(W.phoneSawKind("Pașaport")) · \(W.checkedKind("Pașaport"))"),
            ("How it was read", "\(W.readOnPhone) / \(W.readWithAppleIntelligence) / \(W.readWithProvider(provider.shortName))"),
            ("The photo's frame", "\(W.cropped) \(W.useWholePhoto) / \(W.wholePhotoKept) \(W.onlyDocument)"),
            ("Where it goes", "\(W.chooseAnother) · \(W.check): \(W.addressPartlyAgrees) / \(W.addressDiffers) · a home's policy: \(W.insuredAddressPartlyAgrees) / \(W.insuredAddressDiffers)"),
            ("Kept in no section", "\(W.keepOnly) — \(W.foundInSearch)"),
            ("Filed under a section", "\(W.withPersonsDocuments) / \(W.atSubscription(reviewSubscription)) / \(W.newSubscriptionHere(reviewSubscription)) / \(W.subscriptionAt("Apartament"))"),
            ("A new section", "\(W.newPerson(reviewPerson)) — \(W.addedToDocuments) / \(W.newSubscription(reviewSubscription)) / \(W.newSection(in: "Mașini")) — \(W.madeWhenSaved) / \(W.madeWhenSaved(withSubscription: reviewSubscription))"),
            ("A new section's name", "\(W.personName) / \(W.subscriptionName) / \(W.homeName) / \(W.newSectionName)"),
            ("A section that has gone", W.sectionGone),
            ("The place picker", "\(W.keepOnly) — \(W.keepOnlySubtitle) · \(W.newPersonChoice) — \(W.groupedByPerson) · \(W.newSectionChoice(in: "Mașini")) — \(W.thenFiled) · \(W.otherSection) — \(W.everySectionSubtitle)"),
            ("The place picker, every section", "\(W.everySection) · \(W.newSectionPlain) — \(W.chooseCategoryFirst) · \(W.whatSection) · \(W.example) · \(W.homeHoldsSubscription) · \(W.chosen) · \(W.close)"),
            ("When it reminds", "\(W.whenHeading) · \(W.changeDay) (\(W.changeDayHint)) · \(W.changeLater)"),
            ("More notices", "\(W.moreNotices(1)) / \(W.moreNotices(2))"),
            ("The same photo", "\(W.samePhoto) — \(W.samePhotoMessage) \(W.seeWhereItIs)"),
            ("The card's back", "\(W.photographBack) · \(W.choosePhotos) · \(W.readingBack) · \(W.backNotRead) · \(W.photoDidNotOpen)"),
            ("The code didn't read", "\(W.checkNumbers) — \(W.checkNumbersMessage)"),
            ("The provider didn't read it", W.providerDidNotRead(provider.name)),
            ("Hard to read", "\(W.hardToRead) — \(W.hardToReadMessage)"),
            ("A long PDF", "\(W.firstPagesRead(10)) — \(W.longDocument)"),
            ("Sending the photo", "\(W.sendPhotoQuestion(provider.name)) \(W.sendPhotoMessage(provider.name)) · \(W.sendPhoto) / \(W.keepOnPhone) · \(W.dataPolicy(provider.name))"),
            ("Reading it again", "\(W.readBetter(provider.shortName)) · \(W.readingWith(provider.shortName))"),
            ("What was read", "\(W.whatWasRead) — \(W.checkMarked) · \(W.documentName) · \(W.notFound) \(W.add("Total"))"),
            ("Where a value came from", "\(W.fromDocument("Total de plată 245,30")) (\(W.readFrom("Total de plată 245,30")))"),
            ("Another reader's value", "\(W.phoneRead(reviewValue)) / \(W.readBy(provider, value: reviewValue)) / \(W.readBy(.openAICompatible, value: reviewValue)) · \(W.use) (\(W.useThis(W.phoneRead(reviewValue))))"),
        ] + PhotoOnRequest.allCases.map { subject in
            // `KeepPhotoChoice`, in the review, „Am rezolvat” and the visit form.
            ("A photo kept only on request: \(subject == .bankCard ? "a bank card" : "a page with a card's number")",
             "\(subject.header) — \(subject.keep) — \(subject.note(keepsPhoto: false)) / \(subject.note(keepsPhoto: true))")
        }
    }

    /// The review's section of the matrix: the words every kind shares, then each kind's.
    @MainActor
    static func reviewSection() throws -> String {
        let context = try makeContext()
        var out = """
        ## The capture review

        What the review says to each kind of document, from the kind's description \
        (`CaptureKindProfile`: its title, its noun and the pronoun it takes, what its day means) and \
        what saving does (`CaptureFilingPlan`, said by `CaptureReminderPreview`). Samples: nothing in \
        the binder, read on \(DosarFormat.longDay(reviewToday)), its day on \(DosarFormat.longDay(reviewDayToCome)) \
        or, passed, \(DosarFormat.longDay(reviewDayPassed)).

        ### What every kind shares

        \(table(reviewSharedRows))

        """
        for kind in CaptureDocumentKind.allCases {
            out += "\n### \(kind.profile.title) (`\(kind.rawValue)`)\n\n" + table(try reviewRows(kind, context: context)) + "\n"
        }
        return out
    }
}

/// The rules the review's matrix makes checkable: every word said, a kind's day stated, vehicle
/// words only on a vehicle's papers, a doctor's and a vet's only on theirs, and every sentence
/// that names the paper by a pronoun agreeing with its noun.
@MainActor
@Suite("Copy matrix: review")
struct ReviewCopyRulesTests {
    /// Every row of every kind, with the frame every kind shares.
    static func everyKindsRows() throws -> [(CaptureDocumentKind, [(String, String)])] {
        let context = try makeContext()
        return try CaptureDocumentKind.allCases.map { ($0, try CopyMatrixTests.reviewRows($0, context: context)) }
    }

    @Test("Every word is said: no empty row, no gap where a word should be")
    func noEmptyWords() throws {
        for (kind, rows) in try Self.everyKindsRows() {
            for (place, words) in rows {
                #expect(!words.isEmpty && !words.contains("— —"), "\(kind): \(place) „\(words)”")
            }
        }
        for (place, words) in CopyMatrixTests.reviewSharedRows {
            #expect(!words.isEmpty && !words.contains("— —"), "\(place) „\(words)”")
        }
        #expect(try !CopyMatrixTests.reviewSection().isEmpty)
    }

    @Test("A kind says what its day means exactly when it has a day to follow")
    func everyKindStatesItsDay() {
        for kind in CaptureDocumentKind.allCases {
            let profile = kind.profile
            #expect((profile.deadlineField == nil) == (profile.dayMeaning == nil), "\(kind)")
        }
    }

    /// A paper about a vehicle: filed in Mașini, or a policy whose cover can be a car's.
    static func isAboutAVehicle(_ kind: CaptureDocumentKind) -> Bool {
        let profile = kind.profile
        return profile.templateKey == BuiltInTemplates.Key.vehicle
            || profile.covers.contains { CaptureKindProfile.coverDeadlines[$0]?.templateKey == BuiltInTemplates.Key.vehicle }
    }

    /// A doctor's or a vet's paper: filed in Sănătate or with a pet.
    static func isMedicalOrVet(_ kind: CaptureDocumentKind) -> Bool {
        [BuiltInTemplates.Key.health, BuiltInTemplates.Key.pet].contains(kind.profile.templateKey)
    }

    @Test("Vehicle words only on a vehicle's papers, a doctor's and a vet's only on theirs")
    func wordsStayWithTheirPapers() throws {
        for (kind, rows) in try Self.everyKindsRows() {
            let words = CopyMatrixTests.tokens(rows.map(\.1).joined(separator: " "))
            if !Self.isAboutAVehicle(kind) {
                #expect(words.isDisjoint(with: CopyMatrixTests.vehicleWords), "\(kind): \(words.intersection(CopyMatrixTests.vehicleWords).sorted())")
            }
            if !Self.isMedicalOrVet(kind) {
                #expect(words.isDisjoint(with: CopyMatrixTests.careWords), "\(kind): \(words.intersection(CopyMatrixTests.careWords).sorted())")
            }
        }
        let shared = CopyMatrixTests.tokens(CopyMatrixTests.reviewSharedRows.map(\.1).joined(separator: " "))
        #expect(shared.isDisjoint(with: CopyMatrixTests.careWords), "Every kind's words: \(shared.intersection(CopyMatrixTests.careWords).sorted())")
    }

    /// The object pronouns a noun takes before a verb: „îl pun”, „să-l plătesc”, „o pun”, „le pun”.
    static func objectPronouns(_ gender: CompletionShape.Paper.Gender) -> Set<String> {
        switch gender {
        case .masculine: ["il", "l"]
        case .feminine: ["o"]
        case .plural: ["le"]
        }
    }

    /// The possessive after „abonamentul”: „abonamentul ei” for a bill.
    static func possessive(_ gender: CompletionShape.Paper.Gender) -> String {
        switch gender {
        case .masculine: "lui"
        case .feminine: "ei"
        case .plural: "lor"
        }
    }

    /// Every sentence that names the paper by a pronoun.
    static func pronounSentences(_ noun: CaptureKindProfile.Noun) -> [String] {
        [noun.wherePutWords, noun.nothingReadWords, noun.choosePlaceWords, noun.choosePlaceToPayWords, noun.remindToPayWords]
    }

    /// Whether `sentence`'s pronouns agree with `gender`: the word before „pun”, „păstrez”,
    /// „plătesc” is its object pronoun, and the word after „abonamentul” its possessive.
    static func agrees(_ sentence: String, with gender: CompletionShape.Paper.Gender) -> Bool {
        let words = RomanianText.fold(sentence).split { !$0.isLetter }.map(String.init)
        for (index, word) in words.enumerated() {
            if ["pun", "pui", "pastrez", "platesc", "platesti"].contains(word), index > 0, !objectPronouns(gender).contains(words[index - 1]) {
                return false
            }
            if word == "abonamentul", index + 1 < words.count, words[index + 1] != possessive(gender) {
                return false
            }
        }
        return true
    }

    @Test("A paper's sentences agree with its noun: „O pun” for a bill, „Îl pun” for a contract, for every gender")
    func sentencesAgreeWithTheirNouns() {
        for gender in CompletionShape.Paper.Gender.allCases {
            let noun = CaptureKindProfile.Noun(.on, "act", the: "actul", gender)
            for sentence in Self.pronounSentences(noun) {
                #expect(Self.agrees(sentence, with: gender), "\(gender): „\(sentence)”")
            }
        }
        for kind in CaptureDocumentKind.allCases {
            let noun = kind.profile.noun
            for sentence in Self.pronounSentences(noun) {
                #expect(Self.agrees(sentence, with: noun.gender), "\(kind): „\(sentence)” for „\(noun.onPaper)”")
            }
        }
    }

    @Test("A kind's noun is the one its title names: „O pun” follows „Factură”, „Îl pun” follows „Contract”")
    func nounsMatchTheirTitles() {
        func words(_ text: String) -> [String] {
            RomanianText.fold(text).split { !$0.isLetter }.map(String.init).filter { $0.count > 2 }
        }
        for kind in CaptureDocumentKind.allCases {
            let title = words(kind.profile.title)
            // The noun the pronouns agree with is the one the title is: its head word, with its
            // article („cartea” for „Carte de identitate”, „talonul” for „Talon (…)”), is the
            // title's own, so „îl” never follows a title in the feminine.
            let head = words(kind.profile.noun.itself).first ?? ""
            let named = title.contains { head.hasPrefix($0) || $0.hasPrefix(head) }
            #expect(named, "\(kind): „\(kind.profile.noun.itself)” for „\(kind.profile.title)”")
        }
    }

    @Test("What a paper says is written on it or in it, as its noun declares: „Pe factură scrie”, „În certificat scrie”, „Pe card scrie”")
    func papersSayWhereTheyAreWritten() {
        for kind in CaptureDocumentKind.allCases {
            let noun = kind.profile.noun
            let (opening, inside) = switch noun.surface {
            case .on: ("Pe \(noun.onPaper) scrie", "pe \(noun.onPaper).")
            case .inside: ("În \(noun.onPaper) scrie", "în \(noun.onPaper).")
            }
            #expect(noun.printedWords(CopyMatrixTests.reviewValue).hasPrefix(opening), "\(kind): „\(noun.printedWords(CopyMatrixTests.reviewValue))”")
            #expect(noun.nothingReadWords.contains(inside), "\(kind): „\(noun.nothingReadWords)”")
            #expect(!noun.itself.isEmpty, "\(kind): the paper itself has a name")
        }
        #expect(CaptureDocumentKind.electronicSignature.profile.noun.surface == .inside, "A certificate is written in")
        #expect(CaptureDocumentKind.healthInsuranceCard.profile.noun.surface == .on, "A card is written on")
    }

    @Test("A policy's bonus-malus class is said only for a car's RCA, the deadline that keeps who it insures")
    func bonusMalusOnlyForAVehiclesRCA() throws {
        let context = try makeContext()
        for kind in CaptureDocumentKind.allCases {
            let rows = try CopyMatrixTests.reviewRows(kind, context: context)
            let saysClass = rows.contains { $0.0 == "Its bonus-malus class" }
            #expect(saysClass == (kind == .rcaPolicy), "\(kind)")
        }
        let templates = try TemplateStore(context: context).templatesByKey()
        let home = try #require(templates[BuiltInTemplates.Key.home]?.definition.blueprints.first { $0.key == BuiltInBlueprints.homePAD })
        let rca = try #require(templates[BuiltInTemplates.Key.vehicle]?.definition.blueprints.first { $0.key == BuiltInBlueprints.vehicleRCA })
        let result = CopyMatrixTests.reviewResult(.rcaPolicy, day: CopyMatrixTests.reviewDayToCome, bonusMalus: "B8")
        let review = CaptureReview(result: result, assets: [], context: context)
        #expect(CaptureFilingPlan.bonusMalus(for: review, people: [], deadline: home) == nil, "A home's policy keeps no class")
        #expect(CaptureFilingPlan.bonusMalus(for: review, people: [], deadline: rca) != nil, "A car's RCA says where its class goes")
    }

    @Test("An ITP report says when its inspection stops being valid; a passport, when it expires")
    func daysReadAsTheirKindMeansThem() throws {
        let context = try makeContext()
        let itp = try CopyMatrixTests.reminderLine(.itpReport, day: CopyMatrixTests.reviewDayToCome, context: context)
        #expect(itp.hasPrefix("ITP-ul e valabil până pe"), "\(itp)")
        let bill = try CopyMatrixTests.reminderLine(.utilityInvoice, day: CopyMatrixTests.reviewDayToCome, placeChosen: false, context: context)
        #expect(bill.hasPrefix("De plătit până pe"), "\(bill)")
        #expect(CaptureKindProfile.DayMeaning.expires.opening("12 august 2031") == "Expiră pe 12 august 2031.")
        #expect(CaptureDocumentKind.contract.profile.noun.directDebitWords(CopyMatrixTests.reviewStatement).hasPrefix("În contract scrie:"))
        #expect(CaptureDocumentKind.utilityInvoice.profile.noun.directDebitWords(CopyMatrixTests.reviewStatement).hasPrefix("Pe factură scrie:"))
    }

    @Test("A day already passed is said as passed, and promises no reminder before it")
    func aPassedDayIsSaidAsPassed() throws {
        let context = try makeContext()
        let passed = DueWording.date(CopyMatrixTests.reviewDayPassed, today: CopyMatrixTests.reviewToday)
        for kind in CaptureDocumentKind.allCases {
            guard let meaning = kind.profile.dayMeaning else { continue }
            let line = try CopyMatrixTests.reminderLine(kind, day: CopyMatrixTests.reviewDayPassed, context: context)
            #expect(!line.contains("Te anunț"), "\(kind): „\(line)”")
            #expect(!line.hasPrefix(meaning.opening(passed)), "\(kind): „\(line)” opens as if the day were to come")
            #expect(line.hasPrefix(meaning.passedOpening(passed)) || line.hasPrefix("A fost valabil"), "\(kind): „\(line)”")
        }
    }

    @Test("What a paper says about its direct debit is quoted once, with one full stop")
    func aQuoteEndsWithOneFullStop() {
        for kind in CaptureDocumentKind.allCases {
            let words = kind.profile.noun.directDebitWords(CopyMatrixTests.reviewStatement)
            #expect(!words.contains(".”."), "\(kind): „\(words)”")
        }
    }
}
