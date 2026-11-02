import SwiftUI
import VisionKit
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

/// A high-performance, native document scanner view wrapping `VNDocumentCameraViewController`.
/// Provides automated edge detection, perspective correction, multi-page capture,
/// and tactile haptic feedback matching Apple Craftsmanship & Polish standards.
public struct LiveDocumentScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    
    public let onScannedPages: @MainActor ([UIImage]) -> Void
    public let onCancel: (@MainActor () -> Void)?
    public let onError: (@MainActor (Error) -> Void)?
    
    public init(
        onScannedPages: @escaping @MainActor ([UIImage]) -> Void,
        onCancel: (@MainActor () -> Void)? = nil,
        onError: (@MainActor (Error) -> Void)? = nil
    ) {
        self.onScannedPages = onScannedPages
        self.onCancel = onCancel
        self.onError = onError
    }
    
    /// Checks whether document scanning is supported on the current hardware/OS.
    public static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return VNDocumentCameraViewController.isSupported
        #endif
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    public func makeUIViewController(context: Context) -> UIViewController {
        guard VNDocumentCameraViewController.isSupported else {
            // Fallback controller for environments where VNDocumentCameraViewController is unsupported
            let fallbackVC = UIViewController()
            fallbackVC.view.backgroundColor = .systemBackground
            
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Camera scanner is not supported on this device."
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            
            fallbackVC.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: fallbackVC.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: fallbackVC.view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: fallbackVC.view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(lessThanOrEqualTo: fallbackVC.view.trailingAnchor, constant: -20)
            ])
            return fallbackVC
        }
        
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = context.coordinator
        return scannerViewController
    }
    
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Keep coordinator's parent reference synchronized with latest SwiftUI state and closures
        context.coordinator.parent = self
    }
    
    // MARK: - Coordinator
    
    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        fileprivate var parent: LiveDocumentScannerView
        
        init(parent: LiveDocumentScannerView) {
            self.parent = parent
        }
        
        public func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pageCount = scan.pageCount
            var scannedImages: [UIImage] = []
            scannedImages.reserveCapacity(pageCount)
            
            for pageIndex in 0..<pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                scannedImages.append(image)
            }
            
            // Tactile feedback on successful multipage scan completion
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.success)
            
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.parent.onScannedPages(scannedImages)
                    self.parent.dismiss()
                }
            }
        }
        
        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.prepare()
            feedback.impactOccurred()
            
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.parent.onCancel?()
                    self.parent.dismiss()
                }
            }
        }
        
        public func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.error)
            
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.parent.onError?(error)
                    self.parent.dismiss()
                }
            }
        }
    }
    
    // MARK: - PDF Conversion Utilities
    
    /// Converts an array of scanned images into a structured multi-page `PDFDocument`.
    public static func createPDFDocument(from images: [UIImage]) -> PDFDocument {
        let pdfDocument = PDFDocument()
        for (index, image) in images.enumerated() {
            if let pdfPage = PDFPage(image: image) {
                pdfDocument.insert(pdfPage, at: index)
            }
        }
        return pdfDocument
    }
    
    /// Compresses and serializes scanned images directly into raw PDF `Data`
    /// suitable for storage in `DocumentAttachment.fileData`.
    public static func createPDFData(from images: [UIImage]) -> Data? {
        let pdfDocument = createPDFDocument(from: images)
        return pdfDocument.dataRepresentation()
    }
}
