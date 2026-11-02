import SwiftUI

/// The kinds of text a field can hold. Each kind sets the right keyboard, autofill,
/// capitalization and spell-check, a format example as placeholder, and a VoiceOver hint.
///
/// Kinds only handle input hygiene. What counts as valid, and how a value is normalized
/// (e.g. "b123abc" → "B-123-ABC"), comes from the field system through `validator` and `formatter`.
enum DSTextKind: Sendable, CaseIterable {
    case text
    case longText
    case plate
    case vin
    case microchip
    case iban
    case phone
    case email
    case url
    case address

    var keyboard: UIKeyboardType {
        switch self {
        case .text, .longText, .address: .default
        case .plate, .vin, .iban: .asciiCapable
        case .microchip: .numberPad
        case .phone: .phonePad
        case .email: .emailAddress
        case .url: .URL
        }
    }

    var contentType: UITextContentType? {
        switch self {
        case .phone: .telephoneNumber
        case .email: .emailAddress
        case .url: .URL
        case .address: .fullStreetAddress
        default: nil
        }
    }

    var capitalization: TextInputAutocapitalization {
        switch self {
        case .plate, .vin, .iban: .characters
        case .email, .url, .microchip, .phone: .never
        case .text, .address: .sentences
        case .longText: .sentences
        }
    }

    var disablesAutocorrection: Bool {
        switch self {
        case .text, .longText, .address: false
        default: true
        }
    }

    /// Codes read better in a fixed-width face, where 0/O and 1/I are distinct.
    var usesMonospacedFont: Bool {
        switch self {
        case .vin, .iban, .microchip, .plate: true
        default: false
        }
    }

    var isMultiline: Bool {
        self == .longText || self == .address
    }

    /// A format example, shown when the field is empty. Placeholder data only.
    /// Language-neutral formats are verbatim so they don't land in the String Catalog.
    var defaultPrompt: Text? {
        switch self {
        case .plate: Text(verbatim: "B-123-ABC")
        case .vin: Text("17 litere și cifre", comment: "Placeholder for the vehicle identification number field.")
        case .microchip: Text("15 cifre", comment: "Placeholder for the pet microchip field.")
        case .iban: Text(verbatim: "RO49 AAAA 1B31 0075 9384 0000")
        case .phone: Text(verbatim: "07xx xxx xxx")
        case .email: Text(verbatim: "nume@exemplu.ro")
        case .url: Text(verbatim: "https://")
        case .address: Text("Stradă, număr, localitate", comment: "Placeholder for an address field.")
        case .text, .longText: nil
        }
    }

    var accessibilityHint: LocalizedStringKey? {
        switch self {
        case .plate: "Numărul de înmatriculare, de exemplu B 123 ABC."
        case .vin: "Seria de șasiu din talon, 17 litere și cifre."
        case .microchip: "Cele 15 cifre ale microcipului, din carnetul de sănătate."
        case .iban: "Contul bancar, începe cu RO."
        case .phone: "Un număr de telefon."
        case .email: "O adresă de e-mail."
        case .url: "Un link care începe cu https."
        case .address: "Adresa completă."
        case .text, .longText: nil
        }
    }
}

/// A text input for any `DSTextKind`.
///
/// Validation appears after the person leaves the field (or after a save attempt, through
/// `.environment(\.dsRevealsValidation, true)`), never while they're typing for the first time.
/// `formatter` runs when they leave the field or press Return.
struct DSTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var kind: DSTextKind = .text
    var prompt: LocalizedStringKey?
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?
    var validator: ((String) -> DSValidation)?
    var formatter: ((String) -> String)?

    @FocusState private var isFocused: Bool
    @State private var visibility = DSValidationVisibility()
    @Environment(\.dsRevealsValidation) private var revealsValidation

    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        kind: DSTextKind = .text,
        prompt: LocalizedStringKey? = nil,
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil,
        validator: ((String) -> DSValidation)? = nil,
        formatter: ((String) -> String)? = nil
    ) {
        self.title = title
        self._text = text
        self.kind = kind
        self.prompt = prompt
        self.isRequired = isRequired
        self.footnote = footnote
        self.validator = validator
        self.formatter = formatter
    }

    private var validation: DSValidation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return isRequired ? .requiredMissing : .valid
        }
        return validator?(trimmed) ?? .valid
    }

    private var shownValidation: DSValidation {
        visibility.shown(validation, reveal: revealsValidation)
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: isFocused,
            validation: shownValidation,
            footnote: footnote.map { Text($0) },
            focus: { isFocused = true }
        ) {
            field
                .font(kind.usesMonospacedFont ? .body.monospaced() : .body)
                .keyboardType(kind.keyboard)
                .textContentType(kind.contentType)
                .textInputAutocapitalization(kind.capitalization)
                .autocorrectionDisabled(kind.disablesAutocorrection)
                .focused($isFocused)
                .submitLabel(kind.isMultiline ? .return : .next)
                .onSubmit(commit)
                .accessibilityHint(kind.accessibilityHint.map { Text($0) } ?? Text(verbatim: ""))
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .dsValidationFeedback(shownValidation)
    }

    @ViewBuilder
    private var field: some View {
        let promptText = prompt.map { Text($0) } ?? kind.defaultPrompt
        if kind.isMultiline {
            TextField(title, text: $text, prompt: promptText, axis: .vertical)
                .lineLimit(kind == .address ? 1...4 : 3...10)
        } else {
            TextField(title, text: $text, prompt: promptText)
        }
    }

    private func commit() {
        visibility.hasLeftField = true
        if let formatter {
            let formatted = formatter(text)
            if formatted != text { text = formatted }
        }
    }
}
