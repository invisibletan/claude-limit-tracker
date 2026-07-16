import SwiftUI

/// Clawd, the little orange mascot: rounded clay-colored body, two raised
/// claws, and a friendly face. Pure vector so it stays crisp at any size.
struct ClawdView: View {
    var size: CGFloat = 20

    private let clay = Color(red: 0.85, green: 0.47, blue: 0.34)      // #D97757
    private let clayDark = Color(red: 0.72, green: 0.36, blue: 0.24)

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
                CGRect(x: x * w, y: y * h, width: rw * w, height: rh * h)
            }

            // Raised claws — two chunky pincers above the body.
            let clawShading = GraphicsContext.Shading.color(clayDark)
            var leftClaw = Path()
            leftClaw.addEllipse(in: rect(0.02, 0.10, 0.26, 0.26))
            context.fill(leftClaw, with: clawShading)
            var rightClaw = Path()
            rightClaw.addEllipse(in: rect(0.72, 0.10, 0.26, 0.26))
            context.fill(rightClaw, with: clawShading)
            // Pincer notches (cut a wedge from each claw with the background).
            var leftNotch = Path()
            leftNotch.move(to: CGPoint(x: 0.15 * w, y: 0.23 * h))
            leftNotch.addLine(to: CGPoint(x: 0.00 * w, y: 0.06 * h))
            leftNotch.addLine(to: CGPoint(x: 0.26 * w, y: 0.10 * h))
            leftNotch.closeSubpath()
            context.blendMode = .destinationOut
            context.fill(leftNotch, with: .color(.black))
            var rightNotch = Path()
            rightNotch.move(to: CGPoint(x: 0.85 * w, y: 0.23 * h))
            rightNotch.addLine(to: CGPoint(x: 1.00 * w, y: 0.06 * h))
            rightNotch.addLine(to: CGPoint(x: 0.74 * w, y: 0.10 * h))
            rightNotch.closeSubpath()
            context.fill(rightNotch, with: .color(.black))
            context.blendMode = .normal

            // Arms connecting claws to body.
            var arms = Path()
            arms.addRoundedRect(in: rect(0.10, 0.30, 0.12, 0.22), cornerSize: CGSize(width: 2, height: 2))
            arms.addRoundedRect(in: rect(0.78, 0.30, 0.12, 0.22), cornerSize: CGSize(width: 2, height: 2))
            context.fill(arms, with: clawShading)

            // Body.
            var body = Path()
            body.addRoundedRect(
                in: rect(0.14, 0.36, 0.72, 0.56),
                cornerSize: CGSize(width: 0.20 * w, height: 0.20 * h)
            )
            context.fill(body, with: .color(clay))

            // Eyes.
            var eyes = Path()
            eyes.addEllipse(in: rect(0.32, 0.52, 0.10, 0.14))
            eyes.addEllipse(in: rect(0.58, 0.52, 0.10, 0.14))
            context.fill(eyes, with: .color(.white))
            var pupils = Path()
            pupils.addEllipse(in: rect(0.35, 0.57, 0.05, 0.07))
            pupils.addEllipse(in: rect(0.61, 0.57, 0.05, 0.07))
            context.fill(pupils, with: .color(.black.opacity(0.85)))

            // Smile.
            var smile = Path()
            smile.move(to: CGPoint(x: 0.42 * w, y: 0.78 * h))
            smile.addQuadCurve(
                to: CGPoint(x: 0.58 * w, y: 0.78 * h),
                control: CGPoint(x: 0.50 * w, y: 0.86 * h)
            )
            context.stroke(smile, with: .color(.white.opacity(0.9)), lineWidth: max(1, 0.05 * w))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Clawd")
    }
}
