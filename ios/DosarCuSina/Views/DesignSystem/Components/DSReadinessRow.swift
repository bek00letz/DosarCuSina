import SwiftUI

extension DSStatus {
    /// How a readiness check's outcome is drawn: red for a problem, amber for something
    /// worth a look, green when ready. Something not in the binder and something to bring
    /// draw no status colour. The engine decides the outcome; the design system only draws it.
    init?(readiness status: ReadinessStatus) {
        switch status {
        case .problem: self = .overdue
        case .warning: self = .soon
        case .ok: self = .done
        case .missing, .reminder: return nil
        }
    }
}

extension ReadinessStatus {
    /// The symbol a row shows: its shape differs for every outcome, so colour is never the only signal.
    var systemImage: String {
        switch self {
        case .problem: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .missing: "plus.circle"
        case .ok: "checkmark.circle.fill"
        case .reminder: "arrow.forward.circle"
        }
    }

    /// The outcome in a word or two, read by VoiceOver before the reason.
    var spokenTitle: String {
        switch self {
        case .problem: String(localized: "De rezolvat", comment: "VoiceOver: a readiness check that fails.")
        case .warning: String(localized: "De verificat", comment: "VoiceOver: a readiness check worth a look.")
        case .missing: String(localized: "Nu e în dosar", comment: "VoiceOver: a readiness check the binder can't do yet.")
        case .ok: String(localized: "Pregătit", comment: "VoiceOver: a readiness check that is fine.")
        case .reminder: String(localized: "De luat", comment: "VoiceOver: something to bring.")
        }
    }
}

/// One check of a checklist: its outcome as a symbol, what it is, why in plain words, and
/// what a tap does ("Adaugă" when it adds, a chevron when it opens). The whole row is the
/// target, at least 44 pt tall; nothing hides behind a swipe. The reason wraps at every
/// text size, and the action moves under it when they don't fit side by side.
struct DSReadinessRow: View {
    let status: ReadinessStatus
    let title: Text
    let detail: Text
    /// "Adaugă", shown when a tap adds something; nil when it opens what is there.
    var actionTitle: Text?
    /// Whether a tap does anything.
    var isTappable = true
    let action: () -> Void

    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 28

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Image(systemName: status.systemImage)
                    .font(.title3)
                    .foregroundStyle(DSStatus(readiness: status)?.color ?? DS.Palette.secondaryLabel)
                    .frame(width: symbolWidth)
                    .accessibilityHidden(true)
                DSAdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: DS.Space.s, stackedSpacing: DS.Space.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .dsFont(.headline)
                        // A problem or something worth a look says why in its status's text colour.
                        detail
                            .foregroundStyle(DSStatus(readiness: status).flatMap { $0 == .done ? nil : $0.textColor } ?? DS.Palette.secondaryLabel)
                            .dsFont(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    if let actionTitle, isTappable {
                        actionTitle
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                            .lineLimit(1)
                    }
                }
                if isTappable, actionTitle == nil {
                    Image(systemName: "chevron.forward")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, minHeight: DS.Control.minimumHitTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.dsPressable)
        .disabled(!isTappable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: status.spokenTitle) + Text(verbatim: ", ") + detail)
        .accessibilityHint(actionTitle ?? Text(verbatim: ""))
        .accessibilityAddTraits(isTappable ? .isButton : [])
    }
}

#Preview("Readiness rows") {
    ScrollView {
        DSCard {
            VStack(alignment: .leading, spacing: 0) {
                DSReadinessRow(status: .ok, title: Text(verbatim: "Carte de identitate"), detail: Text(verbatim: "Valabilă până pe 12 august 2031.")) {}
                DSRowSeparator()
                DSReadinessRow(status: .problem, title: Text(verbatim: "Pașaport"), detail: Text(verbatim: "Bun de călătorit doar până pe 3 iunie.")) {}
                DSRowSeparator()
                DSReadinessRow(status: .missing, title: Text(verbatim: "Rovinietă"), detail: Text(verbatim: "Nu e în dosar."), actionTitle: Text(verbatim: "Adaugă")) {}
            }
        }
        .padding(DS.Space.m)
    }
    .background(DS.Palette.background)
}
