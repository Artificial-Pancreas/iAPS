import SwiftData
import SwiftUI

struct MealsHistorySheet: View {
    @State private var summaries: [MealDaySummary] = []
    @State private var previousSummaries: [MealDaySummary] = []
    @State private var selectedRange: MealsRange = .oneWeek

    @Environment(\.dismiss) private var dismiss

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

    private func loadData() {
        let storage = CoreDataStorage()

        // current period
        summaries = storage.generateMealSummariesForLastNDays(
            days: selectedRange.days
        )

        // previous period (same length, directly before current period)
        previousSummaries = storage.generateMealSummariesForLastNDays(
            days: selectedRange.days * 2
        )

        if previousSummaries.count > summaries.count {
            previousSummaries = Array(
                previousSummaries.dropLast(summaries.count)
            )
        }
    }

    // MARK: - Averages and comparison

    private func average(
        of keyPath: KeyPath<MealDaySummary, Double>,
        in data: [MealDaySummary]
    ) -> Double {
        let count = Double(data.count)
        guard count > 0 else { return 0 }
        let sum = data.reduce(0.0) { $0 + $1[keyPath: keyPath] }
        return sum / count
    }

    private func arrow(for delta: Double) -> String {
        if delta > 0.01 { return "↑" }
        if delta < -0.01 { return "↓" }
        return "→"
    }

    private var averagesView: some View {
        let days = selectedRange.days

        let avgKcal = average(of: \.kcal, in: summaries)
        let prevAvgKcal = average(of: \.kcal, in: previousSummaries)
        let deltaKcal = avgKcal - prevAvgKcal

        let avgCarbs = average(of: \.carbs, in: summaries)
        let prevAvgCarbs = average(of: \.carbs, in: previousSummaries)
        let deltaCarbs = avgCarbs - prevAvgCarbs

        let avgFat = average(of: \.fat, in: summaries)
        let prevAvgFat = average(of: \.fat, in: previousSummaries)
        let deltaFat = avgFat - prevAvgFat

        let avgProtein = average(of: \.protein, in: summaries)
        let prevAvgProtein = average(of: \.protein, in: previousSummaries)
        let deltaProtein = avgProtein - prevAvgProtein

        return VStack(alignment: .leading, spacing: 4) {
            Text("Daily average for last \(days) days")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("kcal")
                    .foregroundColor(.orange)
                Spacer()
                Text(avgKcal.formatted(.number.precision(.fractionLength(0))))
                    .foregroundColor(.orange)
                Text(arrow(for: deltaKcal))
                    .foregroundColor(.orange)
            }

            HStack {
                Text("Carbs (g)")
                    .foregroundColor(.red)
                Spacer()
                Text(avgCarbs.formatted(.number.precision(.fractionLength(1))))
                    .foregroundColor(.red)
                Text(arrow(for: deltaCarbs))
                    .foregroundColor(.red)
            }

            HStack {
                Text("Fat (g)")
                    .foregroundColor(.blue)
                Spacer()
                Text(avgFat.formatted(.number.precision(.fractionLength(1))))
                    .foregroundColor(.blue)
                Text(arrow(for: deltaFat))
                    .foregroundColor(.blue)
            }

            HStack {
                Text("Protein (g)")
                    .foregroundColor(.green)
                Spacer()
                Text(avgProtein.formatted(.number.precision(.fractionLength(1))))
                    .foregroundColor(.green)
                Text(arrow(for: deltaProtein))
                    .foregroundColor(.green)
            }
            .font(.footnote)
        }
    }
}
