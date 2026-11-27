import SwiftUI

// MARK: - The detail

/// A session, pushed from its row: older and newer, its wear, the facts, its insulin, glucose, wear days and loop. The
/// screen counts as a page of Statistics (`Stat.StateModel.Page.patch`). It follows its session by id
/// (`Stat.Patches.detailPlace`): the one shown stays (dimmed) while the content is read again, and when a refresh drops
/// the session (a midnight, coming back) the screen pops, the last one shown on it meanwhile.
struct PatchDetailScreen: View {
    /// What the screen shows: the session, and its neighbours' ids for the arrows.
    struct Shown: Equatable {
        let detail: Stat.Patches.Detail
        let naming: Stat.Patches.Naming
        let olderID: String?
        let newerID: String?
    }

    @ObservedObject var state: Stat.StateModel
    /// the session's (`PatchSession.id`)
    @Binding var id: String
    @Binding var isShown: Bool

    /// the one shown, built when the session or the content changes (not on every body): kept on screen while the
    /// content is read again without it, and while it pops
    @State private var shown: Shown?

    var body: some View {
        let place = Stat.Patches.detailPlace(of: id, in: state.patchesContent)
        ScrollView {
            Group {
                if let shown {
                    PatchDetailView(
                        detail: shown.detail,
                        naming: shown.naming,
                        canGoOlder: shown.olderID != nil,
                        canGoNewer: shown.newerID != nil,
                        older: {
                            if let older = shown.olderID {
                                id = older
                            }
                        },
                        newer: {
                            if let newer = shown.newerID {
                                id = newer
                            }
                        }
                    )
                    .opacity(place == .waiting || place == .gone || state.patchesContent.isLoading ? 0.5 : 1)
                } else {
                    StatsCard {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            .statsPageContent()
        }
        .statsPage(title: shown?.detail.navigationTitle ?? "")
        .onAppear {
            state.appear(.patch)
            update(place)
        }
        .onDisappear { state.disappear(.patch) }
        .onChange(of: place) { _, place in update(place) }
        .onChange(of: state.patchesContent) { update(Stat.Patches.detailPlace(of: id, in: state.patchesContent)) }
    }

    /// The session shown, at its place now; gone, the screen pops (the last one shown stays meanwhile).
    private func update(_ place: Stat.Patches.DetailPlace) {
        switch place {
        case let .index(index):
            guard let patches = state.patchesContent.value, patches.stats.indices.contains(index) else { return }
            let stats = patches.stats
            let new = Shown(
                detail: patches.detail(at: index),
                naming: patches.naming,
                olderID: index + 1 < stats.count ? stats[index + 1].id : nil,
                newerID: index > 0 ? stats[index - 1].id : nil
            )
            if new != shown {
                shown = new
            }
        case .waiting:
            break
        case .gone:
            popIfGone(place)
        }
    }

    private func popIfGone(_ place: Stat.Patches.DetailPlace) {
        if place == .gone, isShown {
            isShown = false
        }
    }
}

private struct PatchDetailView: View {
    let detail: Stat.Patches.Detail
    let naming: Stat.Patches.Naming
    let canGoOlder: Bool
    let canGoNewer: Bool
    let older: () -> Void
    let newer: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            StatsCard {
                StatsStepper(
                    title: detail.title,
                    subtitle: detail.subtitle,
                    canGoBack: canGoOlder,
                    canGoForward: canGoNewer,
                    back: older,
                    forward: newer
                )
                PatchWearBar(plot: detail.bar)
                    .equatable()
                VStack(spacing: 0) {
                    StatsDividedRows(detail.facts) { fact in
                        HStack(spacing: 12) {
                            Text(fact.name)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(fact.value)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                        .frame(minHeight: 40)
                    }
                }
            }
            StatsCard { insulin }
            StatsCard { glucose }
            if detail.days.isNotEmpty {
                StatsCard { days }
            }
            StatsCard {
                Text("Loop")
                    .statsSectionTitle()
                PatchesTiles(tiles: detail.loopTiles)
            }
        }
    }

    @ViewBuilder private var insulin: some View {
        StatsCardHeader(title: "Insulin", detail: detail.perDay)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(detail.total)
                .font(.title.bold())
                .monospacedDigit()
            Text("U")
                .font(.headline)
            if detail.soFar {
                Text("so far")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        if detail.split.isNotEmpty {
            StatsSplitBar(segments: detail.split, cornerRadius: 4)
                .frame(height: 12)
        }
        if let external = detail.external {
            Text(external)
                .statsFootnote()
                .monospacedDigit()
        }
        StatsPartRows(rows: detail.parts, unitHeader: NSLocalizedString("U", comment: ""))
    }

    @ViewBuilder private var glucose: some View {
        StatsCardHeader(title: "Glucose", detail: detail.cgm)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(detail.inRange)
                .font(.title.bold())
                .monospacedDigit()
            Text("in range")
                .font(.subheadline.weight(.semibold))
            Text(detail.rangeText)
                .statsFootnote()
        }
        if detail.bands.isNotEmpty {
            BandBar(segments: detail.bands, cornerRadius: 3)
                .frame(height: 12)
        }
        PatchesTiles(tiles: detail.glucoseTiles)
    }

    @ViewBuilder private var days: some View {
        StatsCardHeader(title: "By wear day", detail: naming.thisOneLowercased)
        PatchesDayGrid(
            leadingTitle: nil,
            titles: [
                NSLocalizedString("In range", comment: "Statistics glucose band"),
                NSLocalizedString("Mean", comment: "Statistics Patches detail: the mean glucose"),
                NSLocalizedString("U / 24 h", comment: "Statistics Patches detail by wear day: the insulin column")
            ],
            emphasized: [],
            secondary: [1],
            rows: detail.days.map { day in
                PatchesDayGrid.Row(
                    id: day.id,
                    name: day.name,
                    values: [day.inRange, day.second, day.perDay]
                )
            }
        )
    }
}

/// Wear days as a table: a day's name, then its numbers in columns (Today's in range and insulin against the usual, the
/// detail's). Above the default text size the name goes on a line of its own over the numbers, so the columns fit a
/// 375 pt phone at xxLarge.
struct PatchesDayGrid: View {
    struct Row: Identifiable {
        let id: Int
        let name: String
        let values: [String]
    }

    /// the names' column's header; nil for none
    let leadingTitle: String?
    /// the numbers' columns
    let titles: [String]
    /// columns in semibold (this one's, against the usual)
    let emphasized: Set<Int>
    /// columns in the secondary colour; the others not emphasized are by default (the usual)
    var secondary: Set<Int>?
    let rows: [Row]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 46

    private var isStacked: Bool { dynamicTypeSize > .large }

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 0) {
            GridRow {
                if !isStacked {
                    Text(leadingTitle ?? "")
                        .gridColumnAlignment(.leading)
                }
                ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .frame(minWidth: column, alignment: .trailing)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.bottom, 4)
            ForEach(rows) { row in
                Divider()
                if isStacked {
                    GridRow {
                        name(row)
                            .padding(.top, 8)
                            .gridCellColumns(titles.count)
                    }
                    GridRow {
                        values(row)
                    }
                    .frame(minHeight: 32)
                } else {
                    GridRow {
                        name(row)
                        values(row)
                    }
                    .frame(minHeight: 40)
                }
            }
        }
        .font(.subheadline)
        .monospacedDigit()
    }

    private func name(_ row: Row) -> some View {
        Text(row.name)
            .fontWeight(.semibold)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func values(_ row: Row) -> some View {
        ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
            Text(value)
                .fontWeight(emphasized.contains(index) ? .semibold : .regular)
                .foregroundStyle(isSecondary(index) ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: column, alignment: .trailing)
        }
    }

    private func isSecondary(_ index: Int) -> Bool {
        secondary.map { $0.contains(index) } ?? !emphasized.contains(index)
    }
}
