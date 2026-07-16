import AppKit
import UsageCore

/// Draws the Clawd mascot — a coral pixel-art critter built from rectangles —
/// optionally wrapped in a usage ring. Animated by a walk `phase` (0–1) for the
/// menu bar; drawn static for the panel.
enum ClawdIcon {
    static let coral = NSColor(srgbRed: 0xDD / 255, green: 0x77 / 255, blue: 0x5B / 255, alpha: 1)
    static let coralDark = NSColor(srgbRed: 0xC0 / 255, green: 0x5F / 255, blue: 0x45 / 255, alpha: 1)
    static let eye = NSColor(srgbRed: 0.15, green: 0.11, blue: 0.09, alpha: 1)

    /// Ring gauge color — a clear green→amber→red usage signal.
    static func ringColor(for state: HealthState) -> NSColor {
        switch state {
        case .good: return NSColor(calibratedRed: 0.25, green: 0.62, blue: 0.36, alpha: 1)
        case .warn: return NSColor(calibratedRed: 0.85, green: 0.58, blue: 0.13, alpha: 1)
        case .crit: return NSColor(calibratedRed: 0.82, green: 0.28, blue: 0.23, alpha: 1)
        }
    }

    static func image(
        percent: Double?,
        state: HealthState,
        phase: Double,
        size: CGFloat = 18,
        showRing: Bool = true
    ) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            if showRing {
                let lineWidth = size * 0.10
                let circleRect = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
                ctx.setLineWidth(lineWidth)
                ctx.setLineCap(.round)
                NSColor.secondaryLabelColor.withAlphaComponent(0.3).setStroke()
                ctx.strokeEllipse(in: circleRect)

                let fraction = max(0, min(1, (percent ?? 0) / 100))
                if fraction > 0.01 {
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    let radius = circleRect.width / 2
                    ctx.beginPath()
                    ctx.addArc(
                        center: center, radius: radius,
                        startAngle: .pi / 2,
                        endAngle: .pi / 2 - 2 * .pi * CGFloat(fraction),
                        clockwise: true
                    )
                    ringColor(for: state).setStroke()
                    ctx.strokePath()
                }
            }

            let inner = showRing ? size * 0.60 : size * 0.92
            drawClawd(ctx: ctx, center: CGPoint(x: rect.midX, y: rect.midY), extent: inner, phase: phase)
            return true
        }
    }

    /// Pixel-art critter on a 16×16 grid: rounded coral body, two eyes, four
    /// legs that alternate, two little arms, and a gentle vertical bob.
    private static func drawClawd(ctx: CGContext, center: CGPoint, extent: CGFloat, phase: Double) {
        let px = extent / 16
        let s = sin(phase * 2 * .pi)
        let bob = s * 0.35

        func fill(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            ctx.fill(CGRect(
                x: center.x + CGFloat(x - 8) * px,
                y: center.y + CGFloat(y - 8 + bob) * px,
                width: CGFloat(w) * px,
                height: CGFloat(h) * px
            ))
        }

        // Legs (four): groups alternate lifting to read as walking.
        let liftA = max(0, s) * 1.3
        let liftB = max(0, -s) * 1.3
        coral.setFill()
        fill(4.6, 1.6 + liftA, 1.5, 4.2 - liftA)   // outer-left  (group A)
        fill(9.9, 1.6 + liftA, 1.5, 4.2 - liftA)   // outer-right (group A)
        coralDark.setFill()
        fill(6.5, 1.6 + liftB, 1.5, 4.2 - liftB)   // inner-left  (group B)
        fill(8.0, 1.6 + liftB, 1.5, 4.2 - liftB)   // inner-right (group B)

        // Arms.
        coralDark.setFill()
        fill(3.4, 7.0, 1.4, 3.2)
        fill(11.2, 7.0, 1.4, 3.2)

        // Body — stacked rects for a rounded-square silhouette.
        coral.setFill()
        fill(4.6, 5.4, 6.8, 7.4)      // torso
        fill(5.4, 12.6, 5.2, 1.1)     // top cap
        fill(4.0, 6.6, 0.7, 4.6)      // left edge fill
        fill(11.3, 6.6, 0.7, 4.6)     // right edge fill

        // Eyes.
        eye.setFill()
        fill(6.3, 8.8, 1.5, 2.2)
        fill(8.9, 8.8, 1.5, 2.2)
    }
}
