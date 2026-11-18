import Foundation

/// The app's public pages: the privacy policy and help, published with GitHub Pages from the
/// repository's `site/` folder (`.github/workflows/pages.yml`). The one place their
/// addresses are written: Settings › Despre opens them, and App Store Connect is given the
/// same two. `PublicPagesTests` checks that each one is a page the folder serves.
enum PublicPages {
    /// Where `site/` is served from.
    static let site = URL(string: "https://bek00letz.github.io/DosarCuSina/")!

    /// „Politica de confidențialitate”, in Romanian (its English version is linked from it).
    static let privacyPolicy = page("confidentialitate/")

    /// „Ajutor”: what the app is, how to ask for help and how to report a problem.
    static let help = page("ajutor/")

    /// Every page the app or the App Store links to.
    static let all = [privacyPolicy, help]

    /// The support address, a contact that needs no account: the owner's chosen public one,
    /// written on the help page in both languages (`PublicPagesTests` checks they agree).
    static let supportEmail = "ar6development@gmail.com"

    /// Writing to it, from a link.
    static var supportMail: URL { URL(string: "mailto:" + supportEmail)! }

    private static func page(_ path: String) -> URL {
        site.appending(path: path, directoryHint: .isDirectory)
    }
}
