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

    private static func page(_ path: String) -> URL {
        site.appending(path: path, directoryHint: .isDirectory)
    }
}
