import SwiftUI

/// The Clawd critter, drawn static for the panel and Preferences headers —
/// the same mascot the menu bar animates (there wrapped in the usage ring).
struct ClawdView: View {
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: ClawdIcon.image(percent: nil, state: .good, phase: 0.0, size: size, showRing: false))
            .accessibilityLabel("Clawd")
    }
}
