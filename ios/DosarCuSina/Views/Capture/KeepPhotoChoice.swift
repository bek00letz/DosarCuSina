import SwiftUI

/// The one place a document whose photo is kept only on request asks whether to keep it
/// (`CaptureResult.photoIsOnRequest`): a bank card, or any page that shows a whole card
/// number, since the photo shows the number the binder never keeps. Off until the person
/// turns it on, and it says plainly what is kept either way: a card's bank, kind, last four
/// digits and expiry, or another page's values with the number masked. The review,
/// "Am rezolvat" and the visit form show it.
///
/// A shaped screen: its words are what the photo is of (`PhotoOnRequest`), and it holds none of
/// its own (the `text-in-shaped-screen` check).
struct KeepPhotoChoice: View {
    @Binding var keepsPhoto: Bool
    /// What the photo is of: a bank card, or a page that shows a card's number.
    let subject: PhotoOnRequest

    /// The choice for a document read as `kind` (the review's): a bank card's own words, or a page's.
    init(keepsPhoto: Binding<Bool>, kind: CaptureDocumentKind) {
        _keepsPhoto = keepsPhoto
        subject = PhotoOnRequest(kind)
    }

    /// Whether it speaks of a bank card.
    var isCard: Bool { subject == .bankCard }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(verbatim: subject.header)
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSCheckRow(title: Text(verbatim: subject.keep), isOn: $keepsPhoto)
                    Text(verbatim: subject.note(keepsPhoto: keepsPhoto))
                        .dsFont(.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
