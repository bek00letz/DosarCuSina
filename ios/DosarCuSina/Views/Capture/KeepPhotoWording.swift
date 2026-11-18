import Foundation

/// What a photo kept only on request is of (`CaptureResult.photoIsOnRequest`), and so the words
/// `KeepPhotoChoice` says: a bank card's own, or those of any page that shows a card's whole
/// number. Declared by the kind's profile (`CaptureKindProfile.photoIsOptIn`), never by a test of
/// which kind it is. `KeepPhotoChoice` is a shaped screen and holds no words of its own;
/// `docs/COPY_MATRIX.md` lists both (`CopyMatrixTests.reviewSharedRows`).
enum PhotoOnRequest: CaseIterable {
    /// A bank card: its photo shows the number the binder never keeps.
    case bankCard
    /// Any other page that shows a card's whole number.
    case pageWithCardNumber

    /// For a document read as `kind`.
    init(_ kind: CaptureDocumentKind) {
        self = kind.profile.photoIsOptIn ? .bankCard : .pageWithCardNumber
    }

    /// Above the choice.
    var header: String {
        switch self {
        case .bankCard: String(localized: "Poza cardului")
        case .pageWithCardNumber: String(localized: "Poza documentului")
        }
    }

    /// The choice itself, off until the person turns it on.
    var keep: String {
        switch self {
        case .bankCard: String(localized: "Păstrează și poza cardului")
        case .pageWithCardNumber: String(localized: "Păstrează și poza documentului")
        }
    }

    /// Under it: what is kept either way.
    func note(keepsPhoto: Bool) -> String {
        switch (self, keepsPhoto) {
        case (.bankCard, true):
            String(localized: "Poza arată numărul întreg al cardului. O păstrez în dosar, protejată ca restul documentelor.")
        case (.bankCard, false):
            String(localized: "Păstrez doar banca, tipul cardului, ultimele 4 cifre și data expirării. Poza și numărul întreg nu se păstrează.")
        case (.pageWithCardNumber, true):
            String(localized: "Poza arată numărul întreg al unui card. O păstrez în dosar, protejată ca restul documentelor.")
        case (.pageWithCardNumber, false):
            String(localized: "Poza arată numărul întreg al unui card, așa că nu o păstrez. Păstrez ce am citit pe document, cu numărul cardului ascuns.")
        }
    }
}
