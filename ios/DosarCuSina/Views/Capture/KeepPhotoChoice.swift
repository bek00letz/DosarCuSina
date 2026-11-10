import SwiftUI

/// The one place a document whose photo is kept only on request asks whether to keep it
/// (`CaptureResult.photoIsOnRequest`): a bank card, or any page that shows a whole card
/// number, since the photo shows the number the binder never keeps. Off until the person
/// turns it on, and it says plainly what is kept either way: a card's bank, kind, last four
/// digits and expiry, or another page's values with the number masked. The review and
/// "Am rezolvat" both show it.
struct KeepPhotoChoice: View {
    @Binding var keepsPhoto: Bool
    /// The document is a bank card; otherwise a page that shows a card's number.
    let isCard: Bool

    /// The choice for a document read as `kind` (the review's): a bank card's own words, or a page's.
    init(keepsPhoto: Binding<Bool>, kind: CaptureDocumentKind) {
        _keepsPhoto = keepsPhoto
        isCard = kind.profile.photoIsOptIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if isCard { DSSectionHeader("Poza cardului") } else { DSSectionHeader("Poza actului") }
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    if isCard {
                        DSCheckRow(title: Text("Păstrează și poza cardului"), isOn: $keepsPhoto)
                    } else {
                        DSCheckRow(title: Text("Păstrează și poza actului"), isOn: $keepsPhoto)
                    }
                    note
                        .dsFont(.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var note: Text {
        switch (isCard, keepsPhoto) {
        case (true, true):
            Text("Poza arată numărul întreg al cardului. O păstrez în dosar, protejată ca restul actelor.")
        case (true, false):
            Text("Păstrez doar banca, tipul cardului, ultimele 4 cifre și data expirării. Poza și numărul întreg nu se păstrează.")
        case (false, true):
            Text("Poza arată numărul întreg al unui card. O păstrez în dosar, protejată ca restul actelor.")
        case (false, false):
            Text("Poza arată numărul întreg al unui card, așa că nu o păstrez. Păstrez ce am citit pe act, cu numărul cardului ascuns.")
        }
    }
}
