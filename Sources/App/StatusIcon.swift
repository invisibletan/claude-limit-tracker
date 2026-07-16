import AppKit
import UsageCore

/// Draws the colored progress ring shown in the menu bar.
enum StatusIcon {
    static func color(for state: HealthState) -> NSColor {
        switch state {
        case .good: return NSColor(calibratedRed: 0.25, green: 0.62, blue: 0.36, alpha: 1)
        case .warn: return NSColor(calibratedRed: 0.85, green: 0.58, blue: 0.13, alpha: 1)
        case .crit: return NSColor(calibratedRed: 0.82, green: 0.28, blue: 0.23, alpha: 1)
        }
    }

    static func ring(percent: Double?, state: HealthState) -> NSImage {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let lineWidth: CGFloat = 3
            let inset = lineWidth / 2 + 0.5
            let circleRect = rect.insetBy(dx: inset, dy: inset)

            // Track
            let track = NSBezierPath(ovalIn: circleRect)
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            track.stroke()

            // Progress arc, clockwise from 12 o'clock.
            let fraction = max(0, min(1, (percent ?? 0) / 100))
            if fraction > 0.01 {
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let radius = circleRect.width / 2
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * fraction,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color(for: state).setStroke()
                arc.stroke()
            }
            return true
        }
        // Colored (non-template) so the health state reads at a glance.
        image.isTemplate = false
        return image
    }
}
