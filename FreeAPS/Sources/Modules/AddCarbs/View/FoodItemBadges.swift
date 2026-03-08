import Foundation
import SwiftUI

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
    let unit: String?
    let localizedLabel: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, localizedLabel: String? = nil, color: Color) {
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
            Text("\(Double(value), specifier: unit == "kcal" || value > 20 ? "%.0f" : "%.1f")")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize()
            if let unit = unit {
                Text(NSLocalizedString(unit, comment: ""))
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
    let unit: String?
    let localizedLabel: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, localizedLabel: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.localizedLabel = localizedLabel
        self.color = color
    }

    private var adaptiveColor: Color {
        guard colorScheme == .light else { return color }

        // Use specific darker variants for better contrast in light mode
        switch color {
        case .orange:
            return Color(red: 0.85, green: 0.45, blue: 0.0) // Darker orange
        case .green:
            return Color(red: 0.0, green: 0.6, blue: 0.0) // Darker green
        case .red:
            return Color(red: 0.8, green: 0.0, blue: 0.0) // Darker red
        case .blue:
            return Color(red: 0.0, green: 0.4, blue: 0.8) // Darker blue
        case .purple:
            return Color(red: 0.6, green: 0.0, blue: 0.6) // Darker purple
        case .gray:
            return Color(red: 0.4, green: 0.4, blue: 0.4) // Darker gray for better contrast
        default:
            return color
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(Double(value), specifier: unit == "kcal" || value > 20 ? "%.0f" : "%.1f")")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(adaptiveColor)
                .shadow(color: .black.opacity(colorScheme == .light ? 0.08 : 0), radius: 0.5, x: 0, y: 0.5)
                .fixedSize()
            if let unit = unit {
                Text(NSLocalizedString(unit, comment: ""))
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
    let unit: String?
    let localizedLabel: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, localizedLabel: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.localizedLabel = localizedLabel
        self.color = color
    }

    private var adaptiveColor: Color {
        guard colorScheme == .light else { return color }

        // Use specific darker variants for better contrast in light mode
        switch color {
        case .orange:
            return Color(red: 0.85, green: 0.45, blue: 0.0) // Darker orange
        case .green:
            return Color(red: 0.0, green: 0.6, blue: 0.0) // Darker green
        case .red:
            return Color(red: 0.8, green: 0.0, blue: 0.0) // Darker red
        case .blue:
            return Color(red: 0.0, green: 0.4, blue: 0.8) // Darker blue
        case .purple:
            return Color(red: 0.6, green: 0.0, blue: 0.6) // Darker purple
        case .gray:
            return Color(red: 0.4, green: 0.4, blue: 0.4) // Darker gray for better contrast
        default:
            return color
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("\(Double(value), specifier: unit == "kcal" || value > 10 ? "%.0f" : "%.1f")")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(adaptiveColor)
                    .shadow(color: .black.opacity(colorScheme == .light ? 0.08 : 0), radius: 0.5, x: 0, y: 0.5)
                    .fixedSize()
                if let unit = unit {
                    Text(NSLocalizedString(unit, comment: ""))
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

struct TotalNutritionBadge: View {
    let value: Decimal
    let unit: String?
    let localizedLabel: String?
    let color: Color

    init(value: Decimal, unit: String? = nil, localizedLabel: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.localizedLabel = localizedLabel
        self.color = color
    }

    var body: some View {
        VStack {
            HStack(spacing: 3) {
                // Larger, bolder text for totals
                Text("\(Double(value), specifier: "%.0f")")
                    .font(.system(size: 17, weight: .bold, design: .rounded)) // Larger
                    .foregroundColor(.primary)

                if let unit = unit {
                    Text(NSLocalizedString(unit, comment: ""))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                if let localizedLabel = localizedLabel {
                    Text(localizedLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10) // More padding
        .padding(.vertical, 8)
        .background(color.opacity(0.2)) // Stronger color
        .cornerRadius(10) // Slightly larger radius
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
