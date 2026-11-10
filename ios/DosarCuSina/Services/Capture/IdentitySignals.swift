import Foundation

/// Whether a page may be an identity or other personal document (a cazier, a health card,
/// a bank card, a green card, an electronic signature), whatever kind the reading settled on.
/// A weak reading is often a glared ID card the classifier didn't recognise, so
/// sending a page to the AI provider without asking needs the phone to be sure it is
/// NOT one (`AIProviderSettings.automaticReading`).
enum IdentitySignals {
    static func mayBeIdentity(_ result: CaptureResult) -> Bool {
        if result.kind.isPersonalDocument || result.kindAlternatives.contains(where: { $0.value.isPersonalDocument }) { return true }
        let text = result.source?.text ?? result.recognizedText
        // A whole card number on the page, by the one rule (`CaptureResult.showsCardNumber`).
        return hasMachineReadableZone(text) || hasPersonalNumber(text) || hasIdentityWords(text) || result.showsCardNumber
    }

    /// Fillers of a machine-readable zone: a run of `<`, or a long line of zone characters with `<<` in it.
    static func hasMachineReadableZone(_ text: String) -> Bool {
        if text.contains("<<<") { return true }
        return text.split(whereSeparator: \.isNewline).contains { line in
            let compact = line.replacingOccurrences(of: " ", with: "")
            return compact.count >= 25 && compact.contains("<<")
                && compact.allSatisfy { $0 == "<" || ($0.isASCII && ($0.isUppercase || $0.isNumber)) }
        }
    }

    /// A number shaped like a personal number (CNP): 13 digits, starting 1 to 9.
    static func hasPersonalNumber(_ text: String) -> Bool {
        text.range(of: #"(?<!\d)[1-9]\d{12}(?!\d)"#, options: .regularExpression) != nil
    }

    static func hasIdentityWords(_ text: String) -> Bool {
        let folded = RomanianText.fold(text)
        return CaptureLexicon.identityWords.contains { folded.contains($0) }
    }
}
