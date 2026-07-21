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
    /// then one segment per visible account composed from the config's
    /// elements: `[name] [session: ring % glyph] [W: ring % glyph] [F: ring % glyph]`. Pace
    /// glyphs are monochrome SF Symbols (flame / equal / tortoise) tinted with
    /// the resolved label color — or, in `.ringTint` style, each window's ring
    /// stroke encodes its own pace tier. Percent text turns alarm red at the
    /// severity threshold; a stale account's whole segment draws dimmed.
    /// Everything is a single image because `MenuBarExtra` labels drop all but
    /// the first image. `name` is nil for a single account.
    static func menuBarImage(entries: [MenuBarEntry], phase: Double, height: CGFloat, config: MenuBarConfig) -> NSImage {
        let hasEntries = !entries.isEmpty
        let items = hasEntries ? entries : [MenuBarEntry(name: nil, snapshot: nil)]
        let mascotPreferred = MenuBarLayout.showsMascot(preference: config.showMascot, hasEntries: hasEntries)
        let cfg = MenuBarLayout.effective(config, mascotVisible: mascotPreferred)
        let ringSize = height * 0.82
        let gapMascot = height * 0.28
        let gapEntry = height * 0.44
        let gapNameRing = height * 0.16
        let gapRingPct = height * 0.12
        let gapPctGlyph = height * 0.10
        let gapWeekly = height * 0.30

        let font = NSFont.monospacedDigitSystemFont(ofSize: height * 0.62, weight: .semibold)
        // Resolve the dynamic label colors ONCE against the app's effective
        // appearance. The status item composites this image under the menu
        // bar's *vibrant* appearance, where `labelColor` resolves to a
        // vibrancy-oriented white/grey meant for template blending — drawn as
        // plain color it washes out to ghost text. Concrete colors (black in
        // light mode, white in dark) sidestep that; the 15fps redraw picks up
        // appearance switches.
        let textColor = resolvedLabelColor(.labelColor)
        let secondaryColor = resolvedLabelColor(.secondaryLabelColor)
        func pctAttrs(_ percent: Double?) -> [NSAttributedString.Key: Any] {
            let color = (percent ?? 0) >= Palette.redThreshold ? Palette.alarmRedNS : textColor
            return [.font: font, .foregroundColor: color]
        }
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let weeklyLabelAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: secondaryColor]

        func nameString(_ name: String?) -> NSAttributedString? {
            guard let name, !name.isEmpty else { return nil }
            let trimmed = name.count > 8 ? String(name.prefix(8)) : name
            return NSAttributedString(string: trimmed, attributes: nameAttrs)
        }
        // The glyph is an element of its group (set 1: Ring/Percent/Glyph);
        // it shows when its element checkbox is on, the group is visible, and
        // the pace is known. The state checkboxes (set 2) gate the GROUP.
        func glyphImage(_ state: Pace.State?, enabled: Bool) -> NSImage? {
            guard enabled, let state else { return nil }
            return paceSymbol(state, height: height, tint: textColor)
        }

        // Each segment is a flat token stream — one pass computes width, one draws.
        enum Token {
            case gap(CGFloat)
            case text(NSAttributedString)
            case image(NSImage)
            case ring(percent: Double?, color: NSColor)
        }
        func width(of token: Token) -> CGFloat {
            switch token {
            case .gap(let g): return g
            case .text(let t): return ceil(t.size().width)
            case .image(let i): return ceil(i.size.width)
            case .ring: return ringSize
            }
        }

        var segments: [(tokens: [Token], isStale: Bool, width: CGFloat)] = []
        for item in items {
            var tokens: [Token] = []
            if let name = nameString(item.name) { tokens += [.text(name), .gap(gapNameRing)] }

            // Session group: ring, percent, pace glyph — rendered only while
            // the window's current pace is a checked state (or still unknown).
            var session: [Token] = []
            if cfg.sessionPace.showsGroup(for: item.sessionPace) {
                if cfg.sessionRing {
                    session.append(.ring(percent: item.sessionPercent, color: Palette.nsColor(forPercent: item.sessionPercent)))
                }
                if cfg.sessionPercent {
                    if cfg.sessionRing { session.append(.gap(gapRingPct)) }
                    session.append(.text(NSAttributedString(string: Format.percent(item.sessionPercent), attributes: pctAttrs(item.sessionPercent))))
                }
                if let glyph = glyphImage(item.sessionPace, enabled: cfg.sessionGlyph) {
                    if !session.isEmpty { session.append(.gap(gapPctGlyph)) }
                    session.append(.image(glyph))
                }
            }
            tokens += session

            // Weekly group: the "W:" label anchors the structural elements
            // (ring/percent); a glyph-only weekly stays bare, trailing the
            // session group like a second pace column.
            var weekly: [Token] = []
            if cfg.weeklyPace.showsGroup(for: item.weeklyPace) {
                if cfg.weeklyRing || cfg.weeklyPercent {
                    weekly.append(.text(NSAttributedString(string: "W:", attributes: weeklyLabelAttrs)))
                    if cfg.weeklyRing {
                        weekly.append(.ring(percent: item.weeklyPercent, color: Palette.nsColor(forPercent: item.weeklyPercent)))
                    }
                    if cfg.weeklyPercent {
                        if cfg.weeklyRing { weekly.append(.gap(gapRingPct)) }
                        weekly.append(.text(NSAttributedString(string: Format.percent(item.weeklyPercent), attributes: pctAttrs(item.weeklyPercent))))
                    }
                }
                if let glyph = glyphImage(item.weeklyPace, enabled: cfg.weeklyGlyph) {
                    if !weekly.isEmpty { weekly.append(.gap(gapPctGlyph)) }
                    weekly.append(.image(glyph))
                }
            }
            if !weekly.isEmpty {
                if !tokens.isEmpty {
                    let bareGlyphOnly = !(cfg.weeklyRing || cfg.weeklyPercent)
                    tokens.append(.gap(bareGlyphOnly ? gapPctGlyph : gapWeekly))
                }
                tokens += weekly
            }

            // Fable weekly group ("F:") — same structure as weekly. Skipped
            // entirely while the window is unknown (fallback probe): a "F:–%"
            // placeholder would just be noise.
            var fable: [Token] = []
            if item.fableWeeklyPercent != nil, cfg.fablePace.showsGroup(for: item.fableWeeklyPace) {
                if cfg.fableRing || cfg.fablePercent {
                    fable.append(.text(NSAttributedString(string: "F:", attributes: weeklyLabelAttrs)))
                    if cfg.fableRing {
                        fable.append(.ring(percent: item.fableWeeklyPercent, color: Palette.nsColor(forPercent: item.fableWeeklyPercent)))
                    }
                    if cfg.fablePercent {
                        if cfg.fableRing { fable.append(.gap(gapRingPct)) }
                        fable.append(.text(NSAttributedString(string: Format.percent(item.fableWeeklyPercent), attributes: pctAttrs(item.fableWeeklyPercent))))
                    }
                }
                if let glyph = glyphImage(item.fableWeeklyPace, enabled: cfg.fableGlyph) {
                    if !fable.isEmpty { fable.append(.gap(gapPctGlyph)) }
                    fable.append(.image(glyph))
                }
            }
            if !fable.isEmpty {
                if !tokens.isEmpty {
                    let bareGlyphOnly = !(cfg.fableRing || cfg.fablePercent)
                    tokens.append(.gap(bareGlyphOnly ? gapPctGlyph : gapWeekly))
                }
                tokens += fable
            }

            // An account whose groups are all hidden (pace filter) disappears
            // entirely — a bare name with no data is noise, and dropping it
            // lets the mascot fallback fire when every account is filtered.
            guard !(session.isEmpty && weekly.isEmpty && fable.isEmpty) else { continue }
            // Trim trailing gaps (defensive; group content follows the name).
            while case .some(.gap) = tokens.last { tokens.removeLast() }
            guard !tokens.isEmpty else { continue }

            segments.append((tokens, item.isStale, tokens.reduce(0) { $0 + width(of: $1) }))
        }

        // Group visibility is data-dependent, so the never-empty guarantee gets
        // a dynamic leg: when every segment is currently hidden, the mascot
        // shows regardless of its preference — the item must stay clickable.
        let mascotVisible = mascotPreferred || segments.isEmpty
        let clawdWidth = mascotVisible ? height * CGFloat(gridW / gridH) : 0

        var total = clawdWidth
        for (i, seg) in segments.enumerated() { total += (i == 0 ? gapMascot : gapEntry) + seg.width }

        return NSImage(size: NSSize(width: total, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            if mascotVisible {
                drawClawd(ctx: ctx, rect: CGRect(x: 0, y: 0, width: clawdWidth, height: height), phase: phase)
            }

            var x = clawdWidth
            for (i, seg) in segments.enumerated() {
                x += (i == 0 ? gapMascot : gapEntry)

                // Stale data draws the whole segment dimmed (state via opacity,
                // not hue — the Bjango idiom), leaving severity colors intact.
                if seg.isStale {
                    ctx.saveGState()
                    ctx.setAlpha(0.45)
                    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                }

                for token in seg.tokens {
                    switch token {
                    case .gap(let g):
                        x += g
                    case .text(let t):
                        let sz = t.size()
                        t.draw(at: NSPoint(x: x, y: (height - sz.height) / 2))
                        x += ceil(sz.width)
                    case .image(let image):
                        let sz = image.size
                        image.draw(in: CGRect(x: x, y: (height - sz.height) / 2, width: sz.width, height: sz.height))
                        x += ceil(sz.width)
                    case .ring(let percent, let color):
                        drawRing(
                            ctx: ctx,
                            rect: CGRect(x: x, y: (height - ringSize) / 2, width: ringSize, height: ringSize),
                            size: ringSize, percent: percent, color: color
                        )
                        x += ringSize
                    }
                }

                if seg.isStale {
                    ctx.endTransparencyLayer()
                    ctx.restoreGState()
                }
            }
            return true
        }
    }

    /// A dynamic system color snapshotted as a concrete color under the app's
    /// effective appearance, immune to the menu bar's vibrant drawing context.
    private static func resolvedLabelColor(_ color: NSColor) -> NSColor {
        var resolved = color
        NSApplication.shared.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: color.cgColor) ?? color
        }
        return resolved
    }

    /// Monochrome pace glyph: the SF Symbol for the state, tinted with the
    /// (pre-resolved) label color so it matches the menu bar's text in both
    /// light and dark appearance (unlike color emoji, which render fixed-color).
    private static func paceSymbol(_ state: Pace.State, height: CGFloat, tint: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: height * 0.52, weight: .semibold)
        guard let base = NSImage(
            systemSymbolName: PaceDisplay.symbolName(for: state),
            accessibilityDescription: Format.paceLabel(Pace(ratio: 1, state: state, projectedPercent: 0, timeToLimit: nil))
        )?.withSymbolConfiguration(config) else { return nil }
        return NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func drawRing(ctx: CGContext, rect: CGRect, size: CGFloat, percent: Double?, color: NSColor) {
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
            color.setStroke()
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
