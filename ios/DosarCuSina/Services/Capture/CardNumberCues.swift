import Foundation

/// What tells a card number on a page from other digits of the same shape. Digits alone
/// can't: a Romanian pet's microchip (15 digits starting 642) passes as a Maestro card about
/// one time in ten, and a long code can start like a card and pass its check digit. So a
/// card-shaped number names its kind only beside that kind's own cues, as data on the kind's
/// profile (`CaptureKindProfile.cardNumberCues`, a bank card's `bankCardCues`), read here
/// the one way, by `DocumentClassifier`:
/// - **with a cue** (a word of the card anywhere on the page, a caption only a card prints
///   or a month and two-digit year near the number, the number printed in a card's
///   grouping), it weighs `weight`, as much as a kind's strongest words;
/// - **bare** (one piece, nothing of a card around it), it is a hint of `bareWeight`, counted
///   only when no kind finds a word of its own on the page: it names a page that shows
///   nothing else, and never beats a vet record's "microcip" or any other kind's words.
///
/// Whatever the kind, the number itself is masked by the card rule (`PaymentCardNumbers`),
/// and a page that shows one is still read only on the phone (`PhoneOnlyReading`).
struct CardNumberCues: Sendable {
    /// What a card number with one of its cues weighs for the kind.
    let weight: Double
    /// What a card number with none weighs, only on a page where no kind has a word of its own.
    let bareWeight: Double
    /// Words, folded, that are a card's wherever they are on the page: its network's name, a
    /// cardholder's caption.
    let pageWords: [String]
    /// Words, folded, that are a card's when printed near the number: the captions only a card
    /// prints over its expiry.
    let nearbyWords: [String]
    /// How many lines above and below the number are near it.
    let nearLines: Int
    /// An expiry as a card prints it, near the number: month and two-digit year.
    let expiryPattern: String
    /// A number printed in a card's own grouping (four by four, 4-6-5) is a cue by itself.
    let groupingIsACue: Bool

    /// What a page shows of such a number.
    enum Evidence: Equatable, Sendable {
        /// No card-shaped number.
        case noNumber
        /// A card-shaped number with nothing of a card around it.
        case bare
        /// A card-shaped number with at least one of the card's cues.
        case withCues
    }

    /// What `text` shows: each card-shaped number (`PaymentCardNumbers.containsCardNumber`'s
    /// rule, line by line, since a number never runs across lines) with its cues.
    func evidence(in text: CaptureText) -> Evidence {
        let lines = text.original
        var found = false
        for index in lines.indices {
            let numbers = PaymentCardNumbers.cardNumbers(in: lines[index])
            guard !numbers.isEmpty else { continue }
            found = true
            if groupingIsACue, numbers.contains(where: Self.isGroupedLikeACard) { return .withCues }
            let near = max(lines.startIndex, index - nearLines)...min(lines.endIndex - 1, index + nearLines)
            let nearFolded = text.folded[near].joined(separator: "\n")
            if nearbyWords.contains(where: { CaptureText.containsWord($0, inFolded: nearFolded) }) { return .withCues }
            if TextPattern.first(expiryPattern, in: lines[near].joined(separator: "\n")) != nil { return .withCues }
        }
        guard found else { return .noNumber }
        let page = text.joinedFolded
        return pageWords.contains { CaptureText.containsWord($0, inFolded: page) } ? .withCues : .bare
    }

    /// Printed in groups the way a card prints its number ("4111 1111 1111 1111", 4-6-5),
    /// not in one piece.
    static func isGroupedLikeACard(_ run: PaymentCardNumbers.Run) -> Bool {
        run.groupSizes.count > 1 && run.printedLikeACard
    }
}
