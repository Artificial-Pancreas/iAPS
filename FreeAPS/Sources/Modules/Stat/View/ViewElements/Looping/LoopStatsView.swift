import SwiftUI

struct LoopStatsView: View {
    let statsData: [LoopStatsProcessedData]
    var selectedInterval: StatsTimeIntervalWithToday = .today
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let stats = statsData.first(where: { $0.category == .successfulLoop }) {
            VStack(spacing: 16) {
                heroSection(stats: stats)

                Divider().opacity(0.4)

                tileGrid(stats: stats)
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder private func heroSection(stats: LoopStatsProcessedData) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stats.count.formatted())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("Loops", comment: ""))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(daysSubtitle(days: stats.totalDays))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            successBadge(percent: stats.successPercentage)
        }
    }

    private func successBadge(percent: Double) -> some View {
        let color: Color = percent >= 95 ? Color.loopGreen :
            (percent >= 85 ? Color.loopYellow : Color.loopRed)
        return VStack(spacing: 2) {
            Text((percent / 100).formatted(.percent.grouping(.never).rounded().precision(.fractionLength(1))))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(NSLocalizedString("Success", comment: ""))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
    }

    // MARK: - Tile Grid

    @ViewBuilder private func tileGrid(stats: LoopStatsProcessedData) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        let intervalText = (stats.medianInterval / 60)
            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " m"
        let durationText = stats.medianDuration
            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " s"
        let daysText = stats.totalDays.description

        LazyVGrid(columns: columns, spacing: 10) {
            metricTile(
                icon: "clock",
                color: Color.loopGreen,
                value: intervalText,
                label: NSLocalizedString("Interval", comment: "")
            )
            metricTile(
                icon: "timer",
                color: Color.purple,
                value: durationText,
                label: NSLocalizedString("Duration", comment: "")
            )
            metricTile(
                icon: "calendar",
                color: Color.loopYellow,
                value: daysText,
                label: NSLocalizedString("Days", comment: "")
            )
        }
    }

    private func metricTile(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func daysSubtitle(days: Int) -> String {
        switch selectedInterval {
        case .today:
            return NSLocalizedString("today", comment: "")
        case .day:
            return NSLocalizedString("over the last day", comment: "")
        case .week:
            let format = NSLocalizedString("Ø / day — over the last %d days", comment: "")
            return String(format: format, max(days, 7))
        case .month:
            let format = NSLocalizedString("Ø / day — over the last %d days", comment: "")
            return String(format: format, max(days, 30))
        case .total:
            let format = NSLocalizedString("Ø / day — over the last %d days", comment: "")
            return String(format: format, max(days, 90))
        }
    }
}
