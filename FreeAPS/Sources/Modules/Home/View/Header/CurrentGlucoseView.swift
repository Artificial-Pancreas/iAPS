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
            " \(recentGlucose?.glucose.map { glucoseFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)! })"

        let glucoseStringWithoutSuffix = String(glucoseString.dropFirst(11)) // Drop first 11 characters

        let glucoseStringTrimmed = String(glucoseStringWithoutSuffix.dropLast(3)) // Drop last 3 characters

        switch glucoseStringTrimmed {
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
                    recentGlucose.map { dateFormatter.string(from: $0.dateString) } ?? "--"
                ).font(.caption2).foregroundColor(.secondary)
                Text(
                    delta
                        .map { deltaFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                        } ??
                        "--"
                    
                ).font(.caption2).foregroundColor(.secondary)
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
