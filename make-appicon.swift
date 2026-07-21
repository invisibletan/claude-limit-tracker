import Foundation
import AppKit

/// Generates `AppIcon.icns` from the shared `ClawdSprite` — the app icon is the
/// same coral Clawd as the menu bar, centered on a macOS-style warm rounded-rect,
/// so the two can never drift. Run via build.sh:
///
///     swiftc -O make-appicon.swift Sources/App/ClawdSprite.swift -o gen && ./gen AppIcon.icns
///
/// Renders every `.iconset` size directly (crisper than downsampling one master)
/// then calls `iconutil -c icns`.
@main
enum AppIconGen {
    // macOS Big Sur icon grid: the rounded-rect art fills ~80.5% of the canvas
    // (≈824/1024), with a circular-arc corner radius of ~22.37% of that side.
    // (A true continuous-corner squircle would match Apple's shape even more
    // closely; the circular arc already reads as a native icon at these sizes.)
    static let contentInsetFraction: CGFloat = 0.098
    static let cornerFraction: CGFloat = 0.2237
    // Clawd occupies ~60% of the rounded-rect width, vertically centered.
    static let clawdWidthFraction: CGFloat = 0.60

    static func main() throws {
        let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

        // pixel size → iconset filenames rendered at that size
        let sizes: [(px: Int, names: [String])] = [
            (16,   ["icon_16x16.png"]),
            (32,   ["icon_16x16@2x.png", "icon_32x32.png"]),
            (64,   ["icon_32x32@2x.png"]),
            (128,  ["icon_128x128.png"]),
            (256,  ["icon_128x128@2x.png", "icon_256x256.png"]),
            (512,  ["icon_256x256@2x.png", "icon_512x512.png"]),
            (1024, ["icon_512x512@2x.png"]),
        ]

        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("Clawd-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }

        for (px, names) in sizes {
            let png = try renderPNG(size: px)
            for name in names {
                try png.write(to: iconset.appendingPathComponent(name))
            }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = ["-c", "icns", iconset.path, "-o", output]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw IconError.iconutilFailed(task.terminationStatus)
        }
        print("Wrote \(output)")
    }

    /// Render the icon at `size`×`size` and return PNG bytes.
    static func renderPNG(size: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            // Device-independent space so the generated icon is byte-identical
            // across machines (deviceRGB varies with the host display profile).
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw IconError.renderFailed
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        drawIcon(cg: ctx.cgContext, size: CGFloat(size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw IconError.encodeFailed
        }
        return data
    }

    static func drawIcon(cg: CGContext, size s: CGFloat) {
        cg.clear(CGRect(x: 0, y: 0, width: s, height: s))

        let inset = s * contentInsetFraction
        let side = s - inset * 2
        let radius = side * cornerFraction
        let rrect = NSRect(x: inset, y: inset, width: side, height: side)
        let path = NSBezierPath(roundedRect: rrect, xRadius: radius, yRadius: radius)

        // Warm cream vertical gradient so the coral Clawd pops on light and dark
        // Finder/Notification backdrops alike.
        let top = NSColor(srgbRed: 0xFC / 255, green: 0xF4 / 255, blue: 0xEE / 255, alpha: 1)
        let bottom = NSColor(srgbRed: 0xF5 / 255, green: 0xE4 / 255, blue: 0xD6 / 255, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

        // Faint edge so the rounded rect stays defined on a white background.
        NSColor(srgbRed: 0xE7 / 255, green: 0xD3 / 255, blue: 0xC3 / 255, alpha: 1).setStroke()
        path.lineWidth = max(1, s * 0.004)
        path.stroke()

        let clawdW = side * clawdWidthFraction
        let clawdH = clawdW * CGFloat(ClawdSprite.gridH / ClawdSprite.gridW)
        let clawdRect = CGRect(x: (s - clawdW) / 2, y: (s - clawdH) / 2, width: clawdW, height: clawdH)
        ClawdSprite.draw(ctx: cg, rect: clawdRect, phase: 0)
    }

    enum IconError: LocalizedError {
        case renderFailed, encodeFailed
        case iconutilFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "failed to create the bitmap rendering context"
            case .encodeFailed: return "failed to encode the icon PNG"
            case .iconutilFailed(let code): return "iconutil failed with exit code \(code)"
            }
        }
    }
}
