import SwiftData
import SwiftUI

/// The repair list: each thing an earlier version saved wrongly, in plain words, with
/// "Corectează" and "Lasă așa", one by one or all of one kind. Nothing changes without a tap,
/// and "Lasă așa" is remembered.
struct DataRepairsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var center = DataRepairCenter.shared
    @State private var error: UserFacingError?
    @State private var doneCount = 0

    var body: some View {
        List {
            ForEach(center.groups, id: \.title) { group in
                Section {
                    ForEach(group.findings) { finding in
                        DataRepairRow(finding: finding, apply: { apply([finding]) }, dismiss: { dismiss([finding]) })
                    }
                } header: {
                    HStack {
                        Text(verbatim: group.title)
                        Spacer()
                        if group.findings.count > 1 {
                            Menu {
                                Button { apply(group.findings) } label: {
                                    Text("Corectează toate", comment: "Applies every repair of one kind.")
                                }
                                Button { dismiss(group.findings) } label: {
                                    Text("Lasă-le pe toate așa", comment: "Dismisses every repair of one kind.")
                                }
                            } label: {
                                Text("Toate", comment: "Menu with actions for every repair of one kind.")
                                    .frame(minHeight: 44)
                                    .contentShape(.rect)
                            }
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .overlay {
            if center.pending.isEmpty {
                DSEmptyState("Totul arată bine", systemImage: "checkmark.seal",
                             message: "Nu am găsit nimic salvat greșit de o versiune mai veche.")
            }
        }
        .navigationTitle(Text("Date de verificat", comment: "Title of the repair list."))
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .sensoryFeedback(.success, trigger: doneCount)
        .userErrorAlert($error)
    }

    private func refresh() {
        do {
            try center.refresh(in: context, announce: false)
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func apply(_ findings: [DataRepairFinding]) {
        do {
            try withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
                try center.apply(findings, in: context)
            }
            doneCount += 1
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Nu am putut corecta", comment: "Title of a repair error."))
        }
    }

    private func dismiss(_ findings: [DataRepairFinding]) {
        do {
            try withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
                try center.dismiss(findings, in: context)
            }
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// One finding: what looks wrong, as a question, and its two answers.
private struct DataRepairRow: View {
    let finding: DataRepairFinding
    let apply: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(verbatim: finding.message)
                .dsFont(.body)
                .fixedSize(horizontal: false, vertical: true)
            DSAdaptiveStack(spacing: DS.Space.s, stackedSpacing: DS.Space.xs) { buttons }
        }
        .padding(.vertical, DS.Space.xs)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: apply) {
            Text("Corectează", comment: "Applies one repair from the repair list.")
                .lineLimit(1)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        Button(action: dismiss) {
            Text("Lasă așa", comment: "Dismisses one repair; it isn't offered again.")
                .lineLimit(1)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

/// The row in Settings that opens the repair list, with how many things wait.
struct DataRepairSettings: View {
    @Binding var isShowingList: Bool
    @State private var center = DataRepairCenter.shared

    var body: some View {
        Section {
            Button { isShowingList = true } label: {
                LabeledContent {
                    if !center.pending.isEmpty {
                        Text(center.pending.count, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                } label: {
                    Label { Text("Date de verificat", comment: "Settings row that opens the repair list.") } icon: { Image(systemName: "wrench.and.screwdriver") }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .foregroundStyle(DS.Palette.label)
        } header: {
            Text("Date salvate greșit", comment: "Settings section: the repair list.")
        } footer: {
            Text("Când o versiune mai veche a salvat ceva greșit, îl găsești aici. Nu schimb nimic fără tine.", comment: "Footer of the repair list setting.")
        }
    }
}

extension View {
    /// The calm prompt after launch or an import, when the repair list has something new:
    /// "Am găsit date de verificat", the first thing in words, "Arată-mi" or "Mai târziu".
    /// Shown only when nothing else is in front (no sheet, no lock, onboarding done).
    func dataRepairPrompt(isAllowed: Bool, onShow: @escaping () -> Void) -> some View {
        modifier(DataRepairPromptModifier(isAllowed: isAllowed, onShow: onShow))
    }
}

private struct DataRepairPromptModifier: ViewModifier {
    let isAllowed: Bool
    let onShow: () -> Void
    @State private var center = DataRepairCenter.shared

    func body(content: Content) -> some View {
        content.alert(
            Text("Am găsit date de verificat", comment: "Title of the prompt that opens the repair list."),
            isPresented: Binding(get: { isAllowed && !center.announcement.isEmpty }, set: { if !$0 { center.announcement = [] } })
        ) {
            Button { onShow() } label: { Text("Arată-mi", comment: "Opens the repair list from the prompt.") }
            Button(role: .cancel) {} label: { Text("Mai târziu", comment: "Closes the repair prompt; the list stays in Settings.") }
        } message: {
            Text(verbatim: message)
        }
    }

    private var message: String {
        let first = center.announcement.first?.message ?? ""
        let rest = center.announcement.count > 1
            ? String(localized: "Mai sunt și alte lucruri în listă.", comment: "Repair prompt: more than one finding.")
            : ""
        let promise = String(localized: "Nu schimb nimic fără tine.", comment: "Repair prompt: nothing changes without the owner.")
        return [first, rest, promise].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
