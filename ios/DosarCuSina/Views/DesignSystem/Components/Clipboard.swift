import UIKit
import UniformTypeIdentifiers

/// The one way the app puts a value on the clipboard.
@MainActor
enum Clipboard {
    enum Kind {
        /// A phone number, a policy number: shared with the person's other devices like any copy.
        case ordinary
        /// A personal value (a CNP, a document number, anything from a locked
        /// section) or a code: kept on this phone only, and gone after `personalLifetime`.
        case personal
    }

    /// How long a personal value or a code stays on the clipboard.
    static let personalLifetime: TimeInterval = 60

    static func copy(_ text: String, _ kind: Kind) {
        switch kind {
        case .ordinary:
            UIPasteboard.general.string = text
        case .personal:
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(personalLifetime)]
            )
        }
    }
}
