import SwiftUI

struct MannequinTorsoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let minX = rect.minX
        let minY = rect.minY

        // Start at neck top left
        path.move(to: CGPoint(x: minX + 0.46 * w, y: minY + 0.10 * h))

        // Top of neck flat line
        path.addLine(to: CGPoint(x: minX + 0.54 * w, y: minY + 0.10 * h))

        // Right neck/shoulder slope (strong, athletic downward slope)
        path.addCurve(
            to: CGPoint(x: minX + 0.78 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.58 * w, y: minY + 0.10 * h),
            control2: CGPoint(x: minX + 0.70 * w, y: minY + 0.12 * h)
        )

        // Outer right shoulder to underarm/chest (slender and smooth)
        path.addCurve(
            to: CGPoint(x: minX + 0.72 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.80 * w, y: minY + 0.24 * h),
            control2: CGPoint(x: minX + 0.76 * w, y: minY + 0.30 * h)
        )

        // Waist curve (gentle athletic taper inward, not exaggerated)
        path.addCurve(
            to: CGPoint(x: minX + 0.66 * w, y: minY + 0.65 * h),
            control1: CGPoint(x: minX + 0.70 * w, y: minY + 0.45 * h),
            control2: CGPoint(x: minX + 0.67 * w, y: minY + 0.55 * h)
        )

        // Hip line (gentle tapering inward, masculine hip)
        path.addCurve(
            to: CGPoint(x: minX + 0.68 * w, y: minY + 0.95 * h),
            control1: CGPoint(x: minX + 0.65 * w, y: minY + 0.75 * h),
            control2: CGPoint(x: minX + 0.67 * w, y: minY + 0.85 * h)
        )

        // Bottom flat line
        path.addLine(to: CGPoint(x: minX + 0.32 * w, y: minY + 0.95 * h))

        // Left hip taper
        path.addCurve(
            to: CGPoint(x: minX + 0.34 * w, y: minY + 0.65 * h),
            control1: CGPoint(x: minX + 0.33 * w, y: minY + 0.85 * h),
            control2: CGPoint(x: minX + 0.35 * w, y: minY + 0.75 * h)
        )

        // Left waist sweep (athletic taper)
        path.addCurve(
            to: CGPoint(x: minX + 0.28 * w, y: minY + 0.35 * h),
            control1: CGPoint(x: minX + 0.33 * w, y: minY + 0.55 * h),
            control2: CGPoint(x: minX + 0.30 * w, y: minY + 0.45 * h)
        )

        // Left underarm to shoulder
        path.addCurve(
            to: CGPoint(x: minX + 0.22 * w, y: minY + 0.18 * h),
            control1: CGPoint(x: minX + 0.24 * w, y: minY + 0.30 * h),
            control2: CGPoint(x: minX + 0.20 * w, y: minY + 0.24 * h)
        )

        // Left shoulder to neck
        path.addCurve(
            to: CGPoint(x: minX + 0.46 * w, y: minY + 0.10 * h),
            control1: CGPoint(x: minX + 0.30 * w, y: minY + 0.12 * h),
            control2: CGPoint(x: minX + 0.42 * w, y: minY + 0.10 * h)
        )

        path.closeSubpath()
        return path
    }
}

