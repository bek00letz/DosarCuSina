import SwiftUI

/// The outcome of checking a field's value. Messages say what's wrong and how to fix it,
/// e.g. "Seria de șasiu are 17 caractere. Ai scris 15."
enum DSValidation: Sendable {
    case valid
    /// Blocks saving. Shown in the status text color with an error haptic.
    case invalid(LocalizedStringResource)
    /// Worth knowing but doesn't block saving, e.g. "Pașaportul expiră în mai puțin de 6 luni."
    case warning(LocalizedStringResource)

    var message: LocalizedStringResource? {
        switch self {
        case .valid: nil
        case .invalid(let message), .warning(let message): message
        }
    }

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }

    var isWarning: Bool {
        if case .warning = self { return true }
        return false
    }
}

extension EnvironmentValues {
    /// Set to `true` on a form after the person taps Save, so every field shows its
    /// problems at once, including fields they never touched.
    @Entry var dsRevealsValidation: Bool = false
}

extension DSValidation {
    /// The message every required field shows when left empty.
    static let requiredMissing = DSValidation.invalid(
        LocalizedStringResource("Completează acest câmp.", comment: "Validation message under a required field that was left empty.")
    )
}

/// Decides when a field's problem becomes visible: not while the person is still typing
/// for the first time, only after they leave the field (or after a save attempt).
struct DSValidationVisibility {
    var hasLeftField = false

    func shown(_ validation: DSValidation, reveal: Bool) -> DSValidation {
        (hasLeftField || reveal) ? validation : .valid
    }
}

// MARK: - Container

/// The shared frame of every field: caption above, a filled input area with a focus ring,
/// and a line below for the validation message or a footnote.
///
/// Field controls use this; screens use the controls, not the container.
struct DSFieldContainer<Input: View>: View {
    let title: Text
    var isFocused: Bool
    var validation: DSValidation
    var footnote: Text?
    /// Called when the person taps the caption or the padding around the input.
    var focus: (() -> Void)?
    @ViewBuilder var input: Input

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .dsFont(.captionEmphasized)
                .accessibilityHidden(true)

            input
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 10)
                .frame(minHeight: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.fill, in: shape)
                .overlay {
                    shape.strokeBorder(ringColor, lineWidth: ringWidth)
                        .accessibilityHidden(true)
                }
                .contentShape(shape)

            messageLine
        }
        .contentShape(.rect)
        // Only text inputs take focus from a tap on the frame; fields built from
        // buttons, menus and pickers keep their own taps untouched.
        .simultaneousGesture(TapGesture().onEnded { focus?() }, isEnabled: focus != nil)
        .animation(DS.Motion.animation(DS.Motion.quick, reduceMotion: reduceMotion), value: isFocused)
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: validation.message.map { String(localized: $0) })
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
    }

    private var ringColor: Color {
        if validation.isInvalid { return DSStatus.overdue.color }
        if isFocused { return DS.Palette.accent }
        return contrast == .increased ? DS.Palette.separator : .clear
    }

    private var ringWidth: CGFloat {
        validation.isInvalid || isFocused ? 1.5 : 1
    }

    @ViewBuilder
    private var messageLine: some View {
        if let message = validation.message {
            Label {
                Text(message)
            } icon: {
                Image(systemName: validation.isInvalid ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
            }
            .labelStyle(DSInlineMessageLabelStyle())
            .font(.footnote)
            .foregroundStyle(validation.isInvalid ? DSStatus.overdue.textColor : DSStatus.soon.textColor)
            .transition(.opacity)
        } else if let footnote {
            footnote.dsFont(.footnote)
        }
    }
}

private struct DSInlineMessageLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xxs) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

extension View {
    /// Error haptic the moment a field's problem first becomes visible.
    func dsValidationFeedback(_ validation: DSValidation) -> some View {
        sensoryFeedback(.error, trigger: validation.isInvalid) { old, new in new && !old }
    }
}
