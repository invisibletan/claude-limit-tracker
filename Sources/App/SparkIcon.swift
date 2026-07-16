import AppKit
import UsageCore

/// Draws the Claude "spark" starburst — a ring of tapered petals radiating from
/// the center — used both animated in the menu bar and static in the panel.
enum SparkIcon {
    static let clay = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1) // #D97757

    static func color(for state: HealthState) -> NSColor {
        switch state {
        case .good: return clay // keep the mascot on-brand at normal usage
        case .warn: return NSColor(calibratedRed: 0.85, green: 0.58, blue: 0.13, alpha: 1)
        case .crit: return NSColor(calibratedRed: 0.82, green: 0.28, blue: 0.23, alpha: 1)
        }
    }

    static func image(angleDegrees: Double, color: NSColor, size: CGFloat = 16, rays: Int = 10) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: CGFloat(angleDegrees * .pi / 180))
            color.setFill()

            let outer = size * 0.47      // petal tip radius
            let baseR = size * 0.10      // where the petal starts, near center
            let halfW = size * 0.088     // petal half-width at its base
            let ctrl = outer * 0.68      // curve control height → tapered tip

            for i in 0..<rays {
                ctx.saveGState()
                ctx.rotate(by: CGFloat(Double(i) / Double(rays) * 2 * .pi))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -halfW, y: baseR))
                path.addQuadCurve(to: CGPoint(x: 0, y: outer),
                                  control: CGPoint(x: -halfW * 0.55, y: ctrl))
                path.addQuadCurve(to: CGPoint(x: halfW, y: baseR),
                                  control: CGPoint(x: halfW * 0.55, y: ctrl))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // Small solid center so the petals read as one starburst.
            let dot = size * 0.11
            ctx.fillEllipse(in: CGRect(x: -dot, y: -dot, width: dot * 2, height: dot * 2))
            return true
        }
    }
}
