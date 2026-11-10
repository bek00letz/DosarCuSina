import Foundation
import SwiftData

// MARK: - Days kept with another calendar's year

/// Before the app counted every day in one Gregorian calendar (`Calendar.dosar`), a phone set
/// to another calendar wrote the days it worked out itself in that calendar's years: on a phone
/// set to the Buddhist calendar, today was 2569, and a section's date field kept "2569-03-31".
/// Such a day reads as a year that can't be (more than 200 years ahead, or before 1800), in a
/// section's values or in a day kept on a deadline, a completion or a document.
///
/// A year 543 ahead of a likely one is the Buddhist calendar's (its months and days are the
/// Gregorian ones), so it is offered back 543 years, asking first. Any other year that can't
/// be (a Japanese era's, an Islamic or Hebrew year, whose months differ too) can't be worked
/// back safely: the finding only says where it is and what to check
/// (`DataRepairFinding.isFixable` false).
struct DayYearsStep: DataRepairStep {
    static let id = DataRepairStepID.dayYears
    var title: String { String(localized: "Date cu anul greșit", comment: "Repair group: days kept with another calendar's year by older builds.") }

    /// Where a day is kept.
    enum Place: Hashable, Sendable {
        /// A date field of a section's values.
        case field(assetID: UUID, key: String)
        case due(obligationID: UUID)
        case snooze(obligationID: UUID)
        case cycle(entryID: UUID)
        case next(entryID: UUID)
        case documentDay(attachmentID: UUID)
        case validUntil(attachmentID: UUID)

        /// Its part of a finding's id.
        var key: String {
            switch self {
            case .field(let id, let key): "field:\(id.uuidString):\(key)"
            case .due(let id): "due:\(id.uuidString)"
            case .snooze(let id): "snooze:\(id.uuidString)"
            case .cycle(let id): "cycle:\(id.uuidString)"
            case .next(let id): "next:\(id.uuidString)"
            case .documentDay(let id): "document-day:\(id.uuidString)"
            case .validUntil(let id): "valid-until:\(id.uuidString)"
            }
        }
    }

    /// A day whose year can't be, and the day it means when that can be known.
    struct Candidate {
        let place: Place
        let day: CalendarDay
        let fixed: CalendarDay?
        /// What the list calls it: the field, deadline or document, and its section.
        let name: String
        let section: String?
        /// Writes the day back where it was found.
        let write: (CalendarDay) -> Void
    }

    /// How far a year read from another calendar is from the Gregorian one: the Buddhist era.
    static let buddhistOffset = 543

    /// What a day's year says.
    enum Verdict: Equatable, Sendable {
        /// A year that can be.
        case possible
        /// A year that can't be, and the day it means.
        case means(CalendarDay)
        /// A year that can't be, and no safe way to the day it means.
        case unknown
    }

    /// A year more than 200 years ahead or before 1800 can't be. It means the day 543 years
    /// before when that lands between 1900 and a hundred years ahead.
    static func verdict(_ day: CalendarDay, thisYear: Int) -> Verdict {
        guard day.year > thisYear + 200 || day.year < 1800 else { return .possible }
        let year = day.year - buddhistOffset
        guard (1900...(thisYear + 100)).contains(year), let meant = CalendarDay(validYear: year, month: day.month, day: day.day) else { return .unknown }
        return .means(meant)
    }

    static func candidates(in context: ModelContext, calendar: Calendar, now: Date = Date()) throws -> [Candidate] {
        let thisYear = CalendarDay(now, calendar: calendar).year
        var found: [Candidate] = []
        func check(_ day: CalendarDay?, _ place: Place, _ name: String, _ section: String?, write: @escaping (CalendarDay) -> Void) {
            guard let day else { return }
            let fixed: CalendarDay?
            switch verdict(day, thisYear: thisYear) {
            case .possible: return
            case .means(let meant): fixed = meant
            case .unknown: fixed = nil
            }
            found.append(Candidate(place: place, day: day, fixed: fixed, name: name, section: section, write: write))
        }
        let templates = try TemplateStore.templatesByKey(in: context)
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            let definition = templates[asset.templateKey]?.definition
            for (key, value) in asset.values.storage.sorted(by: { $0.key < $1.key }) {
                check(value.dateValue, .field(assetID: asset.id, key: key), definition?.field(key)?.label ?? key, asset.name) { day in
                    var values = asset.values
                    values[key] = .date(day)
                    asset.values = values
                }
            }
        }
        for deadline in try context.fetch(FetchDescriptor<Obligation>()) {
            check(deadline.dueDay, .due(obligationID: deadline.id), deadline.title, deadline.asset?.name) { deadline.dueDay = $0 }
            check(deadline.snoozedUntil, .snooze(obligationID: deadline.id), deadline.title, deadline.asset?.name) { deadline.snoozedUntil = $0 }
        }
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>()) where entry.isCompletion {
            check(entry.cycleDueDay, .cycle(entryID: entry.id), entry.title, entry.asset?.name) { entry.cycleDueDay = $0 }
            check(entry.nextDueDay, .next(entryID: entry.id), entry.title, entry.asset?.name) { entry.nextDueDay = $0 }
        }
        for document in try context.fetch(FetchDescriptor<Attachment>()) {
            check(document.documentDay, .documentDay(attachmentID: document.id), document.title ?? document.fileName, document.asset?.name) { document.documentDay = $0 }
            check(document.validUntil, .validUntil(attachmentID: document.id), document.title ?? document.fileName, document.asset?.name) { document.validUntil = $0 }
        }
        return found
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context, calendar: scan.calendar).map { candidate in
            let shown = DosarFormat.longDay(candidate.day)
            // The names are shown in the list: never with a card number they may hold.
            let name = PaymentCardNumbers.redact(candidate.name)
            let place = candidate.section.map { PaymentCardNumbers.redact($0) }.map { section in
                String(localized: "La \(section), „\(name)”", comment: "Repair: where a day is kept, a field, deadline or document under a section.")
            } ?? String(localized: "„\(name)”", comment: "Repair: where a day is kept, with no section.")
            let message: String
            if let fixed = candidate.fixed {
                message = String(localized: "\(place) e pe \(shown), un an care nu poate fi. Pare scris în calendarul budist, cu 543 de ani înainte. Îl corectez la \(DosarFormat.longDay(fixed))?",
                                 comment: "Repair: a day kept with the Buddhist calendar's year, offered back in the Gregorian year.")
            } else {
                message = String(localized: "\(place) e pe \(shown), un an care nu poate fi. Verifică data pe act și scrie-o din nou.",
                                 comment: "Repair: a day kept with a year that can't be, which the app can't work back safely.")
            }
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.place.key):\(candidate.day.isoString)",
                step: Self.id,
                message: message,
                subject: .dayYear(candidate.place, from: candidate.day, to: candidate.fixed),
                isFixable: candidate.fixed != nil
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        var approved: [Place: (CalendarDay, CalendarDay)] = [:]
        for finding in findings {
            guard case .dayYear(let place, let from, let to?) = finding.subject else { continue }
            approved[place] = (from, to)
        }
        guard !approved.isEmpty else { return }
        // Checked again: a day changed since it was found stays as it is now.
        for candidate in try Self.candidates(in: context, calendar: calendar) {
            guard let (from, to) = approved[candidate.place], from == candidate.day, candidate.fixed == to else { continue }
            candidate.write(to)
        }
    }
}
