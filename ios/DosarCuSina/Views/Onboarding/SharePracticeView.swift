import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Practice sharing from another app, with the real share sheet and the real
/// share extension: a sample invoice (placeholder data only) goes out through
/// `ShareLink` and comes back into "De verificat". Most people don't know apps
/// can hand things to each other, and the first time Dosar cu Șină may hide
/// under "Mai multe" at the end of the app row, so that part is shown too.
struct SharePracticeView: View {
    let isOnboarding: Bool
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sampleURL: URL?
    @State private var startedAt = Date()
    @State private var arrived = false
    @State private var showsHiddenAppHelp = false

    private var inbox: IntakeInbox { .shared }

    /// How often the practice looks in the inbox itself while it waits. The invoice is
    /// found the moment the share extension signals it, or when the app comes back to the
    /// front; this only covers a signal iOS didn't deliver (another process posts it, and
    /// nothing tells the app it was missed). Nothing on screen waits for it.
    static let missedSignalCheck: Duration = .seconds(1.5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Trimite o factură din altă aplicație")
                        .dsFont(.display)
                        .accessibilityAddTraits(.isHeader)
                    Text("Așa ajung aici facturile primite pe mail sau pe WhatsApp. Încearcă acum cu o factură de probă.")
                        .dsFont(.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }

                SampleInvoiceCard()

                if arrived {
                    arrivedCard
                        .transition(DS.Motion.transition(from: .bottom, reduceMotion: reduceMotion))
                } else {
                    steps
                    shareButton
                    hiddenAppHelp
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle(isOnboarding ? "" : String(localized: "Trimite din altă aplicație"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: arrived)
        .dsAnimation(value: arrived)
        .task {
            startedAt = Date()
            sampleURL = try? SampleInvoice.writePDF()
            // The inbox knows the practice by these exact bytes, whatever the file is called on the way.
            if let sampleURL { try? ShareInbox.shared()?.expectPractice(fileAt: sampleURL) }
        }
        .task(id: arrived) {
            // The extension signals the app; this only covers a missed signal.
            while !arrived && !Task.isCancelled {
                inbox.refresh()
                checkArrival()
                try? await Task.sleep(for: Self.missedSignalCheck)
            }
        }
        .onChange(of: inbox.items) { _, _ in checkArrival() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { inbox.refresh() }
        }
    }

    private var steps: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                DSStepRow(number: 1, text: Text("Apasă „Trimite factura de probă”, mai jos."))
                DSStepRow(number: 2, text: Text("În rândul de aplicații care apare, alege Dosar cu Șină."))
                DSStepRow(number: 3, text: Text("Apasă „Gata”. Factura ajunge în Adaugă › De verificat."))
            }
        }
    }

    @ViewBuilder private var shareButton: some View {
        if let sampleURL {
            ShareLink(item: PracticeInvoiceFile(url: sampleURL), preview: SharePreview(Text("Factură de probă"), image: Image(systemName: "doc.text"))) {
                DSButtonLabel(title: Text("Trimite factura de probă"), systemImage: "square.and.arrow.up")
            }
            .dsFullWidthButton(prominent: true)
        } else {
            DSPrimaryButton("Trimite factura de probă", systemImage: "square.and.arrow.up") {}
                .disabled(true)
        }
        if isOnboarding {
            DSSecondaryButton("Mai târziu", action: onDone)
        }
    }

    private var hiddenAppHelp: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Button {
                    showsHiddenAppHelp.toggle()
                } label: {
                    HStack {
                        Text("Nu vezi Dosar cu Șină în rând?")
                            .dsFont(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: showsHiddenAppHelp ? "chevron.up" : "chevron.down")
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsHiddenAppHelp ? Text("Deschis") : Text("Închis"))

                if showsHiddenAppHelp {
                    Text("Prima dată, iPhone-ul o pune la capătul rândului. O aduci în față o singură dată:")
                        .dsFont(.body)
                    AppRowIllustration()
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        DSStepRow(number: 1, text: Text("În rândul de aplicații, trage cu degetul spre stânga până la capăt."))
                        DSStepRow(number: 2, text: Text("Apasă „Mai multe”, cercul cu trei puncte."))
                        DSStepRow(number: 3, text: Text("Apasă „Editează”, sus."))
                        DSStepRow(number: 4, text: Text("Apasă plusul verde de lângă Dosar cu Șină. Așa apare în față de acum încolo."))
                        DSStepRow(number: 5, text: Text("Apasă „Gata”, apoi alege Dosar cu Șină."))
                    }
                }
            }
        }
        .dsAnimation(value: showsHiddenAppHelp)
    }

    private var arrivedCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DSNotice(.success, title: "A ajuns", message: "Așa faci și cu facturile adevărate: „Trimite”, apoi Dosar cu Șină. Le găsești în Adaugă › De verificat.")
            DSPrimaryButton(isOnboarding ? "Continuă" : "Gata", action: onDone)
        }
    }

    private func checkArrival() {
        guard !arrived else { return }
        if inbox.items.contains(where: { $0.isPractice && $0.receivedAt >= startedAt.addingTimeInterval(-5) }) {
            arrived = true
            AccessibilityNotification.Announcement(String(localized: "Factura de probă a ajuns.")).post()
        }
    }
}