struct FemaleMannequinTorsoShape: Shape {
    func path(in rect: CGRect) -> Path {
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

struct MannequinArmShape: Shape {
    let isRight: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let minX = rect.minX
        let minY = rect.minY

        if isRight {
            // Start at outer shoulder
            path.move(to: CGPoint(x: minX + 0.78 * w, y: minY + 0.18 * h))
            // Outer curve down to elbow
            path.addCurve(
                to: CGPoint(x: minX + 0.84 * w, y: minY + 0.50 * h),
                control1: CGPoint(x: minX + 0.81 * w, y: minY + 0.26 * h),
                control2: CGPoint(x: minX + 0.85 * w, y: minY + 0.38 * h)
            )
            // Outer curve down to hand (reaching 0.95*h)
            path.addCurve(
                to: CGPoint(x: minX + 0.79 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.83 * w, y: minY + 0.65 * h),
                control2: CGPoint(x: minX + 0.81 * w, y: minY + 0.82 * h)
            )
            // Soft rounded point of hand
            path.addCurve(
                to: CGPoint(x: minX + 0.73 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.77 * w, y: minY + 0.96 * h),
                control2: CGPoint(x: minX + 0.75 * w, y: minY + 0.96 * h)
            )
            // Inner curve up to waist (torso waist is at 0.66*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.69 * w, y: minY + 0.50 * h),
                control1: CGPoint(x: minX + 0.74 * w, y: minY + 0.78 * h),
                control2: CGPoint(x: minX + 0.72 * w, y: minY + 0.65 * h)
            )
            // Inner curve up to underarm (torso underarm is at 0.72*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.74 * w, y: minY + 0.32 * h),
                control1: CGPoint(x: minX + 0.67 * w, y: minY + 0.44 * h),
                control2: CGPoint(x: minX + 0.71 * w, y: minY + 0.38 * h)
            )
        } else {
            // Start at outer shoulder
            path.move(to: CGPoint(x: minX + 0.22 * w, y: minY + 0.18 * h))
            // Outer curve down to elbow
            path.addCurve(
                to: CGPoint(x: minX + 0.16 * w, y: minY + 0.50 * h),
                control1: CGPoint(x: minX + 0.19 * w, y: minY + 0.26 * h),
                control2: CGPoint(x: minX + 0.15 * w, y: minY + 0.38 * h)
            )
            // Outer curve down to hand (reaching 0.95*h)
            path.addCurve(
                to: CGPoint(x: minX + 0.21 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.17 * w, y: minY + 0.65 * h),
                control2: CGPoint(x: minX + 0.19 * w, y: minY + 0.82 * h)
            )
            // Soft rounded point of hand
            path.addCurve(
                to: CGPoint(x: minX + 0.27 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.23 * w, y: minY + 0.96 * h),
                control2: CGPoint(x: minX + 0.25 * w, y: minY + 0.96 * h)
            )
            // Inner curve up to waist (torso waist is at 0.34*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.31 * w, y: minY + 0.50 * h),
                control1: CGPoint(x: minX + 0.26 * w, y: minY + 0.78 * h),
                control2: CGPoint(x: minX + 0.28 * w, y: minY + 0.65 * h)
            )
            // Inner curve up to underarm (torso underarm is at 0.28*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.26 * w, y: minY + 0.32 * h),
                control1: CGPoint(x: minX + 0.33 * w, y: minY + 0.44 * h),
                control2: CGPoint(x: minX + 0.29 * w, y: minY + 0.38 * h)
            )
        }
        path.closeSubpath()
        return path
    }
}

struct FemaleMannequinArmShape: Shape {
    let isRight: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let minX = rect.minX
        let minY = rect.minY

