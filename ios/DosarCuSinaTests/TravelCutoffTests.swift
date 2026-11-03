import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A passport is no good for travel in its last six months: many countries refuse entry
/// with less left, and six months covers every country's rule. The margin is data on the
/// document type; only passports have one. Its reminders count back from the cut-off, it
/// joins "Acum" from the cut-off on, its page shows both dates and the trip check uses the
/// same day. Every other document keeps its plain expiry.
@Suite("A passport's travel cut-off")
struct TravelCutoffTests {
    let calendar = Calendar.bucharest
    /// Printed on the passport: valid until 12 August 2027 (the last valid day).
    let expiry = CalendarDay("2027-08-12")
    /// Six calendar months before: the last day it is good for travel.
    let cutoff = CalendarDay("2027-02-12")

    private var passportProfile: ReminderProfile {
        BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew }!
            .reminders(for: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.passport)]))
    }

    private var idCardProfile: ReminderProfile {
        BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew }!
            .reminders(for: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.idCard)]))
    }

    private func passport(isSensitive: Bool = false, profile: ReminderProfile? = nil) -> ObligationSnapshot {
        ObligationSnapshot(title: "Reînnoire", kind: .renewal, dueDay: expiry, reminders: profile ?? passportProfile,
                           assetName: "Pașaport", isSensitive: isSensitive)
    }

    // MARK: Only passports

    @Test func onlyPassportsHaveATravelMargin() {
        for option in DocumentType.options {
            let margin = DocumentType.travelMarginDays(for: option.key)
            #expect(margin == (option.key == DocumentType.passport ? 180 : 0), "\(option.key)")
            // An earlier version stored the label: the same rule.
            #expect(DocumentType.travelMarginDays(for: option.label) == margin, "\(option.label)")
        }
        for variant in DocumentType.variants {
            var values = FieldValues()
            values[DocumentType.typeFieldKey] = .text(variant.type)
            values[DocumentType.variantFieldKey] = .text(variant.option.key)
            #expect(DocumentType.travelMarginDays(in: values) == (variant.type == DocumentType.passport ? 180 : 0), "\(variant.option.key)")
        }
        #expect(DocumentType.travelMarginDays(for: nil) == 0)
        #expect(DocumentType.travelMarginDays(for: "Ceva necunoscut") == 0)
        #expect(Set(DocumentType.travelMargins.keys) == [DocumentType.passport], "No default margin, no other type")
    }

    @Test func theCatalogTakesTheMarginFromTheDocumentTypeAndNowhereElse() {
        let renew = BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew }!
        for option in DocumentType.options {
            let profile = renew.reminders(for: FieldValues([DocumentType.typeFieldKey: .text(option.key)]))
            #expect(profile.travelMarginDays == DocumentType.travelMarginDays(for: option.key), "\(option.key)")
        }
        for template in BuiltInTemplates.all {
            for blueprint in template.blueprints where blueprint.key != BuiltInBlueprints.documentRenew {
                #expect(blueprint.reminders.travelMarginDays == 0, "\(blueprint.key)")
                for profile in blueprint.reminderVariants?.variants.values.map({ $0 }) ?? [] {
                    #expect(profile.travelMarginDays == 0, "\(blueprint.key)")
                }
            }
        }
        #expect(passportProfile == ReminderProfile(leadDays: [90, 0], consequence: .legal, travelMarginDays: 180))
    }

    @Test func theCutoffIsSixCalendarMonthsBeforeTheExpiry() {
        let rule = passportProfile.urgencyRule
        #expect(rule.travelCutoff(before: expiry, calendar: calendar) == cutoff)
        #expect(rule.travelCutoff(before: CalendarDay("2027-08-31"), calendar: calendar) == CalendarDay("2027-02-28"), "A short month ends the cut-off on its last day")
        #expect(rule.travelCutoff(before: CalendarDay("2028-08-29"), calendar: calendar) == CalendarDay("2028-02-29"))
        #expect(idCardProfile.urgencyRule.travelCutoff(before: expiry, calendar: calendar) == nil)
    }

    // MARK: Reminders

    @Test func aPassportRemindsThreeMonthsBeforeTheCutoffAndOnIt() {
        let plan = ReminderPlanner.plan([passport()], now: noon("2026-06-01"), calendar: calendar)
        let days = plan.map { CalendarDay($0.fireDate, calendar: calendar) }
        // 9 and 6 months before the printed expiry, and the day after it lapses.
        #expect(days == [CalendarDay("2026-11-12"), cutoff, CalendarDay("2027-08-13")])
        #expect(plan.map(\.title) == [
            "Bun de călătorit încă 3 luni: Reînnoire",
            "Azi e ultima zi bună de călătorit: Reînnoire",
            "Depășit: Reînnoire",
        ])
        #expect(plan[0].body.hasPrefix("Pașaport · bun de călătorit până pe "))
        #expect(plan.allSatisfy { $0.cycle == expiry }, "Every reminder acts on the passport's own cycle")
        #expect(plan.allSatisfy { ReminderPlanner.cycle(fromIdentifier: $0.identifier, deliveredOn: CalendarDay($0.fireDate, calendar: calendar), calendar: calendar) != cutoff })
    }

    @Test func aProtectedPassportNamesNothing() {
        let plan = ReminderPlanner.plan([passport(isSensitive: true)], now: noon("2026-06-01"), calendar: calendar)
        #expect(plan.prefix(2).map(\.title) == ["Un act e bun de călătorit încă 3 luni", "Azi e ultima zi în care un act e bun de călătorit"])
        #expect(plan.allSatisfy { !$0.title.contains("Reînnoire") && !$0.body.contains("Pașaport") })
    }

    @Test func aPassportAddedAfterItsCutoffStillGetsOneReminderBeforeItExpires() {
        var item = passport()
        item.cycleKnownSince = noon("2027-03-01")
        let plan = ReminderPlanner.plan([item], now: noon("2027-03-01"), calendar: calendar)
        let catchUp = plan.first { $0.identifier.hasSuffix(".\(ReminderPlanner.catchUpSuffix)") }
        #expect(catchUp.map { CalendarDay($0.fireDate, calendar: calendar) } == CalendarDay("2027-03-02"))
        #expect(catchUp?.title == "În 5 luni și o săptămână: Reînnoire")
    }

    @Test func anIdentityCardRemindsAsBefore() {
        let card = ObligationSnapshot(title: "Reînnoire", kind: .renewal, dueDay: expiry, reminders: idCardProfile, assetName: "Carte de identitate")
        #expect(idCardProfile == ReminderProfile(leadDays: [90, 30], consequence: .legal))
        let plan = ReminderPlanner.plan([card], now: noon("2026-06-01"), calendar: calendar)
        #expect(plan.map { CalendarDay($0.fireDate, calendar: calendar) } == [CalendarDay("2027-05-12"), CalendarDay("2027-07-12"), CalendarDay("2027-08-13")])
        #expect(plan.map(\.title) == ["În 3 luni: Reînnoire", "Într-o lună: Reînnoire", "Depășit: Reînnoire"])
        #expect(plan.allSatisfy { !$0.body.contains("călătorit") })
        #expect(plan.prefix(2).allSatisfy { $0.identifier.contains(".d") })
    }

    // MARK: Urgency

    @Test("The passport turns amber and joins Acum from its cut-off on, on every surface", arguments: [
        ("2026-12-01", AttentionUrgency.later),
        ("2027-01-12", AttentionUrgency.later),
        ("2027-01-13", AttentionUrgency.upcoming),
        ("2027-02-11", AttentionUrgency.upcoming),
        ("2027-02-12", AttentionUrgency.soon),
        ("2027-05-01", AttentionUrgency.soon),
        ("2027-08-11", AttentionUrgency.soon),
        ("2027-08-12", AttentionUrgency.today),
        ("2027-08-13", AttentionUrgency.overdue),
    ])
    func everySurfaceAgrees(on iso: String, expected: AttentionUrgency) throws {
        let today = CalendarDay(iso)
        let now = today.noonDate(in: calendar)
        let item = passport()
        let days = today.days(to: expiry, calendar: calendar)
        #expect(item.reminders.urgencyRule.urgency(of: expiry, today: today, calendar: calendar) == expected)

        // Urmează: Acum from the cut-off, Curând in the month before it.
        let digest = AttentionModel.digest([item], now: now, calendar: calendar)
        #expect(!digest.now.isEmpty == expected.needsAttentionNow)
        #expect(!digest.soon.isEmpty == (expected == .upcoming))
        #expect(digest.later.count == (expected == .later ? 1 : 0))

        // The binder's box, in the same tone.
        let box = BoxStatus.make([item], now: now, calendar: calendar)
        #expect(box.urgencyTone == (expected.needsAttentionNow ? expected.tone : .calm))

        // The widget, from the snapshot the app writes: same urgency and words.
        let data = try WidgetSnapshot.encoder().encode(WidgetSnapshot.make(from: [item], now: now, calendar: calendar))
        let rows = WidgetContent.rows(feed: try #require(WidgetFeed.decode(data)), completed: [], now: now, calendar: calendar, protectedTitle: "", limit: 8)
        if expected != .later {
            let row = try #require(rows.first)
            #expect(row.urgency == expected)
            #expect(row.when == WhenWording.standalone(expected, daysRemaining: days, from: now, calendar: calendar))
        }

        // The badge on the passport's page: "Valabil" while calm, else how far its expiry is.
        #expect((DSDueText.expiryText(expected, daysRemaining: days, from: now, calendar: calendar) == "Valabil") == (expected.tone == .calm))
        #expect(expected.tone == (expected == .overdue ? .overdue : (expected.needsAttentionNow ? .soon : .calm)))
    }

    @Test func aWidgetSnapshotFromBeforeTheMarginReadsAsHavingNone() throws {
        let old = #"{"graceDays":0,"firstLeadDays":180,"maxWindowDays":30}"#
        let rule = try JSONDecoder().decode(UrgencyRule.self, from: Data(old.utf8))
        #expect(rule == UrgencyRule(graceDays: 0, firstLeadDays: 180, maxWindowDays: 30))
        let encoded = try JSONEncoder().encode(passportProfile.urgencyRule)
        #expect(try JSONDecoder().decode(UrgencyRule.self, from: encoded) == passportProfile.urgencyRule)
    }

    @Test func anIdentityCardIsUrgentOnlyInItsLastMonthAsBefore() {
        let rule = idCardProfile.urgencyRule
        #expect(rule.travelMarginDays == 0)
        #expect(rule.urgency(of: expiry, today: CalendarDay("2027-02-12"), calendar: calendar) == .later)
        #expect(rule.urgency(of: expiry, today: CalendarDay("2027-07-11"), calendar: calendar) == .later)
        #expect(rule.urgency(of: expiry, today: CalendarDay("2027-07-12"), calendar: calendar) == .soon)
        #expect(rule.attentionStart(before: expiry, calendar: calendar) == CalendarDay("2027-07-12"))
    }

    @Test func aProfileWithoutAMarginIsStoredAsBefore() throws {
        let json = try #require(StoredJSON.encode(idCardProfile)).utf8String
        #expect(!json.contains("travelMarginDays"), "Every other profile, in archives too, reads exactly as before")
        let passportJSON = try #require(StoredJSON.encode(passportProfile))
        #expect(StoredJSON.decode(ReminderProfile.self, from: passportJSON) == passportProfile)
    }

    // MARK: The page

    @Test func thePageShowsBothDates() {
        let rule = passportProfile.urgencyRule
        #expect(DueWording.travelLines(due: expiry, rule: rule, today: CalendarDay("2026-11-03"), calendar: calendar)
                == ["Expiră pe 12 august 2027", "Bun de călătorit până pe 12 februarie 2027"])
        #expect(DueWording.travelLines(due: expiry, rule: rule, today: CalendarDay("2027-03-01"), calendar: calendar)
                == ["Expiră pe 12 august", "A fost bun de călătorit până pe 12 februarie"])
        #expect(DueWording.travelLines(due: expiry, rule: rule, today: CalendarDay("2027-09-01"), calendar: calendar)
                == ["A expirat pe 12 august"])
        #expect(DueWording.travelLines(due: expiry, rule: idCardProfile.urgencyRule, today: CalendarDay("2026-11-03"), calendar: calendar) == nil,
                "An identity card keeps its one due line")
    }

    @Test func remindersReadWhatTheyDoBeforeSaving() {
        let today = CalendarDay("2026-11-03")
        #expect(ReminderWording.sentence(passportProfile) == "Te anunț cu 3 luni înainte de ultima zi bună de călătorit și în ziua aceea.")
        #expect(ReminderWording.expiryLine(expiry, profile: passportProfile, today: today, calendar: calendar)
                == "Expiră pe 12 august 2027. Bun de călătorit până pe 12 februarie 2027. Te anunț cu 3 luni înainte de ultima zi bună de călătorit și în ziua aceea.")
        #expect(ReminderWording.rowTitle(days: 0, from: .init(passportProfile)) == "În ultima zi bună de călătorit")
        #expect(ReminderWording.sentence(idCardProfile) == "Te anunț cu 3 luni și cu o lună înainte.")
        #expect(ReminderWording.expiryLine(expiry, profile: idCardProfile, today: today, calendar: calendar)
                == "Expiră pe 12 august 2027. Te anunț cu 3 luni și cu o lună înainte.")
        #expect(ReminderWording.rowTitle(days: 0, from: .init(idCardProfile)) == "În ziua termenului")
    }

    @Test func changingTheLeadsKeepsTheMargin() {
        #expect(passportProfile.withLeadDays([30]).travelMarginDays == 180)
        #expect(passportProfile.withLeadDays([30]).leadDays == [30])
    }

    // MARK: The trip check


    @Test("Outside the EU, the passport must be good for travel until the trip ends", arguments: [
        ("2027-02-12", ReadinessStatus.ok),
        ("2027-02-13", ReadinessStatus.problem),
    ])
    func theTripCheckUsesTheSameCutoff(end iso: String, expected: ReadinessStatus) {
        let passports = [ReadinessAsset.personalDocument(DocumentType.passport, expires: expiry.isoString)]
        let items = ReadinessEngine.check(
            .trip(.everyone(start: "2027-02-01", end: iso, region: .outsideEU, in: passports)),
            assets: passports, calendar: calendar
        )
        let passport = items.first { $0.id.hasPrefix("trip.passport") }
        #expect(passport?.status == expected)
        #expect(passport?.detail.contains("12 februarie 2027") == true)
    }

    @Test func inTheEUAnIdentityCardIsGoodUntilItExpires() {
        let cards = [ReadinessAsset.personalDocument(DocumentType.idCard, expires: expiry.isoString)]
        let items = ReadinessEngine.check(
            .trip(.everyone(start: "2027-08-01", end: "2027-08-12", region: .europeanUnion, in: cards)),
            assets: cards, calendar: calendar
        )
        #expect(items.first { $0.id == "trip.identity.unfiled" }?.status == .ok)
    }

    // MARK: Existing passports

    @Test @MainActor func anExistingPassportGetsItsCutoffOnlyWithTheOwnersOK() throws {
        let context = try makeContext()
        let fixed = noon("2026-11-03")
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let assets = AssetActions(context: context, calendar: calendar, now: { fixed })
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        values[DocumentFields.expiry] = .date(expiry)
        let passport = try assets.create(name: "Pașaport", template: documents, values: values,
                                         obligations: assets.plannedObligations(for: documents, values: values))
        var cardValues = FieldValues()
        cardValues[DocumentType.typeFieldKey] = .text(DocumentType.idCard)
        cardValues[DocumentFields.expiry] = .date(expiry)
        let card = try assets.create(name: "Carte de identitate", template: documents, values: cardValues,
                                     obligations: assets.plannedObligations(for: documents, values: cardValues))
        let renewal = try #require(passport.activeObligations.first)
        #expect(renewal.reminders == passportProfile, "A new passport gets its cut-off at once")

        // As an earlier version saved it: six and two months before the expiry, no cut-off.
        renewal.reminders = ReminderProfile(leadDays: [180, 60], consequence: .legal, followUpAfterLapse: false)
        try UnitOfWork.save(context)

        let ledger = DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "travel-\(UUID().uuidString)")))
        let repairs = DataRepairs(context: context, calendar: calendar, ledger: ledger)
        let found = try repairs.detect().filter { $0.step == .travelCutoff }
        #expect(found.count == 1, "Only the passport, never the identity card")
        #expect(renewal.travelMarginDays == 0, "Nothing changes before the owner says so")
        let message = try #require(found.first?.message)
        #expect(message == "„Pașaport” e bun de călătorit doar până pe 12 februarie 2027, cu 6 luni înainte să expire. Schimb când te anunț? Te anunț cu 3 luni înainte de ultima zi bună de călătorit și în ziua aceea.")

        try repairs.apply(found)
        #expect(renewal.reminders == passportProfile, "It takes the passport's reminders, as changing the type in Editează does")
        #expect(renewal.travelMarginDays == 180)
        #expect(card.activeObligations.first?.reminders == idCardProfile)
        #expect(try repairs.detect().filter { $0.step == .travelCutoff }.isEmpty, "Applied once, not found again")
    }

    /// The same rule both ways: a deadline that still counts from a cut-off its document no
    /// longer has is offered too, and one whose reminders the person set is left alone.
    @Test @MainActor func theRepairChecksTheSameRuleAsEditing() throws {
        let context = try makeContext()
        let fixed = noon("2026-11-03")
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let assets = AssetActions(context: context, calendar: calendar, now: { fixed })
        func document(_ name: String, type: String) throws -> Obligation {
            var values = FieldValues()
            values[DocumentType.typeFieldKey] = .text(type)
            values[DocumentFields.expiry] = .date(expiry)
            let asset = try assets.create(name: name, template: documents, values: values,
                                          obligations: assets.plannedObligations(for: documents, values: values))
            return try #require(asset.activeObligations.first)
        }
        // A card that was a passport before reminders followed the type: it kept the cut-off.
        let card = try document("Carte de identitate", type: DocumentType.idCard)
        card.reminders = passportProfile
        // A passport whose reminders the person set before margins existed.
        let own = try document("Pașaport", type: DocumentType.passport)
        own.reminders = ReminderProfile(leadDays: [200], consequence: .legal)
        own.remindersCustomized = true
        try UnitOfWork.save(context)

        let repairs = DataRepairs(context: context, calendar: calendar,
                                  ledger: DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "travel-\(UUID().uuidString)"))))
        let found = try repairs.detect().filter { $0.step == .travelCutoff }
        #expect(found.count == 1, "Only the card; the person's own reminders stay")
        #expect(found.first?.message.hasPrefix("La „Carte de identitate” contează doar data de expirare. Schimb când te anunț?") == true)
        try repairs.apply(found)
        #expect(card.reminders == idCardProfile)
        #expect(own.reminders == ReminderProfile(leadDays: [200], consequence: .legal))
    }
}

private extension Data {
    var utf8String: String { String(decoding: self, as: UTF8.self) }
}
