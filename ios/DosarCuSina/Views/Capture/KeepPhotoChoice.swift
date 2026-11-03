import SwiftUI

/// The one place a document whose photo is kept only on request (a bank card: its photo
/// shows the whole number) asks whether to keep it. Off until the person turns it on, and
/// it says plainly what is kept either way. The review and "Am rezolvat" both show it.
struct KeepPhotoChoice: View {
    @Binding var keepsPhoto: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Poza cardului")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSCheckRow(title: Text("Păstrează și poza cardului"), isOn: $keepsPhoto)
                    Group {
                        if keepsPhoto {
                            Text("Poza arată numărul întreg al cardului. O păstrez în dosar, protejată ca restul actelor.")
                        } else {
                            Text("Păstrez doar banca, tipul cardului, ultimele 4 cifre și data expirării. Poza și numărul întreg nu se păstrează.")
                        }
                    }
                    .dsFont(.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
