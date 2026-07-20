import SwiftUI
import UsageCore

/// Single source of truth for the usage colors: orange normally, red once usage
/// passes the threshold. Used by both the menu bar ring and the panel meters.
enum Palette {
    static let redThreshold = 80.0

    private static let orangeRGB = (r: 0.91, g: 0.55, b: 0.16)
    private static let redRGB = (r: 0.82, g: 0.28, b: 0.23)

    private static func rgb(forPercent percent: Double?) -> (r: Double, g: Double, b: Double) {
        (percent ?? 0) >= redThreshold ? redRGB : orangeRGB
    }

    static func color(forPercent percent: Double?) -> Color {
        let c = rgb(forPercent: percent)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    static func nsColor(forPercent percent: Double?) -> NSColor {
        let c = rgb(forPercent: percent)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// Fixed alarm red for percent readouts past the threshold (redundant
    /// severity encoding next to rings).
    static var alarmRedNS: NSColor {
        NSColor(srgbRed: redRGB.r, green: redRGB.g, blue: redRGB.b, alpha: 1)
    }
}
