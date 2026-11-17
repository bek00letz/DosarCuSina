import Foundation
import SwiftData

/// The capture review's words. The review (`CaptureReviewView`) is a shaped screen: it holds no
/// words of its own. What varies by document kind comes from the kind's description
/// (`CaptureKindProfile`: its title, the noun it is named by and the pronoun that noun takes,
/// what the day it follows means, whether it is a bill or a personal document), said here once;
/// the words every kind shares are `CaptureReviewWording`'s. `docs/COPY_MATRIX.md` lists both
/// (`CopyMatrixTests.reviewSection`), and `ReviewCopyRulesTests` checks them.

// MARK: - What a kind says

extension CaptureKindProfile.Noun {
    /// The paper inside a sentence, after its preposition: „factură”, „cartea de identitate”.
    var onPaper: String { String(localized: afterPreposition) }

    /// The paper itself, with its article: „factura”, „contractul”.
    var itself: String { String(localized: definite) }

    /// The summary card's heading and the place picker's title, agreeing with the paper's noun.
    var wherePutWords: String {
        switch gender {
        case .masculine:
            String(localized: "Unde îl pun", comment: "Capture review: where a paper named by a masculine noun goes (a contract, a report).")
        case .feminine:
            String(localized: "Unde o pun", comment: "Capture review: where a paper named by a feminine noun goes (a bill, a policy).")
        case .plural:
            String(localized: "Unde le pun", comment: "Capture review: where papers named by a plural noun go.")
        }
    }

    /// Nothing was read off the page: it is kept all the same, under the name above. On a
    /// paper or in it, as its noun says (`surface`).
    var nothingReadWords: String {
        switch (surface, gender) {
        case (.on, .masculine):
            String(localized: "Nu am găsit date pe \(onPaper). Îl păstrez oricum, cu numele de mai sus.",
                   comment: "Capture review: nothing read off a paper named by a masculine noun (the argument, e.g. „bon”); it is kept.")
        case (.on, .feminine):
            String(localized: "Nu am găsit date pe \(onPaper). O păstrez oricum, cu numele de mai sus.",
                   comment: "Capture review: nothing read off a paper named by a feminine noun (the argument, e.g. „factură”); it is kept.")
        case (.on, .plural):
            String(localized: "Nu am găsit date pe \(onPaper). Le păstrez oricum, cu numele de mai sus.",
                   comment: "Capture review: nothing read off papers named by a plural noun; they are kept.")
        case (.inside, .masculine):
            String(localized: "Nu am găsit date în \(onPaper). Îl păstrez oricum, cu numele de mai sus.",
                   comment: "Capture review: nothing read in a paper named by a masculine noun (the argument, e.g. „contract”); it is kept.")
        case (.inside, .feminine):
            String(localized: "Nu am găsit date în \(onPaper). O păstrez oricum, cu numele de mai sus.",
                   comment: "Capture review: nothing read in a paper named by a feminine noun (the argument, e.g. „poliță”); it is kept.")
        case (.inside, .plural):
            String(localized: "Nu am găsit date în \(onPaper). Le păstrez oricum, cu numele de mai sus.",
                   comment: "Capture review: nothing read in papers named by a plural noun; they are kept.")
        }
    }

    /// The reminder line when no place is chosen yet, for a paper that isn't a bill.
    var choosePlaceWords: String {
        switch gender {
        case .masculine:
            String(localized: "Alege unde îl pui ca să te anunț din timp.", comment: "Capture review: a paper named by a masculine noun needs a place before it can remind.")
        case .feminine:
            String(localized: "Alege unde o pui ca să te anunț din timp.", comment: "Capture review: a paper named by a feminine noun needs a place before it can remind.")
        case .plural:
            String(localized: "Alege unde le pui ca să te anunț din timp.", comment: "Capture review: papers named by a plural noun need a place before they can remind.")
        }
    }

    /// The reminder line when a bill has no subscription chosen yet.
    var choosePlaceToPayWords: String {
        switch gender {
        case .masculine:
            String(localized: "Alege abonamentul lui ca să îți amintesc să-l plătești.", comment: "Capture review: a bill named by a masculine noun needs its subscription before it can remind.")
        case .feminine:
            String(localized: "Alege abonamentul ei ca să îți amintesc s-o plătești.", comment: "Capture review: a bill named by a feminine noun needs its subscription before it can remind.")
        case .plural:
            String(localized: "Alege abonamentul lor ca să îți amintesc să le plătești.", comment: "Capture review: bills named by a plural noun need their subscription before they can remind.")
        }
    }

