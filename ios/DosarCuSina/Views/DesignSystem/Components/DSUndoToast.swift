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
    /// Runs once when the toast leaves without its button used: its time passed, it was
    /// swiped away or replaced, its screen closed, or the app went to the background. For
    /// what waits outside the database until the undo can't come any more (an item leaving
    /// the share inbox).
    var whenGone: (@MainActor () -> Void)?
    /// How long the toast stays. VoiceOver users get twice as long.
    var duration: Duration = .seconds(5)
    /// Haptic played when the toast appears, matching what just happened.
    var feedback: SensoryFeedback? = .success

    /// How long a toast for something deleted stays: longer than other steps, since it
    /// brings back more and the screen it came from has usually closed.
    static let deletionDuration: Duration = .seconds(8)

    /// A toast confirming a saved change the person can take back, e.g. "ITP: gata". The
    /// button appears only when the receipt has something to undo.
    static func undo(_ title: LocalizedStringResource, receipt: UndoReceipt, afterUndo: (@MainActor () -> Void)? = nil) -> DSToast {
        DSToast(title: title, receipt: receipt, afterUndo: afterUndo)
    }

    /// A toast confirming something deleted, with "Anulează" to bring it back whole.
    static func undoDeletion(_ title: LocalizedStringResource, receipt: UndoReceipt) -> DSToast {
        DSToast(title: title, systemImage: "trash.fill", tint: DS.Palette.secondaryLabel, receipt: receipt, duration: deletionDuration)
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
    @MainActor var offersAction: Bool {
        actionTitle != nil && (action != nil || receipt?.canUndo == true)
    }
}

extension View {
    /// Shows `toast` floating at the bottom edge. Setting a new toast replaces the current one;
    /// it dismisses itself after its duration, on swipe down, when its action runs, when its
    /// screen closes, or when the app goes to the background (an undo is for the step just
    /// taken). Of all the toasts in a window, only the newest shows.
    func dsToast(_ toast: Binding<DSToast?>) -> some View {
        modifier(DSToastModifier(toast: toast, bottomInset: 0))
    }

    /// Makes this view the host of `center`'s toasts: drawn over it, `bottomInset` above its
    /// bottom edge (the tab bar), and announced from anywhere inside it with `\.announce`.
    func dsToastHost(_ center: DSToastCenter, bottomInset: CGFloat = 0) -> some View {
        modifier(DSToastModifier(toast: Binding(get: { center.toast }, set: { center.toast = $0 }), bottomInset: bottomInset))
            .environment(\.dsToastCenter, center)
    }
}

/// Where a toast that must outlive its screen is shown: the shell's, above the tab bar on
/// whichever screen is open. Deleting a section closes its page, and the review sheet closes
/// on "Salvează", but their "Anulează" stays. Screens reach it with `\.announce`.
@MainActor
@Observable
final class DSToastCenter {
    /// The toast shown by the host.
    var toast: DSToast?
    /// The toast shown last by any host in this window: an older one makes way for it.
    fileprivate(set) var newest: UUID?

    init() {}
}

/// Shows a toast on the shell's host (`DSToastCenter`), so it stays when the screen that
/// announced it closes: `announce(.undoDeletion("Am șters „VW Golf 2018”.", receipt: receipt))`.
struct DSAnnounceAction {
    fileprivate let center: DSToastCenter?

    @MainActor func callAsFunction(_ toast: DSToast) {
        center?.toast = toast
    }
}

extension EnvironmentValues {
    @Entry var dsToastCenter: DSToastCenter? = nil

    /// Shows a toast that outlives the screen it came from, on the shell's host.
    var announce: DSAnnounceAction { DSAnnounceAction(center: dsToastCenter) }
}

private struct DSToastModifier: ViewModifier {
    @Binding var toast: DSToast?
    let bottomInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dsToastCenter) private var center
    @State private var actionCount = 0
    /// The toast on screen, so it can be told when it leaves.
    @State private var shown: DSToast?
    /// The toast whose button was used: it isn't told it left unused.
    @State private var usedID: UUID?

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
                .padding(.bottom, DS.Space.xs + bottomInset)
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
            .onChange(of: toast?.id, initial: true) { _, _ in follow() }
            // Only the newest toast in the window shows.
            .onChange(of: center?.newest) { _, newest in
                if let newest, let toast, toast.id != newest { dismiss() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { dismiss() }
            }
            .onDisappear {
                letGo()
                toast = nil
            }
    }

    private func dismiss() {
        toast = nil
    }

    /// Keeps up with the toast on screen: the one before is told it's gone, unless it was used.
    private func follow() {
        if shown?.id != toast?.id { letGo() }
        shown = toast
        if let toast { center?.newest = toast.id }
    }

    private func letGo() {
        if let shown, shown.id != usedID { shown.whenGone?() }
        shown = nil
    }

    /// The button: the receipt takes the step back (a failure says why, in its place), or
    /// the toast's own action runs.
    private func run(_ shown: DSToast) {
        actionCount += 1
        guard let receipt = shown.receipt else {
            usedID = shown.id
            shown.action?()
            dismiss()
            return
        }
        do {
            try receipt.undo()
            usedID = shown.id
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