        if isRight {
            // Start at outer shoulder
            path.move(to: CGPoint(x: minX + 0.74 * w, y: minY + 0.18 * h))
            // Outer upper arm curve (slimmer outer boundary: 0.80*w instead of 0.81*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.80 * w, y: minY + 0.45 * h),
                control1: CGPoint(x: minX + 0.77 * w, y: minY + 0.25 * h),
                control2: CGPoint(x: minX + 0.81 * w, y: minY + 0.35 * h)
            )
            // Outer forearm (tapering down to wrist: 0.76*w at 0.80*h)
            path.addCurve(
                to: CGPoint(x: minX + 0.76 * w, y: minY + 0.80 * h),
                control1: CGPoint(x: minX + 0.79 * w, y: minY + 0.60 * h),
                control2: CGPoint(x: minX + 0.77 * w, y: minY + 0.70 * h)
            )
            // Hand (tapering to a soft point at 0.95*h)
            path.addCurve(
                to: CGPoint(x: minX + 0.73 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.75 * w, y: minY + 0.86 * h),
                control2: CGPoint(x: minX + 0.74 * w, y: minY + 0.91 * h)
            )
            // Soft rounded point of fingers to inner hand
            path.addCurve(
                to: CGPoint(x: minX + 0.70 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.72 * w, y: minY + 0.96 * h),
                control2: CGPoint(x: minX + 0.71 * w, y: minY + 0.96 * h)
            )
            // Inner hand to Inner wrist
            path.addCurve(
                to: CGPoint(x: minX + 0.71 * w, y: minY + 0.80 * h),
                control1: CGPoint(x: minX + 0.70 * w, y: minY + 0.91 * h),
                control2: CGPoint(x: minX + 0.71 * w, y: minY + 0.86 * h)
            )
            // Inner forearm (snug taper)
            path.addCurve(
                to: CGPoint(x: minX + 0.69 * w, y: minY + 0.45 * h),
                control1: CGPoint(x: minX + 0.71 * w, y: minY + 0.70 * h),
                control2: CGPoint(x: minX + 0.68 * w, y: minY + 0.58 * h)
            )
            // Inner bicep (snug against torso underarm 0.74*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.74 * w, y: minY + 0.35 * h),
                control1: CGPoint(x: minX + 0.69 * w, y: minY + 0.41 * h),
                control2: CGPoint(x: minX + 0.72 * w, y: minY + 0.38 * h)
            )
            // Shoulder attachment
            path.addCurve(
                to: CGPoint(x: minX + 0.74 * w, y: minY + 0.18 * h),
                control1: CGPoint(x: minX + 0.74 * w, y: minY + 0.30 * h),
                control2: CGPoint(x: minX + 0.74 * w, y: minY + 0.24 * h)
            )
        } else {
            // Start at outer shoulder
            path.move(to: CGPoint(x: minX + 0.26 * w, y: minY + 0.18 * h))
            // Outer upper arm curve (slimmer outer boundary: 0.20*w instead of 0.19*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.20 * w, y: minY + 0.45 * h),
                control1: CGPoint(x: minX + 0.23 * w, y: minY + 0.25 * h),
                control2: CGPoint(x: minX + 0.19 * w, y: minY + 0.35 * h)
            )
            // Outer forearm (tapering down to wrist: 0.24*w at 0.80*h)
            path.addCurve(
                to: CGPoint(x: minX + 0.24 * w, y: minY + 0.80 * h),
                control1: CGPoint(x: minX + 0.21 * w, y: minY + 0.60 * h),
                control2: CGPoint(x: minX + 0.23 * w, y: minY + 0.70 * h)
            )
            // Hand (tapering to a soft point at 0.95*h)
            path.addCurve(
                to: CGPoint(x: minX + 0.27 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.25 * w, y: minY + 0.86 * h),
                control2: CGPoint(x: minX + 0.26 * w, y: minY + 0.91 * h)
            )
            // Soft rounded point of fingers to inner hand
            path.addCurve(
                to: CGPoint(x: minX + 0.30 * w, y: minY + 0.95 * h),
                control1: CGPoint(x: minX + 0.28 * w, y: minY + 0.96 * h),
                control2: CGPoint(x: minX + 0.29 * w, y: minY + 0.96 * h)
            )
            // Inner hand to Inner wrist
            path.addCurve(
                to: CGPoint(x: minX + 0.29 * w, y: minY + 0.80 * h),
                control1: CGPoint(x: minX + 0.30 * w, y: minY + 0.91 * h),
                control2: CGPoint(x: minX + 0.29 * w, y: minY + 0.86 * h)
            )
            // Inner forearm (snug taper)
            path.addCurve(
                to: CGPoint(x: minX + 0.31 * w, y: minY + 0.45 * h),
                control1: CGPoint(x: minX + 0.29 * w, y: minY + 0.70 * h),
                control2: CGPoint(x: minX + 0.32 * w, y: minY + 0.58 * h)
            )
            // Inner bicep (snug against torso underarm 0.26*w)
            path.addCurve(
                to: CGPoint(x: minX + 0.26 * w, y: minY + 0.35 * h),
                control1: CGPoint(x: minX + 0.31 * w, y: minY + 0.41 * h),
                control2: CGPoint(x: minX + 0.28 * w, y: minY + 0.38 * h)
            )
            // Shoulder attachment
            path.addCurve(
                to: CGPoint(x: minX + 0.26 * w, y: minY + 0.18 * h),
                control1: CGPoint(x: minX + 0.26 * w, y: minY + 0.30 * h),
                control2: CGPoint(x: minX + 0.26 * w, y: minY + 0.24 * h)
            )
        }
        path.closeSubpath()
        return path
    }
}

