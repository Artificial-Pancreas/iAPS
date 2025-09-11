import SwiftUI

struct NutritionBadge: View {
    let value: Double
    let unit: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value, specifier: "%.0f")\(unit)")
                .font(.system(size: 12, weight: .bold))
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(8)
    }
}
