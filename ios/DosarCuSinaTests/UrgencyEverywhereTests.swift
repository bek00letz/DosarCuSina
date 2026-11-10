import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Days from today the surface tests walk through: late, today, tomorrow, the leads
/// people meet (a week, two, a month, two, six) and a year.
private let surfaceDays = [-10, -3, -1, 0, 1, 7, 14, 20, 30, 60, 180, 365]

/// One deadline, every surface. Urmează, the binder's box, a section's page, the
/// widget, the badge, Siri and the reminders all take the one rule (`UrgencyRule`,
/// from the reminder profile) and the one wording (`DurationWording`, `WhenWording`),
/// so the same deadline never reads two ways.
@Suite("One urgency and one wording everywhere")
struct UrgencyEverywhereTests {
    let calendar = Calendar.bucharest
    let now = noon("2026-11-02")
    let car = (UUID(), "VW Golf")

    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    private func deadline(_ kind: ObligationKind, in days: Int) -> ObligationSnapshot {
        snapshot("Termen", kind: kind, due: today.adding(days: days, calendar: calendar).isoString, asset: car)
    }

    @Test("Urmează, the box, the widget and the badge agree", arguments: ObligationKind.allCases, surfaceDays)
    func everySurfaceAgrees(kind: ObligationKind, days: Int) throws {
        let item = deadline(kind, in: days)
        let urgency = item.reminders.urgencyRule.urgency(of: item.dueDay, today: today, calendar: calendar)
        let when = WhenWording.phrase(urgency, daysRemaining: days, from: now, calendar: calendar)

        // Urmează: "Acum" exactly when the rule says it needs the person.
        let digest = AttentionModel.digest([item], now: now, calendar: calendar)
        #expect(!digest.now.isEmpty == urgency.needsAttentionNow)
        let listed = digest.now.first ?? digest.soon.first?.entries.first
        #expect(listed.map { $0.urgency == urgency } ?? (days > UrgencyRule.upcomingWindowDays))
        #expect(AttentionModel.entry(for: item, today: today, calendar: calendar).urgency == urgency, "The full list")

        // The binder's box and the hero's status line: shown when it needs the person, in its tone.
        let box = BoxStatus.make([item], now: now, calendar: calendar)
        #expect((box.entry != nil) == urgency.needsAttentionNow)
        if box.entry != nil {
            #expect(box.urgencyTone == urgency.tone)
            #expect(box.line(isSensitive: false, now: now, calendar: calendar) == "Termen · \(when)")
        }

        // The widget: the same urgency and words, from the snapshot the app writes.
        let data = try WidgetFeed.encode(WidgetFeed.make(from: [item], now: now, calendar: calendar))
        let feed = try #require(WidgetFeed.decode(data))
        let rows = WidgetContent.rows(feed: feed, completed: [], now: now, calendar: calendar, protectedTitle: "", limit: 8)
        if let row = rows.first {
            #expect(row.urgency == urgency)
            #expect(row.when == WhenWording.standalone(urgency, daysRemaining: days, from: now, calendar: calendar))
            #expect(row.when.lowercased(with: .dosarDefault) == when.lowercased(with: .dosarDefault))
        } else {
            #expect(days > UrgencyRule.upcomingWindowDays, "Everything in Urmează's next month reaches the widget")
        }

        // The badge and the widget count the same.
        #expect(digest.needsActionCount == (urgency.isAlarming ? 1 : 0))
        #expect(WidgetContent.needsActionCount(rows) == digest.needsActionCount)
    }

