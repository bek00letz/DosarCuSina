import SwiftUI
import UIKit

/// The system share sheet for files the app wrote for this share (a backup, a document's
/// pictures), reporting when it closes and whether something was sent, so the files can go.
/// Present it in a `.sheet` with `.ignoresSafeArea()`.
struct SystemShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    /// True when the person sent or saved them; false when they closed the sheet.
    let onFinish: @MainActor (_ completed: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
