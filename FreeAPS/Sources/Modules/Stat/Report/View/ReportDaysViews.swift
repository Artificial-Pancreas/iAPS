import SwiftUI

// The Days table's print view: fixed columns and a fixed row height, so a page holds a known number of rows
// (`ReportPlan.daysTableRowsPerPage`).

struct ReportDaysContent: View {
    let page: Stat.ReportDaysPage
    /// the content's, points
    let width: CGFloat

    private static let dateWidth: CGFloat = 104
    private static let barWidth: CGFloat = 70
    private static let spacing: CGFloat = 6
    private static let headerHeight: CGFloat = 24

    var body: some View {
        let widths = columnWidths
        VStack(alignment: .leading, spacing: 0) {
            header(widths)
            Rectangle()
                .fill(ReportStyle.rule)
                .frame(width: tableWidth, height: 0.5)
            ForEach(page.rows) { row in
                rowView(row, widths)
                Rectangle()
                    .fill(ReportStyle.hairline)
                    .frame(width: tableWidth, height: 0.5)
            }
            Text(page.footnote)
                .font(ReportStyle.font(7))
                .foregroundStyle(ReportStyle.secondary)
                // three lines are the room under a full page of rows; a longer note shrinks rather than run into the footer
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .frame(width: width, alignment: .topLeading)
                .frame(maxHeight: 27, alignment: .top)
                .padding(.top, 5)
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// the most a column of weight 1 takes: with few columns the table stays compact, at the leading side
    private static let widestColumn: CGFloat = 58

    /// The columns share the width left of the date and the bar by their weights, up to `widestColumn` each.
    private var columnWidths: [CGFloat] {
        let count = CGFloat(page.columns.count)
        let free = Swift.max(width - Self.dateWidth - Self.barWidth - Self.spacing * (count + 1), 0)
        let total = Swift.max(page.columns.reduce(0) { $0 + $1.weight }, 0.1)
        let unit = Swift.min(free / total, Self.widestColumn)
        return page.columns.map { unit * $0.weight }
    }

    /// the table's: the page's, or less with few columns
    private var tableWidth: CGFloat {
        let count = CGFloat(page.columns.count)
        return Swift.min(Self.dateWidth + Self.barWidth + Self.spacing * (count + 1) + columnWidths.reduce(0, +), width)
    }

    private func header(_ widths: [CGFloat]) -> some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            Text(page.dateTitle)
                .font(ReportStyle.font(7.5, .semibold))
                .frame(width: Self.dateWidth, alignment: .leading)
            Color.clear
                .frame(width: Self.barWidth, height: 1)
            ForEach(Array(page.columns.enumerated()), id: \.element.id) { index, column in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(column.title)
                        .font(ReportStyle.font(7.5, .semibold))
                    Text(column.subtitle)
                        .font(ReportStyle.font(6.5))
                        .foregroundStyle(ReportStyle.secondary)
                }
                .minimumScaleFactor(0.6)
                .frame(width: widths[index], alignment: .trailing)
            }
        }
        .lineLimit(1)
        .padding(.bottom, 3)
        .frame(width: tableWidth, height: Self.headerHeight, alignment: .bottomLeading)
    }

    private func rowView(_ row: Stat.ReportDaysPage.Row, _ widths: [CGFloat]) -> some View {
        let isDay = row.style == .day
        let weight: Font.Weight = isDay ? .regular : .semibold
        return HStack(spacing: Self.spacing) {
            Text(row.title)
                .font(ReportStyle.font(8.5, weight))
                .minimumScaleFactor(0.6)
                .frame(width: Self.dateWidth, alignment: .leading)
            bar(row.segments)
            ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .font(ReportStyle.font(8.5, weight))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .frame(width: index < widths.count ? widths[index] : 0, alignment: .trailing)
            }
        }
        .lineLimit(1)
        .frame(width: tableWidth, height: ReportPlan.daysTableRowHeight - 0.5, alignment: .leading)
        .background(isDay ? Color.white : ReportStyle.shade)
    }

    /// The day's time by band, very low at the leading end; empty without readings.
    private func bar(_ segments: [BandSegment]) -> some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                Rectangle()
                    .fill(segment.band.color)
                    .frame(width: Self.barWidth * CGFloat(segment.fraction), height: 7)
            }
        }
        .frame(width: Self.barWidth, height: 7, alignment: .leading)
    }
}
