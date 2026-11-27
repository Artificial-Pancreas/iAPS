import CoreGraphics
import Foundation

// The Patches and CGM parts of a report: what the Patches and CGM topics show for the period, without anything that
// depends on a selection (a patch's detail screen, the CGM's smoothing analysis are not printed). The numbers and
// the strings are the topics' own display models' (`Stat.Patches`, `Stat.CGMReport`), built for the page's unit.

/// What the Patches topic's read takes besides the period and the bands, as the Statistics screen has it when the
/// report is asked for.
struct ReportPatchesInput: Sendable, Equatable {
    /// the current `allowOneMinuteLoop` (a session's loop numbers count its slots by it)
    var allowOneMinuteLoop = false
    /// the plugin delivering now: its open session is the one in use
    var deliveringPlugin: String?
    /// the pump's plugin: the topic's naming (patches, pods, sites)
    var currentPlugin: String?
}

/// How the Patches part is laid out: the numbers and the wear days, then the list, a row a patch, on as many pages as
/// it takes.
enum ReportPatchesLayout {
    typealias Tables = ReportTablesLayout

    /// the count's line and the tiles
    static let summaryHeight: CGFloat = 78
    /// a note under a table (two lines)
    static let noteHeight: CGFloat = 24
    /// the note about the period under the numbers (three lines)
    static let periodNoteHeight: CGFloat = 32
    /// a row of the list
    static let rowHeight: CGFloat = 13

    /// What the first page holds above the list: the numbers, the note about the period and the wear days' table.
    static func topHeight(wearDays: Int, hasPeriodNote: Bool) -> CGFloat {
        summaryHeight + (hasPeriodNote ? periodNoteHeight : 0)
            + Tables.sectionHeight + Tables.headerHeight + CGFloat(wearDays) * Tables.rowHeight + noteHeight
    }

    /// The list's rows a page holds.
    static func rowsPerPage(_ paper: ReportPaper, top: CGFloat) -> Int {
        let height = Tables.available(paper) - top - Tables.sectionHeight - Tables.headerHeight
        return Swift.max(Int(height / rowHeight), 3)
    }

    /// The list's rows of each page (there is always one page).
    static func ranges(rows: Int, wearDays: Int, hasPeriodNote: Bool, paper: ReportPaper) -> [Range<Int>] {
        let count = Swift.max(rows, 0)
        let first = Swift.min(count, rowsPerPage(paper, top: topHeight(wearDays: wearDays, hasPeriodNote: hasPeriodNote)))
        var ranges = [0 ..< first]
        let perPage = rowsPerPage(paper, top: 0)
        var lower = first
        while lower < count {
            let upper = Swift.min(lower + perPage, count)
            ranges.append(lower ..< upper)
            lower = upper
        }
        return ranges
    }

    /// The wear days the topic lists for the sessions: the longest one's, as `Stat.Patches.rangeRows` (at most the
    /// days it shows); the plan counts every started day of the longest wear.
    static func wearDays(_ result: Stat.PatchesResult) -> Int {
        let longest = result.sessions.map(\.session.wear).max() ?? 0
        return Swift.min(Swift.max(Int((longest / .days(1)).rounded(.up)), 1), maximumWearDays)
    }

    /// more wear days than this are not listed (a tube pump's site worn for weeks)
    static let maximumWearDays = 14

    static func pageCount(_ result: Stat.PatchesResult, paper: ReportPaper) -> Int {
        guard !result.isEmpty else { return 1 }
        return ranges(
            rows: result.sessions.count,
            wearDays: wearDays(result),
            hasPeriodNote: true,
            paper: paper
        ).count
    }
}

extension Stat {
    // MARK: - Patches

    /// A page of the Patches part.
    struct ReportPatches: Equatable {
        /// A row of "Patch by patch".
        struct Row: Equatable, Identifiable {
            let id: String
            /// "24 – 27 Oct", "Since 27 Oct"
            let span: String
            /// "3 d 7 h · 41.2 U per day"
            let detail: String
            /// "74%", "–"
            let inRange: String
        }

        let header: ReportPageHeader
        /// in place of everything: no patch in the period, or the pump data couldn't be read
        let emptyNote: String?
        /// the first page: the numbers and the wear days above the list
        let isFirst: Bool
        /// "12 patches"
        let count: String
        /// "The first 14 wear days are listed."; nil when every wear day is
        let wearDaysCut: String?
        /// "1 in use · 11 ended"
        let countDetail: String
        /// Wear time, Per patch, Insulin, In range
        let figures: [ReportFigure]
        /// "Each one overlapping the period counts whole: …"
        let periodNote: String?
        /// "By wear day": a row a day of wear, the time in range, the mean and the insulin per 24 h
        let wearDays: ReportTable
        let wearDayNote: String
        /// "Patch by patch", "Pod by pod"
        let listTitle: String
        /// this page's
        let rows: [Row]

