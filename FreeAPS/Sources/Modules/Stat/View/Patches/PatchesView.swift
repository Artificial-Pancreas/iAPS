import SwiftUI

// MARK: - The topic

/// The Patches topic: 7–90 d the summary, by wear day and patch by patch (a row pushes its detail); Today the patch in
/// use against the ones before it at the same age.
struct PatchesView: View {
    let patches: Stat.Patches
    /// a row tapped: its session's id (`PatchSession.id`)
    let open: (String) -> Void

    var body: some View {
        if let today = patches.today {
            PatchesTodayView(today: today, naming: patches.naming)
        } else {
            VStack(spacing: 16) {
                StatsCard { PatchesSummaryCard(patches: patches) }
                StatsCard { PatchesWearDaysCard(patches: patches) }
                StatsCard { list }
            }
        }
    }

    @ViewBuilder private var list: some View {
        StatsCardHeader(
            verbatim: patches.naming.byOne,
            detail: NSLocalizedString("newest first", comment: "Statistics Patches: the list's order")
        )
        VStack(spacing: 0) {
            StatsDividedRows(patches.rows) { row in
                Button {
                    open(row.id)
                } label: {
                    PatchesListRow(row: row)
                }
                .buttonStyle(.plain)
            }
        }
        Text(patches.barNote)
            .statsNote()
    }
}

/// The count, the ended and in use, the tiles and the period's note.
private struct PatchesSummaryCard: View {
    let patches: Stat.Patches

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

    var body: some View {
        StatsCardHeader(verbatim: patches.naming.title, range: patches.dateRange)

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(patches.count)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                Text(patches.countUnit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(patches.countDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        PatchesTiles(tiles: patches.tiles)

        if let note = patches.periodNote {
            Text(note)
                .statsNote()
        }
    }
}

/// Tiles two across (`StatTile`, compact).
struct PatchesTiles: View {
    let tiles: [Stat.Patches.Tile]

    var body: some View {
        StatsTileGrid(tiles, columns: 2)
    }
}

/// By wear day over the sessions: the bands and the mean, the insulin per 24 h split.
private struct PatchesWearDaysCard: View {
    let patches: Stat.Patches

    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 58

    var body: some View {
        StatsCardHeader(title: "By wear day", detail: patches.wearDayDetail)

        VStack(spacing: 4) {
            HStack {
                Text("In range")
                Spacer(minLength: 8)
                Text(patches.meanTitle)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                StatsDividedRows(patches.rangeRows) { row in
                    PatchesRangeRow(row: row, labelWidth: labelWidth)
                }
            }
        }

        VStack(spacing: 4) {
            HStack {
                Text("Insulin per 24 h")
                Spacer(minLength: 8)
                Text("U")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                StatsDividedRows(patches.insulinRows) { row in
                    PatchesInsulinRow(row: row, labelWidth: labelWidth)
                }
            }
        }

        StatsChartLegend(items: InsulinPart.allCases.map {
            StatsChartLegend.Item(id: $0.rawValue, key: .swatch($0.style), title: $0.name)
        })

        Text(patches.wearDayNote)
            .statsNote()
    }
}

/// A wear day's bands, in range and mean (By wear day).
private struct PatchesRangeRow: View {
    let row: Stat.Patches.RangeRow
    /// the card's day column
    let labelWidth: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: labelWidth, alignment: .leading)
            PatchesBandBar(segments: row.segments)
                .frame(height: 12)
            Text(row.inRange)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
            Text(row.mean)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .frame(minHeight: 48)
    }
}

/// A wear day's insulin per 24 h, its split on the card's scale (By wear day).
private struct PatchesInsulinRow: View {
    let row: Stat.Patches.InsulinRow
    /// the card's day column
    let labelWidth: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Text(row.name)
                .font(.subheadline.weight(.semibold))
                .frame(width: labelWidth, alignment: .leading)
            GeometryReader { geometry in
                StatsSplitBar(segments: row.segments, cornerRadius: 3)
                    .frame(width: geometry.size.width * CGFloat(Swift.min(Swift.max(row.width, 0), 1)))
            }
            .frame(height: 12)
            Text(row.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .frame(minHeight: 40)
    }
}

/// The bands as a bar (`BandBar`), the track without readings.
private struct PatchesBandBar: View {
    let segments: [BandSegment]

