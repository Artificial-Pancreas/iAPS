import SwiftUI

/// The meal card on Home, Today (its name muted after the title): the carbs, fat, protein and energy since local
/// midnight, then, when today has nutrient data, the fiber and how many of today's entries have nutrient data. Two
/// buttons: the top opens the Statistics Meals tab, the Nutrients row its Nutrients screen (both on Today).
///
/// The window's totals (`GlucoseStatsEngine.window` of Today, up to the read), its entries as the Meals tab's
/// (`MealStatsEngine.clean`), its nutrient data counted in entries.
struct HomeMealsCard: View, Equatable {
    /// What the card shows, formatted off the main actor (`Home.Provider.mealsCard`), as of its read: nothing moves it on
    /// with the time alone (an entry dated later counts from the first read after its time). Compared as shown: a
    /// result that displays the same doesn't re-render Home.
    struct Content: Equatable, Sendable {
        /// A number of the top row.
        struct Tile: Equatable, Sendable, Identifiable {
            let id: Int
            /// "Carbs"
            let title: String
            /// "145"
            let value: String
            /// "g", "kcal"
            let unit: String
            /// the energy's: its unit a size smaller
            let isEnergy: Bool
        }

        /// The Nutrients row.
        struct Nutrients: Equatable, Sendable {
            /// "Data on 2 of 3 entries", "Data on 1 of 1 entry"
            let coverage: String
            /// "21", "3" (whole grams, as the Meals tab's Fiber tile)
            let fiber: String
            /// "g"
            let fiberUnit: String
            /// the entries with nutrient data carry less than 80% of today's carbs: a mark after the fiber
            let isLimited: Bool
        }

        /// carbs, fat, protein, energy
        let tiles: [Tile]
        /// nil: the row is hidden (no food, a Meals entry, with nutrient data today, or none logged in the last 90 days)
        let nutrients: Nutrients?

        /// Today's sums up to `now`; the fiber of the entries with nutrient data and of the nutrient-only ones (a
        /// supplement adds its nutrients, as on the Nutrients screen), the 80% rule over today's carbs. The coverage as
        /// the Nutrients screen's today status (`NutrientStatsEngine.day`), which the row opens: the supplements in both
        /// numbers. The row only with a food with nutrient data today, and food with nutrient data logged in the last 90
        /// days (`NutrientStatsEngine.logsNutrients`, the Meals tab's way to the Nutrients screen).
        /// - Parameter points: the meals of `Stat.Provider.mealsRange(.today, ...)` (the last 90 days to the end of today)
        init(points: [MealPoint], now: Date, calendar: Calendar) {
            let window = GlucoseStatsEngine.window(for: .today, now: now, end: now, calendar: calendar)
            let inWindow = { (point: MealPoint) in point.actualDate >= window.start && point.actualDate <= now }
            let entries = MealStatsEngine.clean(points).filter(inWindow)
            let supplements = NutrientStatsEngine.nutrientOnly(points).filter(inWindow)
            let carbs: Double = entries.reduce(0) { $0 + $1.carbs }
            let fat: Double = entries.reduce(0) { $0 + $1.fat }
            let protein: Double = entries.reduce(0) { $0 + $1.protein }
            // kcal: 4 × (carbs + protein) + 9 × fat
            let energy = 4 * (carbs + protein) + 9 * fat

            let grams = NSLocalizedString("g", comment: "Statistics Meals: grams")
            let kcal = NSLocalizedString("kcal", comment: "Home meal card: the unit of the energy")
            tiles = [
                Tile(
                    id: 0,
                    title: NSLocalizedString("Carbs", comment: ""),
                    value: Self.whole(carbs),
                    unit: grams,
                    isEnergy: false
                ),
                Tile(
                    id: 1,
                    title: NSLocalizedString("Fat", comment: ""),
                    value: Self.whole(fat),
                    unit: grams,
                    isEnergy: false
                ),
                Tile(
                    id: 2,
                    title: NSLocalizedString("Protein", comment: ""),
                    value: Self.whole(protein),
                    unit: grams,
                    isEnergy: false
                ),
                Tile(
                    id: 3,
                    title: NSLocalizedString("Energy", comment: "Home meal card: the energy of the carbs, fat and protein"),
                    value: Self.whole(energy),
                    unit: kcal,
                    isEnergy: true
                )
            ]

            let withData = entries.filter(\.hasNutrientData)
            guard NutrientStatsEngine.logsNutrients(points, now: now, calendar: calendar), withData.isNotEmpty else {
                nutrients = nil
                return
            }
            let carbsWithData = withData.reduce(0) { $0 + $1.carbs }
            // a little room for the sums' rounding, as `NutrientStatsEngine.day`'s
            let isLimited = carbs > 0 && carbsWithData + 1E-9 < NutrientStatsEngine.countedCarbShare * carbs
            let fiber: Double = (withData + supplements).reduce(0) { $0 + StatsNutrient.fiber.amount(in: $1) }
            let counted = withData.count + supplements.count
            let total = entries.count + supplements.count
            nutrients = Nutrients(
                // whole grams, as the Meals tab's Fiber tile
                coverage: Self.coverage(counted, of: total),
                fiber: StatsAmount.number(fiber, digits: 0),
                fiberUnit: grams,
                isLimited: isLimited
            )
        }

