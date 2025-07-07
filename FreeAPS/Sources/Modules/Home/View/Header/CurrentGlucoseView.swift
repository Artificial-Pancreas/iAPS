import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var recentGlucose: BloodGlucose?
    @Binding var timerDate: Date
    @Binding var delta: Int?
    @Binding var units: GlucoseUnits
    @Binding var alarm: GlucoseAlarm?
    @Binding var lowGlucose: Decimal
    @Binding var highGlucose: Decimal
    @Binding var bolusProgress: Double?
    @Binding var displayDelta: Bool
    @Binding var alwaysUseColors: Bool
    @Binding var scrolling: Bool
    @Binding var displayExpiration: Bool
    @Binding var cgm: CGMType
    @Binding var sensordays: Double

    // @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize

    @State private var rotationDegrees: Double = 0
    @State private var bumpEffect: Double = 0

    // var backgroundColor: Color //falls triangel während bolus in backgroundColor gewünscht ist

    // Bedingte Farbauswahl für das Dreieck
    private var currentTriangleColor: Color {
        if let progress = bolusProgress, progress < 1.0 {
            return Color.clear
        } else {
            return Color.white
        }
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = units == .mmolL ? 1 : 0
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "  +"
        formatter.negativePrefix = "  -"
        return formatter
    }

    private var timaAgoFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var daysFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        return formatter
    }

    private var remainingTimeFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        return formatter
    }

    private var remainingTimeFormatterDays: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .short
        return formatter
    }

    private func deltaView(_ deltaInt: Int) -> some View {
        ZStack {
            let deltaConverted = units == .mmolL ? deltaInt.asMmolL : Decimal(deltaInt)
            let string = deltaFormatter.string(from: deltaConverted as NSNumber) ?? ""
            let offset: CGFloat = -7

            Text(string)
                .font(.callout).foregroundStyle(.secondary)
                .offset(x: offset, y: 10)
        }
        .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.large)
        .frame(maxHeight: .infinity, alignment: .center).offset(x: 140.5, y: displayExpiration ? -34 : -7)
    }

    var body: some View {
        ZStack {
            // TriangleShape(color: triangleColor)
            TriangleShape(color: currentTriangleColor)
                .rotationEffect(.degrees(rotationDegrees + bumpEffect))
                .animation(.easeInOut(duration: 3.0), value: rotationDegrees)

            VStack(alignment: .center) {
                HStack {
                    Text(
                        (recentGlucose?.glucose ?? 100) == 400 ? "HIGH" : recentGlucose?.glucose
                            .map {
                                glucoseFormatter
                                    .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                            } ?? "--"
                    )
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(alwaysUseColors ? colourGlucoseText : .white)
                }
                HStack {
                    let elapsedSeconds = -1 * (recentGlucose?.dateString.timeIntervalSinceNow ?? 0)
                    let elapsedMinutes = elapsedSeconds / 60
                    let timeText = timaAgoFormatter.string(for: floor(elapsedMinutes)) ?? ""

                    Text(
                        elapsedSeconds < 60 ? "Now" : "\(timeText) min"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.white)

                    Text(
                        delta
                            .map {
                                deltaFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                            } ?? "--"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.white)
                }
            }
        }
        .onChange(of: recentGlucose?.direction) { _, newDirection in
            switch newDirection {
            case .doubleUp,
                 .singleUp,
                 .tripleUp:
                rotationDegrees = -90
            case .fortyFiveUp:
                rotationDegrees = -45
            case .flat:
                rotationDegrees = 0
            case .fortyFiveDown:
                rotationDegrees = 45
            case .doubleDown,
                 .singleDown,
                 .tripleDown:
                rotationDegrees = 90
            case .none?,
                 .notComputable,
                 .rateOutOfRange:
                rotationDegrees = 0
            @unknown default:
                rotationDegrees = 0
            }

            withAnimation(.interpolatingSpring(stiffness: 100, damping: 5).delay(0.5)) {
                bumpEffect = 5
                bumpEffect = 0
            }
        }
        // .frame(width: !scrolling ? 140 : 80, height: !scrolling ? 140 : 80)
    }

    private var adjustments: (degree: Double, x: CGFloat, y: CGFloat) {
        let yOffset: CGFloat = 17
        guard let direction = recentGlucose?.direction else {
            return (90, 0, yOffset)
        }
        switch direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            return (0, 0, yOffset)
        case .fortyFiveUp:
            return (45, 0, yOffset)
        case .flat:
            return (90, 0, yOffset)
        case .fortyFiveDown:
            return (135, 0, yOffset)
        case .doubleDown,
             .singleDown,
             .tripleDown:
            return (180, 0, yOffset)
        case .none,
             .notComputable,
             .rateOutOfRange:
            return (90, 0, yOffset)
        }
    }

    private func direction(degree: Double) -> (x: CGFloat, y: CGFloat) {
        switch degree {
        case 0:
            return (0, -2)
        case 45:
            return (1, -2)
        case 90:
            return (2, 0)
        case 135:
            return (1, 2)
        case 180:
            return (0, 2)
        default:
            return (2, 0)
        }
    }

    var colourGlucoseText: Color {
        let whichGlucose = recentGlucose?.glucose ?? 0
        // let defaultColor = Color.white.opacity(1.0)
        let defaultColor = Color.green.opacity(0.7)

        guard lowGlucose < highGlucose else { return .primary }

        switch whichGlucose {
        case 0 ..< Int(lowGlucose):
            return .red
        case Int(lowGlucose) ..< Int(highGlucose):
            return defaultColor
        case Int(highGlucose)...:
            return .yellow
        default:
            return defaultColor
        }
    }
}

struct TrendShape: View {
    let gradient: AngularGradient
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Group {
                    TriangleShape(color: color)
                }
            }
        }
    }
}

struct TriangleShape: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(90))
            .offset(x: 70)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 15))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.midY + 10))
        path.closeSubpath()

        return path
    }
}