    /// A bill's choice to be reminded to pay it.
    var remindToPayWords: String {
        switch gender {
        case .masculine:
            String(localized: "Amintește-mi să-l plătesc", comment: "Capture review: remind me to pay a bill named by a masculine noun.")
        case .feminine:
            String(localized: "Amintește-mi să o plătesc", comment: "Capture review: remind me to pay a bill named by a feminine noun.")
        case .plural:
            String(localized: "Amintește-mi să le plătesc", comment: "Capture review: remind me to pay bills named by a plural noun.")
        }
    }

    /// Under „Se plătește prin debit direct”: what the paper says, shortened, and what turning it on does.
    func directDebitWords(_ statement: String) -> String {
        // What the paper says, without its own full stop: the quote is followed by one.
        let statement = statement.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".;,")))
        return switch surface {
        case .on:
            String(localized: "Pe \(onPaper) scrie: „\(statement)”. Dacă e așa, nu îți mai amintesc să plătești facturile.",
                   comment: "Capture review: a bill says the bank pays by direct debit. The first argument is the paper, e.g. „factură”; the second what it says.")
        case .inside:
            String(localized: "În \(onPaper) scrie: „\(statement)”. Dacă e așa, nu îți mai amintesc să plătești facturile.",
                   comment: "Capture review: a contract says the bank pays by direct debit. The first argument is the paper, e.g. „contract”; the second what it says.")
        }
    }

    /// A value that passed its own check digit, beside a different one: „Pe factură scrie: …”,
    /// „În contract scrie: …”.
    func printedWords(_ value: String) -> String {
        switch surface {
        case .on:
            String(localized: "Pe \(onPaper) scrie: \(value)",
                   comment: "Capture review: a value that passed its own check digit, beside a different one. The first argument is the paper written on, e.g. „factură”.")
        case .inside:
            String(localized: "În \(onPaper) scrie: \(value)",
                   comment: "Capture review: a value that passed its own check digit, beside a different one. The first argument is the paper written in, e.g. „contract”.")
        }
    }
}

extension CaptureKindProfile {
    /// What the machine-readable zone says, where it is printed: on the back of a card, or at the bottom.
    func machineReadableWords(_ value: String) -> String {
        hasMachineReadableBack
            ? String(localized: "Pe spatele actului scrie: \(value)", comment: "What the machine-readable zone on the back of the card says.")
            : String(localized: "În codul de jos al actului scrie: \(value)", comment: "What the machine-readable zone says.")
    }

    /// Under „Citește mai bine cu …”: what the AI provider is sent, a personal document's
    /// photo or another paper's first page.
    func sentToProviderWords(_ provider: String) -> String {
        documentType != nil
            ? String(localized: "Poza actului se trimite la \(provider), cu cheia ta.",
                     comment: "Capture review: a personal document's photo is sent to the AI provider. The argument is the provider's name.")
            : String(localized: "Prima pagină se trimite la \(provider), cu cheia ta.",
                     comment: "Capture review: a paper's first page is sent to the AI provider. The argument is the provider's name.")
    }
}

extension CaptureKindProfile.DayMeaning {
    /// The reminder line's opening: what the day is, „Expiră pe 12 august 2031.”.
    func opening(_ date: String) -> String {
        switch self {
        case .expires:
            String(localized: "Expiră pe \(date).", comment: "Capture review: the day a document or a policy expires.")
        case .inspectionValidUntil:
            String(localized: "ITP-ul e valabil până pe \(date).", comment: "Capture review: the last day an inspection report keeps the car's ITP valid.")
        case .payBy:
            String(localized: "De plătit până pe \(date).", comment: "Capture review: the day a bill is to be paid by.")
        case .minimumPeriodEnds:
            String(localized: "Perioada minimă se termină pe \(date). De atunci poți, de regulă, renunța fără penalități.",
                   comment: "Capture review: the day a contract's minimum period ends.")
        case .warrantyEnds:
            String(localized: "Garanția se termină pe \(date).", comment: "Capture review: the day a purchase's warranty ends.")
        case .nextDose:
            String(localized: "Următoarea doză e pe \(date).", comment: "Capture review: the day a pet's next vaccine dose is due.")
        }
    }

