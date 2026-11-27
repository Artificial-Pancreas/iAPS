import SwiftUI

// MARK: - The wear bar

/// A session's wear bar: its wear from the activation on the topic's scale (the longest wear), the tick at the wear
/// limit (3 days: Medtrum, Omnipod), its gaps cut out as notches, the time before the recording's start dashed (a short
/// dashed lead when the activation isn't known); the
/// patch in use to its age in the accent colour, the rest up to its grace's end outlined. The big one (the detail's,
/// Today's) marks the days and names them under it. Equatable: redrawn only when the plot changes.
struct PatchWearBar: View, Equatable {
    struct Plot: Equatable, Sendable {
        /// h after the activation
        struct Gap: Equatable, Sendable {
            let start: Double
            let end: Double
        }

        /// h: the bar's end
        let scale: Double
        /// h
        let wear: Double
        /// h after the activation: the recording's start; 0 when it isn't partial
        let dataStart: Double
        /// no activation known: a short dashed lead before the bar (its start is the recording's)
        var isStartUnknown = false
        let gaps: [Gap]
        let isInUse: Bool
        /// h: the tick; nil without a wear limit
        let limit: Double?
        /// in use: the rest outlined up to here, h
        let restEnd: Double?
        /// the big bar: the days under it; empty for a row's
        let dayNames: [String]
        /// the big bar of the one in use: "now" under its age
        let nowLabel: String?
        /// the big one (the detail's, Today's): its day names under it (none without a known activation)
        var isBig = false
    }

    let plot: Plot

    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 16

    nonisolated static func == (lhs: PatchWearBar, rhs: PatchWearBar) -> Bool {
        lhs.plot == rhs.plot
    }

    private var barHeight: CGFloat { plot.isBig ? 10 : 6 }
    private var top: CGFloat { plot.isBig ? 6 : 4 }

    var body: some View {
        let plot = self.plot
        let barHeight = self.barHeight
        let top = self.top
        let labelHeight = self.labelHeight
        Canvas { context, size in
            let width = size.width
            // no activation known: the bar starts after a short dashed lead
            let lead: CGFloat = plot.isStartUnknown ? Swift.min(10, width * 0.06) : 0
            func x(_ hours: Double) -> CGFloat {
                lead + (plot.scale > 0 ? CGFloat(Swift.min(Swift.max(hours, 0), plot.scale) / plot.scale) * (width - lead) : 0)
            }
            func bar(_ from: CGFloat, _ to: CGFloat, inset: CGFloat = 0) -> Path {
                let rect = CGRect(x: from, y: top + inset, width: Swift.max(0, to - from), height: barHeight - inset * 2)
                return Path(roundedRect: rect, cornerRadius: rect.height / 2)
            }
            func line(_ at: CGFloat, from: CGFloat, to: CGFloat) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: at, y: from))
                    path.addLine(to: CGPoint(x: at, y: to))
                }
            }

            context.fill(bar(0, width), with: .color(Color(.systemGray5)))
            if plot.dataStart > 0 || lead > 0 {
                context.stroke(
                    bar(0, x(plot.dataStart), inset: 0.5),
                    with: .color(Color(.systemGray)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }
            context.fill(
                bar(x(plot.dataStart), x(plot.wear)),
                with: .color(plot.isInUse ? Color.accentColor : Color(.systemGray))
            )
            for gap in plot.gaps where gap.end <= plot.wear {
                let rect = CGRect(
                    x: x(gap.start),
                    y: top - 1,
                    width: Swift.max(x(gap.end) - x(gap.start), 2),
                    height: barHeight + 2
                )
                context.fill(Path(rect), with: .color(Color(.secondarySystemGroupedBackground)))
            }
            if let restEnd = plot.restEnd, restEnd > plot.wear {
                context.stroke(
                    bar(x(plot.wear), x(restEnd) - 0.5, inset: 0.5),
                    with: .color(Color(.systemGray)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
            }
            if plot.isBig {
                for day in 1 ..< Swift.max(plot.dayNames.count, 1) {
                    let at = x(Double(day) * 24)
                    context.stroke(
                        line(at, from: top, to: top + barHeight),
                        with: .color(Color(.secondarySystemGroupedBackground)),
                        lineWidth: 1.5
                    )
                }
            }
            if let limit = plot.limit, limit < plot.scale {
                context.stroke(line(x(limit), from: top - 3, to: top + barHeight + 3), with: .color(.primary), lineWidth: 1.5)
            }
            if plot.isInUse {
                context.stroke(
                    line(x(plot.wear), from: top - 4, to: top + barHeight + 4),
                    with: .color(.primary),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }
            if plot.isBig {
                let labelTop = top + barHeight + 4
                for (index, name) in plot.dayNames.enumerated() {
                    let start = x(Double(index) * 24)
                    let end = x(Swift.min(Double(index + 1) * 24, plot.scale))
                    let label = context.resolve(Text(name).font(.caption).foregroundStyle(.secondary))
                    // a day too short for its name (the last one, at the larger sizes) goes without it
                    guard label.measure(in: size).width <= end - start - 2 else { continue }
                    context.draw(label, at: CGPoint(x: (start + end) / 2, y: labelTop), anchor: .top)
                }
                if let now = plot.nowLabel {
                    let at = x(plot.wear)
                    context.draw(
                        Text(now).font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: Swift.min(at + 4, width - 2), y: labelTop + labelHeight),
                        anchor: at + 4 > width * 0.85 ? .topTrailing : .topLeading
                    )
                }
            }
        }
        .frame(height: plot.isBig ? top + barHeight + 4 + labelHeight * (plot.nowLabel == nil ? 1 : 2) : top * 2 + barHeight)
    }
}
