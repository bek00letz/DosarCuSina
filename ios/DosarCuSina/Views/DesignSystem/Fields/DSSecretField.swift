import SwiftUI

/// Typing a secret such as a PIN code. A code already kept is never shown here,
/// not even as typed characters: the field says it is kept and offers to
/// change or remove it. A new code is typed with its characters hidden.
///
/// `value` holds the stored (sealed) text, or what the person typed; the
/// engine seals it when saving.
struct DSSecretField: View {
    let title: LocalizedStringKey
    @Binding var value: String
    var footnote: LocalizedStringKey?
    /// A PIN (digits only, number pad) or any code (a Wi-Fi password, an alarm code).
    var isPIN = true

    @FocusState private var isFocused: Bool
    @State private var isReplacing = false
    @State private var visibility = DSValidationVisibility()
    @Environment(\.dsRevealsValidation) private var revealsValidation

    init(_ title: LocalizedStringKey, value: Binding<String>, footnote: LocalizedStringKey? = nil, isPIN: Bool = true) {
        self.title = title
        self._value = value
        self.footnote = footnote
        self.isPIN = isPIN
    }

    /// A code kept from before, which this field must not show.
    private var isKept: Bool { SecretSealer.isSealed(value) && !isReplacing }

    private var validation: DSValidation {
        guard isPIN, !isKept, !value.isEmpty else { return .valid }
        return value.allSatisfy(\.isNumber)
            ? .valid
            : .warning(LocalizedStringResource("Codurile PIN au de obicei doar cifre.", comment: "Secret PIN field hint"))
    }

    private var focusAction: (() -> Void)? {
        if isKept { return nil }
        return { isFocused = true }
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: isFocused,
            validation: visibility.shown(validation, reveal: revealsValidation),
            footnote: footnote.map { Text($0) },
            focus: focusAction
        ) {
            if isKept {
                kept
            } else {
                SecureField(title, text: $value, prompt: Text("Scrie codul", comment: "Placeholder of a secret PIN field."))
                    .font(.body.monospacedDigit())
                    .keyboardType(isPIN ? .numberPad : .default)
                    .textContentType(isPIN ? .oneTimeCode : nil)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .privacySensitive()
                    .accessibilityHint(Text("Codul rămâne ascuns. Îl vezi după Face ID, din pagina actului.", comment: "VoiceOver hint of a secret field."))
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { visibility.hasLeftField = true }
        }
    }

    /// "Păstrat" with "Schimbă" and "Scoate".
    private var kept: some View {
        return DSAdaptiveStack(spacing: DS.Space.s) {
            Label {
                Text("Păstrat, ascuns", comment: "A secret field that already holds a code.")
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(DS.Palette.secondaryLabel)
            }
            .dsFont(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                value = ""
                isReplacing = true
                isFocused = true
            } label: {
                Text("Schimbă", comment: "Replace a kept secret code.")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                value = ""
                isReplacing = true
            } label: {
                Text("Scoate", comment: "Remove a kept secret code.")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
    }
}