        // MARK: Formatting

        /// "145", "1,820"
        private static func whole(_ value: Double) -> String {
            StatsAmount.number(value, digits: 0 ... 0)
        }

        /// "Data on 2 of 3 entries", "Data on 1 of 1 entry"
        private static func coverage(_ withData: Int, of total: Int) -> String {
            total == 1
                ? String(
                    format: NSLocalizedString(
                        "Data on %d of 1 entry",
                        comment: "Home meal card: the entry with nutrient data, of today's one entry"
                    ),
                    withData
                )
                : String(
                    format: NSLocalizedString(
                        "Data on %1$d of %2$d entries",
                        comment: "Home meal card: the entries with nutrient data, of today's entries"
                    ),
                    withData,
                    total
                )
        }
    }

    let content: Content
    /// the Statistics Meals tab on Today
    let openMeals: () -> Void
    /// the Statistics Meals tab's Nutrients screen on Today
    let openNutrients: () -> Void

    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var fiberSize: CGFloat = 17

    /// `.equatable()` by what it shows: the call site's actions are new closures on every Home re-render, the same
    /// actions (the Home state) while this is the same
    nonisolated static func == (lhs: HomeMealsCard, rhs: HomeMealsCard) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeCardHeader(
                title: NSLocalizedString("Meals", comment: "Home meal card title"),
                rangeLabel: StatsFormatting.label(.today),
                open: openMeals
            ) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            // the row is 44 pt tall (`HomeCardMetrics`): the space above and below it is mostly in it
            .padding(.top, 8)
            Button(action: openMeals) {
                meals
            }
            .buttonStyle(.plain)

            if let nutrients = content.nutrients {
                Divider()
                    .padding(.leading, 16)
                Button(action: openNutrients) {
                    nutrientsRow(nutrients)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meals

    private var meals: some View {
        // one row, the energy's column wider; two rows of two when it doesn't fit (large text)
        ViewThatFits(in: .horizontal) {
            HomeMealsColumns(weights: [1, 1, 1, 1.3], spacing: 8) {
                ForEach(content.tiles) { tile($0) }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach([0, 2], id: \.self) { first in
                    HomeMealsColumns(weights: [1, 1], spacing: 8) {
                        ForEach(content.tiles[first ..< Swift.min(first + 2, content.tiles.count)]) { tile($0) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func tile(_ tile: Content.Tile) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tile.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(tile.value)
                    .font(.system(size: valueSize, weight: .bold))
                    .monospacedDigit()
                Text(tile.unit)
                    .font(tile.isEnergy ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Nutrients

    private func nutrientsRow(_ nutrients: Content.Nutrients) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Nutrients")
                    .font(.subheadline.weight(.semibold))
                Text(nutrients.coverage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("Fiber")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(nutrients.fiber)
                    .font(.system(size: fiberSize, weight: .semibold))
                    .monospacedDigit()
                Text(nutrients.fiberUnit)
                    .font(.subheadline.weight(.semibold))
                if nutrients.isLimited {
                    LimitedDataMarker(note: nil, font: .footnote)
                        .padding(.leading, 2)
                }
            }
            .lineLimit(1)
            // the number never truncates: the coverage does
            .fixedSize()
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// The tiles side by side in columns of the given widths (`weights`, relative), each tile at its column's start. Its
/// ideal width is the narrowest at which each tile fits its column, so `ViewThatFits` takes the next layout when they
/// don't fit. Each subview's ideal size; as many subviews as weights.
private struct HomeMealsColumns: Layout {
    let weights: [CGFloat]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = weights.reduce(0, +)
        let gaps = spacing * CGFloat(Swift.max(subviews.count - 1, 0))
        // the column of each tile is `weight / total` of the width after the gaps
        let needed = zip(sizes, weights).map { size, weight in weight > 0 ? size.width / weight : 0 }.max() ?? 0
        let ideal = needed * total + gaps
        // the width offered, never less than the ideal one: narrower, it reports that the tiles don't fit
        let width = proposal.width.map { Swift.max($0, ideal) } ?? ideal
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let total = weights.reduce(0, +)
        let gaps = spacing * CGFloat(Swift.max(subviews.count - 1, 0))
        let unit = total > 0 ? Swift.max(bounds.width - gaps, 0) / total : 0
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = (index < weights.count ? weights[index] : 0) * unit
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}
