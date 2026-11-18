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
        /// `count` documents (photos shared together are one), and what the person does next;
        /// with `notArrived`, the files of the same share that didn't arrive, and why: those it
        /// tried in vain, those it can't take, those past the limit.
        case saved(count: Int, next: InboxNotice.NextStep, notArrived: ShareFailure.Missed? = nil)
        /// Nothing it can read: not a photo, a PDF or text.
        case unsupported
        /// Nothing arrived, and why (`ShareFailure`), for `count` files: each reason says what to
        /// do next. With `ofReason`, only that many had the reason: the files failed differently.
        case failed(ShareFailure, count: Int = 1, ofReason: Int? = nil)

        /// A share where nothing arrived: why, counted by the files it tried in vain
        /// (`ShareFailure.Tally`), or that there was nothing it can read when it tried none.
        public static func nothingSaved(_ missed: ShareFailure.Missed?) -> Phase {
            missed?.failed.map { .failed($0.failure, count: $0.files, ofReason: $0.isMixed ? $0.ofReason : nil) } ?? .unsupported
        }
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
    /// What didn't arrive when something else did: how many files and why, then what to do
    /// (`ShareFailureWording.note`). Part of the one confirmation, under its message.
    public var note: String?
    public var action: Action

    public init(_ phase: Phase) {
        switch phase {
        case .working:
            title = String(localized: "Se trimite…", table: "Shared", comment: "Share sheet: copying what was shared.")
            message = nil
        case .saved(let count, let next, let notArrived):
            // "Am primit un act", "Am primit 2 acte": the same words as the notice.
            title = InboxNotice.receivedTitle(count)
            message = switch next {
            case .tapNotice: String(localized: "Atinge notificarea ca să continui. Te așteaptă în aplicație, la De verificat.", table: "Shared", comment: "Share sheet: a notice is on its way.")
            case .openApp: String(localized: "Deschide Dosar cu Șină ca să continui. Te așteaptă la De verificat.", table: "Shared", comment: "Share sheet: no notice, notifications aren't allowed.")
            case .practice: String(localized: "Te întorci în aplicație și vezi unde a ajuns.", table: "Shared", comment: "Share sheet: the practice invoice, sent from inside the app.")
            }
            note = notArrived.map(ShareFailureWording.note)
        case .unsupported:
            title = String(localized: "Nu pot primi asta", table: "Shared", comment: "Share sheet: nothing it can read.")
            message = ShareFailureWording.advice(.unsupportedType)
        case .failed(let failure, let count, let ofReason):
            let part = ShareFailure.Missed.Part(files: count, failure: failure, ofReason: ofReason)
            if part.isMixed {
                // Different reasons: the title says what is true of all of them („Nu s-au
                // trimis”), the message the most telling reason, counted by those that had it.
                title = ShareFailureWording.title(.couldNotCopy, count: count)
                message = ShareFailureWording.mixedReason(part)
            } else {
                title = ShareFailureWording.title(failure, count: count)
                message = ShareFailureWording.advice(failure, count: count)
            }
        }
        action = phase == .working ? .cancel : .close
    }
}
