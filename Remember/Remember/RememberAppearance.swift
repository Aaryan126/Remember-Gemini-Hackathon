import SwiftUI
import UIKit

/// Content colors have roles, not source-type hues. Native bars, menus, pickers,
/// and glass controls retain the system's own adaptive material treatment.
nonisolated enum RememberPalette {
    static let canvas = Color(uiColor: canvasColor)
    static let reading = Color(uiColor: readingColor)
    static let surface = Color(uiColor: surfaceColor)
    static let inset = Color(uiColor: insetColor)
    static let secondaryText = Color(uiColor: secondaryTextColor)
    static let action = Color(uiColor: actionColor)
    static let filledAction = Color(uiColor: filledActionColor)
    static let success = Color(uiColor: successColor)
    static let warning = Color(uiColor: warningColor)
    static let danger = Color(uiColor: dangerColor)
    static let rule = Color(uiColor: ruleColor)
    static let mapCanvas = Color(uiColor: mapCanvasColor)
    static let mapShade = Color(uiColor: mapShadeColor)

    static let canvasColor = adaptive(0xF3F4F6, dark: .systemGroupedBackground)
    static let readingColor = adaptive(0xFCFCFD, dark: .systemBackground)
    static let surfaceColor = adaptive(0xFFFFFF, dark: .secondarySystemBackground)
    static let insetColor = adaptive(0xE9EDF2, dark: .tertiarySystemBackground)
    static let secondaryTextColor = adaptive(0x515C6C, dark: .secondaryLabel, highContrast: 0x303947)
    static let actionColor = adaptive(0x005EBF, dark: .systemBlue, highContrast: 0x00468F)
    // White text on an opaque chat bubble needs a deeper blue than a dark-mode
    // control tint, whose foreground is normally managed by the system material.
    static let filledActionColor = adaptive(0x005EBF, dark: UIColor(red: 0, green: 0.31, blue: 0.68, alpha: 1), highContrast: 0x00468F)
    static let successColor = adaptive(0x216E47, dark: .systemGreen, highContrast: 0x155232)
    static let warningColor = adaptive(0x805214, dark: .systemOrange, highContrast: 0x633B06)
    static let dangerColor = adaptive(0xBD2838, dark: .systemRed, highContrast: 0x9D1624)
    static let ruleColor = adaptive(0xBAC3CF, dark: .separator, highContrast: 0x697586)
    static let mapCanvasColor = adaptive(0xE7ECF2, dark: .systemBackground, highContrast: 0xDEE4EB)
    static let mapShadeColor = adaptive(0xD4DDE8, dark: .secondarySystemBackground, highContrast: 0xC6D0DD)

    private static func adaptive(_ light: UInt32, dark: UIColor, highContrast: UInt32? = nil) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark { return dark.resolvedColor(with: traits) }
            let value = traits.accessibilityContrast == .high ? highContrast ?? light : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}

extension View {
    /// Apply to content, not the NavigationStack: sheets and native toolbar glass
    /// must continue to resolve their own background and accessibility behavior.
    func rememberCanvas(reading: Bool = false, dark: UIColor = .systemGroupedBackground) -> some View {
        modifier(RememberCanvas(reading: reading, dark: dark))
    }

    func rememberGroupedList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .rememberCanvas()
    }

    func rememberCard(radius: CGFloat = 16, raised: Bool = false,
                      dark: Color = Color(uiColor: .secondarySystemBackground)) -> some View {
        modifier(RememberCard(radius: radius, raised: raised, dark: dark))
    }
}

private struct RememberCanvas: ViewModifier {
    let reading: Bool
    let dark: UIColor
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background((scheme == .dark ? Color(uiColor: dark) : reading ? RememberPalette.reading : RememberPalette.canvas)
            .ignoresSafeArea())
    }
}

private struct RememberCard: ViewModifier {
    let radius: CGFloat
    let raised: Bool
    let dark: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(scheme == .dark ? dark : RememberPalette.surface, in: shape)
            .clipShape(shape)
            .overlay {
                if scheme == .light {
                    shape.strokeBorder(RememberPalette.rule.opacity(contrast == .increased ? 1 : 0.32),
                                       lineWidth: contrast == .increased ? 1 : 0.5)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(scheme == .light && raised ? 0.045 : 0), radius: 8, y: 3)
    }
}
