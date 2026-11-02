import SwiftUI

// Components for the binder screens: the home boxes, pocket cards, heroes,
// checkboxes, star ratings and full-width actions. Built only from DS tokens.

// MARK: - Category tint

extension TemplateTint {
    /// The system color for a category tint. System colors already carry dark mode
    /// and Increase Contrast variants, so nothing is hand-adjusted here.
    var color: Color {
        switch self {
        case .blue: .blue
        case .orange: .orange
        case .pink: .pink
        case .brown: .brown
        case .indigo: .indigo
        case .teal: .teal
        case .purple: .purple
        case .green: .green
        case .red: .red
        case .yellow: .yellow
        case .mint: .mint
        case .cyan: .cyan
        case .gray: .gray
        }
    }
}

// MARK: - Box status line

/// How a box status reads at a glance: an icon and a semantic color that always
/// travel with the words, so color is never the only signal.
enum DSBoxTone: Sendable, Equatable {
    case allGood
    case pending
    case alarming
    /// Neutral facts such as "12 contacte".
    case neutral

    var status: DSStatus? {
        switch self {
        case .allGood: .done
        case .pending: .soon
        case .alarming: .overdue
        case .neutral: nil
        }
    }

    var systemImage: String {
        switch self {
        case .allGood: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .alarming: "exclamationmark.circle.fill"
        case .neutral: "person.2.fill"
        }
    }
}

extension BoxStatus {
    var tone: DSBoxTone {
        if isAlarming { return .alarming }
        return entry == nil ? .allGood : .pending
    }
}

/// The one status line under a box or a hero.
struct DSStatusLine: View {
    let text: String
    let tone: DSBoxTone

    var body: some View {
        Label {
            Text(verbatim: text)
                .foregroundStyle(tone.status?.textColor ?? DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.status?.color ?? DS.Palette.secondaryLabel)
                .accessibilityHidden(true)
        }
        .labelStyle(DSLeadingIconLabelStyle())
        .dsFont(.subheadline, numeric: true)
        .fontWeight(tone == .alarming ? .semibold : .regular)
    }
}

/// Icon and text aligned on the first baseline, with a small gap.
struct DSLeadingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xxs + 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Example badge

/// Marks records created by "Încarcă exemple", so they are never mistaken for real data.
struct DSExampleBadge: View {
    var body: some View {
        Text("Exemplu", comment: "Badge on example data loaded to explore the app.")
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(DS.Palette.secondaryLabel)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 2)
            .background(DS.Palette.fillStrong, in: .capsule)
            .accessibilityLabel(Text("Date de exemplu", comment: "VoiceOver label of the example badge."))
    }
}

// MARK: - Home box

/// A big box on the Dosar grid: a photo or the category symbol, the name in large
/// type and one status line. The whole box is the tap target.
struct DSBox: View {
    let title: String
    let systemImage: String
    let tint: Color
    var photo: Image?
    let statusText: String
    let tone: DSBoxTone
    var isExample = false
    var isLocked = false

    @ScaledMetric(relativeTo: .title) private var wellSide: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .top) {
                artwork
                Spacer(minLength: DS.Space.xs)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .accessibilityHidden(true)
                } else if isExample {
                    DSExampleBadge()
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: title)
                .dsFont(.sectionTitle)
                .fontWeight(.bold)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            DSStatusLine(text: statusText, tone: tone)
                .lineLimit(3)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .containerShape(.rect(cornerRadius: DS.Radius.card, style: .continuous))
        .dsHairlineBorder(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: Text {
        var parts = [statusText]
        if isLocked { parts.append(String(localized: "Protejat cu Face ID", comment: "VoiceOver: the section is locked.")) }
        if isExample { parts.append(String(localized: "Date de exemplu", comment: "VoiceOver label of the example badge.")) }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    @ViewBuilder
    private var artwork: some View {
        if let photo {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: wellSide, height: wellSide)
                .clipShape(ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemImage)
                .font(.system(.title2, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: wellSide, height: wellSide)
                .background(tint.opacity(0.14), in: ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))
                .accessibilityHidden(true)
        }
    }
}

/// The last box on the grid: a dashed outline that adds a new section.
struct DSAddBox: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: "plus")
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .dsFont(.headline)
                .foregroundStyle(DS.Palette.accent)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, minHeight: 168)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Palette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .contentShape(.rect(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// MARK: - Pocket card

/// One pocket of a section page: a header with an optional count, two or three
/// rows separated by hairlines, and an optional full-width "Vezi tot" row.
struct DSPocketCard<Content: View, Footer: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.count = count
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader(verbatim: title, count: count)
            DSCard(padding: DS.Space.m) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    footer
                }
            }
        }
    }
}

extension DSPocketCard where Footer == EmptyView {
    init(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, count: count, content: content, footer: { EmptyView() })
    }
}

/// A hairline between rows inside a card, inset to the text.
struct DSRowSeparator: View {
    var body: some View {
        DS.Hairline()
            .padding(.vertical, DS.Space.xxs)
    }
}