    /// The same opening for a day already passed, in words for a passed day: „A expirat pe 10 mai.”
    func passedOpening(_ date: String) -> String {
        switch self {
        case .expires:
            String(localized: "A expirat pe \(date).", comment: "Capture review: the day a document or a policy expired, already passed.")
        case .inspectionValidUntil:
            String(localized: "ITP-ul a fost valabil până pe \(date).", comment: "Capture review: the last day an inspection report kept the car's ITP valid, already passed.")
        case .payBy:
            String(localized: "Era de plătit până pe \(date).", comment: "Capture review: the day a bill was to be paid by, already passed.")
        case .minimumPeriodEnds:
            String(localized: "Perioada minimă s-a terminat pe \(date). De atunci poți, de regulă, renunța fără penalități.",
                   comment: "Capture review: the day a contract's minimum period ended, already passed.")
        case .warrantyEnds:
            String(localized: "Garanția s-a terminat pe \(date).", comment: "Capture review: the day a purchase's warranty ended, already passed.")
        case .nextDose:
            String(localized: "Următoarea doză era pe \(date).", comment: "Capture review: the day a pet's next vaccine dose was due, already passed.")
        }
    }
}

// MARK: - The reminder line

/// The reminder a review will set, in plain words, read from its filing plan:
/// "Expiră pe 12 august 2031. Te anunț cu 3 luni și cu o lună înainte." It names a
/// reminder exactly when saving makes or moves one.
enum CaptureReminderPreview {
    @MainActor
    static func text(for review: CaptureReview, templates: [String: CategoryTemplate], assets: [Asset], calendar: Calendar = .dosar, today: CalendarDay) -> String? {
        text(for: review, plan: CaptureFilingPlan.make(for: review, templates: templates, assets: assets, today: today, calendar: calendar), today: today)
    }

    static func text(for review: CaptureReview, plan: CaptureFilingPlan, today: CalendarDay) -> String? {
        // A day comes only from the field the kind's day follows, whose meaning the kind states
        // (`dayMeaning`, `ReviewCopyRulesTests`).
        let profile = review.kind.profile
        guard let day = plan.day, let meaning = profile.dayMeaning else { return nil }
        let date = DueWording.date(day, today: today)
        let passed = day < today
        // Not printed: the document's rule gives it (a cazier judiciar, six months from its issue).
        let opening = review.validityEnd == day
            ? ReminderWording.validityOpening(day, months: review.validityMonths ?? 0, today: today)
            : passed ? meaning.passedOpening(date) : meaning.opening(date)
        if let deadline = plan.deadline {
            let travel = ReminderWording.travelLine(expiring: day, profile: deadline.reminders, today: today)
            // A day already passed: no reminder can come before it, so the line says what happens
            // instead (the deadline shows as late in Urmează), never „Te anunț … înainte”.
            let when = passed ? ReminderWording.alreadyLate : ReminderWording.sentence(deadline.reminders)
            return [opening, travel, when].compactMap { $0 }.joined(separator: " ")
        }
        switch plan.quiet {
        case .notWanted?:
            return nil
        case .paidByDirectDebit?:
            return String(localized: "De plătit până pe \(date). Se plătește prin debit direct, așa că nu îți amintesc.",
                          comment: "Capture review: a bill the bank pays by direct debit sets no reminder.")
        case .needsPlace?:
            return opening + " " + (profile.isBill ? profile.noun.choosePlaceToPayWords : profile.noun.choosePlaceWords)
        case .dayPassed?:
            if meaning == .minimumPeriodEnds {
                // The minimum period is over: nothing to remind about, but worth knowing.
                return opening + " " + String(localized: "Contractul se încheie la cel mult o lună după ce anunți.",
                                              comment: "Capture review: a contract whose minimum period is over ends at most a month after the notice to leave.")
            }
            return opening + " " + String(localized: "Data a trecut, așa că nu îți mai amintesc.", comment: "Capture review: the paper's day has passed.")
        case .alreadyLater(let later)?:
            return opening + " " + String(localized: "Termenul de aici e deja pe \(DueWording.date(later, today: today)), așa că rămâne așa.",
                                          comment: "Capture review: the section's deadline is already later than the paper's day.")
        case .noSuchDeadline?:
            return opening + " " + String(localized: "Categoria aleasă nu are acest termen, așa că nu îți amintesc.",
                                          comment: "Capture review: the category chosen keeps no such deadline.")
        case .billFiledBefore?:
            return opening + " " + String(localized: "Factura e deja în dosar, așa că nu îți amintesc încă o dată de ea.",
                                          comment: "Capture review: another photo of a bill already filed, whose reminder was dealt with.")
        case nil:
            return nil
        }
    }
}

