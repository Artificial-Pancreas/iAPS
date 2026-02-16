
import SwiftData
import SwiftUI

struct MealsHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var selectedRange: MealsRange = .sevenDays
    @State private var summaries: [MealDaySummary] = []

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
                }

                Spacer()
            }
            .navigationTitle("Meals history")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear(perform: loadData)
            .onChange(of: selectedRange) { _ in
                loadData()
            }
        }
    }

    private func loadData() {
        summaries = CoreDataStorage().generateMealSummariesForLastNDays(
            days: selectedRange.days
        )
    }
}
