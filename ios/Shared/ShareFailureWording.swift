import Foundation

/// What a share that didn't arrive says, for each reason (`ShareFailure`), counted by the files
/// it is about: one is „Fișierul…”, several „Fișierele…”, from the String Catalog's plural forms.
/// The one place these words live: the share sheet's confirmation (`ShareConfirmation`) and
/// Setări › Despre › „Probleme la primire” read them.
///
/// - `title`: what happened, when nothing arrived („Fișierul e încă în iCloud”).
/// - `advice`: what to do next („Nu l-am putut descărca acum. Deschide-l o dată în Fișiere…”).
/// - `cause`: how many didn't arrive and why, when others did („Un fișier e încă în iCloud.”),
///   followed by the advice. Files left untried are told on lines of their own: those it can't
///   take („Nu pot primi un fișier.”), those past the limit („3 fișiere au rămas pe dinafară.”).
public enum ShareFailureWording {
    /// What happened, as a title: „Fișierul e încă în iCloud”, „Fișierele sunt încă în iCloud”.
    public static func title(_ failure: ShareFailure, count: Int = 1) -> String {
        switch failure {
        case .stillInCloud, .offline:
            String(localized: "Cele \(count) fișiere sunt încă în iCloud", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the files are in iCloud and couldn't be downloaded. Plural variations without the number: one „Fișierul e încă în iCloud”, several „Fișierele sunt încă în iCloud”.")
        case .noRoom:
            String(localized: "Nu mai e loc pe telefon", table: "Shared", comment: "Share sheet: the phone is out of space.")
        case .noAccess:
            String(localized: "Nu pot deschide cele \(count) fișiere", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the sending app didn't allow reading the files. Plural variations without the number: one „Nu pot deschide fișierul”, several „Nu pot deschide fișierele”.")
        case .tooLarge:
            String(localized: "Cele \(count) fișiere sunt prea mari", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the files or the share are too large. Plural variations without the number: one „Fișierul e prea mare”, several „Fișierele sunt prea mari”.")
        case .notHandedOver, .couldNotCopy:
            String(localized: "Cele \(count) fișiere nu s-au trimis", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the copy failed. Plural variations without the number: one „Nu s-a trimis”, several „Nu s-au trimis”.")
        case .inboxUnavailable:
            String(localized: "Nu am unde să pun cele \(count) fișiere", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the app's shared folder isn't available. Plural variations without the number: one „Nu am unde să pun fișierul”, several „Nu am unde să pun fișierele”.")
        case .unsupportedType:
            String(localized: "Nu pot primi cele \(count) fișiere", table: "Shared", locale: .dosarDefault,
                   comment: "Share: files that aren't a photo, a PDF or text. Plural variations without the number: one „Nu pot primi fișierul”, several „Nu pot primi fișierele”.")
        case .overFileLimit:
            String(localized: "\(count) fișiere au rămas pe dinafară", table: "Shared", locale: .dosarDefault,
                   comment: "Share: how many files were past the most one share takes. One is a word: „Un fișier a rămas pe dinafară”.")
        }
    }

    /// What to do next, in a sentence or two that end with a full stop.
    public static func advice(_ failure: ShareFailure, count: Int = 1) -> String {
        switch failure {
        case .stillInCloud:
            String(localized: "Nu am putut descărca cele \(count) fișiere acum. Deschide-le o dată în Fișiere, apoi trimite-le din nou.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: what to do with files still in iCloud. Plural variations without the number: one „Nu l-am putut descărca acum. Deschide-l o dată în Fișiere, apoi trimite-l din nou.”, several „Nu le-am putut descărca acum. Deschide-le o dată în Fișiere, apoi trimite-le din nou.”")
        case .offline:
            String(localized: "Ca să descarc cele \(count) fișiere, telefonul are nevoie de internet. Conectează-te, apoi trimite-le din nou.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: downloading the files needs the internet. Plural variations without the number: one „Ca să-l descarc, telefonul are nevoie de internet. Conectează-te, apoi trimite-l din nou.”, several „Ca să le descarc, telefonul are nevoie de internet. Conectează-te, apoi trimite-le din nou.”")
        case .noRoom:
            String(localized: "Fă loc din Configurări › General › Spațiu iPhone, apoi trimite cele \(count) fișiere din nou.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: where to free up space. The path names the iPhone's own Settings screens. Plural variations without the number: one „Fă loc din Configurări › General › Spațiu iPhone, apoi trimite-l din nou.”, several „… apoi trimite-le din nou.”")
        case .noAccess:
            String(localized: "Aplicația din care ai trimis cele \(count) fișiere nu mi-a dat voie să le citesc. Salvează-le întâi în Fișiere, apoi trimite-le de acolo.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: what to do when the files can't be read. Plural variations without the number: one „Aplicația din care l-ai trimis nu mi-a dat voie să-l citesc. Salvează-l întâi în Fișiere, apoi trimite-l de acolo.”, several with „le”.")
        case .tooLarge:
            String(localized: "Trimite actele câte unul, sau ca poze în loc de un PDF mare.", table: "Shared", comment: "Share sheet: what to do with a file that is too large.")
        case .notHandedOver:
            String(localized: "Telefonul nu mi-a dat cele \(count) fișiere. Încearcă din nou din aplicația din care le-ai trimis.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the sending app handed over nothing. Plural variations without the number: one „Telefonul nu mi-a dat fișierul. Încearcă din nou din aplicația din care l-ai trimis.”, several „Telefonul nu mi-a dat fișierele. … le-ai trimis.”")
        case .inboxUnavailable:
            String(localized: "Deschide Dosar cu Șină o dată, apoi trimite cele \(count) fișiere din nou.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: what to do when the shared folder isn't available. Plural variations without the number: one „Deschide Dosar cu Șină o dată, apoi trimite-l din nou.”, several „… apoi trimite-le din nou.”")
        case .couldNotCopy:
            String(localized: "Cele \(count) fișiere nu s-au putut copia. Încearcă din nou din aplicația din care le-ai trimis.", table: "Shared", locale: .dosarDefault,
                   comment: "Share failed: the copy failed for a reason the phone didn't name. Plural variations without the number: one „Fișierul nu s-a putut copia. Încearcă din nou din aplicația din care l-ai trimis.”, several „Fișierele nu s-au putut copia. … le-ai trimis.”")
        case .unsupportedType:
            String(localized: "Pot primi poze, PDF-uri și text. Trimite factura sau actul ca poză sau PDF.", table: "Shared", comment: "Share sheet: what it can read.")
        case .overFileLimit:
            String(localized: "Trimite cel mult \(ShareInbox.maxFiles) fișiere odată, apoi restul separat.", table: "Shared", locale: .dosarDefault,
                   comment: "Share: the most files one share takes, and to send the rest after. Plural forms: „Trimite cel mult 20 de fișiere odată, apoi restul separat.”")
        }
    }

    /// How many didn't arrive and why, when others did: „Un fișier e încă în iCloud.”,
    /// „3 fișiere sunt încă în iCloud.”, „20 de fișiere…”. The advice follows it.
    public static func cause(_ failure: ShareFailure, count: Int) -> String {
        switch failure {
        case .stillInCloud, .offline:
            String(localized: "\(count) fișiere sunt încă în iCloud.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many are still in iCloud. One is a word: „Un fișier e încă în iCloud.”")
        case .noRoom:
            String(localized: "\(count) fișiere nu au mai încăput pe telefon.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many didn't fit on the phone. One is a word: „Un fișier nu a mai încăput pe telefon.”")
        case .noAccess:
            String(localized: "Nu am putut deschide \(count) fișiere.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many couldn't be read. One is a word: „Nu am putut deschide un fișier.”")
        case .tooLarge:
            String(localized: "\(count) fișiere sunt prea mari.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many are too large. One is a word: „Un fișier e prea mare.”")
        case .notHandedOver, .couldNotCopy:
            String(localized: "\(count) fișiere nu au ajuns.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many didn't. One is a word: „Un fișier nu a ajuns.”")
        case .inboxUnavailable:
            String(localized: "Nu am avut unde să pun \(count) fișiere.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many had nowhere to go. One is a word: „Nu am avut unde să pun un fișier.”")
        case .unsupportedType:
            String(localized: "Nu pot primi \(count) fișiere.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many aren't a photo, a PDF or text. One is a word: „Nu pot primi un fișier.”")
        case .overFileLimit:
            String(localized: "\(count) fișiere au rămas pe dinafară.", table: "Shared", locale: .dosarDefault,
                   comment: "Share sheet, after some files arrived: how many were past the most one share takes. One is a word: „Un fișier a rămas pe dinafară.”")
        }
    }

    /// What didn't arrive of a share where something did: for each part (the files tried in
    /// vain, then each reason a file was left untried), how many and why, then what to do, a
    /// line each.
    public static func note(_ missed: ShareFailure.Missed) -> String {
        missed.parts.map(line).joined(separator: "\n")
    }

    /// One part of the note. A count goes only with what is true of every file it counts: files
    /// that all had one reason are told by it („2 fișiere sunt încă în iCloud. …”); files with
    /// different reasons by what is true of all of them, then the most telling reason, counted by
    /// the files that had it („2 fișiere nu au ajuns. Un fișier e încă în iCloud. …”).
    public static func line(_ part: ShareFailure.Missed.Part) -> String {
        guard part.isMixed else { return cause(part.failure, count: part.files) + " " + advice(part.failure, count: part.files) }
        return cause(.couldNotCopy, count: part.files) + " " + mixedReason(part)
    }

    /// The most telling reason of files that failed for different reasons, counted by the files
    /// that had it, and what to do about them; for a reason that names no cause (nothing handed
    /// over, a copy that failed), what is true of all of them instead.
    public static func mixedReason(_ part: ShareFailure.Missed.Part) -> String {
        if namesNoCause.contains(part.failure) { return advice(.couldNotCopy, count: part.files) }
        return cause(part.failure, count: part.ofReason) + " " + advice(part.failure, count: part.ofReason)
    }

    /// The reasons whose words say only that a file didn't arrive, not why.
    static let namesNoCause: Set<ShareFailure> = [.notHandedOver, .couldNotCopy]
}
