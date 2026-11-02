import SwiftUI
import SwiftData

/// The top of a section page. Mainstay categories get a purpose-built hero
/// (`HeroStyle`); everything else gets the standard one built from field roles.
struct SectionHero: View {
    let asset: Asset
    let definition: TemplateDefinition

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar

    var body: some View {
        DSCard(padding: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                header
                details
                statusLine
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            artwork
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(verbatim: asset.name)
                    .dsFont(.display)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = HeroFacts.subtitle(asset.values, definition: definition) {
                    Text(verbatim: subtitle)
                        .dsFont(.subheadline, numeric: true)
                }
                if asset.isExample { DSExampleBadge() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let tint = asset.tintOverride?.color ?? definition.tint.color
        if let photo = asset.thumbnail(side: 200) {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(definition.heroStyle == .pet ? AnyShape(.circle) : AnyShape(ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)))
                .accessibilityLabel(Text("Poza lui „\(asset.name)”", comment: "VoiceOver label of a section photo."))
        } else {
            Image(systemName: asset.symbolOverride ?? definition.symbol)
                .font(.system(.largeTitle, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(tint.opacity(0.14), in: ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))
                .accessibilityHidden(true)
        }
    }

    // MARK: Details per hero style

    @ViewBuilder
    private var details: some View {
        switch definition.heroStyle {
        case .vehicle:
            vehicleDetails
        case .home:
            homeDetails
        case .pet:
            petDetails
        case .document:
            documentDetails
        case .standard:
            if asset.templateKey == BuiltInTemplates.Key.member {
                memberDetails
            } else {
                standardDetails
            }
        }
    }

    private var vehicleDetails: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let plate = AssetFacts.text(.identifier, in: asset.values, template: definition) {
                DSPlateBadge(plate: FieldFormatter.formatPlate(plate) ?? plate)
            }
            metricTile
        }
    }

    @ViewBuilder
    private var metricTile: some View {
        if let field = definition.fields(withRole: .heroMetric).first, let value = asset.value(field.key) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: field.label)
                    .dsFont(.captionEmphasized)
                Text(verbatim: FieldFormatter.display(value, field: field))
                    .dsFont(.title, numeric: true)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var homeDetails: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let address = AssetFacts.text(.location, in: asset.values, template: definition) {
                Label {
                    Text(verbatim: address)
                        .dsFont(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(DS.Palette.secondaryLabel)
                }
                .labelStyle(DSLeadingIconLabelStyle())
                .accessibilityLabel(Text("Adresa: \(address)", comment: "VoiceOver label of a home's address."))
            }
            if let window = HeroFacts.meterWindow(asset.values) {
                Label {
                    Text(verbatim: window).dsFont(.subheadline, numeric: true)
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(DS.Palette.secondaryLabel)
                }
                .labelStyle(DSLeadingIconLabelStyle())
            }
        }
    }

    @ViewBuilder
    private var petDetails: some View {
        let facts = [
            AssetFacts.fields(.startDate, in: asset.values, template: definition).first?.dateValue
                .flatMap { AgeWording.text(born: $0, today: CalendarDay(Date(), calendar: calendar), calendar: calendar) },
            definition.fields(withRole: .heroMetric).first.flatMap { field in asset.value(field.key).map { FieldFormatter.display($0, field: field) } },
        ].compactMap { $0 }
        if !facts.isEmpty {
            Text(verbatim: facts.joined(separator: " · "))
                .dsFont(.headline, numeric: true)
        }
    }

    @ViewBuilder
    private var documentDetails: some View {
        if let expiry = AssetFacts.expiry(asset.values, template: definition) ?? AssetFacts.purchase(asset.values, template: definition).warrantyUntil {
            ExpiryLine(label: definition.key == BuiltInTemplates.Key.purchase
                       ? String(localized: "Garanție până la", comment: "Hero: warranty end date.")
                       : String(localized: "Valabil până la", comment: "Hero: document valid until."),
                       day: expiry)
        }
        if let holder = asset.parent {
            Label {
                Text(verbatim: holder.name).dsFont(.subheadline)
            } icon: {
                Image(systemName: "person.fill").foregroundStyle(DS.Palette.secondaryLabel)
            }
            .labelStyle(DSLeadingIconLabelStyle())
        }
    }

    @ViewBuilder
    private var memberDetails: some View {
        let documents = (asset.children ?? []).filter { $0.templateKey == BuiltInTemplates.Key.documents }
        let next = documents
            .compactMap { child in child.value("document.expiry")?.dateValue.map { (child, $0) } }
            .min { $0.1 < $1.1 }
        if let next {
            ExpiryLine(label: String(localized: "Următorul act care expiră: \(next.0.name)", comment: "Hero of a person: the next document to expire."), day: next.1)
        } else {
            Text("Niciun act cu dată de expirare încă.", comment: "Hero of a person with no documents.")
                .dsFont(.subheadline)
        }
    }

    @ViewBuilder
    private var standardDetails: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let identifier = AssetFacts.text(.identifier, in: asset.values, template: definition) {
                Text(verbatim: identifier)
                    .font(.body.monospaced())
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            metricTile
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        let snapshots = (try? ObligationSnapshot.fetchAll(in: context)) ?? []
        let descendants = Set(AssetActions.descendants(of: asset).map(\.id))
        let status = BoxStatus.make(forAsset: asset.id, descendants: descendants, in: snapshots)
        DS.Hairline()
        DSStatusLine(text: status.line(isSensitive: false), tone: status.tone)
    }
}