// MARK: - Where it goes

/// "Unde o pun", in the summary card: the place saving files the document in, as its row
/// shows it, and the name a new section asks for.
@MainActor
struct CaptureReviewPlace {
    var title: String
    var subtitle: String
    var systemImage: String
    /// The name field's title when saving makes a new section.
    var newNameTitle: String?

    init(review: CaptureReview, assets: [Asset], templates: [String: CategoryTemplate]) {
        func role(_ key: String) -> CategoryBehavior.Role? { templates[key]?.behavior.role }
        let underSubscription = review.kind.profile.filing == .subscription
        switch review.destination {
        case .none:
            title = CaptureReviewWording.keepOnly
            subtitle = CaptureReviewWording.foundInSearch
            systemImage = "tray"
            newNameTitle = nil
        case .asset(let id):
            let asset = assets.first { $0.id == id }
            title = asset?.name ?? CaptureReviewWording.sectionGone
            systemImage = asset?.symbolOverride ?? asset.flatMap { templates[$0.templateKey]?.symbol } ?? "folder"
            newNameTitle = nil
            if let asset {
                if role(asset.templateKey) == .holder {
                    subtitle = CaptureReviewWording.withPersonsDocuments
                } else if underSubscription, let subscription = review.existingSubscription(assets: assets), subscription.id != asset.id {
                    subtitle = CaptureReviewWording.atSubscription(subscription.name)
                } else if underSubscription, role(asset.templateKey) == .home {
                    subtitle = CaptureReviewWording.newSubscriptionHere(CaptureFiler.subscriptionName(review))
                } else if underSubscription, let parent = asset.parent {
                    subtitle = CaptureReviewWording.subscriptionAt(parent.name)
                } else {
                    subtitle = templates[asset.templateKey]?.name ?? ""
                }
            } else {
                subtitle = ""
            }
        case .newAsset(let key):
            switch role(key) {
            case .holder?:
                title = CaptureReviewWording.newPerson(review.newAssetName)
                subtitle = CaptureReviewWording.addedToDocuments
                systemImage = "person.crop.circle.badge.plus"
                newNameTitle = CaptureReviewWording.personName
            case .subscription?:
                title = CaptureReviewWording.newSubscription(review.newAssetName)
                subtitle = CaptureReviewWording.madeWhenSaved
                systemImage = templates[key]?.symbol ?? "folder.badge.plus"
                newNameTitle = CaptureReviewWording.subscriptionName
            case .home? where underSubscription:
                title = CaptureReviewWording.newSection(in: templates[key]?.name ?? key)
                subtitle = CaptureReviewWording.madeWhenSaved(withSubscription: CaptureFiler.subscriptionName(review))
                systemImage = templates[key]?.symbol ?? "folder.badge.plus"
                newNameTitle = CaptureReviewWording.homeName
            default:
                title = CaptureReviewWording.newSection(in: templates[key]?.name ?? key)
                subtitle = CaptureReviewWording.madeWhenSaved
                systemImage = templates[key]?.symbol ?? "folder.badge.plus"
                newNameTitle = CaptureReviewWording.newSectionName
            }
        }
    }
}

// MARK: - What every kind shares

