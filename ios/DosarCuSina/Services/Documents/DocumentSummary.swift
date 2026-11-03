import Foundation

/// The one line a personal document shows under its name, where it is listed (a
/// person's documents, Acte): what tells it apart at a glance. A bank card reads
/// "Visa •••• 4821, expiră 08/28", the way the card itself says it; any other document
/// says how long it is valid.
enum DocumentSummary {
    static func line(_ values: FieldValues, today: CalendarDay = CalendarDay(Date())) -> String? {
        let expiry = values[DocumentFields.expiry]?.dateValue
        guard DocumentType.options.option(for: values[DocumentType.typeFieldKey]?.textValue ?? "")?.key == DocumentType.bankCard else {
            return expiry.map { String(localized: "Valabil până la \(DosarFormat.day($0))", comment: "Document row: valid until.") }
        }
        let card = [
            PaymentCardNetwork.label(for: values[DocumentFields.cardNetwork]?.textValue),
            values[DocumentFields.cardLastFour]?.textValue.flatMap(PaymentCardNumbers.lastFour(of:)).map { "\(PaymentCardNumbers.mask) \($0)" },
        ].compactMap { $0 }.joined(separator: " ")
        let until: String? = expiry.map { day in
            let month = DosarFormat.cardExpiry(day)
            return day < today
                ? String(localized: "a expirat \(month)", comment: "Bank card row: it expired, month/year as on the card.")
                : String(localized: "expiră \(month)", comment: "Bank card row: it expires, month/year as on the card.")
        }
        let parts = [card.isEmpty ? nil : card, until].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
