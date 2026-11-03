import SwiftUI

// Motion for every target. The app, its widgets and its share extension all compile
// this file, so the share sheet moves with the same springs as the app and waits
// the same time before it shows a spinner.

/// Namespace for the Dosar cu Șină design system.
///
/// Every screen builds on these tokens and components instead of hand-tuned values,
/// so spacing, corners, color, type and motion stay consistent across the app.
/// Motion and the delayed spinner live here, in `ios/Shared`; the rest of the
/// design system is in the app's `Views/DesignSystem`.
enum DS {}

extension DS {
    /// Motion presets. All are springs (interruptible, velocity-preserving) between 0.2 and 0.4 s.
    ///
    /// When Reduce Motion is on, use `animation(_:reduceMotion:)` and `transition(reduceMotion:)`:
    /// movement becomes a short cross-fade instead of travel or scale.
    enum Motion {
        /// Presses, toggles, small state flips.
        static let quick = Animation.spring(duration: 0.22, bounce: 0)
        /// Default for content changes: rows appearing, sections expanding.
        static let standard = Animation.spring(duration: 0.32, bounce: 0.08)
        /// Things that arrive from off-screen: toasts, banners.
        static let emphasized = Animation.spring(duration: 0.4, bounce: 0.18)

        /// The fade used instead of movement when Reduce Motion is on.
        static let reducedFade = Animation.easeOut(duration: 0.18)

        /// A steady highlight that keeps sweeping, such as a skeleton's shimmer.
        /// It never settles, so it isn't a spring; nothing else should use it.
        static let sweep = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)

        /// How long work may take before a spinner shows (`DSDelayedProgress`).
        static let progressDelay: Duration = .milliseconds(400)

        /// How long a short confirmation stays before it goes by itself, when
        /// nothing else is waiting on it (the share sheet's "Trimis").
        static let confirmationDwell: Duration = .seconds(2.5)

        /// The animation to use given the person's Reduce Motion setting.
        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reducedFade : animation
        }

        /// Slide-and-fade from `edge`, or a plain fade when Reduce Motion is on.
        static func transition(from edge: Edge = .bottom, reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
        }
    }
}

extension View {
    /// `animation(_:value:)` that respects Reduce Motion.
    func dsAnimation<V: Equatable>(_ animation: Animation = DS.Motion.standard, value: V) -> some View {
        modifier(DSAnimationModifier(animation: animation, value: value))
    }
}

private struct DSAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(DS.Motion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - Delayed progress

/// A spinner that stays invisible for a short delay, so fast work never flashes a spinner.
/// Its space is always reserved, so nothing jumps when it appears.
struct DSDelayedProgress: View {
    /// The words under the spinner; `nil` for a spinner that a title nearby already explains.
    var label: LocalizedStringKey? = "Se încarcă…"
    var delay: Duration = DS.Motion.progressDelay

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProgressView {
            if let label {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(!isVisible)
        .task {
            try? await Task.sleep(for: delay)
            withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Press feedback

/// Gives any tappable surface (cards, tiles, custom rows) an immediate pressed state:
/// a slight shrink and dim that springs back. With Reduce Motion it only dims.
struct DSPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.45))
            .animation(DS.Motion.animation(DS.Motion.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DSPressableButtonStyle {
    /// Pressed-state feedback for custom tappable surfaces. For ordinary buttons,
    /// prefer the system styles (`.borderedProminent`, `.bordered`, `.glass`).
    static var dsPressable: DSPressableButtonStyle { DSPressableButtonStyle() }
}
