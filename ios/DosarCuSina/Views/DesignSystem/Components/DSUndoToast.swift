import SwiftUI

/// A short-lived confirmation with an optional undo, shown floating above the content.
/// Prefer this over "Are you sure?" dialogs for anything that can be reversed.
struct DSToast: Identifiable {
    let id = UUID()
    /// What just happened, e.g. "ITP marcat ca rezolvat". Interpolate data values directly.
    var title: LocalizedStringResource
    var systemImage: String = "checkmark.circle.fill"
    var tint: Color = DSStatus.done.color
    /// Set to `nil` for a toast without an undo button.
    var actionTitle: Text? = Text("Anulează", comment: "Toast button that reverses the action just taken.")
    var action: (@MainActor () -> Void)?
    /// How long the toast stays. VoiceOver users get twice as long.
    var duration: Duration = .seconds(5)
    /// Haptic played when the toast appears, matching what just happened.
    var feedback: SensoryFeedback? = .success

    /// A toast confirming something that can be undone, e.g. "ITP marcat ca rezolvat".
    static func undo(_ title: LocalizedStringResource, action: @escaping @MainActor () -> Void) -> DSToast {
        DSToast(title: title, action: action)
    }
}

extension View {
    /// Shows `toast` floating at the bottom edge. Setting a new toast replaces the current one;
    /// it dismisses itself after its duration, on swipe down, or when its action runs.
    func dsToast(_ toast: Binding<DSToast?>) -> some View {
        modifier(DSToastModifier(toast: toast))
    }
}

private struct DSToastModifier: ViewModifier {
    @Binding var toast: DSToast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var actionCount = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let toast {
                        DSToastView(toast: toast) {
                            toast.action?()
                            actionCount += 1
                            dismiss()
                        } onDismiss: {
                            dismiss()
                        }
                        .id(toast.id)
                        .transition(DS.Motion.transition(from: .bottom, reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.bottom, DS.Space.xs)
                .animation(DS.Motion.animation(DS.Motion.emphasized, reduceMotion: reduceMotion), value: toast?.id)
            }
            .sensoryFeedback(trigger: toast?.id) { _, newValue in
                newValue == nil ? nil : toast?.feedback
            }
            .sensoryFeedback(.impact(weight: .light), trigger: actionCount)
            .task(id: toast?.id) {
                guard let current = toast else { return }
                AccessibilityNotification.Announcement(String(localized: current.title)).post()
                let duration = voiceOverEnabled ? current.duration * 2 : current.duration
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled, toast?.id == current.id else { return }
                dismiss()
            }
    }

    private func dismiss() {
        toast = nil
    }
}

private struct DSToastView: View {
    let toast: DSToast
    let onAction: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: toast.systemImage)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(toast.tint)
                .accessibilityHidden(true)

            Text(toast.title)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Palette.label)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle = toast.actionTitle, toast.action != nil {
                Button(action: onAction) {
                    actionTitle
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DS.Space.xs)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.leading, DS.Space.m)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .offset(y: max(dragOffset, 0))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 30 {
                        onDismiss()
                    } else {
                        withAnimation(DS.Motion.quick) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Închide")) { onDismiss() }
    }
}
