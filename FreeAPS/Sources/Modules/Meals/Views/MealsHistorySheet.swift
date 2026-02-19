import SwiftData
import SwiftUI

struct MealsHistorySheet: View {
    @State private var summaries: [MealDaySummary] = []
    @State private var previousSummaries: [MealDaySummary] = []
    @State private var selectedRange: MealsRange = .oneWeek
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // ✅ Optimization: Create storage only once
    private let storage = CoreDataStorage()

    // ✅ Neues Format für die Karten: TT.MM.YY
    private static let cardDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yy"
        return df
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(MealsRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .scaleEffect(isDragging ? 0.98 : 1.0)
                    .opacity(isDragging ? 0.7 : 1.0)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 15, coordinateSpace: .local)
                            .onChanged { value in
                                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
                                    dragOffset = value.translation.width
                                    isDragging = true
                                }
                            }
                            .onEnded { value in
                                handleSwipe(translation: value.translation.width)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    dragOffset = 0
                                    isDragging = false
                                }
                            }
                    )

                    if summaries.isEmpty {
                        Text("Not enough data available for the selected period yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        MealsMacrosChartView(
                            summaries: summaries,
                            range: selectedRange
                        )
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .offset(x: dragOffset * 0.4)
                        .opacity(isDragging ? 0.85 : 1.0)
                        .scaleEffect(isDragging ? 0.98 : 1.0)

                        averagesSection
                            .padding(.top, 12)
                            .padding(.horizontal)
                            .offset(x: dragOffset * 0.35)
                            .opacity(isDragging ? 0.85 : 1.0)
                            .scaleEffect(isDragging ? 0.98 : 1.0)

                        dailyCards
                            .padding(.top, 12)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .local)
                    .onChanged { value in
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
                            dragOffset = value.translation.width
                            isDragging = true
                        }
                    }
                    .onEnded { value in
                        handleSwipe(translation: value.translation.width)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragOffset = 0
                            isDragging = false
                        }
                    }
            )
            .navigationTitle("Meals history")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: loadData)
            .onChange(of: selectedRange) { _, _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    loadData()
                }
            }
        }
    }

    // MARK: - Swipe Handler

    private func handleSwipe(translation: CGFloat) {
        let allRanges = MealsRange.allCases
        guard let currentIndex = allRanges.firstIndex(of: selectedRange) else { return }

        // Sensitivity reduced to 25 points for smoother swiping
        if translation < -25 {
            // Swipe left = next time range (larger)
            let nextIndex = currentIndex + 1
            if nextIndex < allRanges.count {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedRange = allRanges[nextIndex]
                }
            }
        } else if translation > 25 {
            // Swipe right = previous time range (smaller)
            let previousIndex = currentIndex - 1
            if previousIndex >= 0 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedRange = allRanges[previousIndex]
                }
            }
        }
    }

    // ✅ Optimization: Storage is reused
    private func loadData() {
        summaries = storage.generateMealSummariesForLastNDays(
            days: selectedRange.days
        )

        previousSummaries = storage.generateMealSummariesForLastNDays(
            days: selectedRange.days * 2
        )

        if previousSummaries.count > summaries.count {
            previousSummaries = Array(
                previousSummaries.dropLast(summaries.count)
            )
        }
    }

    // MARK: - Adaptive Colors (✅ Optimized with Static Extension)

    private var kcalColor: Color {
        MacroColors.kcal(for: colorScheme)
    }

    private var carbsColor: Color {
        MacroColors.carbs(for: colorScheme)
    }

    private var fatColor: Color {
        MacroColors.fat(for: colorScheme)
    }

    private var proteinColor: Color {
        MacroColors.protein(for: colorScheme)
    }

    private var cardBackgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.05, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.95, green: 0.95, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(isDragging ? 0.25 : 0.15) : Color.black.opacity(isDragging ? 0.3 : 0.2)
    }

    private var cardTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)
    }

    // MARK: - Helpers

    private func average(
        of keyPath: KeyPath<MealDaySummary, Double>,
        in data: [MealDaySummary]
    ) -> Double? {
        guard !data.isEmpty else { return nil }
        let sum = data.reduce(0.0) { $0 + $1[keyPath: keyPath] }
        return sum / Double(data.count)
    }

    private func arrow(for delta: Double) -> String {
        if delta > 0.01 { return "↑" }
        if delta < -0.01 { return "↓" }
        return "→"
    }

    // MARK: - Averages

    private var averagesSection: some View {
        let days = selectedRange.days
        let minimumDaysRequired = 14 // At least 2 weeks of data required

        // Check if enough data is available for current AND previous period
        guard summaries.count >= minimumDaysRequired,
              previousSummaries.count >= minimumDaysRequired
        else {
            return AnyView(
                Text("At least 2 weeks of data required to calculate averages and trends.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            )
        }

        // Calculate averages
        guard
            let avgKcal = average(of: \.kcal, in: summaries),
            let avgCarbs = average(of: \.carbs, in: summaries),
            let avgFat = average(of: \.fat, in: summaries),
            let avgProtein = average(of: \.protein, in: summaries),
            let prevAvgKcal = average(of: \.kcal, in: previousSummaries),
            let prevAvgCarbs = average(of: \.carbs, in: previousSummaries),
            let prevAvgFat = average(of: \.fat, in: previousSummaries),
            let prevAvgProtein = average(of: \.protein, in: previousSummaries)
        else {
            return AnyView(
                Text("∅")
                    .font(.title)
                    .foregroundStyle(.secondary)
            )
        }

        let deltaKcal = avgKcal - prevAvgKcal
        let deltaCarbs = avgCarbs - prevAvgCarbs
        let deltaFat = avgFat - prevAvgFat
        let deltaProtein = avgProtein - prevAvgProtein

        let symbolKcal = arrow(for: deltaKcal)
        let symbolCarbs = arrow(for: deltaCarbs)
        let symbolFat = arrow(for: deltaFat)
        let symbolProtein = arrow(for: deltaProtein)

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily average for last \(days) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("kcal")
                        .foregroundColor(kcalColor)
                    Spacer()
                    Text(avgKcal.formatted(.number.precision(.fractionLength(0))))
                        .foregroundColor(kcalColor)
                    Text(symbolKcal)
                        .foregroundColor(kcalColor)
                }

                HStack {
                    Text("Carbs (g)")
                        .foregroundColor(carbsColor)
                    Spacer()
                    Text(avgCarbs.formatted(.number.precision(.fractionLength(1))))
                        .foregroundColor(carbsColor)
                    Text(symbolCarbs)
                        .foregroundColor(carbsColor)
                }

                HStack {
                    Text("Fat (g)")
                        .foregroundColor(fatColor)
                    Spacer()
                    Text(avgFat.formatted(.number.precision(.fractionLength(1))))
                        .foregroundColor(fatColor)
                    Text(symbolFat)
                        .foregroundColor(fatColor)
                }

                HStack {
                    Text("Protein (g)")
                        .foregroundColor(proteinColor)
                    Spacer()
                    Text(avgProtein.formatted(.number.precision(.fractionLength(1))))
                        .foregroundColor(proteinColor)
                    Text(symbolProtein)
                        .foregroundColor(proteinColor)
                }
            }
            .font(.footnote)
        )
    }

    // MARK: - Daily cards (✅ Optimized without array copy)

    private var dailyCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(summaries.indices, id: \.self) { index in
                let item = summaries[index]

                VStack(alignment: .leading, spacing: 6) {
                    // ✅ Hier ist das neue Datumsformat im Einsatz
                    Text(MealsHistorySheet.cardDateFormatter.string(from: item.date))
                        .font(.caption)
                        .foregroundColor(cardTextColor)

                    HStack {
                        Text("kcal")
                        Spacer()
                        Text(item.kcal.formatted(.number.precision(.fractionLength(0))))
                    }
                    .foregroundColor(kcalColor)

                    HStack {
                        Text("Carbs (g)")
                        Spacer()
                        Text(item.carbs.formatted(.number.precision(.fractionLength(1))))
                    }
                    .foregroundColor(carbsColor)

                    HStack {
                        Text("Fat (g)")
                        Spacer()
                        Text(item.fat.formatted(.number.precision(.fractionLength(1))))
                    }
                    .foregroundColor(fatColor)

                    HStack {
                        Text("Protein (g)")
                        Spacer()
                        Text(item.protein.formatted(.number.precision(.fractionLength(1))))
                    }
                    .foregroundColor(proteinColor)
                }
                .font(.footnote)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBackgroundGradient)
                        .shadow(color: colorScheme == .dark ? .black.opacity(0.8) : .black.opacity(0.15), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: isDragging ? 1.5 : 1)
                )
                .offset(x: dragOffset * (0.25 + Double(index) * 0.02))
                .scaleEffect(isDragging ? 0.97 : 1.0)
                .opacity(isDragging ? 0.80 : 1.0)
                .rotation3DEffect(
                    .degrees(dragOffset * 0.02),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 1.0
                )
            }
        }
    }
}

// MARK: - ✅ Optimization: Static Color Extension

enum MacroColors {
    static func kcal(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .orange : Color(red: 0.9, green: 0.5, blue: 0.0)
    }

    static func carbs(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .red : Color(red: 0.8, green: 0.0, blue: 0.0)
    }

    static func fat(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .blue : Color(red: 0.0, green: 0.4, blue: 0.9)
    }

    static func protein(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .green : Color(red: 0.0, green: 0.6, blue: 0.2)
    }
}