    @Test("A section's page and its badges agree with Urmează", arguments: [-3, 0, 1, 7, 20, 30, 60, 180])
    @MainActor
    func theSectionPageAgrees(days: Int) throws {
        let context = try makeContext()
        let asset = Asset(name: "VW Golf", templateKey: "vehicle", values: FieldValues())
        context.insert(asset)
        let fixed = now
        let actions = ObligationActions(context: context, calendar: calendar, now: { fixed })
        let due = today.adding(days: days, calendar: calendar)
        for kind in ObligationKind.allCases {
            try actions.create(title: kind.rawValue, kind: kind, dueDay: due, for: asset)
        }
        let snapshots = try ObligationSnapshot.fetchAll(in: context, calendar: calendar)
        for obligation in asset.activeObligations {
            let snapshot = try #require(snapshots.first { $0.id == obligation.id })
            let inUrmeaza = AttentionModel.entry(for: snapshot, today: today, calendar: calendar).urgency
            #expect(obligation.urgency(now: now, calendar: calendar) == inUrmeaza, "\(obligation.title): the pocket's badge")
        }
        // A date shown on the page (an expiry) takes the rule of the deadline it drives.
        let first = try #require(asset.activeObligations.first)
        #expect(DateUrgency.rule(for: due, on: asset, calendar: calendar) == first.reminders.urgencyRule)
        #expect(DateUrgency.rule(for: due.adding(days: 1, calendar: calendar), on: asset, calendar: calendar) == .noReminders)
    }

    @Test("A reminder says what every screen says on the day it fires", arguments: ObligationKind.allCases, [0, 1, 7, 14, 20, 30, 60, 180, 365])
    func remindersSayWhatScreensSay(kind: ObligationKind, days: Int) {
        let due = CalendarDay("2027-03-31").adding(days: days, calendar: calendar)
        let item = snapshot("Termen", kind: kind, due: due.isoString)
        let plan = ReminderPlanner.plan([item], now: due.adding(days: -800, calendar: calendar).noonDate(in: calendar), calendar: calendar)
        #expect(!plan.isEmpty)
        for reminder in plan {
            let fireDay = CalendarDay(reminder.fireDate, calendar: calendar)
            let left = fireDay.days(to: due, calendar: calendar)
            let urgency = item.reminders.urgencyRule.urgency(of: due, today: fireDay, calendar: calendar)
            if left >= 0 {
                let when = WhenWording.standalone(urgency, daysRemaining: left, from: reminder.fireDate, calendar: calendar)
                #expect(reminder.title == "\(when): Termen", "\(kind) \(reminder.identifier)")
            } else {
                #expect(reminder.title == (urgency == .withinGrace ? "Încă de făcut: Termen" : "Depășit: Termen"), "\(kind) \(reminder.identifier)")
            }
        }
    }

    @Test("A lead reads the same where it's chosen and in the reminder it fires",
          arguments: ["2027-01-31", "2027-03-31", "2027-03-01", "2028-02-29", "2026-12-15", "2027-07-01"])
    func leadsReadTheSame(due iso: String) throws {
        let due = CalendarDay(iso)
        let profiles = ObligationKind.allCases.map(\.defaultProfile) + [
            ReminderProfile(leadDays: [180, 60], consequence: .legal),
            ReminderProfile(leadDays: [90, 30], consequence: .legal),
            ReminderProfile(leadDays: [270, 180, 60], consequence: .legal),
            ReminderProfile(leadDays: [365, 14, 10, 4], consequence: .health),
        ]
        for profile in profiles {
            let item = ObligationSnapshot(title: "Termen", kind: .renewal, dueDay: due, reminders: profile)
            let plan = ReminderPlanner.plan([item], now: due.adding(days: -800, calendar: calendar).noonDate(in: calendar), calendar: calendar)
            for lead in profile.leadDays where lead >= 2 {
                let reminder = try #require(plan.first { $0.identifier.hasSuffix(".d\(lead)") })
                #expect(reminder.title == "\(DurationWording.inside(ReminderWording.phrase(days: lead), startsSentence: true)): Termen", "\(lead) days before \(iso)")
                #expect(ReminderWording.rowTitle(days: lead, from: .dueDay) == "Cu \(ReminderWording.phrase(days: lead)) înainte")
            }
        }
    }

    @Test func aMonthLeadIsTheSameDayAMonthBefore() {
        #expect(ReminderLead(days: 30).day(before: CalendarDay("2027-03-15"), calendar: calendar) == CalendarDay("2027-02-15"))
        #expect(ReminderLead(days: 30).day(before: CalendarDay("2027-03-31"), calendar: calendar) == CalendarDay("2027-02-28"))
        #expect(ReminderLead(days: 180).day(before: CalendarDay("2027-03-31"), calendar: calendar) == CalendarDay("2026-09-30"))
        #expect(ReminderLead(days: 365).day(before: CalendarDay("2028-02-29"), calendar: calendar) == CalendarDay("2027-02-28"))
        #expect(ReminderLead(days: 14).day(before: CalendarDay("2027-03-15"), calendar: calendar) == CalendarDay("2027-03-01"))
        #expect(ReminderLead(days: 45) == .days(45), "Not a whole number of months: days")
    }

