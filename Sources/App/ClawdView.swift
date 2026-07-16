import SwiftUI

/// The Claude spark mark, drawn static for the panel and Preferences headers —
/// the same starburst the menu bar mascot animates.
struct ClawdView: View {
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: SparkIcon.image(angleDegrees: 0, color: SparkIcon.clay, size: size))
            .accessibilityLabel("Clawd")
    }
}
