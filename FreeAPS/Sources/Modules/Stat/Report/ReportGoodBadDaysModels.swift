import CoreGraphics
import Foundation

// Good & bad days as a report prints it: the screen's display model (`Stat.GoodBadDays`), without the selected time's
// readout. Three blocks flow over the part's pages: the comparison (the two profiles and "Glucose on those days"),
// "What was different on those days", and the two groups' days.

/// How Good & bad days is laid out. Every piece of its print view has a fixed height, given here, so the blocks'
/// heights are known before anything is drawn and a block never runs into the footer: one that doesn't fit under the
/// one before it starts the next page.
enum ReportGoodBadDaysLayout {
    typealias Section = GoodBadFactor.Section

    enum Block: Equatable, Sendable {
        /// the counts, the two profiles, "Glucose on those days"; a message in place of the comparison
        case comparison
        /// "What was different on those days": these sections, whole. `isFirst`: the block opens the factors (a later
        /// one says "continued"); `isLast`: the closing note is under it. Every block has the title and the line that
        /// says what a row's columns are.
        case factors(sections: [Section], isFirst: Bool, isLast: Bool)
        /// the two groups' days
        case lists
        /// no day scored: a line saying so, alone
        case empty
    }

    /// what a page's header and footer take of the height inside the margins
    static let chrome: CGFloat = 86
    /// the counts, up to three lines of the thirds, what the days are ranked by
    static let introHeight: CGFloat = 68
    /// in place of the comparison when the thirds have too few days
    static let messageHeight: CGFloat = 42
    static let chartHeight: CGFloat = 170
    /// the chart's legend and the lines under it
    static let chartNotesHeight: CGFloat = 40
    /// a section's title with its rule and the space around it
    static let sectionHeight: CGFloat = 30
    static let rowHeight: CGFloat = 13
    /// what a factor row is, over the rows
    static let factorIntroHeight: CGFloat = 20
    /// a factor section's title line
    static let factorSectionHeight: CGFloat = 18
    /// the note under the factors
    static let closingHeight: CGFloat = 16
    /// a list's title line
    static let listHeaderHeight: CGFloat = 14
    /// a day of a list
    static let dayHeight: CGFloat = 11.5
    /// a group with more days than this lists them in two columns
    static let singleColumnDays = 12
    /// the line of a part without a scored day
    static let emptyHeight: CGFloat = 24

    /// The rows a group's list takes: its days, or half of them in two columns.
    static func listRows(_ days: Int) -> Int {
        days > singleColumnDays ? (days + 1) / 2 : days
    }

    /// The comparison's height.
    static func comparisonHeight(_ data: Stat.GoodBadDaysData) -> CGFloat {
        let thirds = data.result.thirds
        var height = introHeight
        if !thirds.isComparable {
            height += messageHeight
        }
        if thirds.reference.isShown || thirds.compared.isShown {
            height += chartHeight + chartNotesHeight
        }
        if thirds.isComparable {
            height += sectionHeight + CGFloat(thirds.glucoseRows.count + 1) * rowHeight
        }
        return height
    }

    /// The factor sections that can print, in their order, each with its rows: a section with a row shown, or with a
    /// read that failed (its title and a note, no row). None unless the thirds are compared.
    static func factorSections(_ data: Stat.GoodBadDaysData) -> [(section: Section, rows: Int)] {
        guard data.result.thirds.isComparable else { return [] }
        return Section.allCases.compactMap { section in
            let rows = data.factors.filter { $0.id.section == section }
            let shown = rows.filter(\.isShown).count
            guard shown > 0 || rows.contains(where: \.unavailable) else { return nil }
            return (section, shown)
        }
    }

    /// A factor section's height: its title line and its rows.
    static func factorSectionHeight(rows: Int) -> CGFloat {
        factorSectionHeight + CGFloat(rows) * rowHeight
    }

    /// What every factors block starts with: the title and what a row's columns are.
    static var factorsHeadHeight: CGFloat { sectionHeight + factorIntroHeight }

    /// A factors block's height.
    static func factorsHeight(_ data: Stat.GoodBadDaysData, sections: [Section], isLast: Bool) -> CGFloat {
        let rows = Dictionary(uniqueKeysWithValues: factorSections(data).map { ($0.section, $0.rows) })
        return factorsHeadHeight + sections.reduce(0) { $0 + factorSectionHeight(rows: rows[$1] ?? 0) }
            + (isLast ? closingHeight : 0)
    }

    /// The height the two lists of days take, side by side.
    static func listsHeight(_ data: Stat.GoodBadDaysData) -> CGFloat {
        let thirds = data.result.thirds
        let rows = Swift.max(listRows(thirds.reference.days.count), listRows(thirds.compared.days.count))
        return sectionHeight + listHeaderHeight + CGFloat(rows) * dayHeight
    }

    static func height(_ block: Block, _ data: Stat.GoodBadDaysData) -> CGFloat {
        switch block {
        case .comparison: return comparisonHeight(data)
        case let .factors(sections, _, isLast): return factorsHeight(data, sections: sections, isLast: isLast)
        case .lists: return listsHeight(data)
        case .empty: return emptyHeight
        }
    }

