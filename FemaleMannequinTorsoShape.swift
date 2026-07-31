import SwiftUI

public struct FemaleMannequinTorsoShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let minX = rect.minX
        let minY = rect.minY

        // Start at neck top center
        p.move(to: CGPoint(x: minX + 0.5 * w, y: minY + 0.1 * h))

        // Right neck/shoulder
        p.addCurve(
            to: CGPoint(x: minX + 0.75 * w, y: minY + 0.16 * h),
            control1: CGPoint(x: minX + 0.60 * w, y: minY + 0.1 * h),
            control2: CGPoint(x: minX + 0.70 * w, y: minY + 0.12 * h)
        )

        // Outer right shoulder to armhole
        p.addCurve(
            to: CGPoint(x: minX + 0.85 * w, y: minY + 0.28 * h),
            control1: CGPoint(x: minX + 0.82 * w, y: minY + 0.18 * h),
            control2: CGPoint(x: minX + 0.85 * w, y: minY + 0.22 * h)
        )

        // Bust curve
        p.addCurve(
            to: CGPoint(x: minX + 0.65 * w, y: minY + 0.45 * h),
            control1: CGPoint(x: minX + 0.85 * w, y: minY + 0.35 * h),
            control2: CGPoint(x: minX + 0.75 * w, y: minY + 0.42 * h)
        )

        // Waist curve (narrower)
        p.addCurve(
            to: CGPoint(x: minX + 0.60 * w, y: minY + 0.55 * h),
            control1: CGPoint(x: minX + 0.62 * w, y: minY + 0.48 * h),
            control2: CGPoint(x: minX + 0.60 * w, y: minY + 0.52 * h)
        )

        // Hip curve right (wider)
        p.addCurve(
            to: CGPoint(x: minX + 0.80 * w, y: minY + 0.85 * h),
            control1: CGPoint(x: minX + 0.60 * w, y: minY + 0.65 * h),
            control2: CGPoint(x: minX + 0.80 * w, y: minY + 0.75 * h)
        )

        // Bottom right to bottom center
        p.addCurve(
            to: CGPoint(x: minX + 0.50 * w, y: minY + 0.98 * h),
            control1: CGPoint(x: minX + 0.80 * w, y: minY + 0.95 * h),
            control2: CGPoint(x: minX + 0.65 * w, y: minY + 0.98 * h)
        )

        // Hip curve left
        p.addCurve(
            to: CGPoint(x: minX + 0.20 * w, y: minY + 0.85 * h),
            control1: CGPoint(x: minX + 0.35 * w, y: minY + 0.98 * h),
            control2: CGPoint(x: minX + 0.20 * w, y: minY + 0.95 * h)
        )

        // Waist left
        p.addCurve(
            to: CGPoint(x: minX + 0.40 * w, y: minY + 0.55 * h),
            control1: CGPoint(x: minX + 0.20 * w, y: minY + 0.75 * h),
            control2: CGPoint(x: minX + 0.40 * w, y: minY + 0.65 * h)
        )

        // Bust left
        p.addCurve(
            to: CGPoint(x: minX + 0.35 * w, y: minY + 0.45 * h),
            control1: CGPoint(x: minX + 0.40 * w, y: minY + 0.52 * h),
            control2: CGPoint(x: minX + 0.38 * w, y: minY + 0.48 * h)
        )

        // Armhole / shoulder left
        p.addCurve(
            to: CGPoint(x: minX + 0.15 * w, y: minY + 0.28 * h),
            control1: CGPoint(x: minX + 0.25 * w, y: minY + 0.42 * h),
            control2: CGPoint(x: minX + 0.15 * w, y: minY + 0.35 * h)
        )
        p.addCurve(
            to: CGPoint(x: minX + 0.25 * w, y: minY + 0.16 * h),
            control1: CGPoint(x: minX + 0.15 * w, y: minY + 0.22 * h),
            control2: CGPoint(x: minX + 0.18 * w, y: minY + 0.18 * h)
        )
        p.addCurve(
            to: CGPoint(x: minX + 0.50 * w, y: minY + 0.1 * h),
            control1: CGPoint(x: minX + 0.30 * w, y: minY + 0.12 * h),
            control2: CGPoint(x: minX + 0.40 * w, y: minY + 0.1 * h)
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
