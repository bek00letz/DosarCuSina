import SwiftUI

/// An optional date. Empty until the person adds one, and it can be cleared again.
struct DSDateField: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    var range: ClosedRange<Date>?
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?
    var validator: ((Date) -> DSValidation)?

    @Environment(\.dsRevealsValidation) private var revealsValidation

    init(
        _ title: LocalizedStringKey,
        date: Binding<Date?>,
        in range: ClosedRange<Date>? = nil,
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil,
        validator: ((Date) -> DSValidation)? = nil
    ) {
        self.title = title
        self._date = date
        self.range = range
        self.isRequired = isRequired
        self.footnote = footnote
        self.validator = validator
    }

    private var validation: DSValidation {
        guard let date else { return isRequired && revealsValidation ? .requiredMissing : .valid }
        return validator?(date) ?? .valid
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: false,
            validation: validation,
            footnote: footnote.map { Text($0) }
        ) {
            DSDateInput(title: title, date: $date, range: range) { EmptyView() }
        }
        .dsValidationFeedback(validation)
    }
}

/// An expiry date that shows at a glance whether it's still valid. `urgencyRule` is
/// the rule of the deadline this date drives (from its reminders), so the badge here
/// says what Urmează and the section's page will say.
struct DSExpiryDateField: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    var urgencyRule: UrgencyRule = .noReminders
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?

    @Environment(\.dsRevealsValidation) private var revealsValidation
    @Environment(\.calendar) private var calendar

    init(
        _ title: LocalizedStringKey,
        date: Binding<Date?>,
        urgencyRule: UrgencyRule = .noReminders,
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil
    ) {
        self.title = title
        self._date = date
        self.urgencyRule = urgencyRule
        self.isRequired = isRequired
        self.footnote = footnote
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: false,
            validation: date == nil && isRequired && revealsValidation ? .requiredMissing : .valid,
            footnote: footnote.map { Text($0) }
        ) {
            DSDateInput(title: title, date: $date, range: nil) {
                if let date {
                    let today = CalendarDay(Date(), calendar: calendar)
                    let day = CalendarDay(date, calendar: calendar)
                    DSStatusBadge(
                        expiry: urgencyRule.urgency(of: day, today: today, calendar: calendar),
                        daysRemaining: today.days(to: day, calendar: calendar)
                    )
                    .transition(.opacity)
                }
            }
        }
    }
}

/// The inside of a date field: an "add" button when empty, otherwise a compact picker,
/// a trailing accessory (such as a status badge) and a clear button.
private struct DSDateInput<Accessory: View>: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    var range: ClosedRange<Date>?
    @ViewBuilder var accessory: Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if let current = date {
                picker(selection: Binding(get: { current }, set: { date = $0 }))
                    .labelsHidden()
                    .accessibilityLabel(Text(title))
                Spacer(minLength: 0)
                accessory
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Șterge data", comment: "Button that removes the date from a date field."))
            } else {
                Button {
                    let today = calendar.startOfDay(for: .now)
                    date = range.map { min(max(today, $0.lowerBound), $0.upperBound) } ?? today
                } label: {
                    Label {
                        Text("Adaugă data", comment: "Button in an empty date field.")
                    } icon: {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.Control.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityHint(Text(title))
            }
        }
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: date == nil)
    }

    @ViewBuilder
    private func picker(selection: Binding<Date>) -> some View {
        if let range {
            DatePicker(selection: selection, in: range, displayedComponents: .date) { Text(title) }
                .datePickerStyle(.compact)
        } else {
            DatePicker(selection: selection, displayedComponents: .date) { Text(title) }
                .datePickerStyle(.compact)
        }
    }
}