/// The "Vezi tot" row at the bottom of a pocket: a whole row with a chevron.
struct DSSeeAllRow: View {
    var title: LocalizedStringKey = "Vezi tot"
    var count: Int?

    var body: some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
            Spacer(minLength: DS.Space.xs)
            if let count {
                Text(count, format: .number)
                    .dsFont(.subheadline, numeric: true)
            }
            Image(systemName: "chevron.forward")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

// MARK: - Full-width actions

/// A full-width button with a text label: primary actions use the prominent style.
struct DSWideButton: View {
    let title: Text
    var systemImage: String?
    var isProminent = true
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, isProminent: Bool = true, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.isProminent = isProminent
        self.role = role
        self.action = action
    }

    init(verbatim title: String, systemImage: String? = nil, isProminent: Bool = true, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.isProminent = isProminent
        self.role = role
        self.action = action
    }

    var body: some View {
        let button = Button(role: role, action: action) {
            Label {
                title.multilineTextAlignment(.center)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: DS.Radius.control + 2))
        if isProminent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

// MARK: - Checkbox

/// A plain checkbox with a title and a one-line explanation. The whole row toggles.
struct DSCheckboxRow<Detail: View>: View {
    let title: Text
    var explanation: Text?
    @Binding var isOn: Bool
    @ViewBuilder var detail: Detail

    init(title: Text, explanation: Text? = nil, isOn: Binding<Bool>, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.explanation = explanation
        self._isOn = isOn
        self.detail = detail()
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn ? DS.Palette.accent : DS.Palette.secondaryLabel)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title.dsFont(.headline)
                    if let explanation {
                        explanation.dsFont(.subheadline)
                    }
                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .padding(.vertical, DS.Space.xs)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.dsPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

extension DSCheckboxRow where Detail == EmptyView {
    init(title: Text, explanation: Text? = nil, isOn: Binding<Bool>) {
        self.init(title: title, explanation: explanation, isOn: isOn) { EmptyView() }
    }
}

// MARK: - Stars

/// A 1–5 rating. Read-only by default; with `onRate` every star is a 44 pt button
/// and tapping the current rating clears it.
struct DSStarRating: View {
    let rating: Double?
    var onRate: ((Int?) -> Void)?

    var body: some View {
        if let onRate {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        onRate(Int((rating ?? 0).rounded()) == value ? nil : value)
                    } label: {
                        star(for: value)
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel(Text("Nota \(value) din 5", comment: "VoiceOver: a star rating button."))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue(valueText)
            .sensoryFeedback(.selection, trigger: rating)
        } else {
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { value in
                    star(for: value).imageScale(.small)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(valueText)
        }
    }

    private func star(for value: Int) -> some View {
        let filled = (rating ?? 0) >= Double(value) - 0.25
        let half = !filled && (rating ?? 0) >= Double(value) - 0.75
        return Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
            .foregroundStyle(filled || half ? Color.yellow : DS.Palette.tertiaryLabel)
            .accessibilityHidden(true)
    }

    private var valueText: Text {
        if let rating {
            return Text("\(rating.formatted(.number.precision(.fractionLength(0...1)))) din 5 stele", comment: "VoiceOver value of a star rating.")
        }
        return Text("Fără notă", comment: "VoiceOver value of a rating that hasn't been given.")
    }
}

// MARK: - Plate

/// A Romanian registration plate: the blue EU band with "RO" and the number.
struct DSPlateBadge: View {
    let plate: String

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "RO")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
                .background(Color.blue)
            Text(verbatim: plate)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xxs)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.black.opacity(0.75), lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Număr de înmatriculare \(plate)", comment: "VoiceOver label of the plate badge."))
    }
}

// MARK: - Locked

/// The calm state a protected section shows until it is unlocked.
struct DSLockedState: View {
    let title: Text
    let systemImage: String
    let message: Text?
    let unlockTitle: Text
    var isWorking = false
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.Palette.accent)
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                title
                    .dsFont(.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    message
                        .dsFont(.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
            }
            Button(action: unlock) {
                unlockTitle
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Secret field

/// A field for a secret such as an API key: hidden while typing, pasted more
/// often than typed, never autocorrected.
struct DSSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey?
    var footnote: LocalizedStringKey?

    @FocusState private var isFocused: Bool

    init(_ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey? = nil, footnote: LocalizedStringKey? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.footnote = footnote
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: isFocused,
            validation: .valid,
            footnote: footnote.map { Text($0) },
            focus: { isFocused = true }
        ) {
            SecureField(title, text: $text, prompt: prompt.map { Text($0) })
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .focused($isFocused)
        }
    }
}

// MARK: - Value row

/// A label and a value on one card row, with the value in tabular digits.
/// At accessibility sizes the value moves under the label.
struct DSValueRow: View {
    let label: Text
    let value: Text
    var systemImage: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    label.dsFont(.subheadline)
                    value.dsFont(.headline, numeric: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    label.dsFont(.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    Spacer(minLength: DS.Space.xs)
                    value.dsFont(.headline, numeric: true)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, DS.Space.xs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