/// A drawing of the share sheet's app row, with "Mai multe" at its end. A
/// still picture: nothing here scrolls.
private struct AppRowIllustration: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 44

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ForEach(["message.fill", "envelope.fill", "note.text"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .background(DS.Palette.secondaryLabel, in: .rect(cornerRadius: side * 0.22, style: .continuous))
            }
            Spacer(minLength: 0)
            VStack(spacing: DS.Space.xxs) {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DS.Palette.label)
                    .frame(width: side, height: side)
                    .background(DS.Palette.fillStrong, in: .circle)
                    .overlay(Circle().strokeBorder(DS.Palette.accent, lineWidth: 3))
                Text("Mai multe").dsFont(.caption)
            }
        }
        .padding(DS.Space.s)
        .background(DS.Palette.fill, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Desen: rândul de aplicații, cu „Mai multe” la capăt."))
    }
}

/// The practice invoice as the person sees it before sending it.
private struct SampleInvoiceCard: View {
    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text(verbatim: SampleInvoice.issuer).dsFont(.headline)
                    Spacer()
                    Text("Probă").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.secondaryLabel)
                }
                Text(verbatim: "\(SampleInvoice.car) · \(SampleInvoice.plate)").dsFont(.subheadline)
                DS.Hairline().padding(.vertical, DS.Space.xxs)
                ForEach(SampleInvoice.lines, id: \.name) { line in
                    HStack {
                        Text(verbatim: line.name).dsFont(.body)
                        Spacer()
                        Text(verbatim: Money(line.amount).formattedCompact()).dsFont(.body, numeric: true)
                    }
                }
                DS.Hairline().padding(.vertical, DS.Space.xxs)
                HStack {
                    Text("Total").dsFont(.headline)
                    Spacer()
                    Text(verbatim: Money(SampleInvoice.total).formattedCompact()).dsFont(.headline, numeric: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Factură de probă de la \(SampleInvoice.issuer), total \(Money(SampleInvoice.total).formattedCompact())"))
    }
}

/// The practice invoice as the share sheet sends it: a typed PDF with its own
/// name, the way Mail sends an attachment, so the extension sees a PDF.
struct PracticeInvoiceFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { SentTransferredFile($0.url) }
            .suggestedFileName(ShareInbox.practiceFileName)
    }
}

/// The practice invoice: placeholder data only, never a real firm, plate or person.
enum SampleInvoice {
    static let issuer = "Service Exemplu SRL"
    static let client = "Ion Exemplu"
    static let car = "VW Golf 2018"
    static let plate = "B 123 ABC"
    static let lines: [(name: String, amount: Decimal)] = [
        ("Schimb ulei și filtru de ulei", 420),
        ("Plăcuțe frână față", 380),
        ("Manoperă", 200),
    ]
    static var total: Decimal { lines.reduce(0) { $0 + $1.amount } }

    /// Writes the PDF the share practice sends. The inbox recognizes it by its bytes (`ShareInbox.expectPractice`).
    static func writePDF(date: Date = Date()) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: ShareInbox.practiceFileName)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let day = DosarFormat.numericDay(date)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 60
            func draw(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, x: CGFloat = 56, right: Bool = false) {
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: UIColor.black]
                let string = NSAttributedString(string: text, attributes: attributes)
                let width = string.size().width
                string.draw(at: CGPoint(x: right ? page.width - 56 - width : x, y: y))
            }
            draw(issuer, size: 20, weight: .bold)
            y += 28
            draw("Str. Exemplului nr. 1, București", size: 11)
            y += 40
            draw("FACTURĂ nr. EX-0001", size: 16, weight: .semibold)
            y += 22
            draw("Data facturii: \(day)", size: 12)
            y += 18
            draw("Client: \(client)", size: 12)
            y += 18
            draw("Autoturism: \(car), nr. înmatriculare \(plate)", size: 12)
            y += 36
            for line in lines {
                draw(line.name, size: 12)
                draw("\(NSDecimalNumber(decimal: line.amount).stringValue),00 lei", size: 12, right: true)
                y += 20
            }
            y += 16
            draw("Total de plată: \(NSDecimalNumber(decimal: total).stringValue),00 lei", size: 14, weight: .bold)
            y += 60
            draw("Factură de probă pentru Dosar cu Șină. Nu e o factură reală.", size: 10)
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
