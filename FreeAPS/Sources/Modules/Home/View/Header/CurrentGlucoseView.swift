import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var recentGlucose: BloodGlucose?
    @Binding var delta: Int?
    @Binding var units: GlucoseUnits

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Text(
                    recentGlucose?.glucose
                        .map {
                            glucoseFormatter
                                .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)! }
                        ?? "--"
                )
                .font(.system(size: 24, weight: .bold))
                .fixedSize()
                .foregroundColor(colorOfGlucose)
                image.padding(.bottom, 2)

            }.padding(.leading, 4)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(
                    "\(minutesAgo)m "
                ).font(.caption2).foregroundColor(colorOfMinutesAgo(minutesAgo))
                Text(
                    delta
                        .map { deltaFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                        } ??
                        "--"
                    
                ).font(.caption2).foregroundColor(.secondary)
            }
        }

        var colorOfGlucose: Color {
            guard var recentBG = recentGlucose?.glucose
            else { return .loopYellow }

            recentBG /= 18 // convert to mmol/l for calculation

            switch recentBG {
            case 4 ... 7:
                return .loopGreen
            case 8 ... 9:
                return .loopYellow
            default:
                return .loopRed
            }
        }

        var minutesAgo: Int {
            let lastGlucoseDateString = recentGlucose.map { dateFormatter.string(from: $0.dateString) } ?? "--"
            let LastGlucoseDate = Date(lastGlucoseDateString) ?? Date()
            let now = Date()
            let diff = Int(now.timeIntervalSince1970 - LastGlucoseDate.timeIntervalSince1970)
            let hoursDiff = diff / 3600
            let minutesDiff = (diff - hoursDiff * 3600) / 60
            return minutesDiff
        }

        func colorOfMinutesAgo(_ minutes: Int) -> Color {
            switch minutes {
            case 0 ... 5:
                return .loopGreen
            case 6 ... 9:
                return .loopYellow
            default:
                return .loopRed
        }
    }

    var image: Image {
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
}
