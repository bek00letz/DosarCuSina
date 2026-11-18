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
    /// A small next step offered beside the button ("Adaugă o notă" after a chore's "Gata").
    /// Using it closes the toast.
    var offer: Offer?

    /// A next step a toast offers: its title and what it does, handed the toast it was shown
    /// on (to show again when the step is left without saving).
    struct Offer {
        let title: Text
        let action: @MainActor (DSToast) -> Void
    }

    /// How long a toast for something deleted stays: longer than other steps, since it
    /// brings back more and the screen it came from has usually closed.
    static let deletionDuration: Duration = .seconds(8)
    /// How long a toast that offers a next step stays: long enough to read it and choose.
    static let offerDuration: Duration = .seconds(8)

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
                        } onOffer: {
                            take(toast)
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

    /// The offered next step: the toast closes and the step runs.
    private func take(_ shown: DSToast) {
        guard let offer = shown.offer else { return }
        actionCount += 1
        usedID = shown.id
        dismiss()
        offer.action(shown)
    }
}

private struct DSToastView: View {
    let toast: DSToast
    let onAction: () -> Void
    let onOffer: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let offer = toast.offer {
                // Two buttons: the words on their own line, the buttons under them at the
                // trailing edge, stacked when they don't fit side by side.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Space.s) {
                        icon
                        title
                    }
                    .padding(.top, DS.Space.xs)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        DSAdaptiveStack(horizontalAlignment: .trailing, spacing: DS.Space.xxs, stackedSpacing: 0) {
                            button(offer.title, action: onOffer)
                            if let actionTitle = toast.actionTitle, toast.offersAction {
                                button(actionTitle, action: onAction)
                            }
                        }
                    }
                }
            } else {
                // The words wrap beside „Anulează” while they keep at least as much of the width
                // as the button; at a large text size the button moves under them, at the trailing
                // edge, so the words are never squeezed into a narrow column (`WordsBesideAction`).
                WordsBesideAction(spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.s) {
                        icon
                        title
                    }
                    if let actionTitle = toast.actionTitle, toast.offersAction {
                        button(actionTitle, action: onAction)
                    }
                }
            }
        }
        .padding(.leading, DS.Space.m)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .frame(minHeight: DS.Control.floatingBar)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.floatingBar, style: .continuous))
        .offset(y: max(dragOffset, 0))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 30 {
                        onDismiss()
                    } else {
                        // Back into place with the quick spring, or a short fade with Reduce Motion.
                        withAnimation(DS.Motion.animation(DS.Motion.quick, reduceMotion: reduceMotion)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Închide")) { onDismiss() }
    }

    private var icon: some View {
        Image(systemName: toast.systemImage)
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(toast.tint)
            .accessibilityHidden(true)
    }

    /// The whole message at every text size: it wraps and the toast grows taller, so the next
    /// due day it names is never cut off.
    private var title: some View {
        Text(toast.title)
            .dsFont(.subheadline)
            .foregroundStyle(DS.Palette.label)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, DS.Space.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func button(_ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, DS.Space.xs)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

/// The toast's words and its one button: side by side, the words wrapping beside the button,
/// while the button takes no more of the width than the words keep; otherwise one under the
/// other, the words across the whole width and the button at the trailing edge. It decides by
/// measuring, never by the text size, so a short button stays beside the words at any size and
/// a button grown wide at the largest sizes moves down.
struct WordsBesideAction: Layout {
    var spacing: CGFloat

    /// Whether the button (the last piece) leaves the words at least as much of `width` as it takes.
    func fitsBeside(in width: CGFloat?, subviews: Subviews) -> Bool {
        guard subviews.count == 2, let width, width.isFinite else { return true }
        let button = subviews[1].sizeThatFits(.unspecified).width
        return button <= (width - spacing) / 2
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let words = subviews.first else { return .zero }
        guard subviews.count == 2 else { return words.sizeThatFits(proposal) }
        let button = subviews[1].sizeThatFits(.unspecified)
        if fitsBeside(in: proposal.width, subviews: subviews) {
            let wordsWidth = proposal.width.map { max($0 - button.width - spacing, 0) }
            let wordsSize = words.sizeThatFits(ProposedViewSize(width: wordsWidth, height: nil))
            return CGSize(width: proposal.width ?? wordsSize.width + spacing + button.width, height: max(wordsSize.height, button.height))
        }
        let wordsSize = words.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let buttonSize = subviews[1].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? max(wordsSize.width, buttonSize.width), height: wordsSize.height + buttonSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let words = subviews.first else { return }
        guard subviews.count == 2 else {
            words.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
            return
        }
        let button = subviews[1]
        if fitsBeside(in: bounds.width, subviews: subviews) {
            let buttonSize = button.sizeThatFits(.unspecified)
            let wordsWidth = max(bounds.width - buttonSize.width - spacing, 0)
            let wordsSize = words.sizeThatFits(ProposedViewSize(width: wordsWidth, height: nil))
            words.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: wordsWidth, height: wordsSize.height))
            button.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(buttonSize))
            return
        }
        let wordsSize = words.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        words.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: wordsSize.height))
        let buttonSize = button.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        button.place(at: CGPoint(x: bounds.maxX, y: bounds.minY + wordsSize.height), anchor: .topTrailing,
                     proposal: ProposedViewSize(width: min(buttonSize.width, bounds.width), height: buttonSize.height))
    }
}
