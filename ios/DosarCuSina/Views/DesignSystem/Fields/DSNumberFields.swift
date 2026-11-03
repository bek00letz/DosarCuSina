import SwiftUI

/// What a number field shows for its value and how it reads what the person types: both
/// through `RomanianNumber`, so a value shown and read back never changes.
enum DSNumberText {
    /// The field's validation for what was typed: the reader's message when it refuses.
    static func validation(_ text: String, as kind: NumberKind, unit: MeasurementUnit? = nil, isRequired: Bool) -> (DSValidation, Decimal?) {
        switch RomanianNumber.read(text, as: kind, unit: unit) {
        case .success(let reading):
            return (.valid, reading.value)
        case .failure(.empty):
            return (isRequired ? .requiredMissing : .valid, nil)
        case .failure(let problem):
            return (.invalid(LocalizedStringResource(stringLiteral: problem.message(for: kind))), nil)
        }
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
        let (validation, value) = DSNumberText.validation(text, as: .money, isRequired: isRequired)
        guard let value else { return validation }
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
            // Only what the person types becomes the amount. Showing a stored amount
            // changes the text too, and reading that back could change the amount.
            guard isFocused else { return }
            amount = RomanianNumber.value(newText, as: .money)
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
        let display = RomanianNumber.format(amount)
        if display != text { text = display }
    }
}

// MARK: - Metric

/// A reading with a unit: odometer km, engine hours, cups brewed, kg.
struct DSMetricField: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    /// The unit shown after the number ("km", "h", "kg"), from the template; nil for none.
    let unit: MeasurementUnit?
    var fractionDigits: ClosedRange<Int> = 0...1
    /// False for numbers read as labels rather than amounts, such as a year.
    var groupsDigits: Bool = true
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?
    /// Shown greyed in the empty field, never as its value: an estimate the person can type over.
    var placeholder: Double?
    var validator: ((Double) -> DSValidation)?

    @State private var text = ""
    @State private var visibility = DSValidationVisibility()
    @FocusState private var isFocused: Bool
    @Environment(\.dsRevealsValidation) private var revealsValidation

    init(
        _ title: LocalizedStringKey,
        value: Binding<Double?>,
        unit: MeasurementUnit?,
        fractionDigits: ClosedRange<Int> = 0...1,
        groupsDigits: Bool = true,
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil,
        placeholder: Double? = nil,
        validator: ((Double) -> DSValidation)? = nil
    ) {
        self.title = title
        self._value = value
        self.unit = unit
        self.fractionDigits = fractionDigits
        self.groupsDigits = groupsDigits
        self.isRequired = isRequired
        self.footnote = footnote
        self.placeholder = placeholder
        self.validator = validator
    }

    /// Kilometres by their unit, whole numbers when the field shows no decimals.
    private var kind: NumberKind {
        NumberKind.forField(unit: unit, allowsDecimals: fractionDigits.upperBound > 0)
    }

    private var validation: DSValidation {
        let (validation, parsed) = DSNumberText.validation(text, as: kind, unit: unit, isRequired: isRequired)
        guard let parsed else { return validation }
        return validator?(NSDecimalNumber(decimal: parsed).doubleValue) ?? .valid
    }

    private var prompt: Text {
        guard let placeholder else { return Text(verbatim: "0") }
        return Text(verbatim: RomanianNumber.format(Decimal(placeholder), fractionDigits: 0...fractionDigits.upperBound, groupsDigits: groupsDigits))
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
                TextField(title, text: $text, prompt: prompt)
                    .keyboardType(fractionDigits.upperBound > 0 ? .decimalPad : .numberPad)
                    .font(.body.monospacedDigit())
                    .focused($isFocused)
                    .accessibilityHint(Text(verbatim: unit?.label ?? ""))
                Text(verbatim: unit?.label ?? "")
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .onAppear(perform: syncTextFromValue)
        .onChange(of: value) { _, _ in
            if !isFocused { syncTextFromValue() }
        }
        .onChange(of: text) { _, newText in
            // Only what the person types becomes the value. Showing a stored value
            // changes the text too, and reading that back could turn 45.724 km into 457.
            guard isFocused else { return }
            value = RomanianNumber.value(newText, as: kind, unit: unit).map { NSDecimalNumber(decimal: $0).doubleValue }
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
        let display = RomanianNumber.format(Decimal(value), fractionDigits: 0...fractionDigits.upperBound, groupsDigits: groupsDigits)
        if display != text { text = display }
    }
}
