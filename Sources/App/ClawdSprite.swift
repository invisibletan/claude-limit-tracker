import Foundation
import AppKit

/// The Clawd mascot's pixel spec — a chunky coral critter (wide body, side nubs,
/// two big eyes, four stubby legs) matched pixel-by-pixel to the reference art
/// on a 176×120 grid. Shared by the menu-bar rendering (`ClawdIcon`) AND the app
/// icon generator (`make-appicon.swift`), so the two never drift: edit the sprite
/// here only, and re-measure the reference image rather than eyeballing the pixels.
enum ClawdSprite {
    static let coral = NSColor(srgbRed: 0xCC / 255, green: 0x6B / 255, blue: 0x4E / 255, alpha: 1)
    static let eye = NSColor(srgbRed: 0.09, green: 0.07, blue: 0.06, alpha: 1)

    /// Reference grid (measured pixels); image aspect ratio ≈ 1.467.
    static let gridW = 176.0
    static let gridH = 120.0

    /// Draw Clawd into `rect` at walk `phase` (0–1). Phase 0 is the neutral
    /// standing pose (no bob, legs level) — what the app icon uses.
    static func draw(ctx: CGContext, rect: CGRect, phase: Double) {
        // Uniform scale that fits the sprite inside `rect` at its native aspect
        // ratio, then center it — so an oddly-proportioned rect letterboxes
        // instead of overflowing or anchoring to a corner. A no-op for the
        // current callers, which all pass rects at the gridW:gridH ratio.
        let px = min(rect.width / CGFloat(gridW), rect.height / CGFloat(gridH))
        let originX = rect.minX + (rect.width - CGFloat(gridW) * px) / 2
        let originY = rect.minY + (rect.height - CGFloat(gridH) * px) / 2
        let s = sin(phase * 2 * .pi)
        let bob = s * 3.0   // in reference-pixel units

        func fill(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            ctx.fill(CGRect(
                x: originX + CGFloat(x) * px,
                y: originY + CGFloat(y + bob) * px,
                width: CGFloat(w) * px,
                height: CGFloat(h) * px
            ))
        }

        // Coordinates below are the reference sprite's exact measured pixels
        // (y-up). Bands are 24px tall: legs 0–24, lower body, nubs 48–72,
        // eyes 72–96, body top. Legs sit in two pairs with a wide centre gap.
        // Fill color is set on the passed `ctx` directly (not NSColor.setFill,
        // which would depend on NSGraphicsContext.current matching ctx) so the
        // helper is self-contained for any caller.
        ctx.setFillColor(coral.cgColor)

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
        ctx.setFillColor(eye.cgColor)
        fill(44, 72, 11, 24)
        fill(121, 72, 11, 24)
    }
}
