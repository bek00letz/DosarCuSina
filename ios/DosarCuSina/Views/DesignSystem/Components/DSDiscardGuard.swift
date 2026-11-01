import SwiftUI
import UIKit

extension View {
    /// Protects an editing sheet from losing work.
    ///
    /// While `hasChanges` is true, swiping the sheet down doesn't close it; instead the
    /// person is asked whether to discard their changes, the way Mail and Calendar do.
    /// Put a `DSCancelButton()` in the sheet's toolbar: it asks the same question.
    ///
    /// Apply this to the sheet's root view, inside the sheet.
    func dsDiscardGuard(hasChanges: Bool) -> some View {
        modifier(DSDiscardGuardModifier(hasChanges: hasChanges))
    }
}

/// A Cancel button for editing sheets. Closes right away when nothing changed,
/// otherwise asks before discarding (needs `.dsDiscardGuard(hasChanges:)` on the sheet).
struct DSCancelButton: View {
    @Environment(\.dsAttemptDismiss) private var attemptDismiss
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(role: .cancel) {
            if let attemptDismiss {
                attemptDismiss()
            } else {
                dismiss()
            }
        } label: {
            Text("Anulează", comment: "Button that closes an editing sheet.")
        }
    }
}

// MARK: - Implementation

/// The action a Cancel button calls to close a guarded sheet.
/// Compared by identity so it doesn't invalidate the environment on every update.
struct DSAttemptDismissAction: Equatable {
    fileprivate let id: UUID
    fileprivate let handler: @MainActor () -> Void

    @MainActor func callAsFunction() { handler() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    @Entry var dsAttemptDismiss: DSAttemptDismissAction? = nil
}

private struct DSDiscardGuardModifier: ViewModifier {
    let hasChanges: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false
    @State private var actionID = UUID()

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(hasChanges)
            .background {
                DSDismissAttemptObserver {
                    if hasChanges { isConfirming = true }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .environment(\.dsAttemptDismiss, DSAttemptDismissAction(id: actionID) {
                if hasChanges {
                    isConfirming = true
                } else {
                    dismiss()
                }
            })
            .confirmationDialog(
                Text("Renunți la modificări?", comment: "Title of the dialog shown when closing a sheet with unsaved changes."),
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    dismiss()
                } label: {
                    Text("Renunță la modificări", comment: "Destructive button that closes the sheet and drops unsaved changes.")
                }
                Button(role: .cancel) {} label: {
                    Text("Continuă editarea", comment: "Button that keeps the sheet open.")
                }
            } message: {
                Text("Ce ai completat până acum nu se va salva.", comment: "Explains what discarding unsaved changes means.")
            }
            .sensoryFeedback(.warning, trigger: isConfirming) { _, new in new }
    }
}

/// Listens for a swipe-down on a sheet that can't be dismissed, via UIKit's
/// `presentationControllerDidAttemptToDismiss`, which SwiftUI doesn't expose.
/// It wraps the existing delegate and forwards everything else untouched.
private struct DSDismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: @MainActor () -> Void

    func makeUIViewController(context: Context) -> DSDismissAttemptViewController {
        DSDismissAttemptViewController()
    }

    func updateUIViewController(_ controller: DSDismissAttemptViewController, context: Context) {
        controller.onAttempt = onAttempt
        controller.installIfNeeded()
    }
}

private final class DSDismissAttemptViewController: UIViewController {
    var onAttempt: (@MainActor () -> Void)?
    private var proxy: DSPresentationDelegateProxy?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let presentationController = parent?.presentationController ?? presentationController else { return }
        if let proxy, presentationController.delegate === proxy { return }
        let proxy = DSPresentationDelegateProxy(original: presentationController.delegate) { [weak self] in
            self?.onAttempt?()
        }
        self.proxy = proxy
        presentationController.delegate = proxy
    }
}

@MainActor
private final class DSPresentationDelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
    // Read by the Objective-C runtime's forwarding hooks, which are always called on the main thread.
    nonisolated(unsafe) private weak var original: (any UIAdaptivePresentationControllerDelegate)?
    private let onAttempt: @MainActor () -> Void

    init(original: (any UIAdaptivePresentationControllerDelegate)?, onAttempt: @escaping @MainActor () -> Void) {
        self.original = original
        self.onAttempt = onAttempt
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
        onAttempt()
    }
}
