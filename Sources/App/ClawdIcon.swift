import AppKit
import UsageCore

/// Draws the Clawd mascot — a chunky coral pixel critter (wide body, side nubs,
/// two big eyes, four stubby legs) — and, separately, the usage ring gauge that
/// sits to its right in the menu bar.
enum ClawdIcon {
    static let coral = NSColor(srgbRed: 0xCC / 255, green: 0x6B / 255, blue: 0x4E / 255, alpha: 1)
    static let eye = NSColor(srgbRed: 0.09, green: 0.07, blue: 0.06, alpha: 1)

    // Grid = the reference sprite's measured pixels (176×120, ratio ≈ 1.467).
    private static let gridW = 176.0
    private static let gridH = 120.0

    /// Just the critter, animated by walk `phase` (0–1). Image is wider than tall.
    static func sprite(phase: Double, height: CGFloat) -> NSImage {
        let width = height * CGFloat(gridW / gridH)
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawClawd(ctx: ctx, rect: rect, phase: phase)
            return true
        }
    }

    /// One composited image for the whole menu bar label — Clawd on the left,
    /// then one `[name] ring NN%` segment per visible account. Everything is a
    /// single image because `MenuBarExtra` labels drop all but the first image.
    /// `name` is nil for a single account (matches the original look).
    static func menuBarImage(entries: [(name: String?, percent: Double?)], phase: Double, height: CGFloat) -> NSImage {
        let items = entries.isEmpty ? [(name: Optional<String>.none, percent: Optional<Double>.none)] : entries
        let clawdWidth = height * CGFloat(gridW / gridH)
        let ringSize = height * 0.82
        let gapMascot = height * 0.28
        let gapEntry = height * 0.44
        let gapNameRing = height * 0.16
        let gapRingPct = height * 0.12

        let font = NSFont.monospacedDigitSystemFont(ofSize: height * 0.62, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

        func nameString(_ name: String?) -> NSAttributedString? {
            guard let name, !name.isEmpty else { return nil }
            let trimmed = name.count > 8 ? String(name.prefix(8)) : name
            return NSAttributedString(string: trimmed, attributes: attrs)
        }

        var segments: [(name: NSAttributedString?, pct: NSAttributedString, percent: Double?, width: CGFloat)] = []
        for item in items {
            let name = nameString(item.name)
            let pct = NSAttributedString(string: Format.percent(item.percent), attributes: attrs)
            var width = ringSize + gapRingPct + ceil(pct.size().width)
            if let name { width += ceil(name.size().width) + gapNameRing }
            segments.append((name, pct, item.percent, width))
        }

        var total = clawdWidth
        for (i, seg) in segments.enumerated() { total += (i == 0 ? gapMascot : gapEntry) + seg.width }

        return NSImage(size: NSSize(width: total, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawClawd(ctx: ctx, rect: CGRect(x: 0, y: 0, width: clawdWidth, height: height), phase: phase)
            var x = clawdWidth
            for (i, seg) in segments.enumerated() {
                x += (i == 0 ? gapMascot : gapEntry)
                if let name = seg.name {
                    let sz = name.size()
                    name.draw(at: NSPoint(x: x, y: (height - sz.height) / 2))
                    x += ceil(sz.width) + gapNameRing
                }
                drawRing(
                    ctx: ctx,
                    rect: CGRect(x: x, y: (height - ringSize) / 2, width: ringSize, height: ringSize),
                    size: ringSize, percent: seg.percent
                )
                x += ringSize + gapRingPct
                let psz = seg.pct.size()
                seg.pct.draw(at: NSPoint(x: x, y: (height - psz.height) / 2))
                x += ceil(psz.width)
            }
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
        let bob = s * 3.0   // in reference-pixel units

        func fill(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            ctx.fill(CGRect(
                x: rect.minX + CGFloat(x) * px,
                y: rect.minY + CGFloat(y + bob) * px,
                width: CGFloat(w) * px,
                height: CGFloat(h) * px
            ))
        }

        // Coordinates below are the reference sprite's exact measured pixels
        // (y-up). Bands are 24px tall: legs 0–24, lower body, nubs 48–72,
        // eyes 72–96, body top. Legs sit in two pairs with a wide centre gap.
        coral.setFill()

        // Legs — two pairs (inset from the edges) with a wide centre gap;
        // groups alternate lifting to read as a walk.
        let liftA = max(0, s) * 6
        let liftB = max(0, -s) * 6
        fill(33, 0 + liftA, 11, 24 - liftA)    // group A
        fill(110, 0 + liftA, 11, 24 - liftA)
        fill(55, 0 + liftB, 11, 24 - liftB)    // group B
        fill(132, 0 + liftB, 11, 24 - liftB)

        // Body + side nubs.
        fill(22, 24, 131, 96)          // torso + head
        fill(0, 48, 22, 24)            // left nub
        fill(154, 48, 22, 24)          // right nub

        // Eyes.
        eye.setFill()
        fill(44, 72, 11, 24)
        fill(121, 72, 11, 24)
    }
}