    @Test func itNeedsThePersonFromTheFirstReminderAtMostItsConsequencesWindow() {
        let due = CalendarDay("2027-03-31")
        // An RCA reminds a month ahead, and needs the person from that day on.
        let rca = ObligationKind.insurance.defaultProfile
        let item = ObligationSnapshot(title: "RCA", kind: .insurance, dueDay: due, reminders: rca)
        let plan = ReminderPlanner.plan([item], now: noon("2026-12-01"), calendar: calendar)
        let first = plan.first { $0.identifier.hasSuffix(".d30") }
        #expect(first.map { CalendarDay($0.fireDate, calendar: calendar) } == rca.urgencyRule.attentionStart(before: due, calendar: calendar))
        #expect(rca.urgencyRule.urgency(of: due, today: CalendarDay("2027-02-28"), calendar: calendar) == .soon)
        #expect(rca.urgencyRule.urgency(of: due, today: CalendarDay("2027-02-27"), calendar: calendar) == .later)
        // Twenty days out it is "Acum" in Urmează and drawn in the same tone on the car's page.
        let twenty = rca.urgencyRule.urgency(of: due, today: due.adding(days: -20, calendar: calendar), calendar: calendar)
        #expect(twenty == .soon && twenty.tone == .soon)

        // A deadline that reminds six months ahead needs the person only in its last month.
        let sixMonths = ReminderProfile(leadDays: [180, 60], consequence: .legal).urgencyRule
        #expect(sixMonths.urgency(of: due, today: CalendarDay("2026-09-30"), calendar: calendar) == .later)
        #expect(sixMonths.urgency(of: due, today: CalendarDay("2027-02-28"), calendar: calendar) == .soon)

        // A cat vaccine a few days late is calm everywhere; past its grace it is overdue.
        let vaccine = ReminderProfile(leadDays: [1], consequence: .health, graceDays: 7).urgencyRule
        #expect(vaccine.urgency(of: due, today: due.adding(days: 2, calendar: calendar), calendar: calendar) == .withinGrace)
        #expect(vaccine.urgency(of: due, today: due.adding(days: 2, calendar: calendar), calendar: calendar).tone == .soon)
        #expect(vaccine.urgency(of: due, today: due.adding(days: 8, calendar: calendar), calendar: calendar) == .overdue)

        // A date nothing reminds about is urgent only on the day and after.
        #expect(UrgencyRule.noReminders.urgency(of: due, today: due.adding(days: -1, calendar: calendar), calendar: calendar) == .upcoming)
        #expect(UrgencyRule.noReminders.urgency(of: due, today: due, calendar: calendar) == .today)
    }

    @Test func theWidgetCountsLikeTheBadgeAtEveryMidnight() throws {
        let items = [
            snapshot("ITP", kind: .legal, due: "2026-10-30"),
            snapshot("Vaccin", kind: .health, due: "2026-11-01", offsets: [1], consequence: .health, grace: 7),
            snapshot("Chirie", kind: .payment, due: "2026-11-02"),
            snapshot("Rovinietă", kind: .legal, due: "2026-11-03", offsets: [7, 0], consequence: .legal),
            snapshot("Revizie", kind: .maintenance, due: "2026-11-05"),
            snapshot("Impozit", kind: .tax, due: "2026-11-06"),
            snapshot("Udat", kind: .routine, due: "2026-11-04"),
        ]
        let feed = try #require(WidgetFeed.decode(WidgetFeed.encode(WidgetFeed.make(from: items, now: now, calendar: calendar))))
        for offset in 0..<7 {
            let midnight = calendar.startOfDay(for: today.adding(days: offset, calendar: calendar).noonDate(in: calendar))
            let rows = WidgetContent.rows(feed: feed, completed: [], now: midnight, calendar: calendar, protectedTitle: "", limit: 8)
            let badge = AttentionModel.digest(items, now: midnight, calendar: calendar).needsActionCount
            #expect(WidgetContent.needsActionCount(rows) == badge, "\(offset) days on")
        }
    }