struct HumanBodyThemeView: View {
    private enum Config {
        static let frameWidth: CGFloat = 280
        static let frameHeight: CGFloat = 150
        static let illustrationWidth: CGFloat = 160
        static let illustrationHeight: CGFloat = 140
        static let headWidth: CGFloat = 30
        static let headHeight: CGFloat = 38
        static let torsoCornerRadius: CGFloat = 20
        static let armWidth: CGFloat = 24
        static let armHeight: CGFloat = 70
        static let glucoseFontSize: CGFloat = 34
        static let fractionGlucoseFontSize: CGFloat = 28
        static let deltaFontSize: CGFloat = 12
        static let iobValueFontSize: CGFloat = 12
        static let cobValueFontSize: CGFloat = 14
        static let sensorFontSize: CGFloat = 12
        static let loopGlowSize: CGFloat = 180
        static let loopGlowBlur: CGFloat = 40
        static let loopGlowScale: CGFloat = 1.1
        static let illustrationVerticalOffset: CGFloat = 5
        static let brandingVerticalOffset: CGFloat = 0.50
        static let brandingHorizontalOffset: CGFloat = 0.9
    }

    let shape: FreeAPSSettings.MannequinType
    let recentGlucose: BloodGlucose?
    let glucoseDelta: Int?
    let units: GlucoseUnits
    let suggestion: Suggestion?
    let enactedSuggestion: Suggestion?
    let closedLoop: Bool
    let latestCOB: Decimal?
    let latestIOB: Decimal?
    let maxCOB: Decimal
    let maxIOB: Decimal
    let lowGlucose: Decimal
    let highGlucose: Decimal
    let alwaysUseColors: Bool
    let displayDelta: Bool
    let displaySAGE: Bool
    let displayExpiration: Bool
    let pumpSuspended: Bool
    let minimised: Bool
    let tempRate: Decimal?
    let pumpInfo: PumpDisplayInfo?
    let cgmInfo: CGMDisplayInfo?
    let sensorDays: Double
    let timerDate: Date
    let hideInsulinBadge: Bool

    let setupPump: () -> Void
    let openCGM: () -> Void
    let runLoop: () -> Void
    let showStatusPopup: () -> Void

    @FetchRequest(
        entity: InsulinConcentration.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
    ) var concentration: FetchedResults<InsulinConcentration>

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize
    @Environment(AppUIState.self) private var appUIState

    private var waistY: CGFloat {
        shape == .male ? 0.65 : 0.62
    }

    private var waistLeftX: CGFloat {
        shape == .male ? 0.34 : 0.36
    }

    private var waistRightX: CGFloat {
        shape == .male ? 0.66 : 0.64
    }

    private static let remainingTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let remainingTimeFormatterDays: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let mmolLFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let mgDlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private var iobFill: CGFloat {
        let substance = abs(Double(latestIOB ?? 0))
        guard substance != 0 else { return 0 }
        let maxVal = max(Double(maxIOB), 1)
        let fill = CGFloat(min(max(substance / maxVal, 0), 1))
        return max(fill, 0.1)
    }

    private var cobFill: CGFloat {
        let substance = Double(latestCOB ?? 0)
        guard substance > 0 else { return 0 }
        let maxVal = max(Double(maxCOB), 1)
        let fill = CGFloat(min(max(substance / maxVal, 0), 1))
        return max(fill, 0.1)
    }

    private var cgmFill: CGFloat {
        guard let date = appUIState.cgmStatus?.sessionStartDate ?? recentGlucose?.sessionStartDate else { return 0 }
        let sensorAge = timerDate.timeIntervalSince(date)
        let totalSensorTime = sensorDays * 8.64E4
        return CGFloat(min(max(1 - (sensorAge / totalSensorTime), 0), 1))
    }

