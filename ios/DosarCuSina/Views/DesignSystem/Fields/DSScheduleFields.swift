import SwiftUI

/// "Se repetă": never, or every so many days, weeks, months or years, counted from the due day
/// or from the day it was done (`RepeatChoice`). The one control for how a deadline repeats, in
/// the deadline form and on the deadline's page. Words come from `RepeatWording`.
struct DSRepeatField: View {
    let title: LocalizedStringKey
    @Binding var choice: RepeatChoice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: LocalizedStringKey = "Se repetă", choice: Binding<RepeatChoice>) {
        self.title = title
        self._choice = choice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSChoiceField(title, selection: frequency, options: RepeatChoice.Frequency.allCases, isRequired: true) {
                RepeatWording.title(of: $0)
            }
            if let unit = choice.frequency.unit {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Stepper(value: $choice.every, in: choice.everyRange) {
                        Text(verbatim: RepeatWording.every(choice.every, unit))
                            .dsFont(.headline, numeric: true)
                    }
                    .frame(minHeight: DS.Control.minimumHitTarget)
                    .accessibilityValue(Text(verbatim: RepeatWording.every(choice.every, unit)))
                    DS.Hairline()
                    ForEach(RepeatWording.anchors, id: \.self) { anchor in
                        DSCheckRow(title: Text(verbatim: RepeatWording.title(of: anchor)),
                                   subtitle: Text(verbatim: RepeatWording.detail(of: anchor, every: choice.every, unit)),
                                   isOn: choice.anchor == anchor) {
                            choice.anchor = anchor
                        }
                    }
                }
                .transition(DS.Motion.transition(from: .top, reduceMotion: reduceMotion))
            }
        }
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: choice.repeats)
        .sensoryFeedback(.selection, trigger: choice.every)
    }

    /// The frequency menu writes through `RepeatChoice.choosing`, which keeps the number and
    /// what it counts from where it can.
    private var frequency: Binding<RepeatChoice.Frequency?> {
        Binding { choice.frequency } set: { newValue in
            if let newValue { choice = choice.choosing(newValue) }
        }
    }
}

/// "Ora amintirii": the general reminder time from Settings ("Ora obișnuită (09:00)"), or a
/// time of this deadline's own. Nil is the general time, so a change in Settings reaches it.
///
/// `startsCollapsed`: while it is the general time, the field is one row ("Ora amintirii ·
/// Ora obișnuită (09:00)", *Schimbă*) that opens to the two choices; a time of its own shows
/// them from the start. The deadline form and the deadline's "Editează" use it so.
struct DSReminderTimeField: View {
    @Binding var minuteOfDay: Int?
    /// The general time from Settings, shown on the first choice.
    let usualMinuteOfDay: Int

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen: Bool

    init(minuteOfDay: Binding<Int?>, usualMinuteOfDay: Int, startsCollapsed: Bool = false) {
        self._minuteOfDay = minuteOfDay
        self.usualMinuteOfDay = usualMinuteOfDay
        self._isOpen = State(initialValue: !startsCollapsed || minuteOfDay.wrappedValue != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if isOpen {
                choices
                    .transition(.opacity)
            } else {
                collapsed
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: isOpen)
    }

    /// One row while it is the general time: what it is, and *Schimbă*.
    private var collapsed: some View {
        let usual = ReminderWording.time(nil, usual: usualMinuteOfDay, calendar: calendar)
        return Button { isOpen = true } label: {
            DSListRow(title: Text("Ora amintirii", comment: "A deadline's reminder time: the general one, or its own."),
                      subtitle: Text(verbatim: usual), systemImage: "clock") {
                Text("Schimbă", comment: "Opens the reminder time choices of a deadline.")
                    .foregroundStyle(DS.Palette.accent)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.dsPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ora amintirii"))
        .accessibilityValue(Text(verbatim: usual))
        .accessibilityHint(Text("Alege o oră doar pentru acest termen.", comment: "VoiceOver hint of the collapsed reminder time row."))
        .accessibilityAddTraits(.isButton)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Ora amintirii", comment: "A deadline's reminder time: the general one, or its own.")
                .dsFont(.captionEmphasized)
                .accessibilityAddTraits(.isHeader)
            DSCheckRow(title: Text("Ora obișnuită (\(DosarFormat.time(minuteOfDay: usualMinuteOfDay, calendar: calendar)))",
                                   comment: "Reminder time choice: the general time from Settings, e.g. „Ora obișnuită (09:00)”."),
                       subtitle: Text("Cea din Setări. Dacă o schimbi acolo, se schimbă și aici.", comment: "Explains the general reminder time."),
                       isOn: minuteOfDay == nil) {
                minuteOfDay = nil
            }
            DSCheckRow(title: Text("Altă oră", comment: "Reminder time choice: a time of this deadline's own."),
                       isOn: minuteOfDay != nil) {
                if minuteOfDay == nil { minuteOfDay = usualMinuteOfDay }
            } detail: {
                DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                    Text("Ora", comment: "Label of the time picker for a deadline's own reminder time.")
                }
                .frame(minHeight: DS.Control.minimumHitTarget)
            }
        }
    }

    private var time: Binding<Date> {
        Binding {
            ReminderClock.moment(minuteOfDay: minuteOfDay ?? usualMinuteOfDay, calendar: calendar)
        } set: { date in
            minuteOfDay = ReminderClock.minuteOfDay(of: date, calendar: calendar)
        }
    }
}
