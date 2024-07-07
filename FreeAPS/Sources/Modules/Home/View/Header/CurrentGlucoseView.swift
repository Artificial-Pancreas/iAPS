import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var recentGlucose: BloodGlucose?
    @Binding var timerDate: Date
    @Binding var delta: Int?
    @Binding var units: GlucoseUnits
    @Binding var alarm: GlucoseAlarm?
    @Binding var lowGlucose: Decimal
    @Binding var highGlucose: Decimal
    @Binding var alwaysUseColors: Bool

    @State private var rotationDegrees: Double = 0.0

    enum Config {
        static let size: CGFloat = 100
    }

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
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
        formatter.negativePrefix = ""
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        ZStack {
            VStack {
                let offset: CGFloat = fontSize < .large ? 82 : (fontSize >= .large && fontSize < .extraExtraLarge) ? 87 : 92
                ZStack {
                    Text(
                        (recentGlucose?.glucose ?? 100) == 400 ? "HIGH" : recentGlucose?.glucose
                            .map {
                                glucoseFormatter
                                    .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)! }
                            ?? "--"
                    )
                    .font(.glucoseFont)
                    .foregroundColor(alwaysUseColors ? colorOfGlucose : alarm == nil ? .primary : .loopRed)
                    .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: 10) {
                        image
                            .font(.system(size: 25))
                        VStack {
                            Text(
                                delta
                                    .map {
                                        deltaFormatter
                                            .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                                    } ?? "--"
                            )
                            HStack {
                                let minutesAgo = -1 * (recentGlucose?.dateString.timeIntervalSinceNow ?? 0) / 60
                                let text = timaAgoFormatter.string(for: Double(minutesAgo)) ?? ""
                                Text(
                                    minutesAgo <= 1 ? "" : (
                                        text + " " +
                                            NSLocalizedString("min", comment: "Short form for minutes") + " "
                                    )
                                )
                            }.offset(x: 7, y: 0)
                        }
                        .font(.extraSmall).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .center)
                        .offset(x: offset, y: 0)
                }
                .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.xLarge)
            }
        }
    }

    var image: some View {
        guard let direction = recentGlucose?.direction else {
            return Image(systemName: "arrow.left.and.right")
        }
        switch direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            return Image(systemName: "arrow.up")
        case .fortyFiveUp:
            return Image(systemName: "arrow.up.right")
        case .flat:
            return Image(systemName: "arrow.forward")
        case .fortyFiveDown:
            return Image(systemName: "arrow.down.forward")
        case .doubleDown,
             .singleDown,
             .tripleDown:
            return Image(systemName: "arrow.down")
        case .none,
             .notComputable,
             .rateOutOfRange:
            return Image(systemName: "arrow.left.and.right")
        }
    }

    var colorOfGlucose: Color {
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
