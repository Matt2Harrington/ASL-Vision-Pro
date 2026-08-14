import SwiftUI

/// Phase 1 debug overlay: draws the extracted landmarks so you can confirm tracking is
/// working on real hardware before any model exists. Hands in cyan, body in yellow,
/// face in magenta. Normalized [0,1] coordinates are mapped to the view bounds.
struct LandmarkOverlayView: View {
    let frame: SignFrame

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(frame.leftHand,  in: &context, size: size, color: .cyan)
                draw(frame.rightHand, in: &context, size: size, color: .cyan)
                draw(frame.body,      in: &context, size: size, color: .yellow)
                draw(frame.face,      in: &context, size: size, color: .pink)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private func draw(_ points: [Landmark], in context: inout GraphicsContext,
                      size: CGSize, color: Color) {
        for lm in points {
            let p = CGPoint(x: lm.position.x * size.width,
                            y: (1 - lm.position.y) * size.height)   // Vision origin is bottom-left
            let dot = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            context.fill(dot, with: .color(color.opacity(Double(lm.confidence))))
        }
    }
}
