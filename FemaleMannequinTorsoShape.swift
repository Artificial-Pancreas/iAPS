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
        p.move(to: CGPoint(x: minX + 0.46 * w, y: minY + 0.12 * h))

        // Top of neck flat line
        p.addLine(to: CGPoint(x: minX + 0.54 * w, y: minY + 0.12 * h))

        // Right neck/shoulder (elegant downward slope)
        p.addCurve(
            to: CGPoint(x: minX + 0.74 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.58 * w, y: minY + 0.12 * h),
            control2: CGPoint(x: minX + 0.68 * w, y: minY + 0.14 * h)
        )

        // Outer right shoulder to underarm/chest (slender and smooth)
        p.addCurve(
            to: CGPoint(x: minX + 0.70 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.76 * w, y: minY + 0.24 * h),
            control2: CGPoint(x: minX + 0.73 * w, y: minY + 0.30 * h)
        )

        // Waist curve (continuous, elegant concave taper inward to a beautiful defined waist)
        p.addCurve(
            to: CGPoint(x: minX + 0.60 * w, y: minY + 0.65 * h),
            control1: CGPoint(x: minX + 0.67 * w, y: minY + 0.45 * h),
            control2: CGPoint(x: minX + 0.61 * w, y: minY + 0.55 * h)
        )

        // Hip peak right (gorgeous flare, wider than shoulders)
        p.addCurve(
            to: CGPoint(x: minX + 0.76 * w, y: minY + 0.82 * h),
            control1: CGPoint(x: minX + 0.59 * w, y: minY + 0.72 * h),
            control2: CGPoint(x: minX + 0.76 * w, y: minY + 0.77 * h)
        )

        // Lower hip taper (gracefully curves back inward at the bottom)
        p.addCurve(
            to: CGPoint(x: minX + 0.68 * w, y: minY + 0.95 * h),
            control1: CGPoint(x: minX + 0.76 * w, y: minY + 0.87 * h),
            control2: CGPoint(x: minX + 0.71 * w, y: minY + 0.92 * h)
        )

        // Bottom flat line (slender)
        p.addLine(to: CGPoint(x: minX + 0.32 * w, y: minY + 0.95 * h))

        // Left lower hip taper (curving outward to peak)
        p.addCurve(
            to: CGPoint(x: minX + 0.24 * w, y: minY + 0.82 * h),
            control1: CGPoint(x: minX + 0.29 * w, y: minY + 0.92 * h),
            control2: CGPoint(x: minX + 0.24 * w, y: minY + 0.87 * h)
        )

        // Left waist sweep (continuous inward)
        p.addCurve(
            to: CGPoint(x: minX + 0.40 * w, y: minY + 0.65 * h),
            control1: CGPoint(x: minX + 0.24 * w, y: minY + 0.77 * h),
            control2: CGPoint(x: minX + 0.41 * w, y: minY + 0.72 * h)
        )

        // Left underarm sweep (continuous concave taper outward)
        p.addCurve(
            to: CGPoint(x: minX + 0.30 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.39 * w, y: minY + 0.55 * h),
            control2: CGPoint(x: minX + 0.33 * w, y: minY + 0.45 * h)
        )

        // Armhole / shoulder left
        p.addCurve(
            to: CGPoint(x: minX + 0.26 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.27 * w, y: minY + 0.30 * h),
            control2: CGPoint(x: minX + 0.24 * w, y: minY + 0.24 * h)
        )

        // Shoulder to neck (sloped collar)
        p.addCurve(
            to: CGPoint(x: minX + 0.46 * w, y: minY + 0.12 * h),
            control1: CGPoint(x: minX + 0.32 * w, y: minY + 0.14 * h),
            control2: CGPoint(x: minX + 0.42 * w, y: minY + 0.12 * h)
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
