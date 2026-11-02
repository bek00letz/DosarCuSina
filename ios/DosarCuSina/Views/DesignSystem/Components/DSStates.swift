import SwiftUI

/// A designed empty state: symbol, short title, one sentence on what goes here,
/// and the action that fills it. Built on the system's `ContentUnavailableView`.
struct DSEmptyState: View {
    let systemImage: String
    let title: Text
    let message: Text
    var actionTitle: Text?
    var action: (() -> Void)?

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = Text(title)
        self.message = Text(message)
        self.actionTitle = actionTitle.map { Text($0) }
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label { title } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Palette.accent)
            }
        } description: {
            message
        } actions: {
            if let actionTitle, let action {
                Button(action: action) { actionTitle }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        }
    }
}

/// A full-area error: what happened, and what to do next. Offer a retry whenever
/// trying again can help. See COPY_GUIDE.md for wording.
struct DSErrorState: View {
    let title: Text
    let message: Text
    var retryTitle: Text = Text("Încearcă din nou")
    var retry: (() -> Void)?

    init(_ title: LocalizedStringKey, message: LocalizedStringKey, retry: (() -> Void)? = nil) {
        self.title = Text(title)
        self.message = Text(message)
        self.retry = retry
    }

    var body: some View {
        ContentUnavailableView {
            Label { title } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DSStatus.overdue.color)
            }
        } description: {
            message
        } actions: {
            if let retry {
                Button(action: retry) { retryTitle }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        }
    }
}

/// An inline notice inside a screen or form: information, a warning, or an error,
/// with an optional action. Never blocks the screen.
struct DSNotice: View {
    enum Kind: Sendable {
        case info, warning, error, success

        var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            case .success: "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: DS.Palette.accent
            case .warning: DSStatus.soon.color
            case .error: DSStatus.overdue.color
            case .success: DSStatus.done.color
            }
        }
    }

    let kind: Kind
    let title: Text
    var message: Text?
    var actionTitle: Text?
    var action: (() -> Void)?

    init(
        _ kind: Kind,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = Text(title)
        self.message = message.map { Text($0) }
        self.actionTitle = actionTitle.map { Text($0) }
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                title.dsFont(.headline)
                if let message {
                    message.dsFont(.subheadline)
                }
                if let actionTitle, let action {
                    Button(action: action) { actionTitle.font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.m)
        .background(kind.tint.opacity(0.1), in: .rect(cornerRadius: DS.Radius.control + 4, style: .continuous))
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}