    var body: some View {
        if segments.isEmpty {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray5))
        } else {
            BandBar(segments: segments, cornerRadius: 3)
        }
    }
}

/// A session of "Patch by patch": its span, in use, its wear and insulin per day, its time in range, its wear bar.
private struct PatchesListRow: View {
    let row: Stat.Patches.ListRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(row.span)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if row.isInUse {
                            Text("In use")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: Capsule())
                        }
                        if row.isPartial {
                            // the row is the control: the mark alone (the detail explains)
                            LimitedDataMarker(note: nil, font: .footnote)
                        }
                    }
                    Text(row.detail)
                        .statsFootnote()
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.inRange)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("in range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            PatchWearBar(plot: row.bar)
                .equatable()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Today

/// The Today period: the patch in use, its age, its bar and when it expires, against the ones before it at the same
/// age; "No patch in use" without one.
private struct PatchesTodayView: View {
    let today: Stat.Patches.Today
    let naming: Stat.Patches.Naming

    var body: some View {
        if let inUse = today.inUse {
            VStack(spacing: 16) {
                StatsCard { PatchesInUseCard(inUse: inUse, naming: naming) }
                StatsCard { PatchesAgainstPreviousCard(inUse: inUse, naming: naming) }
            }
        } else {
            StatsCard {
                Text(naming.inUse)
                    .statsSectionTitle()
                Text(naming.noneInUse)
                    .statsEmptyNote()
            }
        }
    }
}

private struct PatchesInUseCard: View {
    let inUse: Stat.Patches.Today.InUse
    let naming: Stat.Patches.Naming

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

    var body: some View {
        StatsCardHeader(verbatim: naming.inUse, detail: inUse.plugin)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let dayName = inUse.dayName {
                    Text(dayName)
                        .font(.system(size: size, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(inUse.age)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(inUse.since)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        PatchWearBar(plot: inUse.bar)
            .equatable()
        if inUse.tiles.isNotEmpty {
            PatchesTiles(tiles: inUse.tiles)
        }
    }
}

/// The patch in use against the usual: the ones before it, each up to its age.
private struct PatchesAgainstPreviousCard: View {
    let inUse: Stat.Patches.Today.InUse
    let naming: Stat.Patches.Naming

    var body: some View {
        StatsCardHeader(verbatim: naming.againstPrevious) {
            if let usualTitle = inUse.usualTitle {
                Text(usualTitle)
                    .statsFootnote()
                    .monospacedDigit()
            }
        }

        // not compared (its age unknown, no pump data yet): its own column alone, no wear days
        PatchesAgainstPreviousTable(inUse: inUse, naming: naming)

        if inUse.compares {
            PatchesDayGrid(
                leadingTitle: NSLocalizedString("By wear day", comment: "Statistics Patches: the card of the wear days"),
                titles: [
                    NSLocalizedString("In range", comment: "Statistics glucose band"),
                    NSLocalizedString("Usual", comment: "Statistics Insulin Today: the usual insulin"),
                    NSLocalizedString("U/24 h", comment: "Statistics Patches Today by wear day: the insulin column"),
                    NSLocalizedString("Usual", comment: "Statistics Insulin Today: the usual insulin")
                ],
                emphasized: [0, 2],
                rows: inUse.days.map { day in
                    PatchesDayGrid.Row(
                        id: day.id,
                        name: day.name,
                        values: [day.inRange, day.second, day.perDay, day.usualPerDay ?? "–"]
                    )
                }
            )
        }

        Text(inUse.note)
            .statsNote()
    }
}

/// The patch in use's rows, this one against the usual (not compared: its own column alone).
private struct PatchesAgainstPreviousTable: View {
    let inUse: Stat.Patches.Today.InUse
    let naming: Stat.Patches.Naming

    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(naming.thisOne)
                    .frame(minWidth: column, alignment: .trailing)
                if inUse.compares {
                    Text("Usual")
                        .frame(minWidth: column, alignment: .trailing)
                }
            }
            .statsColumnHeader()
            StatsDividedRows(inUse.rows) { row in
                HStack(spacing: 10) {
                    Text(row.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.value)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(minWidth: column, alignment: .trailing)
                    if inUse.usual.indices.contains(row.id) {
                        Text(inUse.usual[row.id])
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(minWidth: column, alignment: .trailing)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .frame(minHeight: 40)
            }
        }
    }
}
