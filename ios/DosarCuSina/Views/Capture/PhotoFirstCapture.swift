import SwiftUI

extension View {
    /// Photo first, for something that belongs on a section: asks where the photo comes
    /// from (camera, photos, files), reads it with capture and offers to file it on
    /// `assetID`. The one way a page asks for "a photo of this paper" (a document's own
    /// picture, the policy a claim needs, a car's invoices).
    ///
    /// `onFiled` gets capture's confirmation for a toast; `onError` a message to show
    /// when the photo couldn't be opened.
    func photoFirstCapture(
        isPresented: Binding<Bool>,
        title: Text,
        assetID: UUID?,
        onFiled: @escaping @MainActor (LocalizedStringResource) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> some View {
        modifier(PhotoFirstCapture(isPresented: isPresented, title: title, assetID: assetID, onFiled: onFiled, onError: onError))
    }
}

private struct PhotoFirstCapture: ViewModifier {
    @Binding var isPresented: Bool
    let title: Text
    let assetID: UUID?
    let onFiled: @MainActor (LocalizedStringResource) -> Void
    let onError: @MainActor (String) -> Void

    @State private var source: CaptureSource?
    @State private var flow: CaptureFlowInput?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                if CaptureSource.isCameraAvailable {
                    Button { source = .camera } label: { Text("Fotografiază actul", comment: "Photo source: camera.") }
                }
                Button { source = .photos } label: { Text("Alege din poze", comment: "Photo source: library.") }
                Button { source = .files } label: { Text("Din Fișiere", comment: "Photo source: files.") }
                Button(role: .cancel) {} label: { Text("Renunță", comment: "Cancels a choice.") }
            }
            .captureSourcePicker($source) { payload in
                flow = CaptureFlowInput(payload: payload, preferredAssetID: assetID)
            } onError: { error in
                onError(SaveFailure.message(for: error, formKept: false))
            }
            .sheet(item: $flow) { input in
                CaptureFlowView(input: input) { result in
                    flow = nil
                    switch result {
                    case .filed(let message, _), .visitSaved(let message):
                        onFiled(message)
                    case .dismissed:
                        break
                    }
                }
            }
    }
}
