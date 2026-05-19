import Charts
import Foundation
import SwiftUI

struct StatChartUtils {
    static func visibleDomainLength(for selectedInterval: StatsTimeInterval) -> TimeInterval {
        switch selectedInterval {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .total: return 90 * 24 * 3600
        }
    }

    static func visibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        if selectedInterval == .day {
            let end = scrollPosition.addingTimeInterval(visibleDomainLength(for: selectedInterval) - 1)
            return (scrollPosition, end)
        } else {
            let startOfDay = calendar.startOfDay(for: scrollPosition)
            let components = calendar.dateComponents([.hour, .minute, .second], from: scrollPosition)
            let totalSeconds = Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 +
                Double(components.second ?? 0)

            let alignedStart = totalSeconds > 12 * 3600 ?
                calendar.date(byAdding: .day, value: 1, to: startOfDay)! : startOfDay
            let intervalLength = visibleDomainLength(for: selectedInterval)
            let end = alignedStart.addingTimeInterval(intervalLength + (2 * 3600))
            let alignedEnd = calendar.startOfDay(for: end).addingTimeInterval(-1)

            return (alignedStart, alignedEnd)
        }
    }

    static func dateFormat(for selectedInterval: StatsTimeInterval) -> Date.FormatStyle {
        switch selectedInterval {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .total: return .dateTime.month(.abbreviated)
        }
    }

    static func getInitialScrollPosition(for selectedInterval: StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let baseDate: Date
        switch selectedInterval {
        case .day: baseDate = today
        case .week: baseDate = calendar.date(byAdding: .day, value: -6, to: today)!
        case .month: baseDate = calendar.date(byAdding: .day, value: -29, to: today)!
        case .total: baseDate = calendar.date(byAdding: .day, value: -89, to: today)!
        }
        return calendar.date(byAdding: .second, value: 1, to: baseDate)!
    }

    static func isSameTimeUnit(_ date1: Date, _ date2: Date, for selectedInterval: StatsTimeInterval) -> Bool {
        let calendar = Calendar.current
        switch selectedInterval {
        case .day: return calendar.isDate(date1, equalTo: date2, toGranularity: .hour)
        default: return calendar.isDate(date1, inSameDayAs: date2)
        }
    }

    static func formatVisibleDateRange(
        from start: Date,
        to end: Date,
        for selectedInterval: StatsTimeInterval
    ) -> String {
        let calendar = Calendar.current
        guard selectedInterval == .day else {
            let formatDate: (Date) -> String = { $0.formatted(.dateTime.day().month()) }
            return "\(formatDate(start)) - \(formatDate(end))"
        }

        let dayStart = calendar.startOfDay(for: start)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let tolerance: TimeInterval = 60 * 15

        let isStartNearMidnight = abs(start.timeIntervalSince(dayStart)) < tolerance
        let isEndNearNextMidnight = abs(end.timeIntervalSince(nextDayStart)) < tolerance

        if isStartNearMidnight, isEndNearNextMidnight {
            return dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        } else {
            let formatDay: (Date) -> String = { $0.formatted(.dateTime.day().month(.abbreviated)) }
            return "\(formatDay(start)) - \(formatDay(end))"
        }
    }

    static func statView(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    static func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count
        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    static func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count
        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    @ViewBuilder static func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// Format glucose value for display
    static func formatGlucose(_ value: Double, units: GlucoseUnits) -> String {
        if units == .mmolL {
            return (value * 0.0555).formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
        } else {
            return value.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
        }
    }

    /// Format glucose Decimal for display
    static func formatGlucoseDecimal(_ value: Decimal, units: GlucoseUnits) -> String {
        if units == .mmolL {
            let mmol = value * Decimal(0.0555)
            return mmol.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
        } else {
            return value.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
        }
    }
}
