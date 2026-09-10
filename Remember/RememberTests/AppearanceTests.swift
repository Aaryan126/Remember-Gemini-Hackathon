import Testing
import UIKit
@testable import Remember

struct AppearanceTests {
    @Test func filledActionsKeepWhiteTextReadableInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style),
                    UITraitCollection(accessibilityContrast: contrast)])
                #expect(ratio(.white, RememberPalette.filledActionColor, traits: traits) >= 4.5)
            }
        }
    }

    @Test func lightTextAndStatusRolesHaveReadableContrast() {
        for contrast in [UIAccessibilityContrast.normal, .high] {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(accessibilityContrast: contrast)])
            let backgrounds = [RememberPalette.canvasColor, RememberPalette.surfaceColor,
                RememberPalette.readingColor, RememberPalette.insetColor, RememberPalette.mapShadeColor]
            for background in backgrounds {
                for foreground in [UIColor.label, RememberPalette.secondaryTextColor] {
                    #expect(ratio(foreground, background, traits: traits) >= 4.5)
                }
            }
            for status in [RememberPalette.actionColor, RememberPalette.successColor,
                           RememberPalette.warningColor, RememberPalette.dangerColor] {
                #expect(ratio(status, RememberPalette.surfaceColor, traits: traits) >= 4.5)
                #expect(ratio(status, RememberPalette.canvasColor, traits: traits) >= 4.5)
            }
            #expect(ratio(.white, RememberPalette.actionColor, traits: traits) >= 4.5)
        }
    }

    @Test func lightSurfaceHierarchyAndHighContrastAreDistinct() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        #expect(luminance(RememberPalette.surfaceColor, traits: light) > luminance(RememberPalette.canvasColor, traits: light))
        #expect(luminance(RememberPalette.canvasColor, traits: light) > luminance(RememberPalette.insetColor, traits: light))
        #expect(luminance(RememberPalette.insetColor, traits: light) > luminance(RememberPalette.mapShadeColor, traits: light))
        let high = UITraitCollection(traitsFrom: [light, UITraitCollection(accessibilityContrast: .high)])
        #expect(ratio(RememberPalette.ruleColor, .white, traits: high) >= 3)
        #expect(ratio(RememberPalette.secondaryTextColor, .white, traits: high) > ratio(RememberPalette.secondaryTextColor, .white, traits: light))
    }

    @Test func darkSurfacesContinueToUseNativeSemanticColors() {
        for contrast in [UIAccessibilityContrast.normal, .high] {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .dark),
                UITraitCollection(accessibilityContrast: contrast)])
            for (actual, expected) in [(RememberPalette.canvasColor, UIColor.systemGroupedBackground),
                (RememberPalette.readingColor, UIColor.systemBackground),
                (RememberPalette.surfaceColor, UIColor.secondarySystemBackground),
                (RememberPalette.actionColor, UIColor.systemBlue)] {
                #expect(actual.resolvedColor(with: traits) == expected.resolvedColor(with: traits))
            }
        }
    }

    private func ratio(_ foreground: UIColor, _ background: UIColor, traits: UITraitCollection) -> Double {
        let a = luminance(foreground, traits: traits), b = luminance(background, traits: traits)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: UIColor, traits: UITraitCollection) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        let channels = [r, g, b].map { Double($0) <= 0.04045 ? Double($0) / 12.92 : pow((Double($0) + 0.055) / 1.055, 2.4) }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}