    private var loopColor: Color {
        let lastLoopDate = appUIState.lastLoopDate
        let manualTempBasal = appUIState.manualTempBasal
        guard actualSuggestion?.timestamp != nil else { return .loopGray }
        guard manualTempBasal == false else { return .loopManualTemp }
        let delta = timerDate.timeIntervalSince(lastLoopDate ?? .distantPast) - 30
        if delta <= 8 * 60 {
            return actualSuggestion?.deliverAt != nil ? .loopGreen : .loopYellow
        } else if delta <= 12 * 60 {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    private var actualSuggestion: Suggestion? {
        closedLoop && enactedSuggestion?.recieved == true ? enactedSuggestion : suggestion
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(loopColor.opacity(0.15))
                .frame(width: Config.loopGlowSize, height: Config.loopGlowSize)
                .blur(radius: Config.loopGlowBlur)
                .scaleEffect(Config.loopGlowScale)

            bodyType()
                .offset(y: Config.illustrationVerticalOffset)
                .onTapGesture { showStatusPopup() }
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    runLoop()
                }
        }
        .frame(width: Config.frameWidth / (minimised == true ? 2 : 1), height: Config.frameHeight / (minimised == true ? 2 : 1))
    }

    @ViewBuilder private func bodyType() -> some View {
        if shape == .male {
            illustrationView(
                torso: MannequinTorsoShape(),
                armRight: MannequinArmShape(isRight: true),
                armLeft: MannequinArmShape(isRight: false)
            )
        } else {
            illustrationView(
                torso: FemaleMannequinTorsoShape(),
                armRight: FemaleMannequinArmShape(isRight: true),
                armLeft: FemaleMannequinArmShape(isRight: false)
            )
        }
    }

