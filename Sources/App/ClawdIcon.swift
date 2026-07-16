import AppKit
import UsageCore

/// Draws the Clawd mascot — a chunky coral pixel critter (wide body, side nubs,
/// two big eyes, four stubby legs) — and, separately, the usage ring gauge that
/// sits to its right in the menu bar.
enum ClawdIcon {
    static let coral = NSColor(srgbRed: 0xCC / 255, green: 0x6B / 255, blue: 0x4E / 255, alpha: 1)
    static let coralDark = NSColor(srgbRed: 0xB4 / 255, green: 0x57 / 255, blue: 0x3D / 255, alpha: 1)
    static let eye = NSColor(srgbRed: 0.09, green: 0.07, blue: 0.06, alpha: 1)

    static func ringColor(for state: HealthState) -> NSColor {
        switch state {
        case .good: return NSColor(calibratedRed: 0.25, green: 0.62, blue: 0.36, alpha: 1)
        case .warn: return NSColor(calibratedRed: 0.85, green: 0.58, blue: 0.13, alpha: 1)
        case .crit: return NSColor(calibratedRed: 0.82, green: 0.28, blue: 0.23, alpha: 1)
        }
    }

    // Grid the critter is laid out on — wide and chunky, short legs.
    private static let gridW = 16.0
    private static let gridH = 12.0

    /// Just the critter, animated by walk `phase` (0–1). Image is wider than tall.
    static func sprite(phase: Double, height: CGFloat) -> NSImage {
        let width = height * CGFloat(gridW / gridH)
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawClawd(ctx: ctx, rect: rect, phase: phase)
            return true
        }
    }

    /// The usage ring gauge (no critter inside).
    static func ring(percent: Double?, state: HealthState, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawRing(ctx: ctx, rect: rect, size: size, percent: percent, state: state)
            return true
        }
    }

    private static func drawRing(ctx: CGContext, rect: CGRect, size: CGFloat, percent: Double?, state: HealthState) {
        let lineWidth = size * 0.16
        let circleRect = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        // Neutral track that stays visible on light, dark, and highlighted menu bars.
        NSColor(white: 0.6, alpha: 0.6).setStroke()
        ctx.strokeEllipse(in: circleRect)

        let fraction = max(0, min(1, (percent ?? 0) / 100))
        if fraction > 0.01 {
            ctx.beginPath()
            ctx.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: circleRect.width / 2,
                startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi * CGFloat(fraction),
                clockwise: true
            )
            ringColor(for: state).setStroke()
            ctx.strokePath()
        }
    }

    /// One composited image — Clawd on the left, the usage ring to its right —
    /// so the whole thing renders reliably as a single menu bar label image.
    static func menuBarImage(percent: Double?, state: HealthState, phase: Double, height: CGFloat) -> NSImage {
        let clawdWidth = height * CGFloat(gridW / gridH)
        let ringSize = height * 0.86
        let gap = height * 0.30
        let totalWidth = clawdWidth + gap + ringSize
        return NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawClawd(ctx: ctx, rect: CGRect(x: 0, y: 0, width: clawdWidth, height: height), phase: phase)
            drawRing(
                ctx: ctx,
                rect: CGRect(x: clawdWidth + gap, y: (height - ringSize) / 2, width: ringSize, height: ringSize),
                size: ringSize, percent: percent, state: state
            )
            return true
        }
    }

    private static func drawClawd(ctx: CGContext, rect: CGRect, phase: Double) {
        let px = rect.width / CGFloat(gridW)
        let s = sin(phase * 2 * .pi)
        let bob = s * 0.3

        func fill(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            ctx.fill(CGRect(
                x: rect.minX + CGFloat(x) * px,
                y: rect.minY + CGFloat(y + bob) * px,
                width: CGFloat(w) * px,
                height: CGFloat(h) * px
            ))
        }

        // Flat coral throughout, matching the reference's uniform pixel art.
        coral.setFill()

        // Legs — short stubs (groups alternate to read as a walk).
        let liftA = max(0, s) * 0.9
        let liftB = max(0, -s) * 0.9
        fill(2.8, 0.2 + liftA, 1.7, 2.4 - liftA)    // group A
        fill(8.6, 0.2 + liftA, 1.7, 2.4 - liftA)
        fill(5.7, 0.2 + liftB, 1.7, 2.4 - liftB)    // group B
        fill(11.5, 0.2 + liftB, 1.7, 2.4 - liftB)

        // Body: one fat rectangle + side nubs.
        fill(2.0, 2.4, 12.0, 9.6)      // torso + head
        fill(0.0, 5.0, 2.0, 3.0)       // left nub
        fill(14.0, 5.0, 2.0, 3.0)      // right nub

        // Eyes.
        eye.setFill()
        fill(4.6, 8.4, 1.9, 2.2)
        fill(9.5, 8.4, 1.9, 2.2)
    }
}
