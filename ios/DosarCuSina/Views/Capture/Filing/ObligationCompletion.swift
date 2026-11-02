import Foundation
import SwiftData

/// "Am rezolvat" with what the person has in hand: the date, what it cost, and
/// optionally a photo of the new document (the new policy, the ITP report).
/// The new document's date sets the next deadline and the document is filed
/// with the obligation, all through the engine's actions.
@MainActor
struct ObligationCompletion {
    let context: ModelContext
    var store: CaptureDocumentStore = .shared()
    var calendar: Calendar = .current
    var now: () -> Date = { Date() }

    struct Outcome {
        /// The completion written, for undo. Nil when the new date was written on
        /// the asset instead (a renewed document keeps its one obligation).
        var entry: HistoryEntry?
        var attachment: Attachment?
        /// The deadline it moved to, if it repeats.
        var nextDue: CalendarDay?
    }

    /// The next deadline printed on a captured document (expiry, due date, next dose).
    static func nextDay(in result: CaptureResult) -> CalendarDay? {
        let keys: [CaptureFieldKey] = [.expiryDate, .nextDoseDate, .warrantyUntil, .dueDate]
        return keys.lazy.compactMap { result.field($0)?.value.day }.first.map(CaptureMapping.calendarDay)
    }

    /// Completing and filing the new document is one unit of work: both are kept, or neither.
    func complete(_ obligation: Obligation, on date: Date, cost: Money?, document: CaptureResult?, title: String?) async throws -> Outcome {
        try await UnitOfWork.perform(in: context) {
            try await completeAndFile(obligation, on: date, cost: cost, document: document, title: title)
        }
    }

    private func completeAndFile(_ obligation: Obligation, on date: Date, cost: Money?, document: CaptureResult?, title: String?) async throws -> Outcome {
        let actions = ObligationActions(context: context, calendar: calendar, now: now)
        let today = CalendarDay(now(), calendar: calendar)
        let newDay = document.flatMap(Self.nextDay(in:)).flatMap { $0 > today ? $0 : nil }
        var outcome = Outcome()

        if let newDay, let asset = obligation.asset, let fieldKey = fieldDrivingDueDate(of: obligation) {
            // A renewed document: its new expiry moves the same obligation.
            var values = asset.values
            values[fieldKey] = .date(newDay)
            try AssetActions(context: context, calendar: calendar, now: now).update(asset, name: asset.name, values: values, notes: asset.notes)
            outcome.nextDue = obligation.dueDay(in: calendar)
        } else {
            outcome.entry = try actions.complete(obligation, on: date, cost: cost)
            if obligation.status == .active {
                if let newDay, obligation.dueDay(in: calendar) != newDay {
                    try actions.reschedule(obligation, to: newDay)
                }
                outcome.nextDue = obligation.dueDay(in: calendar)
            }
        }

        // New pages are filed; a photo already in the binder is moved here (`fileCaptured` does both).
        if let document, let id = document.documentID {
            let kind = DocumentKind(capturedKind: document.kind)
            let documentDay = [CaptureFieldKey.issueDate, .startDate].lazy.compactMap { document.field($0)?.value.day }.first.map(CaptureMapping.calendarDay)
            outcome.attachment = try await AttachmentActions(context: context, calendar: calendar).fileCaptured(
                documentID: id,
                from: store,
                title: title,
                kind: kind,
                extractedText: document.recognizedText.isEmpty ? nil : document.recognizedText,
                documentDate: documentDay ?? CalendarDay(date, calendar: calendar),
                asset: obligation.asset,
                obligation: obligation,
                historyEntry: outcome.entry
            )
        }
        return outcome
    }

    /// The asset field a one-off obligation takes its date from (a document's expiry).
    private func fieldDrivingDueDate(of obligation: Obligation) -> String? {
        guard let key = obligation.blueprintKey, let asset = obligation.asset,
              let template = try? TemplateStore(context: context).template(forKey: asset.templateKey),
              let blueprint = template.blueprints.first(where: { $0.key == key }),
              !blueprint.recurrence.repeats,
              case .field(let field, _) = blueprint.firstDue else { return nil }
        return field
    }
}
