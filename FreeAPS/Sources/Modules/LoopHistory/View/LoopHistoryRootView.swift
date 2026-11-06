import SwiftUI
import Swinject

extension LoopHistory {
    /// The Loops screen: one page, the calendar of the last five weeks and the detail of the last 30 days or of the day
    /// picked (`Content`). Opened by the Home Loops card, presented as Statistics is.
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    if let content = state.content {
                        CalendarCard(content: content, select: { state.select(.day($0)) })
                        DetailCard(
                            detail: content.detail,
                            showsReset: content.selection != .lastDays,
                            reset: { state.showLastDays() },
                            showDay: { state.select(.day($0)) }
                        )
                    } else if state.failed {
                        StatsCard {
                            Text("The loops couldn't be read.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    } else {
                        StatsCard {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationBarTitle(NSLocalizedString("Loops", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
            .onAppear { state.appear() }
            .onDisappear { state.disappear() }
        }
    }
}

// MARK: - Calendar

private extension LoopHistory {
    /// "By day": a cell per day of the last five weeks, coloured by its share of the loops due that ran; a tap
    /// picks the day (again: the 30 days).
    struct CalendarCard: View {
        let content: Content
        let select: (Date) -> Void

        @ScaledMetric(relativeTo: .subheadline) private var cellHeight: CGFloat = 46

        var body: some View {
            StatsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("By day")
                            .font(.headline)
                        Spacer(minLength: 0)
                        Text(content.calendarDates)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            ForEach(Array(content.weekdays.enumerated()), id: \.offset) { _, weekday in
                                Text(weekday)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.bottom, 2)
                            }
                        }
                        ForEach(Array(content.weeks.enumerated()), id: \.offset) { _, week in
                            GridRow {
                                ForEach(week) { cell in
                                    CalendarCell(cell: cell, height: cellHeight, select: select)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, -12)
                    legend
                        .padding(.top, 4)
                }
            }
        }

        private var legend: some View {
            FlowLayout(spacing: 10) {
                swatch(.best, NSLocalizedString("95–100 %", comment: "Loops screen: the heat-map's key"))
                swatch(.good, NSLocalizedString("90–95", comment: "Loops screen: the heat-map's key"))
                swatch(.fair, NSLocalizedString("75–90", comment: "Loops screen: the heat-map's key"))
                swatch(.poor, NSLocalizedString("under 75", comment: "Loops screen: the heat-map's key"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        private func swatch(_ bin: Bin, _ label: String) -> some View {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(bin.fill)
                    .frame(width: 14, height: 14)
                Text(label)
            }
        }
    }

    /// A day: its number (and "Today" or the month above it) on its colour; outlined without readings; the number only
    /// after today.
    struct CalendarCell: View {
        let cell: Cell
        let height: CGFloat
        let select: (Date) -> Void

        var body: some View {
            if cell.isFuture {
                Text(cell.number)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                Button { select(cell.id) } label: {
                    face
                        .padding(3)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .overlay {
                            if cell.isSelected {
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        private var face: some View {
            VStack(spacing: 0) {
                if let caption = cell.caption {
                    Text(caption)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(cell.number)
                    .font(.subheadline.weight(cell.isToday || cell.isSelected ? .bold : .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(cell.bin.map(\.label) ?? Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if let bin = cell.bin {
                    RoundedRectangle(cornerRadius: 9).fill(bin.fill)
                } else {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
        }
    }
}

private extension LoopHistory.Bin {
    var fill: Color {
        switch self {
        case .best: return Color(.statsLoopHeat0)
        case .good: return Color(.statsLoopHeat1)
        case .fair: return Color(.statsLoopHeat2)
        case .poor: return Color(.statsLoopHeat3)
        }
    }

    var label: Color {
        switch self {
        case .best: return Color(.statsLoopHeatLabel0)
        case .good: return Color(.statsLoopHeatLabel1)
        case .fair: return Color(.statsLoopHeatLabel2)
        case .poor: return Color(.statsLoopHeatLabel3)
        }
    }
}

// MARK: - Detail

private extension LoopHistory {
    /// The last 30 days or the day picked: the share, the tiles, the strip, the longest gaps, why loops failed.
    struct DetailCard: View {
        let detail: Detail
        let showsReset: Bool
        let reset: () -> Void
        let showDay: (Date) -> Void

        @ScaledMetric(relativeTo: .largeTitle) private var percentSize: CGFloat = 44
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            StatsCard {
                header
                headline
                tiles
                strip
                gaps
                causes
            }
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.title)
                        .font(.title3.weight(.bold))
                    Text(detail.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if showsReset {
                    Button(action: reset) {
                        Label(
                            String(
                                format: NSLocalizedString("%d days", comment: "Loops screen: back to the last 30 days"),
                                LoopHistory.Config.aggregateDays
                            ),
                            systemImage: "arrow.uturn.backward"
                        )
                        .font(.subheadline)
                    }
                    .frame(minHeight: 44)
                }
            }
        }

        private var headline: some View {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    percent
                    caption
                }
                VStack(alignment: .leading, spacing: 4) {
                    percent
                    caption
                }
            }
        }

        private var percent: some View {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(detail.percent)
                    .font(.system(size: percentSize, weight: .bold))
                if detail.hasPercent {
                    Text(verbatim: "%")
                        .font(.system(size: percentSize / 2, weight: .semibold))
                }
            }
            .monospacedDigit()
            .lineLimit(1)
        }

        private var caption: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("of loops ran")
                    .font(.subheadline.weight(.semibold))
                Text(detail.counts)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }

        @ViewBuilder private var tiles: some View {
            let failed = StatTile(
                title: NSLocalizedString("Failed loops", comment: "Loops screen: the loops due that failed"),
                value: detail.failed,
                style: .compact
            )
            let missed = StatTile(
                title: NSLocalizedString("No loop ran", comment: "Loops screen: the loops due that didn't start"),
                value: detail.missed,
                style: .compact
            )
            let median = StatTile(
                title: NSLocalizedString("Median loop", comment: "Loops screen: the median loop duration"),
                value: detail.medianDuration,
                unit: "s",
                style: .compact
            )
            if dynamicTypeSize >= .xLarge {
                VStack(spacing: 8) {
                    failed
                    missed
                    median
                }
            } else {
                HStack(spacing: 8) {
                    failed
                    missed
                    median
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        private var strip: some View {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(detail.stripTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if detail.isDay {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.statsLoopGap))
                                .frame(width: 10, height: 10)
                            Text("Gap")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                ZStack {
                    LoopStripColumns(columns: detail.columns)
                        .fill(Color(.statsLoopColumn))
                    LoopStripGapMarks(marks: detail.gapMarks)
                        .fill(Color(.statsLoopGap))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Color(.statsLoopTrack))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                HStack(spacing: 0) {
                    ForEach(Array(detail.axis.enumerated()), id: \.offset) { index, label in
                        if index > 0 {
                            Spacer(minLength: 2)
                        }
                        Text(label)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }
        }

        private var gaps: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Longest gaps")
                    .font(.headline)
                    .padding(.bottom, 2)
                if detail.gaps.isEmpty {
                    Text("No gap of 15 min or more")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(Array(detail.gaps.enumerated()), id: \.element.id) { index, gap in
                    if index > 0 {
                        Divider()
                    }
                    if let day = gap.day {
                        Button { showDay(gap.dayStart) } label: {
                            HStack(spacing: 8) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(day).font(.subheadline)
                                        gapTimes(gap)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(day).font(.subheadline)
                                        gapTimes(gap)
                                    }
                                }
                                Spacer(minLength: 0)
                                gapLength(gap)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 8) {
                            Text(gap.times)
                                .font(.subheadline)
                                .monospacedDigit()
                            Spacer(minLength: 0)
                            gapLength(gap)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }

        private func gapTimes(_ gap: GapRow) -> some View {
            Text(gap.times)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        private func gapLength(_ gap: GapRow) -> some View {
            Text(gap.length)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }

        private var causes: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Why loops failed")
                        .font(.headline)
                    Spacer(minLength: 0)
                    if let line = detail.causesLine {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 2)
                if detail.causes.isEmpty {
                    Text("Every loop ran")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(Array(detail.causes.enumerated()), id: \.element.id) { index, cause in
                    if index > 0 {
                        Divider()
                    }
                    CauseRowView(cause: cause)
                }
            }
        }
    }

    struct CauseRowView: View {
        let cause: CauseRow

        @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 30

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .frame(width: iconSize, height: iconSize)
                    .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(cause.title)
                        .font(.subheadline.weight(.semibold))
                    if let message = cause.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill))
                            Capsule()
                                .fill(Color(.systemGray))
                                .frame(width: max(2, geometry.size.width * cause.fraction))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 2)
                }
                Text(cause.count)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(.vertical, 9)
        }

        private var symbol: String {
            switch cause.kind {
            case let .failure(type): return type.symbol
            case .other: return "ellipsis"
            case .missed: return LoopEventType.skippedLoops.symbol
            }
        }

        private var color: Color {
            switch cause.kind {
            case let .failure(type): return type.color
            case .other: return LoopEventType.other.color
            case .missed: return LoopEventType.skippedLoops.color
            }
        }
    }
}
