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
        p.move(to: CGPoint(x: minX + 0.45 * w, y: minY + 0.12 * h))

        // Top of neck flat line
        p.addLine(to: CGPoint(x: minX + 0.55 * w, y: minY + 0.12 * h))

        // Right neck/shoulder
        p.addCurve(
            to: CGPoint(x: minX + 0.80 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.62 * w, y: minY + 0.12 * h),
            control2: CGPoint(x: minX + 0.72 * w, y: minY + 0.14 * h)
        )

        // Outer right shoulder to armhole
        p.addCurve(
            to: CGPoint(x: minX + 0.74 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.82 * w, y: minY + 0.24 * h),
            control2: CGPoint(x: minX + 0.78 * w, y: minY + 0.30 * h)
        )

        // Bust curve (bulges out slightly for pronounced form)
        p.addCurve(
            to: CGPoint(x: minX + 0.77 * w, y: minY + 0.45 * h),
            control1: CGPoint(x: minX + 0.72 * w, y: minY + 0.37 * h),
            control2: CGPoint(x: minX + 0.78 * w, y: minY + 0.41 * h)
        )

        // Waist curve (narrower hourglass contour, matched to male height 0.65)
        p.addCurve(
            to: CGPoint(x: minX + 0.65 * w, y: minY + 0.65 * h),
            control1: CGPoint(x: minX + 0.76 * w, y: minY + 0.49 * h),
            control2: CGPoint(x: minX + 0.63 * w, y: minY + 0.58 * h)
        )

        // Hip curve right (wider)
        p.addCurve(
            to: CGPoint(x: minX + 0.77 * w, y: minY + 0.95 * h),
            control1: CGPoint(x: minX + 0.67 * w, y: minY + 0.72 * h),
            control2: CGPoint(x: minX + 0.76 * w, y: minY + 0.85 * h)
        )

        // Bottom flat line
        p.addLine(to: CGPoint(x: minX + 0.23 * w, y: minY + 0.95 * h))

        // Hip curve left
        p.addCurve(
            to: CGPoint(x: minX + 0.35 * w, y: minY + 0.65 * h),
            control1: CGPoint(x: minX + 0.24 * w, y: minY + 0.85 * h),
            control2: CGPoint(x: minX + 0.33 * w, y: minY + 0.72 * h)
        )

        // Waist left
        p.addCurve(
            to: CGPoint(x: minX + 0.23 * w, y: minY + 0.45 * h),
            control1: CGPoint(x: minX + 0.37 * w, y: minY + 0.58 * h),
            control2: CGPoint(x: minX + 0.24 * w, y: minY + 0.49 * h)
        )

        // Bust left
        p.addCurve(
            to: CGPoint(x: minX + 0.26 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.22 * w, y: minY + 0.41 * h),
            control2: CGPoint(x: minX + 0.28 * w, y: minY + 0.37 * h)
        )

        // Armhole / shoulder left
        p.addCurve(
            to: CGPoint(x: minX + 0.20 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.22 * w, y: minY + 0.30 * h),
            control2: CGPoint(x: minX + 0.18 * w, y: minY + 0.24 * h)
        )

        // Shoulder to neck
        p.addCurve(
            to: CGPoint(x: minX + 0.45 * w, y: minY + 0.12 * h),
            control1: CGPoint(x: minX + 0.28 * w, y: minY + 0.14 * h),
            control2: CGPoint(x: minX + 0.38 * w, y: minY + 0.12 * h)
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