        /// "No patches in this period", by the topic's naming.
        static func emptyText(_ topic: PatchTopic?) -> String {
            switch topic?.kind {
            case .pod: return NSLocalizedString("No pods in this period", comment: "")
            case .site: return NSLocalizedString("No sites in this period", comment: "")
            case nil,
                 .patch: return NSLocalizedString("No patches in this period", comment: "")
            }
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`, `units`)
        ///   - calendar: the header's dates' time zone
        @MainActor init(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            typealias Layout = ReportPatchesLayout
            let read = data.patches
            let result = read?.value
            let model = result.map { Patches($0, settings: StatsSettings(report: page.units, hbA1cUnit: data.request.hbA1cUnit)) }
            isFirst = page.index == 0

            let days = result.map { ReportData.days(of: $0.window, calendar: calendar) } ?? data.days(calendar: calendar)
            count = model.map { $0.count + " " + $0.countUnit } ?? ""
            countDetail = model?.countDetail ?? ""
            // the count is the page's first line: not said again beside the dates
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(days.first, days.last, calendar: calendar),
                days: ""
            )
            if read == .failed || read == nil {
                emptyNote = NSLocalizedString("The pump data couldn't be read.", comment: "")
            } else if result?.isEmpty ?? true {
                emptyNote = Self.emptyText(result?.topic)
            } else {
                emptyNote = nil
            }
            figures = (model?.tiles ?? []).map { ReportFigure(id: $0.id, title: $0.title, value: $0.value, unit: $0.unit) }
            // on paper nothing is marked: the screen's sentence about the marked ones without the mark
            periodNote = model?.periodNote?.replacingOccurrences(
                of: NSLocalizedString(
                    "Other marked ones count from where their pump data starts: recorded late, or their activation isn't known.",
                    comment: "Statistics Patches: partial ones other than those activated before the recording"
                ),
                with: NSLocalizedString(
                    "Others count from where their pump data starts: recorded late, or their activation isn't known.",
                    comment: "PDF report, Patches: partial ones other than those activated before the recording"
                )
            )

            // a wear day's rows of the two cards, side by side
            let ranges = model?.rangeRows ?? []
            let insulin = Dictionary(uniqueKeysWithValues: (model?.insulinRows ?? []).map { ($0.id, $0.value) })
            // as many as the plan counted: the list under them starts where it expects
            let shown = ranges.prefix(result.map { Layout.wearDays($0) } ?? 0)
            wearDays = ReportTable(
                name: NSLocalizedString("Wear day", comment: "PDF report, Patches: the day of wear's column"),
                columns: [
                    ReportTable.Column(
                        id: 0,
                        title: model?.naming.title ?? "",
                        subtitle: NSLocalizedString("counted", comment: "PDF report, Patches: the patches a wear day pools")
                    ),
                    ReportTable.Column(
                        id: 1,
                        title: StatsFormatting.name(.inRange),
                        subtitle: StatsFormatting.label(
                            .inRange,
                            bands: ReportBuilder.standardBands(page.units),
                            units: page.units
                        ) ?? ""
                    ),
                    ReportTable.Column(
                        id: 2,
                        title: NSLocalizedString("Mean", comment: "Statistics, mean glucose"),
                        subtitle: StatsFormatting.unit(page.units)
                    ),
                    ReportTable.Column(
                        id: 3,
                        title: NSLocalizedString("Insulin", comment: "Statistics topic"),
                        subtitle: NSLocalizedString("U per 24 h", comment: "PDF report, Patches: a wear day's insulin")
                    )
                ],
                rows: shown.map { row in
                    ReportTable.Row(
                        id: row.id,
                        title: row.name,
                        cells: [row.detail, row.inRange, row.mean, insulin[row.id] ?? "–"]
                    )
                }
            )
            wearDayNote = model?.wearDayNote ?? ""
            wearDaysCut = ranges.count > shown.count
                ? String(
                    format: NSLocalizedString(
                        "The first %d wear days are listed.",
                        comment: "PDF report, Patches: the wear days' table is cut"
                    ),
                    shown.count
                )
                : nil
            listTitle = model?.naming.byOne ?? ""

            let all = (model?.rows ?? []).map { Row(id: $0.id, span: $0.span, detail: $0.detail, inRange: $0.inRange) }
            let pages = Layout.ranges(
                rows: all.count,
                wearDays: result.map { Layout.wearDays($0) } ?? 0,
                hasPeriodNote: true,
                paper: data.request.paper
            )
            if pages.indices.contains(page.index) {
                rows = Array(all[pages[page.index].clamped(to: 0 ..< all.count)])
            } else {
                rows = []
            }
        }
    }

    // MARK: - CGM

    /// A page of the CGM part: a CGM's Overview (its readings, the rate of change, the CGMs side by side), or its
    /// Sensors (the sensors and the noise by sensor day). The smoothing analysis is not printed.
    struct ReportCGM: Equatable {
        enum Kind: Equatable {
            case overview
            case sensors
        }

        /// A sensor of the list.
        struct Sensor: Equatable, Identifiable {
            let id: UUID
            /// "Dexcom G7", "Dexcom G7 · in use · From Nightscout"
            let title: String
            /// "Sun 11 Oct, 23:06 – Mon 26 Oct, 10:37 · 14 d 13 h"
            let span: String
            /// "97%": its length of its expected life; "–" when the life isn't known
            let life: String
            /// "noise 0.18 mmol/L", "–"
            let noise: String
        }

        /// the CGMs a report prints at most: the page estimate counts on it
        static let maximumCGMs = 3
        /// a sensor's row, the list's title and column titles, and what the noise by sensor day takes under the list
        static let sensorRowHeight: CGFloat = 13
        static let sensorsChrome: CGFloat = 60
        static let noiseHeight: CGFloat = 206

        /// The sensors a page lists, by the paper's height: more than these are counted in a line under them.
        static func maximumSensors(_ paper: ReportPaper, hasNoise: Bool) -> Int {
            let height = ReportTablesLayout.available(paper) - sensorsChrome - (hasNoise ? noiseHeight : 0)
            return Swift.max(Int(height / sensorRowHeight), 4)
        }

        /// the pages a CGM takes: its Overview and its Sensors
        static let pagesPerCGM = 2

        let header: ReportPageHeader
        /// in place of everything: no reading in the period, or the readings couldn't be read
        let emptyNote: String?
        let kind: Kind
        /// the topic's own model for the CGM printed, in the page's unit; nil without readings
        let report: CGMReport?
        /// the Sensors page's list
        let sensors: [Sensor]
        /// "and 3 more": the sensors the page has no room for; nil when all are listed
        let moreSensors: String?
        /// "Not printed: Dexcom G6, Libre 2": the CGMs of the period a report leaves out, on its first page; nil without
        let omittedNote: String?
        /// what Unknown is, when it is the CGM printed: the readings no recorded session names
        let unknownNote: String?
        /// the noise by sensor day, a bar a day; nil without any
        let noiseBars: ReportBars?
        /// "Day 1 is the first 24 hours after a sensor start; under each day, the sensors with readings on it."
        let noiseNote: String

        /// The CGMs a report prints, in the topic's order: every named one; Unknown (the readings no session names)
        /// only when it is alone. With more than `maximumCGMs`: the one the screen opens on (`CGMResult.defaultPick`)
        /// and the others with the most readings. A view's own export: the one on screen.
        static func picks(_ result: CGMResult, shown: CGMPick?) -> [CGMPick] {
            if let shown, result.cgms.contains(where: { $0.pick == shown }) { return [shown] }
            let named = result.cgms.map(\.pick).filter { $0 != .unknown }
            guard named.count > maximumCGMs else { return named.isEmpty ? result.cgms.map(\.pick) : named }
            var kept: Set<CGMPick> = []
            if let first = result.defaultPick, named.contains(first) {
                kept.insert(first)
            }
            let byReadings = named.enumerated().sorted { a, b in
                let ra = result.picks[a.element]?.stats.readings ?? 0
                let rb = result.picks[b.element]?.stats.readings ?? 0
                return ra == rb ? a.offset < b.offset : ra > rb
            }
            for item in byReadings where kept.count < maximumCGMs {
                kept.insert(item.element)
            }
            return named.filter { kept.contains($0) }
        }

        /// The named CGMs of the period a report doesn't print (`picks`), in the topic's order.
        static func omitted(_ result: CGMResult, shown: CGMPick?) -> [String] {
            guard shown == nil || !result.cgms.contains(where: { $0.pick == shown }) else { return [] }
            let printed = Set(picks(result, shown: shown))
            return result.cgms.filter { $0.pick != .unknown && !printed.contains($0.pick) }.map(\.name)
        }

        static func pageCount(_ result: CGMResult, shown: CGMPick?) -> Int {
            Swift.max(picks(result, shown: shown).count * pagesPerCGM, 1)
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`: a CGM's Overview, then its Sensors; `units`)
        ///   - calendar: the header's dates' time zone
        @MainActor init(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            let read = data.cgm
            let result = read?.value
            let picks = result.map { Self.picks($0, shown: data.request.cgmPick) } ?? []
            let index = page.index / Self.pagesPerCGM
            kind = page.index % Self.pagesPerCGM == 0 ? .overview : .sensors
            let pick = picks.indices.contains(index) ? picks[index] : nil
            // the smoothing setting only feeds the Smoothing view's facts, which aren't printed
            let report = result.flatMap { result in
                pick.map { CGMReport(result, pick: $0, units: page.units, smoothing: .none) }
            }
            self.report = report

            let days = result.map { ReportData.days(of: $0.window, calendar: calendar) } ?? data.days(calendar: calendar)
            let name = result?.cgms.first { $0.pick == pick }?.name ?? ""
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(days.first, days.last, calendar: calendar),
                days: name
            )
            if read == .failed || read == nil {
                emptyNote = NSLocalizedString("The CGM readings couldn't be read.", comment: "")
            } else if result?.isEmpty ?? true || report == nil {
                emptyNote = NSLocalizedString("No CGM data in this period", comment: "")
            } else {
                emptyNote = nil
            }

            let omitted = result.map { Self.omitted($0, shown: data.request.cgmPick) } ?? []
            omittedNote = page.index == 0 && omitted.isNotEmpty
                ? String(
                    format: NSLocalizedString("Not printed: %@", comment: "PDF report, CGM: the CGMs of the period left out"),
                    omitted.joined(separator: ", ")
                )
                : nil
            unknownNote = pick == .unknown ? report?.unknown?.body : nil

            let rows = report?.sensors.rows ?? []
            let maximum = Self.maximumSensors(data.request.paper, hasNoise: (report?.sensors.noiseDays ?? []).isNotEmpty)
            sensors = rows.prefix(maximum).map { row in
                // the screen's tags, as words
                let tags = [
                    row.isInUse ? NSLocalizedString("in use", comment: "PDF report, CGM: the sensor in use") : nil,
                    row.isEntered
                        ? NSLocalizedString("Entered by you", comment: "Statistics CGM Sensors: a sensor the user entered")
                        : nil,
                    row.isBackfilled
                        ? NSLocalizedString("From Nightscout", comment: "Statistics CGM Sensors: a sensor named from Nightscout")
                        : nil
                ]
                return Sensor(
                    id: row.id,
                    title: ([row.title] + tags.compactMap { $0 }).joined(separator: " · "),
                    span: row.span,
                    life: row.bar.map { StatsFormatting.percent(fraction: $0) } ?? "–",
                    noise: row.noise ?? "–"
                )
            }
            moreSensors = rows.count > maximum
                ? String(
                    format: NSLocalizedString("and %d more", comment: "PDF report, CGM: the sensors a page has no room for"),
                    rows.count - maximum
                )
                : nil

            let noise = report?.sensors.noiseDays ?? []
            if let sensors = report?.sensors, noise.isNotEmpty {
                noiseBars = ReportBars(
                    bars: noise.enumerated().map { index, day in ReportBars.Bar(id: index, values: [day.value]) },
                    styles: [StatsBarStyle(fill: ReportStyle.accent)],
                    levels: sensors.noiseLevels,
                    levelLabels: sensors.noiseLevelLabels,
                    average: nil,
                    ticks: noise.enumerated().map { index, day in
                        ReportBars.Tick(
                            id: index,
                            label: String(
                                format: NSLocalizedString(
                                    "%1$d (%2$d)",
                                    comment: "PDF report, CGM: a sensor day and its sensors"
                                ),
                                day.day,
                                day.sensors
                            )
                        )
                    },
                    legend: [
                        ReportBars.LegendItem(
                            id: 0,
                            key: .swatch(StatsBarStyle(fill: ReportStyle.accent)),
                            title: String(
                                format: NSLocalizedString(
                                    "Noise, %@, by sensor day (the sensors with readings on it)",
                                    comment: "PDF report, CGM: the noise chart's key (\"mmol/L\")"
                                ),
                                StatsFormatting.unit(page.units)
                            )
                        )
                    ]
                )
            } else {
                noiseBars = nil
            }
            noiseNote = NSLocalizedString(
                "Day 1 is the first 24 hours after a sensor start; under each day, the sensors with readings on it.",
                comment: "PDF report, CGM Sensors: what the noise by sensor day is"
            )
        }
    }
}