    @ViewBuilder private func illustrationView<T: Shape, A: Shape>(torso: T, armRight: A, armLeft: A) -> some View {
        let bW: CGFloat = Config.illustrationWidth
        let bH: CGFloat = Config.illustrationHeight

        ZStack {
            // --- 1. ARMS (Below Torso) ---
            Group {
                armLeft
                    .fill(colorScheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.15))
                armRight
                    .fill(colorScheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.15))

                // IOB Fill (Left Arm)
                armLeft
                    .fill(LinearGradient(
                        colors: [(latestIOB ?? 0) < 0 ? .red : .insulin, .insulin.opacity(0.4)],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .mask(VStack(spacing: 0) {
                        Spacer()
                        Rectangle().frame(height: bH * 0.32 * iobFill)
                        Spacer().frame(height: bH * 0.05)
                    }.frame(width: bW, height: bH))

                // Arm Strokes
                armLeft
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.2), lineWidth: 0.3)
                armRight
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.2), lineWidth: 0.3)
            }
            .frame(width: bW, height: bH)

            // --- 2. TORSO ---
            Group {
                // Torso Solid Background (Prevents arms from shining through the transparent lower abdomen)
                torso
                    .fill(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.5))

                // Torso Base with Shadows (Masked to Chest)
                torso
                    .fill(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.5))
                    .shadow(color: Color.white.opacity(colorScheme == .dark ? 0.1 : 0.8), radius: 4, x: -3, y: -3)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 4, x: 3, y: 3)
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.black).frame(height: bH * waistY)
                            Rectangle().fill(Color.clear)
                        }
                    )

                // Torso Gradient (Masked to Chest)
                torso
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.black.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.black).frame(height: bH * waistY)
                            Rectangle().fill(Color.clear)
                        }
                    )

                // Abdomen - Weak Yellow Shade
                torso
                    .fill(Color.loopYellow.opacity(0.06))
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.clear).frame(height: bH * waistY)
                            Rectangle().fill(Color.black)
                        }
                    )

                // COB Fill (Inside Torso)
                torso
                    .fill(LinearGradient(
                        colors: [Color.loopYellow.opacity(0.6), Color.loopYellow.opacity(0.2)],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .mask(VStack(spacing: 0) {
                        Spacer()
                        Rectangle().frame(height: bH * (0.95 - waistY) * cobFill)
                        Spacer().frame(height: bH * 0.05)
                    }.frame(width: bW, height: bH))

                // Torso Stroke
                torso
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.clear, Color.black.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .frame(width: bW, height: bH)

            headView(bH: bH)
            brandingView(bW: bW, bH: bH)
            metabolicDataView(bW: bW, bH: bH)
            equipmentView(bW: bW, bH: bH)

        }.scaleEffect(x: minimised ? 0.5 : 1, y: minimised ? 0.5 : 1)
    }

    private func headView(bH: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(loopColor.opacity(colorScheme == .dark ? 0.1 : 0.25))
                .frame(width: Config.headWidth, height: Config.headHeight)
                .background(
                    Ellipse()
                        .fill(loopColor.opacity(colorScheme == .dark ? 0.15 : 0.4))
                        .shadow(color: Color.white.opacity(0.5), radius: 3, x: -2, y: -2)
                        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 2, y: 2)
                )
                .overlay(Ellipse().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: loopColor.opacity(0.4), radius: 6)

            if let lastLoopDate = appUIState.lastLoopDate {
                let minutes = Int(timerDate.timeIntervalSince(lastLoopDate) / 60)
                Text("\(minutes)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 1)
            }
        }
        .offset(y: -bH * 0.48)
    }

    private func brandingView(bW: CGFloat, bH: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("i").font(.system(size: 12, design: .rounded)).offset(y: 0.4)
            Text("APS").font(.system(size: 15, design: .rounded))
        }
        .foregroundStyle(.secondary.opacity(0.7))
        .carvingOrRelief(carve: colorScheme == .light)
        .offset(x: -bW * Config.brandingHorizontalOffset, y: -bH * Config.brandingVerticalOffset)
    }

    private func metabolicDataView(bW: CGFloat, bH: CGFloat) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: bW * waistLeftX, y: bH * waistY))
                path.addLine(to: CGPoint(x: bW * waistRightX, y: bH * waistY))
            }
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

            VStack(spacing: -2) {
                if let recent = recentGlucose {
                    let val = Double(units == .mmolL ? recent.glucose.asMmolL : Decimal(recent.glucose))
                    let statusColor = alwaysUseColors ? colorOfGlucose(recent.glucose) :
                        (appUIState.glucoseAlarm == nil ? .primary : .loopRed)
                    let glucoseString = units == .mmolL ? (Self.mmolLFormatter.string(from: val as NSNumber) ?? "") :
                        (Self.mgDlFormatter.string(from: val as NSNumber) ?? "")
                    let glucoseComponents = glucoseString.components(separatedBy: NumberFormatter().decimalSeparator)

                    if glucoseComponents.count == 2 {
                        HStack(spacing: 0) {
                            Text(glucoseComponents[0])
                                .font(.glucoseBodyFont)
                                .fontWeight(.black)
                            Text(NumberFormatter().decimalSeparator)
                                .font(.system(size: 28)).baselineOffset(-5)
                                .offset(x: NumberFormatter().decimalSeparator == "," ? -2 : 0)
                            Text(glucoseComponents[1])
                                .font(.system(size: 28)).baselineOffset(-5)
                                .offset(x: NumberFormatter().decimalSeparator == "," ? -2 : 0)
                        }
                        .foregroundStyle(statusColor)
                    } else {
                        Text(Self.mgDlFormatter.string(from: val as NSNumber) ?? "")
                            .font(minimised ? .glucoseSmallFont : .glucoseBodyFont)
                            .fontWeight(.black)
                            .foregroundStyle(statusColor)
                    }

                    HStack(spacing: 4) {
                        if let dir = recent
                            .direction { Image(systemName: dir.sfSymbol).font(.system(size: 16, weight: .bold)) }
                    }.foregroundStyle(statusColor.opacity(0.8), .clear)
                }
            }
            .offset(y: -bH * 0.10)

            VStack(spacing: 2) {
                Text("COB").font(.system(size: 8, weight: .black)).foregroundColor(.secondary)
                Text(Self.mmolLFormatter.string(from: (latestCOB ?? 0) as NSNumber) ?? "0")
                    .font(.system(size: Config.cobValueFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .offset(y: bH * 0.30)
        }
        .frame(width: bW, height: bH)
        .dynamicTypeSize(...DynamicTypeSize.medium)
    }

    private func equipmentView(bW: CGFloat, bH: CGFloat) -> some View {
        ZStack {
            let pumpExpiration = pumpInfo?.expiresAt.map { max(0, $0.timeIntervalSince(timerDate)) }

            VStack(spacing: 2) {
                Text("IOB").font(.system(size: 8, weight: .black)).foregroundColor(.secondary)
                Text(Self.mmolLFormatter.string(from: (latestIOB ?? 0) as NSNumber) ?? "0")
                    .font(.system(size: Config.iobValueFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke((latestIOB ?? 0) < 0 ? Color.red.opacity(0.2) : Color.insulin.opacity(0.2), lineWidth: 1)
            )
            .offset(x: -bW * (shape == .female ? 0.41 : 0.47), y: 60)

            HStack(spacing: 2) {
                if let expiration = pumpExpiration {
                    Text("\(Int(expiration / 86400))d").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(expiration < 86400 ? .red : .secondary)
                }
                pumpIllustration.scaleEffect(0.75)
            }
            .offset(
                x: -bW * (shape == .female ? (pumpExpiration != nil ? 0.43 : 0.39) : (pumpExpiration != nil ? 0.46 : 0.42)),
                y: -bH * 0.08
            )

            let cgmDate = appUIState.cgmStatus?.sessionStartDate ?? recentGlucose?.sessionStartDate
            let cgmExpiration = cgmDate.map { max(0, (sensorDays * 86400) - timerDate.timeIntervalSince($0)) }
            HStack(spacing: 2) {
                cgmIllustration.scaleEffect(0.75)
                if let expiration = cgmExpiration {
                    let sensorAge = cgmDate.map { timerDate.timeIntervalSince($0) } ?? 0
                    let minutesAndHours = (displayExpiration && expiration < 1 * 8.64E4) ||
                        (displaySAGE && sensorAge < 1 * 8.64E4)
                    let timeToShow = displayExpiration ? expiration : sensorAge

                    Text(
                        minutesAndHours ? (Self.remainingTimeFormatter.string(from: timeToShow) ?? "")
                            .replacingOccurrences(of: ",", with: " ") :
                            (Self.remainingTimeFormatterDays.string(from: timeToShow) ?? "")
                            .replacingOccurrences(of: ",", with: " ")
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(expiration < 86400 ? .red : .secondary)
                }
            }
            .offset(
                x: bW * (shape == .female ? (cgmExpiration != nil ? 0.46 : 0.42) : (cgmExpiration != nil ? 0.52 : 0.48)),
                y: -bH * 0.12 + 3
            )
        }
    }

    @ViewBuilder private var concentrationBadge: some View {
        if let conc = concentration.last?.concentration, conc != 1, !hideInsulinBadge {
            let concString = "U" + String(format: "%.0f", conc * 100)
            Text(concString)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
    }

    private var pumpIllustration: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(
                        colors: [.gray.opacity(0.8), .gray.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )).frame(width: 26, height: 40)
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.2)).frame(width: 20, height: 24)
                        .overlay(VStack(spacing: 0) {
                            if case let .units(insulin) = appUIState.pumpReservoir { Spacer(minLength: 0)
                                Rectangle().fill(pumpSuspended ? .red : .insulin)
                                    .frame(height: 24 * min(1, Double(insulin) / 200.0))
                                    .opacity(0.7) } })
                    if case let .units(insulin) = appUIState
                        .pumpReservoir { Text("\(Int(insulin))").font(.system(size: 8, weight: .black)).foregroundColor(.white) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.3), lineWidth: 0.5))

            concentrationBadge
                .offset(x: 10, y: -6)
        }
        .onTapGesture { setupPump() }
    }

    private var cgmIllustration: some View {
        VStack {
            if let date = appUIState.cgmStatus?.sessionStartDate ?? recentGlucose?.sessionStartDate {
                let age = timerDate.timeIntervalSince(date)
                let total = sensorDays * 8.64E4
                let expiration = max(0, total - age)
                Sage(
                    amount: age,
                    expiration: expiration,
                    lineColour: age >= total - 86400 ? .red :
                        (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.05)),
                    sensordays: total
                )
                .frame(width: 34, height: 34).shadow(radius: 3).onTapGesture { openCGM() }
            }
        }
    }

    private var glucoseOverlay: some View { EmptyView() }

    private func colorOfGlucose(_ glucose: Int) -> Color {
        let low = Double(truncating: lowGlucose as NSNumber)
        let high = Double(truncating: highGlucose as NSNumber)
        switch Double(glucose) {
        case 0 ..< low: return .loopRed
        case low ..< high: return .loopGreen
        default: return .loopYellow
        }
    }
}