    @Test @MainActor func countedStringsUseTheirPluralForms() {
        #expect(DayCount.phrase(1) == "o zi")
        #expect(DayCount.phrase(20) == "20 de zile")
        #expect(CalendarCount.weeks(3) == "3 săptămâni")
        #expect(CalendarCount.months(1) == "o lună")
        #expect(CalendarCount.years(20) == "20 de ani")
        #expect(TemplateStoreError.inUse(assetCount: 1).errorDescription == "Categoria are încă un activ. Mută-l sau șterge-l mai întâi.")
        #expect(TemplateStoreError.inUse(assetCount: 3).errorDescription == "Categoria are încă 3 active. Mută-le sau șterge-le mai întâi.")
        #expect(TemplateStoreError.inUse(assetCount: 20).errorDescription == "Categoria are încă 20 de active. Mută-le sau șterge-le mai întâi.")
        let jobs = { (n: Int) in HistoryActions.visitTitle(for: (1...n).map { LineItemDraft(name: "Lucrare \($0)") }) }
        #expect(jobs(3) == "Revizie: 3 lucrări")
        #expect(jobs(20) == "Revizie: 20 de lucrări")
        #expect(UpcomingActions.snoozeTitle(days: 1) == "Mâine")
        #expect(UpcomingActions.snoozeTitle(days: 14) == "Peste 14 zile")
    }

    /// A count of one is a word, two and up are digits; „în” joins „o” and „un”, so no
    /// phrase reads "în o lună" or "1 lună".
    @Test @MainActor func countsOfOneAreWordsInEveryPhrase() {
        let start = noon("2026-11-01")
        #expect(DurationWording.inside("5 zile") == "în 5 zile")
        #expect(DurationWording.inside(CalendarCount.months(1)) == "într-o lună")
        #expect(DurationWording.inside(CalendarCount.years(1)) == "într-un an")
        #expect(DurationWording.inside(CalendarCount.weeks(1), startsSentence: true) == "Într-o săptămână")
        #expect(DurationWording.inside(DurationWording.yearsAndMonths(years: 1, months: 4)) == "într-un an și 4 luni")
        #expect(DurationWording.distance(days: 30, from: start, calendar: calendar) == "o lună")
        #expect(WhenWording.phrase(.soon, daysRemaining: 30, from: start, calendar: calendar) == "într-o lună")
        #expect(WhenWording.phrase(.withinGrace, daysRemaining: -1, from: start, calendar: calendar) == "întârziat cu o zi")
        #expect(WhenWording.phrase(.overdue, daysRemaining: -1, from: start, calendar: calendar) == "depășit de o zi")
        #expect(WhenWording.standalone(.soon, daysRemaining: 30, from: start, calendar: calendar) == "Într-o lună")
        #expect(DSDueText.expiryText(.soon, daysRemaining: 365, from: start, calendar: calendar) == "Expiră într-un an")
        #expect(DueWording.relative(daysRemaining: 30, from: start, calendar: calendar) == "într-o lună")
        #expect(DueWording.relative(daysRemaining: -7, from: start, calendar: calendar) == "acum 7 zile")
        #expect(ReminderPlanner.specificTitle("ITP", daysBefore: 30, from: start, calendar: calendar) == "Într-o lună: ITP")
        #expect(ReminderPlanner.genericTitle(daysBefore: 365, from: start, calendar: calendar) == "Ai o scadență într-un an")
        #expect(ReminderWording.rowTitle(days: 30, from: .dueDay) == "Cu o lună înainte")
        #expect(ReminderWording.rowTitle(days: 1, from: .dueDay) == "Cu o zi înainte")
        #expect(ReminderWording.rowTitle(days: 365, from: .dueDay) == "Cu un an înainte")
        #expect(UpcomingActions.snoozeTitle(days: 7) == "Peste 7 zile")
        #expect(TemplateStoreError.inUse(assetCount: 1).errorDescription == "Categoria are încă un activ. Mută-l sau șterge-l mai întâi.")
    }
}
