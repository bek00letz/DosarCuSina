import SwiftUI
import SwiftData

/// "Mută la…": a short list of the places something filed under another can
/// go (the other household members, the other homes), plus "O persoană nouă"
/// for a document. A document named after its holder offers to take the new
/// holder's name. Moving saves at once; the page underneath offers the undo.
struct MoveAssetSheet: View {
    let asset: Asset
    /// Called after the move is saved, with what to take back.
    let onMoved: (Moved) -> Void

    /// A move just saved: its receipt, the name before it, and the toast's words.
    struct Moved {
        let receipt: UndoReceipt
        let previousName: String
        /// "Mutat la „Manole Corina”", for the toast with the undo.
        let toastTitle: LocalizedStringResource
    }

    private enum Choice: Hashable {
        case asset(UUID)
        case newMember
        case standalone
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Asset.name) private var assets: [Asset]

    @State private var choice: Choice?
    @State private var newMemberName = ""
    @State private var renames = true
    @State private var reveals = false
    @State private var error: UserFacingError?

    private var destinations: [Asset] { AssetActions.moveDestinations(for: asset, among: assets) }
    private var offersNewMember: Bool { AssetActions.offersNewMember(for: asset) }
    private var offersStandalone: Bool { AssetActions.offersStandalone(for: asset) }

    /// The holder's name the document would move to, for the rename offer.
    private var newHolderName: String? {
        switch choice {
        case .asset(let id)?: return destinations.first { $0.id == id }?.name
        case .newMember?:
            let name = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        case .standalone?, nil: return nil
        }
    }

    private var proposedName: String? {
        newHolderName.flatMap { AssetActions.renamedForHolder(asset, newHolder: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if destinations.isEmpty && !offersNewMember && !offersStandalone {
                    DSEmptyState(
                        "Nu ai unde să-l muți",
                        systemImage: "arrow.turn.up.right",
                        message: "Mai adaugă una de același fel în Dosar, apoi îl poți muta acolo."
                    )
                } else {
                    list
                }
            }
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, reveals)
            .navigationTitle(Text("Mută la…", comment: "Title of the sheet that files something under another parent."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .userErrorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if let parent = asset.parent {
                    Text("Acum e la „\(parent.name)”.", comment: "Where the item is filed now, in the move sheet.")
                        .dsFont(.subheadline)
                }
                DSCard {
                    VStack(spacing: 0) {
                        ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                            if index > 0 { DSRowSeparator() }
                            DSCheckRow(title: Text(verbatim: destination.name), isOn: choice == .asset(destination.id)) {
                                choice = .asset(destination.id)
                            }
                            .padding(.vertical, DS.Space.xxs)
                        }
                        if offersStandalone {
                            if !destinations.isEmpty { DSRowSeparator() }
                            DSCheckRow(
                                title: Text("În Abonamente, fără locuință", comment: "Move option: a subscription stands on its own, like a phone plan."),
                                isOn: choice == .standalone
                            ) {
                                choice = .standalone
                            }
                            .padding(.vertical, DS.Space.xxs)
                        }
                        if offersNewMember {
                            if !destinations.isEmpty { DSRowSeparator() }
                            DSCheckRow(
                                title: Text("O persoană nouă", comment: "Move option: file the document under a new household member."),
                                isOn: choice == .newMember,
                                action: { choice = .newMember }
                            ) {
                                DSTextField("Numele persoanei", text: $newMemberName, prompt: "Nume și prenume", isRequired: true,
                                            footnote: "Numele de familie întâi, ca în acte.")
                                    .padding(.bottom, DS.Space.s)
                            }
                            .padding(.vertical, DS.Space.xxs)
                        }
                    }
                }
                if let proposedName {
                    DSCard {
                        DSCheckRow(
                            title: Text("Schimbă și numele", comment: "Move option: rename a document after its new holder."),
                            subtitle: Text("„\(proposedName)”", comment: "The name a moved document would take."),
                            isOn: $renames
                        )
                    }
                    .transition(.opacity)
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .dsAnimation(value: proposedName)
        }
        .scrollDismissesKeyboard(.interactively)
        .dsPinnedAction {
            DSPrimaryButton("Mută aici", systemImage: "arrow.turn.up.right") { move() }
                .disabled(choice == nil)
        }
    }

    private func move() {
        let target: AssetActions.MoveTarget
        switch choice {
        case .asset(let id)?:
            target = .asset(id)
        case .newMember?:
            guard newHolderName != nil else { reveals = true; return }
            target = .newMember(name: newMemberName)
        case .standalone?:
            target = .standalone
        case nil:
            return
        }
        do {
            let previousName = asset.name
            let receipt = try AssetActions(context: context).move(asset, to: target, renamingTo: renames ? proposedName : nil)
            dismiss()
            onMoved(Moved(receipt: receipt, previousName: previousName, toastTitle: toastTitle))
        } catch {
            self.error = UserFacingError(error)
        }
    }

    /// Where it is now, for the toast.
    private var toastTitle: LocalizedStringResource {
        guard let place = asset.parent?.name else {
            return LocalizedStringResource("Mutat în Abonamente", comment: "Toast after a subscription was taken out of its home.")
        }
        return LocalizedStringResource("Mutat la „\(place)”", comment: "Toast after moving something under another parent.")
    }
}
