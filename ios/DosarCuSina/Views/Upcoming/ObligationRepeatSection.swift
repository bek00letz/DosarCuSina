import SwiftData
import SwiftUI

/// "Cum se repetă" on a deadline's page: how it repeats, in words, and, for a deadline that
/// repeats every so many days, weeks, months or years (or not at all), "Schimbă cum se
/// repetă". A rule on fixed dates, by a counter or by law is shown in words only: its
/// category decides it (`CategorySwitches`, the built-in templates).
struct ObligationRepeatSection: View {
    let obligation: Obligation
    @Binding var toast: DSToast?

    @State private var isEditing = false

    var body: some View {
        let rule = obligation.recurrence
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Cum se repetă")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: RepeatWording.sentence(rule))
                        .dsFont(.headline)
                    if RepeatChoice(rule: rule) != nil {
                        DS.Hairline().padding(.vertical, DS.Space.xxs)
                        Button { isEditing = true } label: {
                            DSListRow("Schimbă cum se repetă", systemImage: "repeat", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            RepeatSettingsSheet(obligation: obligation) { result in
                isEditing = false
                if let result { toast = result }
            }
        }
    }
}

/// "Schimbă cum se repetă": the shared control (`DSRepeatField`) over the deadline's rule as it
/// opened, saved once with "Salvează" as one undoable step. The due day stays; the new rule
/// counts from the next time it is done.
private struct RepeatSettingsSheet: View {
    let obligation: Obligation
    let onClose: (DSToast?) -> Void

    @Environment(\.modelContext) private var context
    /// The rule the sheet opened with: only what the person changed is laid over the rule as it
    /// is when they save (`ObligationActions.setRecurrence(_:_:startedFrom:)`).
    private let start: RecurrenceRule
    @State private var choice: RepeatChoice
    @State private var errorMessage: String?

    init(obligation: Obligation, onClose: @escaping (DSToast?) -> Void) {
        self.obligation = obligation
        self.onClose = onClose
        self.start = obligation.recurrence
        self._choice = State(initialValue: RepeatChoice(rule: obligation.recurrence) ?? .never)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSCard { DSRepeatField(choice: $choice) }
                    Text("Termenul de acum rămâne pe \(DosarFormat.longDay(obligation.dueDay)). Regula nouă se aplică după ce îl bifezi.",
                         comment: "Under the repeat control on a deadline's page: the current due day stays.")
                        .dsFont(.footnote)
                        .padding(.horizontal, DS.Space.xs)
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .dsPinnedAction {
                DSPrimaryButton("Salvează", systemImage: "checkmark", action: save)
            } note: {
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage))
                }
            }
            .navigationTitle("Cum se repetă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
            .dsDiscardGuard(hasChanges: choice.rule != start)
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard choice.rule != start else { onClose(nil); return }
        do {
            let receipt = try ObligationActions(context: context).setRecurrence(obligation, choice.rule, startedFrom: start)
            onClose(.undo("\(RepeatWording.sentence(obligation.recurrence))", receipt: receipt))
        } catch {
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
    }
}
