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
    /// problems at once, including fields they never touched. Forms set it through
    /// `dsRevealsValidation(_:)`, which also takes the person to the first problem.
    @Entry var dsRevealsValidation: Bool = false
    /// The fields of the form around, which say here whether they hold a problem and where they are.
    @Entry var dsValidationTargets: DSValidationTargets? = nil
    /// The field VoiceOver is sent to after a refused save.
    @Entry var dsValidationFocus: DSValidationFocus? = nil
}

// MARK: - A refused save

/// A form's request to show every field's problem: its save refused for a missing or wrong
/// value. Each refusal is another attempt, so the form scrolls to its first problem and
/// VoiceOver lands on it every time, not only the first. `reset()` hides the problems again
/// (a form started over).
struct DSValidationReveal: Equatable {
    private(set) var attempt = 0

    var isOn: Bool { attempt > 0 }

    /// A save was refused: show every problem and go to the first.
    mutating func reveal() { attempt += 1 }

    mutating func reset() { attempt = 0 }
}

/// Where VoiceOver goes after a refused save: the field, and the attempt that sent it there.
struct DSValidationFocus: Equatable {
    let field: UUID
    let attempt: Int
}

/// The fields of one form with a problem, and how high each sits on the screen, so a refused
/// save goes to the one nearest the top. Fields keep it up to date themselves
/// (`dsValidationTarget`); only the form's `dsRevealsValidation` reads it.
@MainActor
final class DSValidationTargets {
    private var messages: [UUID: String] = [:]
    private var tops: [UUID: CGFloat] = [:]

    func set(_ id: UUID, message: String?) { messages[id] = message }
    func place(_ id: UUID, top: CGFloat) { tops[id] = top }
    func remove(_ id: UUID) {
        messages[id] = nil
        tops[id] = nil
    }

    /// The problem highest on the screen.
    var first: (id: UUID, message: String)? {
        messages.min { (tops[$0.key] ?? .greatestFiniteMagnitude) < (tops[$1.key] ?? .greatestFiniteMagnitude) }
            .map { (id: $0.key, message: $0.value) }
    }
}

extension View {
    /// The one way a form shows its problems after a refused save: every field shows its own,
    /// the form scrolls to the first (the one highest on the screen), VoiceOver moves to it and
    /// says what is wrong. Put it where the form's `ScrollView` is, or around it; fields take
    /// part by themselves (`DSFieldContainer`), anything else that says a problem through
    /// `dsValidationTarget(_:)`.
    func dsRevealsValidation(_ reveal: DSValidationReveal) -> some View {
        modifier(DSValidationRevealModifier(reveal: reveal))
    }

    /// Takes part in a refused save's reveal: while `message` is set, this view is a problem the
    /// form can scroll to and send VoiceOver to, with these words. The DS fields do this
    /// themselves; a form's own line ("Alege al cui e actul.") uses it.
    func dsValidationTarget(_ message: LocalizedStringResource?) -> some View {
        modifier(DSValidationTargetModifier(message: message.map { String(localized: $0) }))
    }
}

private struct DSValidationRevealModifier: ViewModifier {
    let reveal: DSValidationReveal

    @State private var targets = DSValidationTargets()
    @State private var focus: DSValidationFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.dsRevealsValidation, reveal.isOn)
                .environment(\.dsValidationTargets, targets)
                .environment(\.dsValidationFocus, focus)
                // After the fields have shown their problems for this attempt (they do so as the
                // reveal reaches them, in the same update), go to the first.
                .task(id: reveal.attempt) {
                    guard reveal.isOn else { return }
                    await Task.yield()
                    goToFirst(proxy)
                }
        }
    }

    private func goToFirst(_ proxy: ScrollViewProxy) {
        guard let first = targets.first else { return }
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
            proxy.scrollTo(first.id, anchor: .center)
        }
        focus = DSValidationFocus(field: first.id, attempt: reveal.attempt)
        AccessibilityNotification.Announcement(first.message).post()
    }
}

private struct DSValidationTargetModifier: ViewModifier {
    let message: String?

    @State private var id = UUID()
    @Environment(\.dsValidationTargets) private var targets
    @Environment(\.dsValidationFocus) private var focus
    @AccessibilityFocusState private var isVoiceOverFocused: Bool

    func body(content: Content) -> some View {
        content
            .id(id)
            .accessibilityFocused($isVoiceOverFocused)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                targets?.place(id, top: top)
            }
            .onChange(of: message, initial: true) { _, message in
                targets?.set(id, message: message)
            }
            .onChange(of: focus) { _, focus in
                if focus?.field == id { isVoiceOverFocused = true }
            }
            .onDisappear { targets?.remove(id) }
    }
}

extension DSValidation {
    /// The message every required field shows when left empty.
    static let requiredMissing = DSValidation.invalid(
        LocalizedStringResource("Completează acest câmp.", comment: "Validation message under a required field that was left empty.")
    )

    /// What a field says when its text holds a card number: saving keeps only the last four
    /// digits (`FreeText`), so the person knows before they see "•••• 1111". It never blocks saving.
    /// Nothing for a value its field's type keeps whole (`PaymentCardNumbers.keepsWhole`: a
    /// microchip that passes its check), which the save keeps as typed.
    static func keepingCardNumberOut(of text: String, as type: FieldType? = nil) -> DSValidation? {
        guard PaymentCardNumbers.containsCardNumber(text), !PaymentCardNumbers.keepsWhole(text, as: type) else { return nil }
        return .warning(LocalizedStringResource("Din numărul cardului păstrez doar ultimele patru cifre.",
                                                comment: "Note under a field whose text holds a whole bank card number: only its last four digits are kept on save."))
    }

    /// This validation, or the card number note when this one has nothing to say.
    func notingCardNumber(in text: String, as type: FieldType? = nil) -> DSValidation {
        guard case .valid = self else { return self }
        return Self.keepingCardNumberOut(of: text, as: type) ?? self
    }
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
                // A problem that blocks saving: a refused save scrolls here and VoiceOver lands here.
                .dsValidationTarget(validation.isInvalid ? validation.message : nil)

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
