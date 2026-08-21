import SwiftUI

public struct FemaleMannequinTorsoShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let minX = rect.minX
        let minY = rect.minY

        // Start at neck top left
        p.move(to: CGPoint(x: minX + 0.47 * w, y: minY + 0.10 * h))

        // Top of neck flat line
        p.addLine(to: CGPoint(x: minX + 0.53 * w, y: minY + 0.10 * h))

        // Right neck/shoulder (elegant downward slope)
        p.addCurve(
            to: CGPoint(x: minX + 0.74 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.57 * w, y: minY + 0.10 * h),
            control2: CGPoint(x: minX + 0.68 * w, y: minY + 0.12 * h)
        )

        // Outer right shoulder to underarm/chest (widened from 0.69*w to 0.72*w to fit glucose text)
        p.addCurve(
            to: CGPoint(x: minX + 0.74 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.77 * w, y: minY + 0.24 * h),
            control2: CGPoint(x: minX + 0.75 * w, y: minY + 0.30 * h)
        )

        // Waist curve (continuous, elegant concave taper inward to a beautiful defined waist, widened from 0.63 to 0.64)
        p.addCurve(
            to: CGPoint(x: minX + 0.64 * w, y: minY + 0.62 * h),
            control1: CGPoint(x: minX + 0.69 * w, y: minY + 0.45 * h),
            control2: CGPoint(x: minX + 0.64 * w, y: minY + 0.54 * h)
        )

        // Hip peak right (gorgeous flare, narrowed from 0.75 to 0.71 to make lower part less protruding)
        p.addCurve(
            to: CGPoint(x: minX + 0.71 * w, y: minY + 0.82 * h),
            control1: CGPoint(x: minX + 0.64 * w, y: minY + 0.70 * h),
            control2: CGPoint(x: minX + 0.71 * w, y: minY + 0.75 * h)
        )

        // Lower hip taper (gracefully curves back inward at the bottom)
        p.addCurve(
            to: CGPoint(x: minX + 0.66 * w, y: minY + 0.95 * h),
            control1: CGPoint(x: minX + 0.71 * w, y: minY + 0.88 * h),
            control2: CGPoint(x: minX + 0.68 * w, y: minY + 0.92 * h)
        )

        // Bottom flat line (slender)
        p.addLine(to: CGPoint(x: minX + 0.34 * w, y: minY + 0.95 * h))

        // Left lower hip taper (curving outward to peak, narrowed from 0.25 to 0.29 to be less protruding and perfectly symmetric)
        p.addCurve(
            to: CGPoint(x: minX + 0.29 * w, y: minY + 0.82 * h),
            control1: CGPoint(x: minX + 0.32 * w, y: minY + 0.92 * h),
            control2: CGPoint(x: minX + 0.29 * w, y: minY + 0.88 * h)
        )

        // Left waist sweep (continuous inward, perfectly symmetric)
        p.addCurve(
            to: CGPoint(x: minX + 0.36 * w, y: minY + 0.62 * h),
            control1: CGPoint(x: minX + 0.29 * w, y: minY + 0.75 * h),
            control2: CGPoint(x: minX + 0.36 * w, y: minY + 0.70 * h)
        )

        // Left underarm sweep (continuous concave taper outward, perfectly symmetric)
        p.addCurve(
            to: CGPoint(x: minX + 0.26 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.36 * w, y: minY + 0.54 * h),
            control2: CGPoint(x: minX + 0.31 * w, y: minY + 0.45 * h)
        )

        // Armhole / shoulder left
        p.addCurve(
            to: CGPoint(x: minX + 0.26 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.25 * w, y: minY + 0.30 * h),
            control2: CGPoint(x: minX + 0.23 * w, y: minY + 0.24 * h)
        )

        // Shoulder to neck (sloped collar)
        p.addCurve(
            to: CGPoint(x: minX + 0.47 * w, y: minY + 0.10 * h),
            control1: CGPoint(x: minX + 0.32 * w, y: minY + 0.12 * h),
            control2: CGPoint(x: minX + 0.43 * w, y: minY + 0.10 * h)
        )

        p.closeSubpath()

        return p
    }
}

#Preview("Female torso shape") {
    FemaleMannequinTorsoShape()
        .fill(.pink.opacity(0.4))
        .frame(width: 200, height: 300)
        .overlay(
            FemaleMannequinTorsoShape().stroke(.pink, lineWidth: 2)
        )
        .padding()
}
