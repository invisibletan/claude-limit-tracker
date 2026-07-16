import AppKit

/// Draws the Clawd mascot — a chunky coral pixel critter (wide body, side nubs,
/// two big eyes, four stubby legs) — and, separately, the usage ring gauge that
/// sits to its right in the menu bar.
enum ClawdIcon {
    static let coral = NSColor(srgbRed: 0xCC / 255, green: 0x6B / 255, blue: 0x4E / 255, alpha: 1)
    static let eye = NSColor(srgbRed: 0.09, green: 0.07, blue: 0.06, alpha: 1)

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

    /// One composited image — Clawd on the left, the usage ring to its right —
    /// so the whole thing renders reliably as a single menu bar label image.
    static func menuBarImage(percent: Double?, phase: Double, height: CGFloat) -> NSImage {
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
                size: ringSize, percent: percent
            )
            return true
        }
    }

    private static func drawRing(ctx: CGContext, rect: CGRect, size: CGFloat, percent: Double?) {
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
            Palette.nsColor(forPercent: percent).setStroke()
            ctx.strokePath()
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

        // Legs — four EQUAL stubs cut from the body bottom: equal width (1.8)
        // and equal gaps (1.6), with the outer two FLUSH to the body edges
        // (x2 and x14) so the body's side edges run straight down into them.
        let liftA = max(0, s) * 0.7
        let liftB = max(0, -s) * 0.7
        fill(2.0, 0.2 + liftA, 1.8, 2.3 - liftA)    // flush left  (group A)
        fill(8.8, 0.2 + liftA, 1.8, 2.3 - liftA)    // group A
        fill(5.4, 0.2 + liftB, 1.8, 2.3 - liftB)    // group B
        fill(12.2, 0.2 + liftB, 1.8, 2.3 - liftB)   // flush right (group B)

        // Body: one fat rectangle (x2–14) + side nubs.
        fill(2.0, 2.3, 12.0, 9.7)      // torso + head
        fill(0.0, 5.0, 2.0, 3.0)       // left nub
        fill(14.0, 5.0, 2.0, 3.0)      // right nub

        // Eyes.
        eye.setFill()
        fill(4.6, 8.4, 1.9, 2.2)
        fill(9.5, 8.4, 1.9, 2.2)
    }
}
