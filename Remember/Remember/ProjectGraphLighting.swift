import SwiftUI

/// Viewport-relative light, not a timer: dragging and snapping share the same
/// presentation geometry, and stationary nodes never shimmer on their own.
nonisolated struct ProjectGraphLighting: Equatable {
    let highlightOrigin: CGPoint
    let rimAngle: Double

    init(center: CGPoint, viewport: CGSize, reduceMotion: Bool) {
        let valid = center.x.isFinite && center.y.isFinite && viewport.width.isFinite && viewport.height.isFinite
        let x = !reduceMotion && valid ? tanh((center.x - viewport.width / 2) / max(100, viewport.width * 0.5)) : 0
        let y = !reduceMotion && valid ? tanh((center.y - (viewport.height - 40) / 2) / max(100, viewport.height * 0.5)) : 0
        highlightOrigin = CGPoint(x: 0.30 - x * 0.065, y: 0.18 - y * 0.045)
        rimAngle = -125 + Double(x) * 12 - Double(y) * 8
    }
}

/// Standard content material with restrained lighting, not a Liquid Glass control.
struct ProjectGraphNodeSurface: View {
    let diameter: CGFloat
    let prominence: CGFloat
    let focused: Bool
    let lighting: ProjectGraphLighting
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var dark: Bool { colorScheme == .dark }
    private var silver: Color {
        dark ? Color(red: 0.77, green: 0.80, blue: 0.85) : Color(red: 0.43, green: 0.46, blue: 0.51)
    }

    var body: some View {
        ZStack {
            if !dark {
                // An opaque pearl base gives the light map a clear silhouette and
                // dependable text contrast; only the lighting moves above it.
                Circle().fill(RememberPalette.surface)
                Circle().fill(LinearGradient(colors: [.clear, RememberPalette.mapShade.opacity(focused ? 0.32 : 0.62)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            } else if reduceTransparency {
                Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
            } else {
                Circle().fill(.regularMaterial)
                Circle().fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(dark ? 0.50 : 0.38))
            }
            if dark { Circle().fill(silver.opacity(0.015 + prominence * 0.035 + (focused ? 0.02 : 0))) }
            Circle().fill(LinearGradient(colors: [.white.opacity(dark ? 0.035 : 0.12),
                                                  .black.opacity(dark ? 0.04 : 0.015)],
                                         startPoint: .top, endPoint: .bottom))
            Circle().fill(RadialGradient(
                colors: [.white.opacity(dark ? 0.035 + prominence * 0.02 + (focused ? 0.025 : 0) : 0.22 + (focused ? 0.08 : 0)), .clear],
                center: UnitPoint(x: lighting.highlightOrigin.x, y: lighting.highlightOrigin.y),
                startRadius: 0, endRadius: diameter * 0.7))
            if contrast == .increased {
                Circle().strokeBorder(.primary.opacity(0.65), lineWidth: focused ? 2 : 1.5)
            } else {
                let edge = dark ? Color.primary.opacity(focused ? 0.28 : 0.10)
                                : silver.opacity(focused ? 0.52 : 0.20)
                let reflection = dark ? Color.white.opacity(0.23 + prominence * 0.09 + (focused ? 0.13 : 0))
                                      : Color.white.opacity(0.95)
                Circle().strokeBorder(AngularGradient(stops: [
                    .init(color: edge, location: 0),
                    .init(color: reflection, location: 0.16),
                    .init(color: edge, location: 0.32),
                    .init(color: edge, location: 1)
                ], center: .center, startAngle: .degrees(lighting.rimAngle - 57.6),
                   endAngle: .degrees(lighting.rimAngle + 302.4)), lineWidth: focused ? 1.15 : 0.85)
            }
        }
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}