/// The words the review says for every kind alike.
enum CaptureReviewWording {
    // The screen
    static var title: String { String(localized: "Verifică actul", comment: "Capture review: the screen's title.") }
    static var save: String { String(localized: "Salvează", comment: "Capture review: files the document.") }
    static var notSaved: String { String(localized: "Nu s-a salvat") }
    static var later: String { String(localized: "Mai târziu", comment: "Closes the review of something shared; it stays in De verificat.") }
    static var removeFromInbox: String {
        String(localized: "Șterge din De verificat", comment: "Takes something shared out of De verificat, from its review.")
    }
    static var discardFromInbox: String {
        String(localized: "Ce ai schimbat nu se salvează. Actul rămâne în De verificat.", comment: "Closing the review of something shared, after changes.")
    }
    static var photoDidNotOpen: String { String(localized: "Poza nu s-a putut deschide. Încearcă din nou.") }

    // The summary card
    static var whenHeading: String { String(localized: "Când te anunț", comment: "Capture review: the summary card's heading over the reminder.") }
    static var seeLarge: String { String(localized: "Vezi actul mare", comment: "VoiceOver label of the document thumbnail in the review.") }
    static var seeLargeHint: String {
        String(localized: "Se deschide pe tot ecranul. Poți mări sau roti pagina.", comment: "VoiceOver hint of the document thumbnail.")
    }
    static var whatKind: String { String(localized: "Ce act e", comment: "Capture review: the menu of document kinds.") }
    static var notThis: String { String(localized: "Nu e asta? Schimbă", comment: "Capture review: opens the menu of document kinds.") }
    static func phoneSawKind(_ kind: String) -> String {
        String(localized: "Pe telefon părea: \(kind)", comment: "The kind the phone read, beside the AI provider's.")
    }
    static func checkedKind(_ kind: String) -> String {
        String(localized: "Codul de jos al actului arată: \(kind)", comment: "The kind the checked machine-readable zone shows.")
    }
    static func readWithProvider(_ shortName: String) -> String {
        String(localized: "Citit și cu \(shortName), cu cheia ta.", comment: "The AI provider read the document too. The argument is the provider's short name.")
    }
    static var readWithAppleIntelligence: String {
        String(localized: "Citit pe telefon, cu Apple Intelligence.", comment: "Capture review: read on the phone, with the on-device model.")
    }
    static var readOnPhone: String {
        String(localized: "Citit pe telefon. Nimic n-a plecat de aici.", comment: "Capture review: read on the phone alone.")
    }
    static var cropped: String { String(localized: "Am păstrat doar actul, fără ce e în jur.", comment: "The review: the document was cut out of its photo.") }
    static var wholePhotoKept: String { String(localized: "Se păstrează poza întreagă.", comment: "The review: the whole photo is kept, not the cut-out.") }
    static var useWholePhoto: String { String(localized: "Folosește poza întreagă", comment: "The review: keeps the whole photo instead of the cut-out.") }
    static var onlyDocument: String { String(localized: "Doar actul", comment: "The review: keeps only the document cut out of its photo.") }
    static var chooseAnother: String { String(localized: "Alege alta", comment: "Capture review: opens the choice of a place.") }
    static var check: String { String(localized: "Verifică", comment: "Capture review: a value or a place worth a look.") }
    static var changeDay: String { String(localized: "Schimbă ziua", comment: "Capture review: scrolls to the day the reminder follows.") }
    static var changeDayHint: String {
        String(localized: "Arată ziua de pe act, ca s-o poți schimba.", comment: "VoiceOver hint of the review's reminder line.")
    }
    static var directDebit: String { String(localized: "Se plătește prin debit direct", comment: "Capture review: the bank pays this subscription's bills. Said of the bills, like „Se plătește prin debit direct, așa că nu îți amintesc.”") }
    static var changeLater: String { String(localized: "Poți schimba după, pe pagina termenului.", comment: "Capture review: under the reminder.") }

