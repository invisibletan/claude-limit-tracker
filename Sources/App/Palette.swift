import SwiftUI
import UsageCore

/// Single source of truth for the usage colors. The bar / ring / percent color
/// follows the **pace tier** (`UsageTier`): green when under-pacing, amber when
/// on an even pace, red when burning fast or within a hair of the cap, and a
/// neutral gray while the pace is still unknown. Used by both the menu bar ring
/// and the panel meters so every surface reads the same tier.
enum Palette {
    // Tier colors — chosen to stay legible on both light and dark menu bars.
    private static let greenRGB = (r: 0.26, g: 0.63, b: 0.28)   // safe    (slow)
    private static let amberRGB = (r: 0.93, g: 0.66, b: 0.13)   // onTrack (steady)
    private static let redRGB = (r: 0.82, g: 0.28, b: 0.23)     // danger  (fast / near cap)
    private static let neutralRGB = (r: 0.55, g: 0.55, b: 0.57) // unknown (no pace yet)

    private static func rgb(for tier: UsageTier) -> (r: Double, g: Double, b: Double) {
        switch tier {
        case .safe: return greenRGB
        case .onTrack: return amberRGB
        case .danger: return redRGB
        case .unknown: return neutralRGB
        }
    }

    static func color(pace: Pace.State?, percent: Double?) -> Color {
        let c = rgb(for: UsageTier.resolve(pace: pace, percent: percent))
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    static func nsColor(pace: Pace.State?, percent: Double?) -> NSColor {
        let c = rgb(for: UsageTier.resolve(pace: pace, percent: percent))
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// Whether the percent readout should render in alarm red (danger tier).
    static func isAlarm(pace: Pace.State?, percent: Double?) -> Bool {
        UsageTier.resolve(pace: pace, percent: percent).isAlarm
    }

    /// Fixed alarm red for percent readouts in the danger tier (redundant
    /// severity encoding next to the rings, kept legible on the menu bar).
    static var alarmRedNS: NSColor {
        NSColor(srgbRed: redRGB.r, green: redRGB.g, blue: redRGB.b, alpha: 1)
    }
}
