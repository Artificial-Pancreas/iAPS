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
        p.move(to: CGPoint(x: minX + 0.44 * w, y: minY + 0.12 * h))

        // Top of neck flat line
        p.addLine(to: CGPoint(x: minX + 0.56 * w, y: minY + 0.12 * h))

        // Right neck/shoulder (elegant, gentle slope)
        p.addCurve(
            to: CGPoint(x: minX + 0.65 * w, y: minY + 0.20 * h),
            control1: CGPoint(x: minX + 0.59 * w, y: minY + 0.12 * h),
            control2: CGPoint(x: minX + 0.62 * w, y: minY + 0.15 * h)
        )

        // Outer right shoulder to underarm/chest (soft and smooth)
        p.addCurve(
            to: CGPoint(x: minX + 0.61 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.67 * w, y: minY + 0.24 * h),
            control2: CGPoint(x: minX + 0.64 * w, y: minY + 0.30 * h)
        )

        // Waist curve (continuous, gentle organic curve)
        p.addCurve(
            to: CGPoint(x: minX + 0.54 * w, y: minY + 0.62 * h),
            control1: CGPoint(x: minX + 0.58 * w, y: minY + 0.45 * h),
            control2: CGPoint(x: minX + 0.54 * w, y: minY + 0.54 * h)
        )

        // Hip peak right (slender hourglass, very soft flare)
        p.addCurve(
            to: CGPoint(x: minX + 0.63 * w, y: minY + 0.82 * h),
            control1: CGPoint(x: minX + 0.54 * w, y: minY + 0.70 * h),
            control2: CGPoint(x: minX + 0.63 * w, y: minY + 0.75 * h)
        )

        // Lower hip taper (gracefully curves back inward at the bottom)
        p.addCurve(
            to: CGPoint(x: minX + 0.58 * w, y: minY + 0.95 * h),
            control1: CGPoint(x: minX + 0.63 * w, y: minY + 0.88 * h),
            control2: CGPoint(x: minX + 0.60 * w, y: minY + 0.92 * h)
        )

        // Bottom flat line
        p.addLine(to: CGPoint(x: minX + 0.42 * w, y: minY + 0.95 * h))

        // Left lower hip taper
        p.addCurve(
            to: CGPoint(x: minX + 0.37 * w, y: minY + 0.82 * h),
            control1: CGPoint(x: minX + 0.40 * w, y: minY + 0.92 * h),
            control2: CGPoint(x: minX + 0.37 * w, y: minY + 0.88 * h)
        )

        // Left waist sweep
        p.addCurve(
            to: CGPoint(x: minX + 0.46 * w, y: minY + 0.62 * h),
            control1: CGPoint(x: minX + 0.37 * w, y: minY + 0.75 * h),
            control2: CGPoint(x: minX + 0.46 * w, y: minY + 0.70 * h)
        )

        // Left underarm sweep
        p.addCurve(
            to: CGPoint(x: minX + 0.39 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.46 * w, y: minY + 0.54 * h),
            control2: CGPoint(x: minX + 0.42 * w, y: minY + 0.45 * h)
        )

        // Left shoulder
        p.addCurve(
            to: CGPoint(x: minX + 0.35 * w, y: minY + 0.20 * h),
            control1: CGPoint(x: minX + 0.36 * w, y: minY + 0.30 * h),
            control2: CGPoint(x: minX + 0.33 * w, y: minY + 0.24 * h)
        )

        // Left shoulder to neck
        p.addCurve(
            to: CGPoint(x: minX + 0.44 * w, y: minY + 0.12 * h),
            control1: CGPoint(x: minX + 0.38 * w, y: minY + 0.15 * h),
            control2: CGPoint(x: minX + 0.41 * w, y: minY + 0.12 * h)
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
