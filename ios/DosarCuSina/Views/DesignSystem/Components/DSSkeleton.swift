import SwiftUI

extension View {
    /// Shows this view as a placeholder shape while `isActive`, keeping the real layout,
    /// so content swaps in without moving anything. A soft shimmer runs unless Reduce Motion is on.
    func dsSkeleton(_ isActive: Bool) -> some View {
        modifier(DSSkeletonModifier(isActive: isActive))
    }
}

private struct DSSkeletonModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .redacted(reason: isActive ? .placeholder : [])
            .allowsHitTesting(!isActive)
            .overlay {
                if isActive && !reduceMotion {
                    DSShimmer()
                        .mask { content.redacted(reason: .placeholder) }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .accessibilityHidden(isActive)
            .overlay {
                if isActive {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(Text("Se încarcă…"))
                }
            }
            .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: isActive)
    }
}

/// A slow highlight that sweeps across placeholder shapes.
private struct DSShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: phase * proxy.size.width * 1.6)
        }
        .blendMode(.plusLighter)
        .onAppear {
            withAnimation(DS.Motion.sweep) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
    }
}
