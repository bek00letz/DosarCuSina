import SwiftUI

/// Calendar-day arithmetic for due and expiry dates. Pure so it can be unit tested.
enum DSDayMath {
    /// Whole calendar days from `today` to `date` (negative when `date` is in the past),
    /// counted between the starts of the two days so the time of day never matters.
    static func daysRemaining(until date: Date, from today: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

extension DSDueText {
    /// Wording for documents and warranties: "Expiră în 20 de zile", "Expirat de 3 zile", "Valabil".
    static func expiryText(daysRemaining days: Int, soonWithinDays: Int) -> LocalizedStringResource {
        switch days {
        case ..<0:
            let ago = -days
            return LocalizedStringResource("Expirat de \(ago) zile", comment: "Badge: a document expired this many days ago.")
        case 0:
            return LocalizedStringResource("Expiră azi", comment: "Badge: a document expires today.")
        case 1...soonWithinDays:
            return LocalizedStringResource("Expiră în \(days) zile", comment: "Badge: a document expires in this many days.")
        default:
            return LocalizedStringResource("Valabil", comment: "Badge: a document is valid and not close to expiring.")
        }
    }
}

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

/// An expiry date that shows at a glance whether it's still valid.
/// `soonWithinDays` sets when the warning starts, e.g. 180 for passports (the 6-month travel rule).
struct DSExpiryDateField: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    var soonWithinDays: Int = 30
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?

    @Environment(\.dsRevealsValidation) private var revealsValidation
    @Environment(\.calendar) private var calendar

    init(
        _ title: LocalizedStringKey,
        date: Binding<Date?>,
        soonWithinDays: Int = 30,
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil
    ) {
        self.title = title
        self._date = date
        self.soonWithinDays = soonWithinDays
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
                    let days = DSDayMath.daysRemaining(until: date, calendar: calendar)
                    DSStatusBadge(
                        days < 0 ? .overdue : (days <= soonWithinDays ? .soon : .done),
                        text: Text(DSDueText.expiryText(daysRemaining: days, soonWithinDays: soonWithinDays))
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
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
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