    // The notices
    static func moreNotices(_ count: Int) -> String {
        String(localized: "Mai sunt \(count) observații",
               locale: .dosarDefault, comment: "Opens the review's other notices. The number is how many more there are, with Romanian plural forms (Mai e o observație).")
    }
    static var samePhoto: String { String(localized: "Ai mai adăugat poza asta", comment: "Capture review: the same photo was added before.") }
    static var samePhotoMessage: String {
        String(localized: "Dacă salvezi, o pun la locul ales, împreună cu ce am citit.", comment: "Capture review: saving moves the same photo to the place chosen.")
    }
    static var seeWhereItIs: String { String(localized: "Vezi unde e acum", comment: "Capture review: opens the document already kept.") }
    static var backPage: String {
        String(localized: "Ai și o poză cu spatele? Acolo e codul care confirmă datele.", comment: "Capture review: asks for the back of an identity card.")
    }
    static var readingBack: String { String(localized: "Citesc și spatele…", comment: "Capture review: the back of the card is being read.") }
    static var photographBack: String { String(localized: "Fotografiază spatele", comment: "Capture review: takes a photo of the card's back.") }
    static var choosePhotos: String { String(localized: "Alege din poze") }
    static var backNotRead: String { String(localized: "Nu am putut citi spatele", comment: "Capture review: the card's back couldn't be read.") }
    static var checkNumbers: String { String(localized: "Verifică numărul și datele", comment: "Capture review: the machine-readable zone didn't read for sure.") }
    static var checkNumbersMessage: String {
        String(localized: "Codul de jos al actului nu s-a citit sigur.", comment: "Capture review: the machine-readable zone didn't read for sure.")
    }
    static func providerDidNotRead(_ name: String) -> String {
        String(localized: "\(name) nu a citit actul", comment: "Capture review: the AI provider couldn't read the document. The argument is its name.")
    }
    static var hardToRead: String { String(localized: "Poza e greu de citit", comment: "Capture review: little text was read.") }
    static var hardToReadMessage: String {
        String(localized: "O poză nouă, dreaptă și fără reflexii, ajută.", comment: "Capture review: what helps a photo hard to read.")
    }
    static func firstPagesRead(_ count: Int) -> String {
        String(localized: "Am citit primele \(count) pagini", locale: .dosarDefault, comment: "Capture review: only the first pages of a long PDF were read, with Romanian plural forms.")
    }
    static var longDocument: String {
        String(localized: "E un document lung. Se păstrează tot, cu toate paginile.", comment: "Capture review: a long PDF is kept whole.")
    }

    // Sending to the AI provider
    static func sendPhotoQuestion(_ name: String) -> String {
        String(localized: "Trimit poza la \(name)?", comment: "Capture review: asks before an identity document's photo goes to the AI provider.")
    }
    static func sendPhotoMessage(_ name: String) -> String {
        String(localized: "Nu sunt sigur ce am citit. \(name) poate citi actul mai bine, cu cheia ta. Fără un da, poza rămâne pe telefon.",
               comment: "Capture review: why the photo would be sent, and that it stays without a yes. The argument is the AI provider's name.")
    }
    static var sendPhoto: String { String(localized: "Trimite poza", comment: "Capture review: sends the photo to the AI provider.") }
    static var keepOnPhone: String { String(localized: "Nu, rămâne pe telefon", comment: "Capture review: the photo isn't sent.") }
    static func dataPolicy(_ name: String) -> String {
        String(localized: "Cum folosește \(name) ce trimiți", comment: "Link to the AI provider's data-use terms.")
    }
    static var cardsStayOnPhone: String {
        String(localized: "Cardurile bancare se citesc doar pe telefon.", comment: "Capture review: why a bank card can't be read by the AI provider.")
    }
    static func readingWith(_ shortName: String) -> String {
        String(localized: "Citesc cu \(shortName)…", comment: "Capture review: the AI provider is reading the document.")
    }
    static func readBetter(_ shortName: String) -> String {
        String(localized: "Citește mai bine cu \(shortName)", comment: "Capture review: asks the AI provider to read the document.")
    }

    // What was read
    static var whatWasRead: String { String(localized: "Ce am citit", comment: "Capture review: the section of values read.") }
    static var checkMarked: String { String(localized: "Verifică ce e marcat.", comment: "Capture review: some values are worth a look.") }
    static var documentName: String { String(localized: "Numele actului", comment: "Capture review: the document's name field.") }
    static var notFound: String { String(localized: "Nu am găsit pe act:", comment: "Capture review: the fields the kind usually carries, not read.") }
    static func add(_ field: String) -> String {
        String(localized: "Adaugă: \(field)", comment: "Capture review: adds an empty field the kind usually carries. The argument is the field's name.")
    }
    static func fromDocument(_ source: String) -> String {
        String(localized: "Din act: „\(source)”", comment: "Capture review: the bit of the page a value was read from.")
    }
    static func readFrom(_ source: String) -> String {
        String(localized: "Citit din: \(source)", comment: "VoiceOver label of the bit of the page a value was read from.")
    }
    static func phoneRead(_ value: String) -> String {
        String(localized: "Pe telefon am citit: \(value)", comment: "The phone's value, beside the AI provider's.")
    }
    static var use: String { String(localized: "Folosește-l", comment: "Applies a value another reader read instead of the one shown.") }
    static func useThis(_ text: String) -> String {
        String(localized: "Folosește: \(text)", comment: "VoiceOver label of the button that applies another reader's value.")
    }

