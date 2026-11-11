import SwiftUI

/// Said in place of the examples while the person's binder may still be coming down from
/// iCloud on this phone (`PersistenceController.binderMayBeArriving`): calmly, with the progress
/// held back so a quick download never flashes it (`DSDelayedProgress`).
struct BinderArrivingNotice: View {
    var body: some View {
        VStack(spacing: DS.Space.s) {
            DSDelayedProgress(label: "Se aduce dosarul tău din iCloud…")
            Text("Dacă ai deja un dosar pe alt dispozitiv, apare aici. Dacă e gol, poți încărca exemplele după.",
                 comment: "Shown on a new device while the person's binder may still be coming down from iCloud, in place of the examples.")
                .dsFont(.footnote)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
