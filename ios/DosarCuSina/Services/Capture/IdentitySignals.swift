import Foundation

/// Whether a page may be an identity document, whatever kind the reading settled on.
/// A weak reading is often a glared ID card the classifier didn't recognise, so
/// sending a page to the AI provider without asking needs the phone to be sure it is
/// NOT one (`AIProviderSettings.automaticReading`).
enum IdentitySignals {
    /// Words printed only on identity documents, folded (`CaptureText.fold`).
    static let identityWords = [
        "carte de identitate", "carte electronica de identitate", "identity card", "carte d'identite",
        "pasaport", "passport", "passeport", "permis de conducere", "driving licence", "permis de conduire",
        "cod numeric personal", "data nasterii", "date of birth", "locul nasterii", "place of birth", "cetatenie",
    ]

    static func mayBeIdentity(_ result: CaptureResult) -> Bool {
        if result.kind.isIdentityDocument || result.kindAlternatives.contains(where: { $0.value.isIdentityDocument }) { return true }
        let text = result.source?.text ?? result.recognizedText
        return hasMachineReadableZone(text) || hasPersonalNumber(text) || hasIdentityWords(text)
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
        let folded = CaptureText.fold(text)
        return identityWords.contains { folded.contains($0) }
    }
}
