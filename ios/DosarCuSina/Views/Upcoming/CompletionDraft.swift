import Foundation

/// What "Am rezolvat"'s sheet holds while the person fills it, and the one rule for what
/// saving it files: only what the deadline's kind asks (`CompletionShape`), so a value the
/// sheet doesn't show is never written, whatever the draft still holds.
struct CompletionDraft {
    var date: Date? = Date()
    var amount: Decimal?
    var currency = Money.defaultCurrency
    var note = ""
    var reading: Double?
    /// The renewed document's new expiry: read off its photo, or typed.
    var newExpiry: Date?
    var document: CaptureResult?
    /// The person asked to keep the photo of a document kept only on request (a bank card).
    var keepsPhotoOnRequest = false
    /// A bill that only looked like one already filed: the person said it is another bill.
    var isAnotherBill = false

    /// Whether the person filled in anything that would be lost by closing the sheet.
    var hasChanges: Bool {
        amount != nil || document != nil || reading != nil || newExpiry != nil
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What saving files, for `obligation`, as its kind asks it. The date is today when the
    /// kind doesn't ask one. `counter` is the counter the sheet asked for, if any
    /// (`ObligationActions.counter`): a reading is kept only on one.
    func completion(of obligation: Obligation, shape: CompletionShape, counter: ObligationActions.Counter?,
                    calendar: Calendar = .dosar, now: Date = Date()) -> CaptureFiler.Completion {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaptureFiler.Completion(
            obligation: obligation,
            date: shape.asksDate ? (date ?? now) : now,
            cost: shape.cost == nil ? nil : amount.map { Money($0, currency: currency) },
            document: shape.paper == nil ? nil : document,
            nextDue: shape.asksNewExpiry ? newExpiry.map { CalendarDay($0, calendar: calendar) } : nil,
            note: shape.asksNote && !trimmed.isEmpty ? trimmed : nil,
            metricReading: shape.asksReading && counter != nil ? reading : nil,
            keepsPhotoOnRequest: keepsPhotoOnRequest,
            isAnotherBill: isAnotherBill
        )
    }
}
