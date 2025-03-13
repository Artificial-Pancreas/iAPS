import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var recentGlucose: BloodGlucose?
    @Binding var delta: Int?
    @Binding var units: GlucoseUnits
    @Binding var alarm: GlucoseAlarm?
    @Binding var lowGlucose: Decimal
    @Binding var highGlucose: Decimal
    @Binding var alwaysUseColors: Bool
    @Binding var displayDelta: Bool
    @Binding var scrolling: Bool
    @Binding var displayExpiration: Bool
    @Binding var cgm: CGMType
    @Binding var sensordays: Double
    @Binding var anubis: Bool

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            formatter.roundingMode = .halfUp
        }
        return formatter
    }

    private var manualGlucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            formatter.roundingMode = .ceiling
        }
        return formatter
    }

    private var decimalString: String {
        let formatter = NumberFormatter()
        return formatter.decimalSeparator
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if units == .mmolL {
            formatter.decimalSeparator = "."
        }
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+ "
        formatter.negativePrefix = "- "
        return formatter
    }

    private var timaAgoFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.negativePrefix = ""
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
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

    var body: some View {
        glucoseView
            .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.xLarge)
    }

    var glucoseView: some View {
        ZStack {
            if let recent = recentGlucose {
                if displayDelta, !scrolling, let deltaInt = delta,
                   !(units == .mmolL && abs(deltaInt) <= 1) { deltaView(deltaInt) }
                if displayExpiration || anubis {
                    sageView
                }
                VStack(spacing: 15) {
                    let formatter = recent.type == GlucoseType.manual.rawValue ? manualGlucoseFormatter : glucoseFormatter
                    if let string = recent.glucose.map({
                        formatter
                            .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber) ?? "" })
                    {
                        glucoseText(string).asAny()
                            .background { glucoseDrop }
                        if !scrolling {
                            let minutesAgo = -1 * recent.dateString.timeIntervalSinceNow / 60
                            let text = timaAgoFormatter.string(for: Double(minutesAgo)) ?? ""
                            Text(
                                minutesAgo <= 1 ? NSLocalizedString("Now", comment: "") :
                                    (text + " " + NSLocalizedString("min", comment: "Short form for minutes") + " ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .offset(x: 1, y: fontSize >= .extraLarge ? -3 : 0)
                        }
                    }
                }
            }
        }
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

    private var sageView: some View {
        ZStack {
            if let date = recentGlucose?.sessionStartDate {
                let expiration = (cgm == .xdrip || cgm == .glucoseDirect) ? sensordays * 8.64E4 : cgm.expiration
                let remainingTime: TimeInterval = anubis ? (-1 * date.timeIntervalSinceNow) : expiration -
                    (-1 * date.timeIntervalSinceNow)

                Sage(amount: remainingTime, expiration: anubis ? remainingTime : expiration)
                    .frame(width: 59, height: 26)
                    .overlay {
                        HStack {
                            Text(
                                remainingTime >= 1 * 8.64E4 ?
                                    (remainingTimeFormatterDays.string(from: remainingTime) ?? "")
                                    .replacingOccurrences(of: ",", with: " ") :
                                    (remainingTimeFormatter.string(from: remainingTime) ?? "")
                                    .replacingOccurrences(of: ",", with: " ")
                            )
                        }
                    }
            }
        }
        .font(.footnote)
        .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.large)
        .frame(maxHeight: .infinity, alignment: .center).offset(x: 140.5, y: 3)
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

    private func glucoseText(_ string: String) -> any View {
        ZStack {
            let decimal = string.components(separatedBy: decimalString)
            if decimal.count > 1 {
                HStack(spacing: 0) {
                    Text(decimal[0]).font(scrolling ? .glucoseSmallFont : .glucoseFont)
                    Text(decimalString).font(.system(size: !scrolling ? 28 : 14).weight(.semibold)).baselineOffset(-10)
                    Text(decimal[1]).font(.system(size: !scrolling ? 28 : 18)).baselineOffset(!scrolling ? -10 : -4)
                }
                .tracking(-1)
                .offset(x: -2, y: 14)
                .foregroundColor(alwaysUseColors ? colorOfGlucose : alarm == nil ? .primary : .loopRed)
            } else {
                Text(string)
                    .font(scrolling ? .glucoseSmallFont : .glucoseFontMdDl.width(.condensed)) // .tracking(-2)
                    .foregroundColor(alwaysUseColors ? colorOfGlucose : alarm == nil ? .primary : .loopRed)
                    .offset(x: string.count > 2 ? -1 : -1, y: 16)
            }
        }
        .offset(y: scrolling ? 3 : 0)
    }

    private var glucoseDrop: some View {
        let adjust = adjustments
        let degree = adjustments.degree
        let shadowDirection = direction(degree: degree)
        return Image("glucoseDrops")
            .resizable()
            .frame(width: !scrolling ? 140 : 80, height: !scrolling ? 140 : 80).rotationEffect(.degrees(degree))
            .animation(.bouncy(duration: 1, extraBounce: 0.2), value: degree)
            .offset(x: adjust.x, y: adjust.y)
            .shadow(radius: 3, x: shadowDirection.x, y: shadowDirection.y)
    }

    private var colorOfGlucose: Color {
        let whichGlucose = recentGlucose?.glucose ?? 0
        guard lowGlucose < highGlucose else { return .primary }

        switch whichGlucose {
        case 0 ..< Int(lowGlucose):
            return .loopRed
        case Int(lowGlucose) ..< Int(highGlucose):
            return .loopGreen
        case Int(highGlucose)...:
            return .loopYellow
        default:
            return .loopYellow
        }
    }
}
