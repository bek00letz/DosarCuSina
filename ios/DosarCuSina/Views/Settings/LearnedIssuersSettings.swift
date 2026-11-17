import SwiftData
import SwiftUI

/// „Ce am învățat”: the issuers capture learned of from papers the person saved, each with the
/// labels it prints its values under, in plain words. Swiping a row forgets that issuer, and
/// the toast's "Anulează" brings it back (`IssuerLessons.forget`).
struct LearnedIssuersSettings: View {
    /// Settings' toast: forgetting an issuer can be taken back from it.
    @Binding var toast: DSToast?
    @Environment(\.modelContext) private var context
    @Query private var lessons: [IssuerLesson]
    @State private var error: UserFacingError?

    var body: some View {
        let issuers = IssuerLessons.issuers(lessons)
        Section {
            if issuers.isEmpty {
                Text("Când salvezi un act pe care nu l-am citit întreg, țin minte unde scrie fiecare valoare pe actele firmei care l-a emis. Pe următorul îl citesc singur, pe telefon.",
                     comment: "Settings: nothing learned from saved papers yet, and what learning does.")
                    .dsFont(.subheadline)
                    .frame(minHeight: 44, alignment: .leading)
            }
            ForEach(issuers) { issuer in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: issuer.name)
                        .dsFont(.body)
                    ForEach(issuer.lessons, id: \.self) { lesson in
                        Text(verbatim: IssuerWording.lesson(lesson))
                            .dsFont(.subheadline)
                    }
                }
                .padding(.vertical, DS.Space.xs)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { forget(issuer) } label: {
                        Text("Uită", comment: "Swipe action: forget what was learned of an issuer's papers.")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) { forget(issuer) } label: {
                        Label { Text("Uită ce am învățat", comment: "Menu: forget what was learned of an issuer's papers.") } icon: { Image(systemName: "trash") }
                    }
                }
            }
        } header: {
            // On the header, the one view of the section that stays: a modifier on the Section
            // would reach every row (`presentation-on-section`).
            Text("Ce am învățat", comment: "Settings page and section: what capture learned from the papers the person saved, by issuer.")
                .userErrorAlert($error)
        } footer: {
            Text("Țin minte doar cuvintele și așezarea actelor unei firme, nimic despre tine. Se sincronizează cu dosarul.",
                 comment: "Footer of what capture learned: only an issuer's words and layout are kept, and they sync with the binder.")
        }
    }

    private func forget(_ issuer: IssuerLessons.Issuer) {
        do {
            let receipt = try IssuerLessons(context: context).forget(issuer.key)
            toast = .undoDeletion(LocalizedStringResource("Am uitat ce știam despre „\(issuer.name)”.", comment: "Toast after forgetting what was learned of an issuer's papers."),
                                  receipt: receipt)
        } catch {
            self.error = UserFacingError(error)
        }
    }
}
