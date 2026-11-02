import SwiftUI

/// Locale-aware number parsing for typed input: accepts "1.250,50" and "1250,5" in Romanian,
/// "1,250.50" in English. Pure and small so it can be unit tested.
enum DSNumberInput {
    /// Parses what a person typed into a decimal, or `nil` if it isn't a number.
    static func decimal(from text: String, locale: Locale) -> Decimal? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ""
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        if !groupingSeparator.isEmpty, groupingSeparator != decimalSeparator {
            cleaned = cleaned.replacingOccurrences(of: groupingSeparator, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: decimalSeparator, with: ".")
        let allowed = CharacterSet(charactersIn: "0123456789.-")
        guard cleaned.unicodeScalars.allSatisfy(allowed.contains),
              cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// How a parsed amount reads back in the field once the person leaves it.
    static func display(_ value: Decimal, locale: Locale, fractionDigits: ClosedRange<Int> = 0...2, groupsDigits: Bool = true) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(groupsDigits ? .automatic : .never).locale(locale))
    }
}

// MARK: - Money

/// An amount with its currency. The number is typed with the decimal keyboard;
/// the currency is picked from a short list next to it.
struct DSMoneyField: View {
    let title: LocalizedStringKey
    @Binding var amount: Decimal?
    @Binding var currencyCode: String
    var currencies: [String] = ["RON", "EUR", "USD"]
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?
    var validator: ((Decimal) -> DSValidation)?

    @State private var text = ""
    @State private var visibility = DSValidationVisibility()
    @FocusState private var isFocused: Bool
    @Environment(\.locale) private var locale
    @Environment(\.dsRevealsValidation) private var revealsValidation

    init(
        _ title: LocalizedStringKey,
        amount: Binding<Decimal?>,
        currencyCode: Binding<String>,
        currencies: [String] = ["RON", "EUR", "USD"],
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil,
        validator: ((Decimal) -> DSValidation)? = nil
    ) {
        self.title = title
        self._amount = amount
        self._currencyCode = currencyCode
        self.currencies = currencies
        self.isRequired = isRequired
        self.footnote = footnote
        self.validator = validator
    }

    private var validation: DSValidation {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return isRequired ? .requiredMissing : .valid
        }
        guard let value = DSNumberInput.decimal(from: text, locale: locale) else {
            return .invalid(LocalizedStringResource("Scrie suma doar cu cifre, de exemplu 1.250,50.", comment: "Validation message when a money amount isn't a number."))
        }
        if value < 0 {
            return .invalid(LocalizedStringResource("Suma nu poate fi negativă.", comment: "Validation message when a money amount is below zero."))
        }
        return validator?(value) ?? .valid
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
            HStack(spacing: DS.Space.xs) {
                TextField(title, text: $text, prompt: Text(verbatim: "0"))
                    .keyboardType(.decimalPad)
                    .font(.body.monospacedDigit())
                    .focused($isFocused)

                Menu {
                    Picker(selection: $currencyCode) {
                        ForEach(currencies, id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    } label: {
                        Text("Monedă", comment: "Label of the currency picker next to an amount.")
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(verbatim: currencyCode)
                            .font(.body.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityLabel(Text("Monedă", comment: "Label of the currency picker next to an amount."))
                .accessibilityValue(Text(verbatim: currencyCode))
                .sensoryFeedback(.selection, trigger: currencyCode)
            }
        }
        .onAppear(perform: syncTextFromAmount)
        .onChange(of: amount) { _, _ in
            if !isFocused { syncTextFromAmount() }
        }
        .onChange(of: text) { _, newText in
            amount = DSNumberInput.decimal(from: newText, locale: locale)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                visibility.hasLeftField = true
                syncTextFromAmount()
            }
        }
        .dsValidationFeedback(shownValidation)
    }

    private func syncTextFromAmount() {
        // Keep what the person typed if it doesn't parse, so they can fix it.
        guard let amount else { return }
        let display = DSNumberInput.display(amount, locale: locale)
        if display != text { text = display }
    }
}

// MARK: - Metric

/// A reading with a unit: odometer km, engine hours, cups brewed, kg.
struct DSMetricField: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    /// The unit as shown after the number, e.g. "km", "h", "kg". Comes from the template.
    let unit: String
    var fractionDigits: ClosedRange<Int> = 0...1
    /// False for numbers read as labels rather than amounts, such as a year.
    var groupsDigits: Bool = true
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?
    var validator: ((Double) -> DSValidation)?

    @State private var text = ""
    @State private var visibility = DSValidationVisibility()
    @FocusState private var isFocused: Bool
    @Environment(\.locale) private var locale
    @Environment(\.dsRevealsValidation) private var revealsValidation

    init(
        _ title: LocalizedStringKey,
        value: Binding<Double?>,
        unit: String,
        fractionDigits: ClosedRange<Int> = 0...1,
        groupsDigits: Bool = true,
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil,
        validator: ((Double) -> DSValidation)? = nil
    ) {
        self.title = title
        self._value = value
        self.unit = unit
        self.fractionDigits = fractionDigits
        self.groupsDigits = groupsDigits
        self.isRequired = isRequired
        self.footnote = footnote
        self.validator = validator
    }

    private var validation: DSValidation {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return isRequired ? .requiredMissing : .valid
        }
        guard let parsed = DSNumberInput.decimal(from: text, locale: locale) else {
            return .invalid(LocalizedStringResource("Scrie doar cifre, de exemplu 84.200.", comment: "Validation message when a reading such as kilometers isn't a number."))
        }
        return validator?(NSDecimalNumber(decimal: parsed).doubleValue) ?? .valid
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
            HStack(spacing: DS.Space.xs) {
                TextField(title, text: $text, prompt: Text(verbatim: "0"))
                    .keyboardType(fractionDigits.upperBound > 0 ? .decimalPad : .numberPad)
                    .font(.body.monospacedDigit())
                    .focused($isFocused)
                    .accessibilityHint(Text(verbatim: unit))
                Text(verbatim: unit)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .onAppear(perform: syncTextFromValue)
        .onChange(of: value) { _, _ in
            if !isFocused { syncTextFromValue() }
        }
        .onChange(of: text) { _, newText in
            value = DSNumberInput.decimal(from: newText, locale: locale).map { NSDecimalNumber(decimal: $0).doubleValue }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                visibility.hasLeftField = true
                syncTextFromValue()
            }
        }
        .dsValidationFeedback(shownValidation)
    }

    private func syncTextFromValue() {
        guard let value else { return }
        let display = DSNumberInput.display(Decimal(value), locale: locale, fractionDigits: 0...fractionDigits.upperBound, groupsDigits: groupsDigits)
        if display != text { text = display }
    }
}
