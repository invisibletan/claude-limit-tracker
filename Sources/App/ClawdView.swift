import SwiftUI

/// The Clawd critter, drawn static for the panel and Preferences headers —
/// the same mascot the menu bar animates.
struct ClawdView: View {
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: ClawdIcon.sprite(phase: 0.0, height: size))
            .accessibilityLabel("Clawd")
    }
}
