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
    /// The button's work for something outside the database (an item leaving the inbox).
    /// A saved change is taken back with `receipt` instead.
    var action: (@MainActor () -> Void)?
    /// What "Anulează" takes back: the receipt of the action just taken.
    var receipt: UndoReceipt?
    /// Runs after the receipt took the step back, for a screen that shows what changed.
    var afterUndo: (@MainActor () -> Void)?
    /// How long the toast stays. VoiceOver users get twice as long.
    var duration: Duration = .seconds(5)
    /// Haptic played when the toast appears, matching what just happened.
    var feedback: SensoryFeedback? = .success

    /// A toast confirming a saved change the person can take back, e.g. "ITP: gata". The
    /// button appears only when the receipt has something to undo.
    static func undo(_ title: LocalizedStringResource, receipt: UndoReceipt, afterUndo: (@MainActor () -> Void)? = nil) -> DSToast {
        DSToast(title: title, receipt: receipt, afterUndo: afterUndo)
    }

    /// A failed save or undo, said in plain words with what to do next.
    static func failure(_ error: any Error) -> DSToast {
        DSToast(
            title: "\(SaveFailure.message(for: error, formKept: false))",
            systemImage: "exclamationmark.circle.fill",
            tint: DSStatus.overdue.color,
            actionTitle: nil,
            feedback: .error
        )
    }

    /// Whether the toast shows its button.
    var offersAction: Bool {
        actionTitle != nil && (action != nil || receipt?.canUndo == true)
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
                            run(toast)
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

    /// The button: the receipt takes the step back (a failure says why, in its place), or
    /// the toast's own action runs.
    private func run(_ shown: DSToast) {
        actionCount += 1
        guard let receipt = shown.receipt else {
            shown.action?()
            dismiss()
            return
        }
        do {
            try receipt.undo()
            shown.afterUndo?()
            dismiss()
        } catch {
            toast = .failure(error)
        }
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

            if let actionTitle = toast.actionTitle, toast.offersAction {
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
