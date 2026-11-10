import Foundation

// Switched off, kept as a way back (AGENTS.md, "Keep a way back"). Nothing here is
// compiled: ios/Legacy sits outside the app's synchronized group.
//
// The readings of a policy's and an invoice's number before values printed in parts had
// one rule (`CompositeValue`, read with `LabelledLayout.composite`). They were switched
// off in RomanianFieldExtractor and moved here so no list of labels lives in reading code
// (`labels-outside-their-table`). To switch one back: move the function into
// `RomanianFieldExtractor` (ios/DosarCuSina/Services/Capture/RomanianFieldExtractor.swift),
// its label list into `CaptureLexicon`, and call it where `policyNumber(in:)` or
// `invoiceNumber(in:)` is called. Remove this file once the composite readers have read
// real policies and invoices well and the owner agrees.
extension RomanianFieldExtractor {

    /// The reading before values printed in parts had one rule, kept switched off until
    /// that rule is proven on real documents (`invoiceNumber(in:)` replaces it).
    static func legacyInvoiceNumber(in text: CaptureText) -> (value: String, source: String)? {
        let patterns = [
            #"(?:factura|factura fiscala|invoice)[^\n]*?seri[ae]\s*[:.]?\s*([a-z]{1,6})\s*(?:nr\.?|numar|no\.?)\s*[:.]?\s*([a-z0-9-]{2,20})"#,
            #"seri[ae]\s*[:.]?\s*([a-z]{1,6})\s*(?:nr\.?|numar)\s*[:.]?\s*(\d{2,12})"#,
            #"(?:factura|factura fiscala|invoice)\s*(?:nr\.?|numar|no\.?)\s*[:.]?\s*()([a-z0-9][a-z0-9 /-]{2,20}[0-9])"#,
            #"nr\.?\s*factura\s*[:.]?\s*()([a-z0-9][a-z0-9/-]{2,20})"#,
        ]
        for (index, line) in text.folded.enumerated() {
            for pattern in patterns {
                if let match = TextPattern.first(pattern, in: line), let number = match[2] {
                    let series = (match[1] ?? "").uppercased()
                    let value = (series.isEmpty ? "" : series + " ") + number.uppercased().trimmingCharacters(in: .whitespaces)
                    return (value, text.original[index])
                }
            }
        }
        return nil
    }

    /// The reading before values printed in parts had one rule, kept switched off until
    /// that rule is proven on real documents (`policyNumber(in:)` replaces it).
    static func legacyPolicyNumber(in text: CaptureText) -> (value: String, source: String)? {
        let labels = legacyPolicyLabels
        for index in text.lines(containing: labels) {
            let original = text.original[index]
            let folded = text.folded[index]
            let labelEnd = labels.compactMap { folded.range(of: $0)?.upperBound }.min() ?? folded.startIndex
            let offset = folded.distance(from: folded.startIndex, to: labelEnd)
            let tail = String(original.dropFirst(min(offset, original.count)))
            if let match = TextPattern.first(#"([A-Z0-9][A-Z0-9/ .-]{3,40}\d)"#, in: tail.uppercased(), caseInsensitive: false),
               let value = match[1] {
                let cleaned = value
                    .replacingOccurrences(of: "NR.", with: "NR")
                    .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":.")))
                return (cleaned, original)
            }
        }
        return nil
    }

    /// The labels the switched-off reading looked for (`CompositeLabels.policy` replaces them).
    static let legacyPolicyLabels = [
        "seria si numarul", "seria si nr", "nr. polita", "nr polita", "numar polita", "numarul politei",
        "polita nr", "polita seria", "polita rca seria", "serie polita",
    ]

}
