import Foundation
import SwiftUI

private func adaptiveNutritionColor(_ color: Color, colorScheme: ColorScheme) -> Color {
    guard colorScheme == .light else { return color }
    switch color {
    case .orange: return Color(red: 0.85, green: 0.45, blue: 0.0)
    case .green: return Color(red: 0.0, green: 0.6, blue: 0.0)
    case .red: return Color(red: 0.8, green: 0.0, blue: 0.0)
    case .blue: return Color(red: 0.0, green: 0.4, blue: 0.8)
    case .purple: return Color(red: 0.6, green: 0.0, blue: 0.6)
    case .gray: return Color(red: 0.4, green: 0.4, blue: 0.4)
    default: return color
    }
}

enum NutritionBadgeConfig {
    static let caloriesColor = Color.gray
}

extension NutrientType {
    var badgeColor: Color {
        switch self {
        case .carbs: Color.orange
        case .protein: Color.green
        case .fat: Color.blue
        case .fiber: Color.purple
        case .sugars: Color.purple
        }
    }
}

extension ConfidenceLevel {
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

struct NutritionBadge: View {
    let value: Decimal
    let unit: Dimension?
    let localizedLabel: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: Dimension? = nil, localizedLabel: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.localizedLabel = localizedLabel
        self.color = color
    }

    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.25 : 0.15
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(Double(value), specifier: unit == UnitEnergy.kilocalories || value > 20 ? "%.0f" : "%.1f")")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize()
            if let unit = unit {
                Text(unit.symbol)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            if let localizedLabel = localizedLabel {
                Text(localizedLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.lowercase)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(backgroundOpacity))
        .cornerRadius(8)
    }
}

struct NutritionBadgePlain: View {
    let value: Decimal
    let unit: Dimension?
    let localizedLabel: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: Dimension? = nil, localizedLabel: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.localizedLabel = localizedLabel
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(Double(value), specifier: unit == UnitEnergy.kilocalories || value > 20 ? "%.0f" : "%.1f")")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(adaptiveNutritionColor(color, colorScheme: colorScheme))
                .shadow(color: .black.opacity(colorScheme == .light ? 0.08 : 0), radius: 0.5, x: 0, y: 0.5)
                .fixedSize()
            if let unit = unit {
                Text(unit.symbol)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            if let localizedLabel = localizedLabel {
                Text(localizedLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.lowercase)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct NutritionBadgePlainStacked: View {
    let value: Decimal
    let unit: Dimension?
    let localizedLabel: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: Dimension? = nil, localizedLabel: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.localizedLabel = localizedLabel
        self.color = color
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("\(Double(value), specifier: unit == UnitEnergy.kilocalories || value > 10 ? "%.0f" : "%.1f")")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(adaptiveNutritionColor(color, colorScheme: colorScheme))
                    .shadow(color: .black.opacity(colorScheme == .light ? 0.08 : 0), radius: 0.5, x: 0, y: 0.5)
                    .fixedSize()
                if let unit = unit {
                    Text(unit.symbol)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
            Text(localizedLabel ?? "")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .textCase(.lowercase)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConfidenceBadge: View {
    let level: ConfidenceLevel

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.2 : 0.4
    }

    private var textColor: Color {
        colorScheme == .dark ? level.color : .primary.opacity(0.75)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 11))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(level.color.opacity(backgroundOpacity))
        .foregroundColor(textColor)
        .cornerRadius(4)
    }
}

struct AdjustmentBadge: View {
    let value: Decimal
    let localizedLabel: String
    let color: Color

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private var formattedValue: String {
        let valueString = Self.numberFormatter.string(from: NSDecimalNumber(decimal: abs(value))) ?? "0"
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(valueString)"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(formattedValue)
                .font(.caption2)
                .fontWeight(.semibold)
            Text(localizedLabel)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}

struct PortionSizeBadge: View {
    let value: Decimal
    let color: Color
    let icon: String
    let foodItem: FoodItemDetailed

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .opacity(0.3)
            }
            HStack(spacing: 2) {
                switch foodItem.nutrition {
                case .per100:
                    Text("\(Double(value), specifier: "%.0f")")
                        .font(.system(size: 15, weight: .bold))
                    Text((foodItem.units ?? .grams).dimension.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.4)
                case .perServing:
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.system(size: 15, weight: .bold))
                    Text(value == 1 ? "serving" : "servings")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.4)
                }
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemGray4))
        .cornerRadius(8)
    }
}
