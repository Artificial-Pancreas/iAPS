
import SwiftData
import SwiftUI

struct MealsHistorySheet: View {
    @State private var summaries: [MealDaySummary] = []
    @State private var selectedRange: MealsRange = .oneWeek

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Range", selection: $selectedRange) {
                    ForEach(MealsRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if summaries.isEmpty {
                    Text("Not enough data available for the selected period yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    MealsMacrosChartView(summaries: summaries)
                        .padding(.horizontal)
                        .padding(.top, 10)

                    averagesView
                        .padding(.top, 12)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Meals history")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadData)
            .onChange(of: selectedRange) { _, _ in
                loadData()
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private func loadData() {
        summaries = CoreDataStorage().generateMealSummariesForLastNDays(
            days: selectedRange.days
        )
    }

    private var averagesView: some View {
        let count = Double(summaries.count)
        let avgKcal = summaries.reduce(0.0) { $0 + $1.kcal } / count
        let avgCarbs = summaries.reduce(0.0) { $0 + $1.carbs } / count
        let avgFat = summaries.reduce(0.0) { $0 + $1.fat } / count
        let avgProtein = summaries.reduce(0.0) { $0 + $1.protein } / count

        return VStack(alignment: .leading, spacing: 4) {
            Text("Daily average for last \(selectedRange.days) days")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("kcal")
                Spacer()
                Text(avgKcal.formatted(.number.precision(.fractionLength(0))))
            }
            HStack {
                Text("Carbs (g)")
                Spacer()
                Text(avgCarbs.formatted(.number.precision(.fractionLength(1))))
            }
            HStack {
                Text("Fat (g)")
                Spacer()
                Text(avgFat.formatted(.number.precision(.fractionLength(1))))
            }
            HStack {
                Text("Protein (g)")
                Spacer()
                Text(avgProtein.formatted(.number.precision(.fractionLength(1))))
            }
            .font(.footnote)
        }
    }
}
