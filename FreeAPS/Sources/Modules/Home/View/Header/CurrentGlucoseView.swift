import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var recentGlucose: BloodGlucose?
    @Binding var delta: Int?
    let units: GlucoseUnits

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
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var colorOfGlucose: Color {
        let glucoseString =
            recentGlucose?.glucose
                .map { glucoseFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)! } ?? "--"
        let glucoseStringFirstTwoCharacters = String(glucoseString.dropLast(1))

        switch glucoseStringFirstTwoCharacters {
        case "4,",
             "5,",
             "6,",
             "7,":
            return .loopGreen
        case "8,",
             "9,":
            return .loopYellow
        default:
            return .loopRed
        }
    }

    var minutesAgo: Int {
        let lastGlucoseDate = recentGlucose.map { dateFormatter.string(from: $0.dateString) } ?? "--"
        let glucoseDate = Date(lastGlucoseDate) ?? Date()
        let now = Date()
        let diff = Int(glucoseDate.timeIntervalSince1970 - now.timeIntervalSince1970)
        let hoursDiff = diff / 3600
        var minutesDiff = (diff - hoursDiff * 3600) / 60
        minutesDiff.negate() // Remove "-" sign
        return minutesDiff
    }

    func colorOfMinutesAgo(_ minutes: Int) -> Color {
        print("number of minutes ago: \(minutesAgo)")
        switch minutes {
        case 0 ... 5:
            return .loopGray
        case 6 ... 9:
            return .loopYellow
        default:
            return .loopRed
        }
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
            HStack(spacing: 2) {
                Text(
                    "\(minutesAgo)m "
                ).font(.caption2).foregroundColor(colorOfMinutesAgo(minutesAgo))
                Text(
                    delta
                        .map { deltaFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                        } ??
                        "--"

                ).font(.system(size: 12, weight: .bold))
            }
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
