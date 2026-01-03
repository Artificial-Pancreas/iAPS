import Foundation
import SwiftUI

enum NutritionBadgeConfig {
    static let caloriesColor = Color.red
    static let carbsColor = Color.orange
    static let proteinColor = Color.green
    static let fatColor = Color.blue
    static let fiberColor = Color.purple
    static let sugarsColor = Color.purple
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
    let label: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, label: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.label = label
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
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            if let label = label {
                Text(label)
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
    let label: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, label: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.label = label
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(Double(value), specifier: unit == "kcal" || value > 20 ? "%.0f" : "%.1f")")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .fixedSize()
            if let unit = unit {
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            if let label = label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.lowercase)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

struct NutritionBadgePlainStacked: View {
    let value: Decimal
    let unit: String?
    let label: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, label: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.label = label
        self.color = color
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("\(Double(value), specifier: unit == "kcal" || value > 10 ? "%.0f" : "%.1f")")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .fixedSize()
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
            Text(label ?? "")
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
    let label: String?
    let color: Color

    init(value: Decimal, unit: String? = nil, label: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.label = label
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
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                if let label = label {
                    Text(label)
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
                .font(.system(size: 14))

            Text(level.description)
                .font(.caption)
                .fontWeight(.regular)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(level.color.opacity(backgroundOpacity))
        .foregroundColor(textColor)
        .cornerRadius(6)
    }
}
