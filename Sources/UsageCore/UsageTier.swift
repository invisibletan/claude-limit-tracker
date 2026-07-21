import Foundation

/// The severity tier of a usage meter, used to color its bar / ring / percent.
///
/// The tier is driven by **pace** — how fast the window is burning relative to an
/// even fill — because that's the *leading* signal: a fast burn will hit the cap
/// before reset even while the absolute level still looks low, so coloring by pace
/// warns in time to slow down. Absolute utilization is a *lagging* safety net:
/// once you're within a hair of the cap (`nearCapPercent`), the tier is forced to
/// `.danger` no matter how gentle the current pace reads.
public enum UsageTier: Sendable, Equatable {
    /// Under-pacing (slow burn) — green.
    case safe
    /// On an even pace (steady) — amber.
    case onTrack
    /// Fast burn, or near the cap — red. "Slow down."
    case danger
    /// Pace not yet known and not near the cap — neutral gray.
    case unknown

    /// At/above this utilization the tier is `.danger` regardless of pace: you're
    /// close enough to the cap that the trajectory no longer matters. Tuned low
    /// (was 90) so the absolute-level red warning arrives with margin to spare.
    public static let nearCapPercent = 80.0

    /// Resolve the tier from the window's current pace state and utilization.
    /// The near-cap override is checked **before** pace so a near-full-but-slow
    /// window and a low-but-fast window both correctly land on `.danger`.
    public static func resolve(pace: Pace.State?, percent: Double?) -> UsageTier {
        if let percent, percent >= nearCapPercent { return .danger }
        switch pace {
        case .slow:   return .safe
        case .steady: return .onTrack
        case .fast:   return .danger
        case nil:     return .unknown
        }
    }

    /// Whether the percent readout should render in alarm red — only in `.danger`
    /// (fast burn or near cap), keeping the other tiers legible on the menu bar.
    public var isAlarm: Bool { self == .danger }
}
