import Foundation
import Testing
@testable import DosarCuSina

/// The privacy policy and help pages Settings › Despre opens, and App Store Connect links to,
/// are pages the repository's `site/` folder really serves (`.github/workflows/pages.yml`
/// publishes it at `PublicPages.site`), and every link inside the site leads to a page it has.
@Suite("Public pages")
struct PublicPagesTests {
    /// The repository, from this file: `ios/DosarCuSinaTests/PublicPagesTests.swift`.
    static var repository: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static var siteFolder: URL { repository.appending(path: "site", directoryHint: .isDirectory) }

    /// The file the site serves at an address, or nil for an address outside the site.
    static func file(servedAt url: URL) -> URL? {
        guard url.scheme == PublicPages.site.scheme, url.host() == PublicPages.site.host() else { return nil }
        let base = PublicPages.site.path()
        let path = url.path()
        guard path.hasPrefix(base) else { return nil }
        var relative = String(path.dropFirst(base.count))
        if relative.isEmpty || relative.hasSuffix("/") { relative += "index.html" }
        return siteFolder.appending(path: relative)
    }

    /// The site's pages, as paths inside `site/`.
    static func pages() throws -> [String] {
        let base = siteFolder.standardizedFileURL.path()
        let enumerator = try #require(FileManager.default.enumerator(at: siteFolder, includingPropertiesForKeys: nil))
        var pages: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "html" else { continue }
            pages.append(String(url.standardizedFileURL.path().dropFirst(base.count)))
        }
        return pages.sorted()
    }

    @Test(arguments: PublicPages.all)
    func everyPageTheAppOpensIsOneTheSiteServes(_ url: URL) throws {
        let file = try #require(Self.file(servedAt: url), "\(url) is outside \(PublicPages.site)")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)), "site/ has no page for \(url)")
    }

    /// The app speaks Romanian, so the pages it opens are the Romanian ones; each links to its
    /// English version.
    @Test(arguments: PublicPages.all)
    func thePagesTheAppOpensAreInRomanian(_ url: URL) throws {
        let file = try #require(Self.file(servedAt: url))
        let html = try String(contentsOf: file, encoding: .utf8)
        #expect(html.contains(#"<html lang="ro">"#))
        #expect(html.contains(#"hreflang="en""#))
    }

    /// The help page, in both languages, offers the support address as a contact that needs no
    /// account, the same one `PublicPages` keeps.
    @Test func bothHelpPagesOfferTheSupportAddress() throws {
        #expect(PublicPages.supportMail.scheme == "mailto")
        for page in ["ajutor/index.html", "en/help/index.html"] {
            let html = try String(contentsOf: Self.siteFolder.appending(path: page), encoding: .utf8)
            #expect(html.contains(#"href="mailto:\#(PublicPages.supportEmail)""#), "\(page) links to the support address")
            #expect(html.contains(">\(PublicPages.supportEmail)</a>"), "\(page) shows it")
        }
    }

    @Test func theWorkflowPublishesTheFolderTheAppLinksInto() throws {
        let workflow = try String(contentsOf: Self.repository.appending(path: ".github/workflows/pages.yml"), encoding: .utf8)
        #expect(workflow.contains("path: site\n"))
        #expect(PublicPages.site.absoluteString == "https://bek00letz.github.io/DosarCuSina/")
    }

    /// Every link, picture and stylesheet inside the site that points into it leads to a file
    /// it has, so moving a page can't leave a link, the App Store's or the app's, behind.
    @Test func everyLinkInsideTheSiteLeadsToAPageItHas() throws {
        let pages = try Self.pages()
        #expect(pages.contains("confidentialitate/index.html"))
        #expect(pages.contains("en/privacy/index.html"))
        for page in pages {
            let html = try String(contentsOf: Self.siteFolder.appending(path: page), encoding: .utf8)
            let served = try #require(URL(string: page, relativeTo: PublicPages.site))
            for match in html.matches(of: /(?:href|src)="([^"]+)"/) {
                let link = String(match.1)
                guard !link.hasPrefix("#") else { continue }
                let target = try #require(URL(string: link, relativeTo: served)?.absoluteURL, "\(page): \(link)")
                guard let file = Self.file(servedAt: target) else { continue }
                #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)), "\(page) links to \(link), which site/ doesn't have")
            }
        }
    }
}
