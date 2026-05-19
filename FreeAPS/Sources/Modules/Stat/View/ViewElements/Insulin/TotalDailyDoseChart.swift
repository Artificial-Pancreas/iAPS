import Charts
import SwiftUI

struct TotalDailyDoseChart: View {
    @Binding var selectedInterval: StatsTimeIntervalWithToday
    let tddStats: [TDDStats]

    @State private var scrollPosition: Date = StatChartUtils.getInitialScrollPosition(for: .day as StatsTimeInterval)
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    private var selectable: Bool { true }

    private var selectedStat: TDDStats? {
        guard let selectedDate else { return nil }
        let cal = Calendar.current
        if selectedInterval.isHourly {
            return tddStats.first {
                cal.compare($0.date, to: selectedDate, toGranularity: .hour) == .orderedSame
            }
        }
        return tddStats.first { cal.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        let average = tddStats.isEmpty ? 0 : tddStats.map(\.amount).reduce(0, +) / Double(tddStats.count)
        let total = tddStats.map(\.amount).reduce(0, +)
        let isHourly = selectedInterval.isHourly

        VStack(spacing: 16) {
            // Stats row
            HStack {
                if isHourly {
                    StatChartUtils.statView(
                        title: selectedInterval == .today
                            ? NSLocalizedString("TDD Today", comment: "Total Daily Dose for today")
                            : NSLocalizedString("TDD 24h", comment: "Total Daily Dose last 24 hours"),
                        value: total
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " " +
                            NSLocalizedString("U", comment: "Unit")
                    )
                } else {
                    StatChartUtils.statView(
                        title: NSLocalizedString("Ø / Day", comment: "Average per day"),
                        value: average
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " " +
                            NSLocalizedString("U", comment: "Unit")
                    )
                    Spacer()
                    StatChartUtils.statView(
                        title: NSLocalizedString("Total", comment: ""),
                        value: total
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " " +
                            NSLocalizedString("U", comment: "Unit")
                    )
                }
            }
            .padding(.horizontal)

            Divider()

            // Chart
            Chart {
                ForEach(tddStats) { stat in
                    BarMark(
                        x: .value("Date", stat.date, unit: isHourly ? .hour : .day),
                        y: .value("TDD", stat.amount)
                    )
                    .foregroundStyle(Color.insulin.gradient)
                    .cornerRadius(3)
                    .opacity(selectable && selectedStat != nil && selectedStat?.id != stat.id ? 0.35 : 1.0)
                }

                if selectable, let sel = selectedStat {
                    RuleMark(x: .value("Selected", sel.date, unit: isHourly ? .hour : .day))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval.asChartInterval))
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let val = value.as(Double.self) {
                            Text("\(Int(val))U")
                                .font(.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval.asChartInterval))
            .chartScrollPosition(x: $scrollPosition)
            .frame(height: 200)
            .padding(.horizontal)
            .overlay(alignment: .top) {
                if selectable, let sel = selectedStat {
                    let title = isHourly
                        ? sel.date.formatted(.dateTime.hour().minute())
                        : sel.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
                    let label = isHourly
                        ? NSLocalizedString("Insulin", comment: "")
                        : NSLocalizedString("TDD", comment: "")
                    InsulinBarDetailPopover(
                        title: title,
                        color: Color.insulin,
                        items: [
                            (
                                label,
                                sel.amount
                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " " +
                                    NSLocalizedString("U", comment: "Unit")
                            )
                        ]
                    )
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 4)
                }
            }
        }
        .onChange(of: selectedInterval) { _, newValue in
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: newValue.asChartInterval)
            selectedDate = nil
        }
    }
}

// MARK: - Shared Popover

struct InsulinBarDetailPopover: View {
    let title: String
    let color: Color
    let items: [(label: String, value: String)]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.label).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(item.value).bold()
                }
                .font(.footnote)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color.white.opacity(0.95))
                .shadow(color: .secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color, lineWidth: 2)
                )
        }
    }
}