    /// The height of a (portrait) page's content.
    static func available(_ paper: ReportPaper) -> CGFloat {
        paper.size.height - ReportStyle.margin * 2 - chrome
    }

    /// The blocks page by page, in the screen's order: the comparison, the factors, the days. Each goes under the one
    /// before it while it fits, else on the next page; the factors break between two sections, never inside one, and
    /// the part after a break starts with the title and the columns' line again.
    static func pages(_ data: Stat.GoodBadDaysData, paper: ReportPaper) -> [[Block]] {
        guard !data.isEmpty else { return [[.empty]] }
        let available = available(paper)
        var pages: [[Block]] = [[]]
        var used: CGFloat = 0
        func place(_ block: Block, _ height: CGFloat) {
            if used > 0, used + height > available {
                pages.append([])
                used = 0
            }
            pages[pages.count - 1].append(block)
            used += height
        }
        place(.comparison, comparisonHeight(data))

        let sections = factorSections(data)
        // the sections of the factors block being filled, on the last page
        var open: [Section] = []
        var isFirst = true
        for (index, item) in sections.enumerated() {
            let isLast = index == sections.count - 1
            let height = factorSectionHeight(rows: item.rows) + (isLast ? closingHeight : 0)
            if open.isEmpty {
                place(.factors(sections: [item.section], isFirst: isFirst, isLast: isLast), factorsHeadHeight + height)
                open = [item.section]
            } else if used + height > available {
                // the block ends here; the rest starts the next page, under the title again
                isFirst = false
                pages.append([.factors(sections: [item.section], isFirst: false, isLast: isLast)])
                used = factorsHeadHeight + height
                open = [item.section]
            } else {
                open.append(item.section)
                pages[pages.count - 1].removeLast()
                pages[pages.count - 1].append(.factors(sections: open, isFirst: isFirst, isLast: isLast))
                used += height
            }
        }
        place(.lists, listsHeight(data))
        return pages
    }

    static func pageCount(_ data: Stat.GoodBadDaysData, paper: ReportPaper) -> Int {
        pages(data, paper: paper).count
    }
}

extension Stat {
    /// A page of Good & bad days.
    struct ReportGoodBadDays: Equatable {
        typealias Block = ReportGoodBadDaysLayout.Block

        let header: ReportPageHeader
        /// the screen's model: the groups, their profiles and days, the rows
        let model: GoodBadDays
        /// what this page holds, top down
        let blocks: [Block]
        /// "Days are ranked by GRI, the Glycemia Risk Index: 0 is best, 100 worst."
        let griNote: String
        /// "Lines: each group's median. Bands: the middle half of its readings (25–75%). Medians differ most …": what
        /// the chart draws, where the medians differ most, and that the figures are provisional when a group has few days
        let chartNote: String
        /// "Range 70–180 mg/dL": the chart's in-range band
        let rangeLegend: String
        /// in place of everything: no day of the period was scored
        let emptyNote: String?

        var content: GoodBadDays.Content { model.content }

        /// nil without the part's result
        /// - Parameters:
        ///   - page: one of the part's (`index`, `units`)
        ///   - calendar: the days' (their names, the dates' time zone)
        @MainActor init?(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            guard let result = data.goodBadDays else { return nil }
            let settings = StatsSettings(report: page.units, hbA1cUnit: data.request.hbA1cUnit)
            let model = GoodBadDays(result, settings: settings, now: data.generatedAt, calendar: calendar)
            self.model = model
            let pages = ReportGoodBadDaysLayout.pages(result, paper: data.request.paper)
            blocks = pages.indices.contains(page.index) ? pages[page.index] : []
            griNote = GoodBadDays.griCaption
            emptyNote = result.isEmpty
                ? NSLocalizedString("No day in this period has enough CGM data to be scored: the days end yesterday", comment: "")
                : nil
            // on the first page, under the chart: a group of few days makes everything after it provisional
            chartNote = [
                NSLocalizedString(
                    "Lines: each group's median. Bands: the middle half of its readings (25–75%).",
                    comment: "PDF report, Good & bad days: what the chart draws"
                ),
                model.content.caption.map { $0 + "." },
                model.content.isLimited ? model.limitedNote : nil
            ]
            .compactMap { $0 }.joined(separator: " ")
            rangeLegend = String(
                format: NSLocalizedString("Range %@", comment: "PDF report, percentile chart legend: the in-range band"),
                StatsFormatting.inRangeLabel(bands: settings.bands, units: page.units)
            )
            let days = result.period.calendarDayCount ?? 0
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(result.result.window, calendar: calendar),
                days: String(
                    format: NSLocalizedString(
                        "%1$d complete days to yesterday · %2$d with enough CGM data",
                        comment: "PDF report, Good & bad days header: the period's days, the days scored"
                    ),
                    days,
                    result.result.scored
                )
            )
        }
    }
}
