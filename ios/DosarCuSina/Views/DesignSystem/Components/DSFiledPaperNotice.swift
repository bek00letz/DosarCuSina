import SwiftUI

/// A bill or an invoice being filed that is already in the binder (`FiledPaper`): where it
/// is and what saving does with it, "Vezi factura" to open it, and "E altă factură" when the
/// match isn't certain (`FiledPaper.mayBeAnother`). The one notice for the review, the visit
/// form and "Am rezolvat", in the words of `FiledPaperWording`.
struct DSFiledPaperNotice: View {
    let filed: FiledPaper
    let paper: FiledPaperWording.Paper
    /// Opens the entry it is logged as; nil where the screen can't leave for it.
    var onOpen: (() -> Void)?
    /// The person says it is another paper: saving then logs it on its own.
    let onAnother: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSNotice(
                .info,
                title: Text(verbatim: FiledPaperWording.title),
                message: Text(verbatim: FiledPaperWording.message(filed, paper: paper, today: CalendarDay(Date()))),
                actionTitle: onOpen.map { _ in Text(verbatim: FiledPaperWording.open) },
                action: onOpen
            )
            if filed.mayBeAnother {
                DSCompactButton(verbatim: FiledPaperWording.another, systemImage: "doc.badge.plus") {
                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { onAnother() }
                }
            }
        }
        .transition(.opacity)
    }
}
