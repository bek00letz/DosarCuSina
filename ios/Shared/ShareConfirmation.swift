import Foundation

/// What the share sheet's confirmation says and does, phase by phase. The share
/// extension draws it; it lives here so the app's tests pin it.
///
/// It stays until the person taps "Închide" (`closesByItself` is off): what happens next
/// ("Atinge notificarea ca să continui…") matters too much to vanish before it is read.
public struct ShareConfirmation: Equatable, Sendable {
    /// Where the share is.
    public enum Phase: Equatable, Sendable {
        case working
        /// `count` documents (photos shared together are one), and what the person does next.
        case saved(count: Int, next: InboxNotice.NextStep)
        /// Nothing it can read: not a photo, a PDF or text.
        case unsupported
        /// The phone couldn't hand the file over, or there's no room.
        case failed
        /// A file, or the whole share, is bigger than the inbox accepts.
        case tooLarge
    }

    /// The one button under it. Neither is "Gata" or "Anulează": the share is already made when
    /// there is something to say, so the button only closes the sheet ("Închide"), and while
    /// copying it stops before anything arrives ("Renunță"). Those two words keep their one
    /// meaning: marking a deadline done, taking back the step just taken (docs/COPY_GUIDE.md).
    public enum Action: Equatable, Sendable {
        /// While copying: stop and close ("Renunță").
        case cancel
        /// Once there is something to say: close the sheet ("Închide"), its main action.
        case close

        /// What the button says.
        public var title: String {
            switch self {
            case .cancel: String(localized: "Renunță", table: "Shared", comment: "Share sheet: stops copying what was shared and closes.")
            case .close: String(localized: "Închide", table: "Shared", comment: "Share sheet: closes the confirmation; what was shared is already in the app.")
            }
        }
    }

    /// The confirmation used to close by itself `DS.Motion.confirmationDwell` after a
    /// successful share. Off: it stays until "Închide". Kept switched off as the way back
    /// until the owner has seen the new one on a phone.
    public static let closesByItself = false

    public var title: String
    public var message: String?
    public var action: Action

    public init(_ phase: Phase) {
        switch phase {
        case .working:
            title = String(localized: "Se trimite…", table: "Shared", comment: "Share sheet: copying what was shared.")
            message = nil
        case .saved(let count, let next):
            // "Am primit un act", "Am primit 2 acte": the same words as the notice.
            title = InboxNotice.receivedTitle(count)
            message = switch next {
            case .tapNotice: String(localized: "Atinge notificarea ca să continui. Te așteaptă în aplicație, la De verificat.", table: "Shared", comment: "Share sheet: a notice is on its way.")
            case .openApp: String(localized: "Deschide Dosar cu Șină ca să continui. Te așteaptă la De verificat.", table: "Shared", comment: "Share sheet: no notice, notifications aren't allowed.")
            case .practice: String(localized: "Te întorci în aplicație și vezi unde a ajuns.", table: "Shared", comment: "Share sheet: the practice invoice, sent from inside the app.")
            }
        case .unsupported:
            title = String(localized: "Nu pot primi asta", table: "Shared", comment: "Share sheet: nothing it can read.")
            message = String(localized: "Pot primi poze, PDF-uri și text. Trimite factura sau actul ca poză sau PDF.", table: "Shared", comment: "Share sheet: what it can read.")
        case .failed:
            title = String(localized: "Nu s-a trimis", table: "Shared", comment: "Share sheet: the copy failed.")
            message = String(localized: "Telefonul nu mi-a dat fișierul. Încearcă din nou din aplicația din care l-ai trimis.", table: "Shared", comment: "Share sheet: what to do after a failed copy.")
        case .tooLarge:
            title = String(localized: "Fișierul e prea mare", table: "Shared", comment: "Share sheet: a file or the share is too large.")
            message = String(localized: "Trimite actele câte unul, sau ca poze în loc de un PDF mare.", table: "Shared", comment: "Share sheet: what to do with a file that is too large.")
        }
        action = phase == .working ? .cancel : .close
    }
}