    /// "Gemini a citit: …", in the provider's own name.
    static func readBy(_ provider: AIProvider, value: String) -> String {
        switch provider {
        case .openAICompatible:
            String(localized: "Modelul tău a citit: \(value)", comment: "The value the person's own AI model read.")
        default:
            String(localized: "\(provider.shortName) a citit: \(value)", comment: "The value the AI provider read. The first argument is the provider's short name.")
        }
    }

    // A policy's class, a home's address
    static func bonusMalusKept(_ name: String) -> String {
        String(localized: "Clasa bonus-malus o păstrez la \(name): e a celui asigurat, nu a mașinii.",
               comment: "Capture review: a policy's bonus-malus class is kept on the person it insures. The argument is their name.")
    }
    static var bonusMalusNoPolicyholder: String {
        String(localized: "Clasa bonus-malus n-o păstrez: în poliță nu scrie cine e asiguratul.", comment: "Capture review: a policy that doesn't say who it insures.")
    }
    static func bonusMalusNotInHousehold(_ name: String) -> String {
        String(localized: "Clasa bonus-malus n-o păstrez: \(name) nu e printre persoanele din dosar. Adaugă persoana și citește polița din nou.",
               comment: "Capture review: the person a policy insures isn't in the household. The argument is the name on the policy.")
    }
    static var addressPartlyAgrees: String {
        String(localized: "Adresa locului de consum seamănă cu cea a locuinței, dar nu e chiar aceeași.", comment: "Capture review: the supply address only partly agrees with the home's.")
    }
    static var addressDiffers: String {
        String(localized: "Adresa locului de consum nu e cea a locuinței.", comment: "Capture review: the supply address isn't the home's.")
    }
    static var insuredAddressPartlyAgrees: String {
        String(localized: "Adresa din poliță seamănă cu cea a locuinței, dar nu e chiar aceeași.",
               comment: "Capture review: the address of the home a policy insures only partly agrees with the home's.")
    }
    static var insuredAddressDiffers: String {
        String(localized: "Adresa din poliță nu e cea a locuinței.", comment: "Capture review: the address of the home a policy insures isn't the home's.")
    }

    /// Where a policy's bonus-malus class goes, in a line under what was read.
    static func bonusMalus(_ choice: CaptureFilingPlan.BonusMalus) -> String {
        switch choice {
        case .keep(_, _, let name): bonusMalusKept(name)
        case .noPolicyholder: bonusMalusNoPolicyholder
        case .notInHousehold(let name): bonusMalusNotInHousehold(name)
        }
    }

    /// Why the home was chosen without being sure: the address the paper names for it (`address`:
    /// a bill's supply address, a policy's insured home) only partly agrees, or isn't the home's.
    static func placeCheck(_ check: SubscriptionMatcher.HouseCheck, address: CaptureFieldKey) -> String {
        switch (check, address == .insuredAddress) {
        case (.addressPartlyAgrees, false): addressPartlyAgrees
        case (.addressDiffers, false): addressDiffers
        case (.addressPartlyAgrees, true): insuredAddressPartlyAgrees
        case (.addressDiffers, true): insuredAddressDiffers
        }
    }

