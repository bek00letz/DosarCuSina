import SwiftData
import SwiftUI

/// „Ce am învățat”: the issuers capture learned of from papers the person saved, each with the
/// labels it prints its values under, in plain words. Swiping a row forgets that issuer, and
/// the toast's "Anulează" brings it back (`IssuerLessons.forget`). An issuer learned of only from
/// papers of locked categories (`IssuerLessons.Issuer.isProtected`) shows without its name or
/// labels until Face ID opens the binder, as anything else of a locked category does.
struct LearnedIssuersSettings: View {
    /// Settings' toast: forgetting an issuer can be taken back from it.
    @Binding var toast: DSToast?
    @Environment(\.modelContext) private var context
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var lessons: [IssuerLesson]
    /// The categories and the sections, for the binder's locks (`BinderLocks`).
    @Query private var templates: [CategoryTemplate]
    @Query(BinderLocks.sections) private var sections: [Asset]
    @State private var error: UserFacingError?

    var body: some View {
        let locks = IssuerLessons.locks(templates: templates, sections: sections, lessons: lessons, in: context.container)
        let issuers = IssuerLessons.issuers(lessons, locks: locks)
        Section {
            if issuers.isEmpty {
                Text("Când salvezi un act pe care nu l-am citit întreg, țin minte unde scrie fiecare valoare pe actele firmei care l-a emis. Pe următorul îl citesc singur, pe telefon.",
                     comment: "Settings: nothing learned from saved papers yet, and what learning does.")
                    .dsFont(.subheadline)
                    .frame(minHeight: 44, alignment: .leading)
            }
            ForEach(issuers) { issuer in
                if vault.isLocked(sectionIsSensitive: issuer.isProtected) {
                    protectedRow
                } else {
                    issuerRow(issuer)
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

    /// An issuer learned of only from a locked category's papers, before Face ID: nothing of it
    /// shows; a tap unlocks.
    private var protectedRow: some View {
        Button(action: unlock) {
            DSListRow(
                title: Text("Firmă dintr-o categorie protejată", comment: "Settings: an issuer learned of from papers of a locked category, before Face ID."),
                subtitle: Text("Deblochează ca să vezi ce am învățat.", comment: "Settings: unlock to see what was learned of an issuer from a locked category's papers."),
                systemImage: "lock.fill",
                trailing: { EmptyView() }
            )
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func issuerRow(_ issuer: IssuerLessons.Issuer) -> some View {
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

    private func unlock() {
        Task {
            _ = await vault.unlock(reason: String(localized: "Vezi ce am învățat din documentele protejate",
                                                  comment: "Face ID reason: show what was learned from papers of locked categories in Settings."))
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
