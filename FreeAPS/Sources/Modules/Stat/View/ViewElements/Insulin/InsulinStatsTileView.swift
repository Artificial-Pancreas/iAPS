import SwiftUI

struct InsulinStatsTileView: View {
    let neg: Int
    let tddChange: Decimal
    let tddAverage: Decimal
    let tddYesterday: Decimal
    let tdd2DaysAgo: Decimal
    let tdd3DaysAgo: Decimal
    let tddActualAverage: Decimal

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            heroSection

            Divider().opacity(0.4)

            dayTiles

            comparisonTiles
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.insulin.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "syringe.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.insulin)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatTDD(tddActualAverage))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("U", comment: "Unit"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(NSLocalizedString("Ø 10 days", comment: ""))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Spacer()

            if neg > 0 {
                negBadge
            }
        }
    }

    private var negBadge: some View {
        VStack(spacing: 2) {
            Text("\(neg)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.insulin)
            Text(NSLocalizedString("neg min", comment: "Negative insulin minutes"))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.insulin.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
    }

    // MARK: - Day Tiles

    private var dayTiles: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            metricTile(
                icon: "1.circle.fill",
                color: Color.loopGreen,
                value: formatTDD(tddYesterday),
                unit: NSLocalizedString("U", comment: "Unit"),
                label: NSLocalizedString("Yesterday", comment: "")
            )
            metricTile(
                icon: "2.circle.fill",
                color: Color.purple,
                value: formatTDD(tdd2DaysAgo),
                unit: NSLocalizedString("U", comment: "Unit"),
                label: NSLocalizedString("2 Days", comment: "")
            )
            metricTile(
                icon: "3.circle.fill",
                color: Color.loopYellow,
                value: formatTDD(tdd3DaysAgo),
                unit: NSLocalizedString("U", comment: "Unit"),
                label: NSLocalizedString("3 Days", comment: "")
            )
        }
    }

    // MARK: - Comparison Tiles

    private var comparisonTiles: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            deltaTile(
                value: tddChange,
                label: NSLocalizedString("vs Yesterday", comment: "")
            )
            deltaTile(
                value: tddAverage,
                label: NSLocalizedString("vs Ø 10 days", comment: "")
            )
        }
    }

    private func deltaTile(value: Decimal, label: String) -> some View {
        let isUp = value > 0
        let isDown = value < 0
        let color: Color = isUp ? Color.loopYellow : (isDown ? Color.loopGreen : .secondary)
        let icon: String = isUp ? "arrow.up.right" : (isDown ? "arrow.down.right" : "equal")

        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatSignedTDD(value))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(NSLocalizedString("U", comment: "Unit"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private func metricTile(
        icon: String,
        color: Color,
        value: String,
        unit: String,
        label: String
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
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Formatting

    private func formatTDD(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    private func formatSignedTDD(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "−"
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }
}
