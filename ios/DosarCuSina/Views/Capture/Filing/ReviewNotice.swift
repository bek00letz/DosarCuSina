import Foundation

/// Something the review says about the reading before the values: a question waiting, a paper
/// already in the binder, values to check, a reading that didn't work, a way to read it better.
///
/// The review shows one at a time, the most important first by one rule (`importance`), and the
/// others behind "Mai sunt 2 observații" (never "de verificat", which is the share inbox), so nothing is lost and nothing piles up
/// above what the person came to confirm.
enum ReviewNotice: Equatable, Identifiable {
    /// "Citește automat" wants to send an identity document's photo to the AI provider: it waits
    /// for the person's answer.
    case askToSend
    /// A bill already in the binder: the same document, or another photo of the same bill.
    case alreadyFiled(FiledPaper)
    /// The same photo was added before; saving moves it to the place chosen.
    case samePhoto(attachmentID: UUID)
    /// The card's back carries the code that confirms the values: add it, or it is being read.
    case backPage(isReading: Bool, error: String?)
    /// The machine-readable zone didn't read for sure: check the number and the dates.
    case checkNumbers
    /// The AI provider was asked and didn't read the document, with why.
    case cloudFailed(message: String)
    /// The photo was hard to read.
    case hardToRead
    /// Only the first pages of a long PDF were read.
    case pagesTruncated(read: Int)

    var id: String {
        switch self {
        case .askToSend: "askToSend"
        case .alreadyFiled: "alreadyFiled"
        case .samePhoto: "samePhoto"
        case .backPage: "backPage"
        case .checkNumbers: "checkNumbers"
        case .cloudFailed: "cloudFailed"
        case .hardToRead: "hardToRead"
        case .pagesTruncated: "pagesTruncated"
        }
    }

    /// How much it matters now, highest first. What is happening or waits for an answer comes
    /// first (the back being read, a question about sending the photo); then what would make
    /// saving wrong (a paper already in the binder, the same photo); then values to check; then
    /// what didn't work; then a way to read it better; then what is only worth knowing.
    var importance: Int {
        switch self {
        case .backPage(isReading: true, _): 90
        case .askToSend: 80
        case .alreadyFiled: 70
        case .samePhoto: 60
        case .checkNumbers: 50
        case .cloudFailed: 40
        case .backPage(isReading: false, _): 30
        case .hardToRead: 20
        case .pagesTruncated: 10
        }
    }

    /// The notices in the order the review shows them: the first on its own, the rest behind
    /// "Mai sunt … observații". Ties keep the order they came in.
    static func byImportance(_ notices: [ReviewNotice]) -> [ReviewNotice] {
        notices.enumerated()
            .sorted { ($0.element.importance, -$0.offset) > ($1.element.importance, -$1.offset) }
            .map(\.element)
    }

    /// Everything the review has to say about a reading, most important first: one place that
    /// gathers what the review, the reading and the capture session know.
    static func present(
        asksToSend: Bool,
        filedBill: FiledPaper?,
        samePhoto: UUID?,
        asksForBackPage: Bool,
        readingBackPage: Bool,
        backPageError: String?,
        resultNotices: [CaptureNotice],
        cloudMessage: String?
    ) -> [ReviewNotice] {
        var notices: [ReviewNotice] = []
        if asksToSend { notices.append(.askToSend) }
        // A bill already filed says so; the same photo is the weaker of the two.
        if let filedBill {
            notices.append(.alreadyFiled(filedBill))
        } else if let samePhoto {
            notices.append(.samePhoto(attachmentID: samePhoto))
        }
        if asksForBackPage || readingBackPage {
            notices.append(.backPage(isReading: readingBackPage, error: readingBackPage ? nil : backPageError))
        }
        for notice in resultNotices {
            switch notice {
            case .machineReadableZoneUnverified: notices.append(.checkNumbers)
            case .littleTextRecognized: notices.append(.hardToRead)
            case .pagesTruncated(let read, _): notices.append(.pagesTruncated(read: read))
            default: break
            }
        }
        if let cloudMessage { notices.append(.cloudFailed(message: cloudMessage)) }
        // Each once, whatever the reading repeated.
        var seen = Set<String>()
        return byImportance(notices.filter { seen.insert($0.id).inserted })
    }
}
