import Charts
import CoreData
import SwiftUI

struct GlucoseSectorChart: View {
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let glucose: FetchedResults<Readings>
    let showChart: Bool

    @Environment(\.colorScheme) private var colorScheme

    private let conversionFactor = 0.0555

    @State private var selectedCount: Int?
    @State private var selectedRange: GlucoseRange?

    private enum GlucoseRange: String, Plottable {
        case high = "High"
        case inRange = "In Range"
        case low = "Low"
    }

    var body: some View {
        if glucose.count < 1 {
            Text(NSLocalizedString("No glucose readings found.", comment: "Empty state when no glucose readings exist"))
        } else {
            let total = Decimal(glucose.count)
            let high = glucose.filter { $0.glucose > Int(highLimit) }.count
            let normal = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= Int(highLimit) }.count
            let low = glucose.filter { $0.glucose < Int(lowLimit) }.count
            let tight = glucose.filter { $0.glucose >= 70 && $0.glucose <= 140 }.count

            let justGlucoseArray = glucose.compactMap { Int($0.glucose as Int16) }
            let sumReadings = justGlucoseArray.reduce(0, +)
            let glucoseAverage = Decimal(sumReadings) / total
            let medianGlucose = StatChartUtils.medianCalculation(array: justGlucoseArray)

            let lowPercentage = Decimal(low) / total * 100
            let inRangePercentage = Decimal(normal) / total * 100
            let highPercentage = Decimal(high) / total * 100
            let tightPercentage = Decimal(tight) / total * 100

            let lowFormatted = StatChartUtils.formatGlucoseDecimal(lowLimit, units: units)
            let highFormatted = StatChartUtils.formatGlucoseDecimal(highLimit, units: units)
            let tightLowFormatted = StatChartUtils.formatGlucose(70, units: units)
            let tightHighFormatted = StatChartUtils.formatGlucose(140, units: units)

            VStack(spacing: 8) {
                heroSection(
                    average: Double(truncating: glucoseAverage as NSNumber),
                    median: medianGlucose,
                    inRangePercentage: inRangePercentage
                )

                Divider().opacity(0.4)

                tileGrid(
                    lowPercentage: lowPercentage,
                    inRangePercentage: inRangePercentage,
                    tightPercentage: tightPercentage,
                    highPercentage: highPercentage,
                    lowFormatted: lowFormatted,
                    highFormatted: highFormatted,
                    tightLowFormatted: tightLowFormatted,
                    tightHighFormatted: tightHighFormatted
                )
            }
            .onChange(of: selectedCount) { _, newValue in
                if let newValue {
                    withAnimation { getSelectedRange(value: newValue) }
                } else {
                    withAnimation { selectedRange = nil }
                }
            }
            .overlay(alignment: .top) {
                if let selectedRange {
                    let data = getDetailedData(for: selectedRange)
                    RangeDetailPopover(data: data)
                        .transition(.scale.combined(with: .opacity))
                        .offset(y: -20)
                }
            }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder private func heroSection(
        average: Double,
        median: Double,
        inRangePercentage: Decimal
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                avgMedianRow(
                    label: NSLocalizedString("Ø", comment: ""),
                    labelSize: 15,
                    value: formatGlucoseValue(average) + " " + units.rawValue
                )
                avgMedianRow(
                    label: NSLocalizedString("MED", comment: ""),
                    labelSize: 11,
                    value: formatGlucoseValue(median) + " " + units.rawValue
                )
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(formatPercentage(inRangePercentage))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.loopGreen)
                Text(NSLocalizedString("Time in Range", comment: ""))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            if showChart {
                donutChart
                    .frame(width: 86, height: 86)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.loopGreen.opacity(colorScheme == .dark ? 0.20 : 0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.loopGreen)
                }
            }
        }
    }

    private func avgMedianRow(label: String, labelSize: CGFloat, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var donutChart: some View {
        Chart {
            ForEach(rangeData, id: \.range) { data in
                SectorMark(
                    angle: .value("Percentage", data.count),
                    innerRadius: .ratio(0.618),
                    outerRadius: selectedRange == data.range ? .ratio(1.0) : .ratio(0.88)
                )
                .foregroundStyle(data.color)
            }
        }
        .chartAngleSelection(value: $selectedCount)
    }

    // MARK: - Tile Grid

    @ViewBuilder private func tileGrid(
        lowPercentage: Decimal,
        inRangePercentage: Decimal,
        tightPercentage: Decimal,
        highPercentage: Decimal,
        lowFormatted: String,
        highFormatted: String,
        tightLowFormatted: String,
        tightHighFormatted: String
    ) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        LazyVGrid(columns: columns, spacing: 8) {
            metricTile(
                icon: "arrow.down.circle.fill",
                color: Color.loopRed,
                value: formatPercentage(lowPercentage),
                label: NSLocalizedString("Low", comment: ""),
                sublabel: "< \(lowFormatted)"
            )
            metricTile(
                icon: "checkmark.circle.fill",
                color: Color.loopGreen,
                value: formatPercentage(inRangePercentage),
                label: NSLocalizedString("In Range", comment: ""),
                sublabel: "\(lowFormatted)–\(highFormatted)"
            )
            metricTile(
                icon: "arrow.up.circle.fill",
                color: Color.loopYellow,
                value: formatPercentage(highPercentage),
                label: NSLocalizedString("High", comment: ""),
                sublabel: "> \(highFormatted)"
            )
            metricTile(
                icon: "target",
                color: Color.loopGreen.opacity(0.7),
                value: formatPercentage(tightPercentage),
                label: NSLocalizedString("Tight Range", comment: ""),
                sublabel: "\(tightLowFormatted)–\(tightHighFormatted)"
            )
        }
    }

    private func metricTile(
        icon: String,
        color: Color,
        value: String,
        label: String,
        sublabel: String
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(sublabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Range Data / Popover Helpers

    private var rangeData: [(range: GlucoseRange, count: Int, percentage: Decimal, color: Color)] {
        let total = glucose.count
        guard total > 0 else { return [] }

        let highCount = glucose.filter { $0.glucose > Int(highLimit) }.count
        let lowCount = glucose.filter { $0.glucose < Int(lowLimit) }.count
        let inRangeCount = total - highCount - lowCount

        return [
            (.high, highCount, Decimal(highCount) / Decimal(total) * 100, Color.loopYellow),
            (.inRange, inRangeCount, Decimal(inRangeCount) / Decimal(total) * 100, Color.loopGreen),
            (.low, lowCount, Decimal(lowCount) / Decimal(total) * 100, Color.loopRed)
        ]
    }

    private func getSelectedRange(value: Int) {
        var cumulativeTotal = 0
        _ = rangeData.first { data in
            cumulativeTotal += data.count
            if value <= cumulativeTotal {
                selectedRange = data.range
                return true
            }
            return false
        }
    }

    private func getDetailedData(for range: GlucoseRange) -> RangeDetail {
        let total = Decimal(glucose.count)

        switch range {
        case .high:
            let veryHigh = glucose.filter { $0.glucose > 250 }.count
            let high = glucose.filter { $0.glucose > Int(highLimit) && $0.glucose <= 250 }.count
            let values = glucose.filter { $0.glucose > Int(highLimit) }.map { Int($0.glucose) }
            let (average, median, sd) = calculateDetailedStats(for: values)

            return RangeDetail(
                title: NSLocalizedString("High Glucose", comment: ""),
                color: Color.loopYellow,
                items: [
                    (
                        NSLocalizedString("Very High", comment: "") + " (>\(formatGlucoseInt(250)))",
                        formatPercentage(Decimal(veryHigh) / total * 100)
                    ),
                    (
                        NSLocalizedString("High", comment: ""),
                        formatPercentage(Decimal(high) / total * 100)
                    ),
                    (NSLocalizedString("Average", comment: ""), formatGlucoseValue(average)),
                    (NSLocalizedString("Median", comment: ""), formatGlucoseValue(median)),
                    (NSLocalizedString("SD", comment: ""), formatSD(sd))
                ]
            )

        case .inRange:
            let values = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= Int(highLimit) }.map { Int($0.glucose) }
            let tight = glucose.filter { $0.glucose >= 70 && $0.glucose <= 140 }.count
            let (average, median, sd) = calculateDetailedStats(for: values)

            return RangeDetail(
                title: NSLocalizedString("In Range", comment: ""),
                color: Color.loopGreen,
                items: [
                    (
                        NSLocalizedString("Normal", comment: ""),
                        formatPercentage(Decimal(values.count) / total * 100)
                    ),
                    (
                        NSLocalizedString("Tight", comment: "") + " (70–140)",
                        formatPercentage(Decimal(tight) / total * 100)
                    ),
                    (NSLocalizedString("Average", comment: ""), formatGlucoseValue(average)),
                    (NSLocalizedString("Median", comment: ""), formatGlucoseValue(median)),
                    (NSLocalizedString("SD", comment: ""), formatSD(sd))
                ]
            )

        case .low:
            let veryLow = glucose.filter { $0.glucose <= 54 }.count
            let low = glucose.filter { $0.glucose > 54 && $0.glucose < Int(lowLimit) }.count
            let values = glucose.filter { $0.glucose < Int(lowLimit) }.map { Int($0.glucose) }
            let (average, median, sd) = calculateDetailedStats(for: values)

            return RangeDetail(
                title: NSLocalizedString("Low Glucose", comment: ""),
                color: Color.loopRed,
                items: [
                    (
                        NSLocalizedString("Low", comment: ""),
                        formatPercentage(Decimal(low) / total * 100)
                    ),
                    (
                        NSLocalizedString("Very Low", comment: "") + " (<\(formatGlucoseInt(54)))",
                        formatPercentage(Decimal(veryLow) / total * 100)
                    ),
                    (NSLocalizedString("Average", comment: ""), formatGlucoseValue(average)),
                    (NSLocalizedString("Median", comment: ""), formatGlucoseValue(median)),
                    (NSLocalizedString("SD", comment: ""), formatSD(sd))
                ]
            )
        }
    }

    private func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = value == 100 ? 0 : 1
        formatter.maximumFractionDigits = value == 100 ? 0 : 1
        formatter.positiveSuffix = "%"
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "0%"
    }

    private func formatGlucoseValue(_ value: Double) -> String {
        StatChartUtils.formatGlucose(value, units: units)
    }

    private func formatGlucoseInt(_ value: Int) -> String {
        StatChartUtils.formatGlucose(Double(value), units: units)
    }

    private func formatSD(_ sd: Double) -> String {
        if units == .mmolL {
            return (sd * conversionFactor).formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
        }
        return sd.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
    }

    private func calculateDetailedStats(for values: [Int]) -> (Double, Double, Double) {
        guard !values.isEmpty else { return (0, 0, 0) }
        let total = values.reduce(0, +)
        let average = Double(total) / Double(values.count)
        let median = StatChartUtils.medianCalculation(array: values)
        let sumOfSquares = values.reduce(0.0) { $0 + pow(Double($1) - average, 2) }
        let sd = sqrt(sumOfSquares / Double(values.count))
        return (average, median, sd)
    }
}

// MARK: - Supporting Types

private struct RangeDetail {
    let title: String
    let color: Color
    let items: [(label: String, value: String)]
}

private struct RangeDetailPopover: View {
    let data: RangeDetail
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(data.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(data.color)
                .padding(.bottom, 4)

            ForEach(Array(data.items.enumerated()), id: \.offset) { index, item in
                if index < 2 {
                    HStack {
                        Text(item.label)
                        Text(item.value).bold()
                    }.font(.footnote)
                }
            }

            HStack(spacing: 20) {
                ForEach(Array(data.items.enumerated()), id: \.offset) { index, item in
                    if index > 1 {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.label)
                            Text(item.value).bold()
                        }.font(.footnote)
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color.white.opacity(0.95))
                .shadow(color: .secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(data.color, lineWidth: 2)
                )
        }
    }
}
