import Foundation

/// The banks that issue cards in Romania, by the words printed on their cards, so a bank
/// card's bank is read by name. Data: a bank not listed is left for the person (or the
/// AI provider) to fill in.
enum RomanianBanks {
    /// Folded words on the card, most specific first, and the bank's name as people write it.
    static let names: [(words: String, name: String)] = [
        ("banca transilvania", "Banca Transilvania"),
        ("banca comerciala romana", "BCR"),
        ("bcr", "BCR"),
        ("brd groupe societe generale", "BRD"),
        ("brd", "BRD"),
        ("ing bank", "ING Bank"),
        ("ing", "ING Bank"),
        ("raiffeisen bank", "Raiffeisen Bank"),
        ("raiffeisen", "Raiffeisen Bank"),
        ("cec bank", "CEC Bank"),
        ("unicredit bank", "UniCredit Bank"),
        ("unicredit", "UniCredit Bank"),
        ("alpha bank", "Alpha Bank"),
        ("otp bank", "OTP Bank"),
        ("libra internet bank", "Libra Internet Bank"),
        ("garanti bbva", "Garanti BBVA"),
        ("first bank", "First Bank"),
        ("patria bank", "Patria Bank"),
        ("vista bank", "Vista Bank"),
        ("exim banca romaneasca", "Exim Banca Românească"),
        ("banca romaneasca", "Banca Românească"),
        ("procredit bank", "ProCredit Bank"),
        ("intesa sanpaolo", "Intesa Sanpaolo Bank"),
        ("credit europe bank", "Credit Europe Bank"),
        ("salt bank", "Salt Bank"),
        ("revolut", "Revolut"),
        ("tbi bank", "TBI Bank"),
    ]

    /// The bank the folded text names, matched as whole words.
    static func name(in folded: String) -> String? {
        names.first { CaptureText.containsWord($0.words, inFolded: folded) }?.name
    }
}