    // Where it goes
    static var keepOnly: String { String(localized: "Doar păstrez actul", comment: "Capture review: the document goes to no section.") }
    static var foundInSearch: String { String(localized: "Îl găsești în Caută.", comment: "Capture review: a document kept in no section is found in Caută.") }
    static var keepOnlySubtitle: String {
        String(localized: "Fără secțiune; îl găsești în Caută.", comment: "Place picker: the document goes to no section.")
    }
    static var sectionGone: String { String(localized: "Secțiune ștearsă", comment: "Capture review: the section chosen has gone.") }
    static var withPersonsDocuments: String {
        String(localized: "Actul stă la actele acestei persoane.", comment: "Capture review: a document filed under a person.")
    }
    static func atSubscription(_ name: String) -> String {
        String(localized: "La abonamentul „\(name)”", comment: "Capture review: the bill goes to this subscription.")
    }
    static func newSubscriptionHere(_ name: String) -> String {
        String(localized: "Abonament nou aici: \(name)", comment: "Capture review: a new subscription is made under the home chosen.")
    }
    static func subscriptionAt(_ home: String) -> String {
        String(localized: "Abonament la \(home)", comment: "Capture review: a subscription under this home.")
    }
    static func newPerson(_ name: String) -> String {
        String(localized: "Persoană nouă: \(name)", comment: "Capture review: the document goes to a new person.")
    }
    static func newSubscription(_ name: String) -> String {
        String(localized: "Abonament nou: \(name)", comment: "Capture review: the document goes to a new subscription.")
    }
    static func newSection(in category: String) -> String {
        String(localized: "Secțiune nouă în \(category)", comment: "Capture review: the document goes to a new section of this category.")
    }
    static var addedToDocuments: String { String(localized: "Se adaugă în Acte când salvezi.", comment: "Capture review: a new person is made when saving.") }
    static var madeWhenSaved: String { String(localized: "Se creează când salvezi.", comment: "Capture review: a new section is made when saving.") }
    static func madeWhenSaved(withSubscription name: String) -> String {
        String(localized: "Se creează când salvezi, cu abonamentul „\(name)”.", comment: "Capture review: a new home is made when saving, with its subscription.")
    }
    static var personName: String { String(localized: "Numele persoanei", comment: "Capture review: the new person's name field.") }
    static var subscriptionName: String { String(localized: "Numele abonamentului", comment: "Capture review: the new subscription's name field.") }
    static var homeName: String { String(localized: "Numele locuinței", comment: "Capture review: the new home's name field.") }
    static var newSectionName: String { String(localized: "Numele secțiunii noi", comment: "Capture review: the new section's name field.") }

    // The place picker
    static var newPersonChoice: String { String(localized: "Persoană nouă", comment: "Place picker: the document goes to a new person.") }
    static var groupedByPerson: String { String(localized: "Actele stau grupate pe persoane.", comment: "Place picker: under „Persoană nouă”.") }
    static func newSectionChoice(in category: String) -> String {
        String(localized: "Secțiune nouă în „\(category)”", comment: "Makes a new section of the category the document fits.")
    }
    static var thenFiled: String { String(localized: "Completezi ce trebuie, apoi pun actul acolo.", comment: "Place picker: a new section is made first.") }
    static var otherSection: String { String(localized: "Altă secțiune…", comment: "Place picker: lists every section.") }
    static var everySectionSubtitle: String { String(localized: "Toate secțiunile din dosar.", comment: "Place picker: under „Altă secțiune…”.") }
    static var close: String { String(localized: "Închide") }
    static var everySection: String { String(localized: "Toate secțiunile", comment: "Place picker: the list of every section.") }
    static var whatSection: String { String(localized: "Ce fel de secțiune", comment: "Place picker: the list of categories for a new section.") }
    static var newSectionPlain: String { String(localized: "Secțiune nouă", comment: "Place picker: makes a new section of any category.") }
    static var chooseCategoryFirst: String {
        String(localized: "Alegi ce fel de secțiune, apoi pun actul acolo.", comment: "Place picker: under „Secțiune nouă”.")
    }
    static var example: String { String(localized: "Exemplu", comment: "Place picker: a section of the example data.") }
    static var homeHoldsSubscription: String {
        String(localized: "La abonamentul de aici, sau unul nou", comment: "Destination picker: a bill filed under a home goes to its subscription there.")
    }
    static var chosen: String { String(localized: "Ales", comment: "VoiceOver: the place chosen.") }

    /// A printed line, kept short enough to read in a row: cut at a word, with "…".
    static func shortened(_ text: String, limit: Int = 90) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }
}
