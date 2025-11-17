import SwiftUI

struct NutritionSummaryBadge: View {
    let value: Double
    let unit: LocalizedStringKey
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value, specifier: "%.0f")")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