/// "Valabil până la 14 mar. 2027" with a badge saying how far that is.
struct ExpiryLine: View {
    let label: String
    let day: CalendarDay
    @Environment(\.calendar) private var calendar

    var body: some View {
        let date = day.startDate(in: calendar)
        let days = DSDayMath.daysRemaining(until: date, calendar: calendar)
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(verbatim: label).dsFont(.captionEmphasized)
            Text(date, format: .dateTime.day().month(.wide).year())
                .dsFont(.title, numeric: true)
            DSStatusBadge(
                days < 0 ? .overdue : (days <= 60 ? .soon : .done),
                text: Text(DSDueText.expiryText(daysRemaining: days, soonWithinDays: 60))
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// Facts the heroes read from field roles, so templates stay data.
enum HeroFacts {
    /// The subtitle fields in order: "Volkswagen Golf · 2018". Numbers without a
    /// unit (a year) are written without thousands separators.
    static func subtitle(_ values: FieldValues, definition: TemplateDefinition, locale: Locale = .dosarDefault) -> String? {
        var words: [String] = []
        var numbers: [String] = []
        for field in definition.fields(withRole: .subtitle) {
            guard let value = values[field.key] else { continue }
            if case .number(let number) = value, field.unit == nil {
                numbers.append(number.formatted(.number.grouping(.never).precision(.fractionLength(0)).locale(locale)))
            } else {
                words.append(FieldFormatter.display(value, field: field, locale: locale))
            }
        }
        let parts = [words.joined(separator: " ")].filter { !$0.isEmpty } + numbers
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Autocitire între 15 și 20 ale lunii", from the home template's meter-reading days.
    static func meterWindow(_ values: FieldValues) -> String? {
        guard let from = values["home.meterReadFrom"]?.numberValue, let to = values["home.meterReadTo"]?.numberValue else { return nil }
        return String(localized: "Autocitire între \(Int(from)) și \(Int(to)) ale lunii", comment: "Home hero: the days of the month when meters are read.")
    }
}

extension AssetFacts {
    /// Values of the fields with `role`, in the template's order.
    static func fields(_ role: FieldRole, in values: FieldValues, template: TemplateDefinition) -> [FieldValue] {
        template.fields(withRole: role).compactMap { values[$0.key] }
    }
}
