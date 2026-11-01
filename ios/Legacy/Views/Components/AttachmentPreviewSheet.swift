import SwiftUI
import PDFKit
#if canImport(UIKit)
import UIKit
import QuickLook
#endif

public struct AttachmentPreviewSheet: View {
    public let attachment: DocumentAttachment
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewMode: PreviewMode = .document
    @State private var zoomScale: CGFloat = 1.0
    
    public enum PreviewMode: String, CaseIterable, Identifiable {
        case document = "Document"
        case extractedText = "Text OCR"
        public var id: String { rawValue }
    }
    
    public init(attachment: DocumentAttachment) {
        self.attachment = attachment
    }
    
    private var isPDF: Bool {
        attachment.fileExtension.lowercased() == "pdf" ||
        (attachment.fileData?.prefix(4) == Data([0x25, 0x50, 0x44, 0x46])) // "%PDF"
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if attachment.extractedText != nil {
                    Picker("Mod vizualizare", selection: $viewMode) {
                        ForEach(PreviewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
                
                Group {
                    if viewMode == .document {
                        documentVisualView
                    } else {
                        extractedTextScrollView
                    }
                }
                
                metadataFooterBar
            }
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if let data = attachment.fileData {
                        ShareLink(
                            item: data,
                            preview: SharePreview(attachment.fileName)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var documentVisualView: some View {
        #if canImport(UIKit)
        if isPDF, let data = attachment.fileData {
            PDFKitRepresentable(pdfData: data)
                .ignoresSafeArea(edges: .bottom)
        } else if let data = attachment.fileData, let uiImage = UIImage(data: data) {
            ZoomableImageView(image: uiImage)
        } else if let text = attachment.extractedText, !text.isEmpty {
            extractedTextScrollView
        } else {
            unavailableBinaryView
        }
        #else
        if let text = attachment.extractedText, !text.isEmpty {
            extractedTextScrollView
        } else {
            unavailableBinaryView
        }
        #endif
    }
    
    private var extractedTextScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Text detectat prin Vision OCR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    #if canImport(UIKit)
                    Button {
                        UIPasteboard.general.string = attachment.extractedText
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Copiază", systemImage: "doc.on.doc")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    #endif
                }
                Divider()
                Text(attachment.extractedText ?? "Niciun text disponibil.")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(16)
        }
    }
    
    private var metadataFooterBar: some View {
        HStack {
            Image(systemName: isPDF ? "doc.text.fill" : "photo")
                .foregroundStyle(.secondary)
            Text(attachment.fileExtension.uppercased())
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(Capsule())
            
            if let count = attachment.fileData?.count {
                let kb = Double(count) / 1024.0
                Text(kb > 1024 ? String(format: "%.1f MB", kb / 1024.0) : String(format: "%.0f KB", kb))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(attachment.createdAt.formatted(.dateTime.day().month().year()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    
    private var unavailableBinaryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text(attachment.fileName)
                .font(.headline)
            Text("Fișierul nu conține date binare sau formatul nu este suportat.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxHeight: .infinity)
    }
}

#if canImport(UIKit)
public struct PDFKitRepresentable: UIViewRepresentable {
    public let pdfData: Data
    
    public init(pdfData: Data) {
        self.pdfData = pdfData
    }
    
    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(data: pdfData)
        return pdfView
    }
    
    public func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: pdfData)
        }
    }
}

public struct ZoomableImageView: View {
    public let image: UIImage
    @State private var scale: CGFloat = 1.0
    
    public init(image: UIImage) {
        self.image = image
    }
    
    public var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in scale = max(1.0, min(val, 4.0)) }
                )
                .padding(8)
        }
    }
}
#endif
