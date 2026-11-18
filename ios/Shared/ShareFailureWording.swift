import Foundation

/// What a share that didn't arrive says, for each reason (`ShareFailure`), counted by the files
/// it is about: one is „Fișierul…”, several „Fișierele…”, from the String Catalog's plural forms.
/// The one place these words live: the share sheet's confirmation (`ShareConfirmation`) and
/// Setări › Despre › „Probleme la primire” read them.
///
/// - `title`: what happened, when nothing arrived („Fișierul e încă în iCloud”).
/// - `advice`: what to do next („Nu l-am putut descărca acum. Deschide-l o dată în Fișiere…”).
/// - `cause`: how many didn't arrive and why, when others did („Un fișier e încă în iCloud.”),
///   followed by the advice.
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
        }
    }

    /// What didn't arrive of a share where something did: how many and why, then what to do.
    public static func note(_ missed: ShareFailure.Missed) -> String {
        cause(missed.failure, count: missed.files) + " " + advice(missed.failure, count: missed.files)
    }
}
