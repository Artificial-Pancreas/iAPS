import SwiftUI

extension Stat {
    /// The Patches topic, formatted for display. The sessions and their numbers come ready from the provider
    /// (`PatchesResult`, `PatchStatsEngine`); only strings and the wear bars are built here, a session's detail when it
    /// is pushed (`detail(at:)`).
    struct Patches: Equatable {
        /// The words that follow the naming: patches, Omnipod's pods, or a tube pump's sites.
        struct Naming: Equatable {
            /// "Patches", "Pods"
            let title: String
            /// "patch", "pod": the count's unit for one
            let one: String
            /// "patches", "pods"
            let many: String
            /// "Patch by patch"
            let byOne: String
            /// "Patch in use"
            let inUse: String
            /// "No patch in use"
            let noneInUse: String
            /// "Against previous patches"
            let againstPrevious: String
            /// "Per patch": the insulin of each
            let perOne: String
            /// "This patch": Today's column
            let thisOne: String
            /// "this patch": the detail's by-wear-day card
            let thisOneLowercased: String
            /// "+ %@ pen, not from the patch": External Insulin in its time
            let externalFormat: String
            /// "No earlier patches to compare yet": Today with none of its plugin before it
            let noEarlier: String
            /// "No earlier patch reached this age yet": Today with some before it, none worn this long (its grace)
            let noneReached: String

            init(_ topic: PatchTopic?) {
                switch topic?.kind {
                case .pod:
                    title = NSLocalizedString("Pods", comment: "Statistics topic: Omnipod pods")
                    one = NSLocalizedString("pod", comment: "Statistics Patches: the unit of a count of one pod")
                    many = NSLocalizedString("pods", comment: "Statistics Patches: the unit of a count of pods")
                    byOne = NSLocalizedString("Pod by pod", comment: "Statistics Patches: the list of the pods")
                    inUse = NSLocalizedString("Pod in use", comment: "Statistics Patches Today: the pod delivering now")
                    noneInUse = NSLocalizedString("No pod in use", comment: "Statistics Patches Today: no pod delivering")
                    againstPrevious = NSLocalizedString(
                        "Against previous pods",
                        comment: "Statistics Patches Today: the pod in use against the ones before it"
                    )
                    perOne = NSLocalizedString("Per pod", comment: "Statistics Patches: the insulin of each pod")
                    thisOne = NSLocalizedString("This pod", comment: "Statistics Patches Today: the pod in use's column")
                    thisOneLowercased = NSLocalizedString("this pod", comment: "Statistics Patches detail: the pod's own")
                    noneReached = NSLocalizedString(
                        "No earlier pod reached this age yet",
                        comment: "Statistics Patches Today: pods before the one in use, none worn as long"
                    )
                    noEarlier = NSLocalizedString(
                        "No earlier pods to compare yet",
                        comment: "Statistics Patches Today: no pod before the one in use reached its age"
                    )
                    externalFormat = NSLocalizedString(
                        "+ %@ pen, not from the pod",
                        comment: "Statistics Patches detail: External Insulin in its time (\"2.0 U\")"
                    )
                case .site:
                    title = NSLocalizedString("Sites", comment: "Statistics topic: a tube pump's infusion sites")
                    one = NSLocalizedString("site", comment: "Statistics Patches: the unit of a count of one site")
                    many = NSLocalizedString("sites", comment: "Statistics Patches: the unit of a count of sites")
                    byOne = NSLocalizedString("Site by site", comment: "Statistics Patches: the list of the sites")
                    inUse = NSLocalizedString("Site in use", comment: "Statistics Patches Today: the site delivering now")
                    noneInUse = NSLocalizedString("No site in use", comment: "Statistics Patches Today: no site delivering")
                    againstPrevious = NSLocalizedString(
                        "Against previous sites",
                        comment: "Statistics Patches Today: the site in use against the ones before it"
                    )
                    perOne = NSLocalizedString("Per site", comment: "Statistics Patches: the insulin of each site")
                    thisOne = NSLocalizedString("This site", comment: "Statistics Patches Today: the site in use's column")
                    thisOneLowercased = NSLocalizedString("this site", comment: "Statistics Patches detail: the site's own")
                    noneReached = NSLocalizedString(
                        "No earlier site reached this age yet",
                        comment: "Statistics Patches Today: sites before the one in use, none worn as long"
                    )
                    noEarlier = NSLocalizedString(
                        "No earlier sites to compare yet",
                        comment: "Statistics Patches Today: no site before the one in use reached its age"
                    )
                    externalFormat = NSLocalizedString(
                        "+ %@ pen, not from the pump",
                        comment: "Statistics Patches detail: External Insulin in a site's time (\"2.0 U\")"
                    )
                case nil,
                     .patch:
                    title = NSLocalizedString("Patches", comment: "Statistics topic: the pump's patches")
                    one = NSLocalizedString("patch", comment: "Statistics Patches: the unit of a count of one patch")
                    many = NSLocalizedString("patches", comment: "Statistics Patches: the unit of a count of patches")
                    byOne = NSLocalizedString("Patch by patch", comment: "Statistics Patches: the list of the patches")
                    inUse = NSLocalizedString("Patch in use", comment: "Statistics Patches Today: the patch delivering now")
                    noneInUse = NSLocalizedString("No patch in use", comment: "Statistics Patches Today: no patch delivering")
                    againstPrevious = NSLocalizedString(
                        "Against previous patches",
                        comment: "Statistics Patches Today: the patch in use against the ones before it"
                    )
                    perOne = NSLocalizedString("Per patch", comment: "Statistics Patches: the insulin of each patch")
                    thisOne = NSLocalizedString("This patch", comment: "Statistics Patches Today: the patch in use's column")
                    thisOneLowercased = NSLocalizedString(
                        "this patch",
                        comment: "Statistics Patches detail: the patch's own"
                    )
                    noneReached = NSLocalizedString(
                        "No earlier patch reached this age yet",
                        comment: "Statistics Patches Today: patches before the one in use, none worn as long"
                    )
                    noEarlier = NSLocalizedString(
                        "No earlier patches to compare yet",
                        comment: "Statistics Patches Today: no patch before the one in use reached its age"
                    )
                    externalFormat = NSLocalizedString(
                        "+ %@ pen, not from the patch",
                        comment: "Statistics Patches detail: External Insulin in its time (\"2.0 U\")"
                    )
                }
            }

            /// "1 patch", "12 patches"
            func count(_ count: Int) -> String {
                "\(count) " + (count == 1 ? one : many)
            }
        }

        /// A number with its title and unit (`StatTile`, compact).
        typealias Tile = StatsTileItem

        /// A wear day's time in range over the sessions.
        struct RangeRow: Equatable, Identifiable {
            let id: Int
            /// "Day 1"
            let name: String
            /// "12 patches"
            let detail: String
            let segments: [BandSegment]
            /// "74%", "–"
            let inRange: String
            /// "6.3", "–"
            let mean: String
        }

        /// A wear day's insulin per 24 h over the sessions.
        struct InsulinRow: Equatable, Identifiable {
            let id: Int
            let name: String
            let segments: [StatsSplitBar.Segment]
            /// the bar's length, of the card's scale (0...1)
            let width: Double
            /// "41.2", "–"
            let value: String
        }

        /// A row of "Patch by patch".
        struct ListRow: Equatable, Identifiable {
            let id: String
            /// in `stats`
            let index: Int
            /// "24 – 27 Oct", "Since 27 Oct"
            let span: String
            let isInUse: Bool
            /// activated before the recording began: the limited mark
            let isPartial: Bool
            /// "3 d 7 h · 41.2 U per day", "2 d 18 h so far · …", "… · recorded from Mon 26 Oct"
            let detail: String
            /// "74%", "–"
            let inRange: String
            let bar: PatchWearBar.Plot
        }

        /// A row of name and value (the detail's facts).
        struct Fact: Equatable, Identifiable {
            let id: Int
            let name: String
            let value: String
        }

        /// Basal, SMB or bolus of a session: U and % of its total.
        typealias PartRow = InsulinPartRow

        /// A wear day of one session (the detail's), or of the patch in use against the usual (Today's).
        struct DayRow: Equatable, Identifiable {
            let id: Int
            /// "Day 2", "Day 3 so far"
            let name: String
            let inRange: String
            /// the detail: the mean; Today: the usual in range
            let second: String
            let perDay: String
            /// Today: the usual per 24 h; nil in the detail
            var usualPerDay: String?
        }

        /// A session, pushed from its row: its wear, facts, insulin, glucose, wear days and loop.
        struct Detail: Equatable {
            /// "Tue 27 Oct – Fri 30 Oct", "Since Tue 27 Oct"
            let title: String
            /// "Medtrum · 3 d 7 h 15 m", "Medtrum · in use"
            let subtitle: String
            /// the row's span: the screen's title
            let navigationTitle: String
            let bar: PatchWearBar.Plot
            let facts: [Fact]
            /// "158.3", "–"
            let total: String
            let soFar: Bool
            /// "41.2 U per day"
            let perDay: String
            /// External Insulin in its time: "+ 2.0 U pen, not from the patch"; nil without
            let external: String?
            let split: [StatsSplitBar.Segment]
            let parts: [PartRow]
            /// "CGM data 97% of the time"
            let cgm: String
            let inRange: String
            /// "4.0–9.0 mmol/L"
            let rangeText: String
            let bands: [BandSegment]
            let glucoseTiles: [Tile]
            let days: [DayRow]
            let loopTiles: [Tile]
        }

        /// The Today period: the patch in use against the ones before it at the same age.
        struct Today: Equatable {
            /// the patch in use
            struct InUse: Equatable {
                /// "Medtrum"
                let plugin: String
                /// "Day 3"; nil when its activation isn't known (its age isn't)
                let dayName: String?
                /// "2 d 18 h 55 m old"; its activation unknown, "recorded for 1 d 4 h"
                let age: String
                /// "since Tue 27 Oct, 19:40"
                let since: String
                let bar: PatchWearBar.Plot
                /// Expires, Grace ends (Medtrum, Omnipod)
                let tiles: [Tile]
                /// "by 2 d 19 h · 10 before"; nil without any before it at its age
                let usualTitle: String?
                /// Insulin, In range, Mean, Negative IOB per day: this one, the usual ("–" without any before it at its age)
                let rows: [Fact]
                let usual: [String]
                let days: [DayRow]
                /// what the usual is; without any before it at its age, "No earlier patch reached this age yet" or (none
                /// of its plugin before it at all) "No earlier patches to compare yet"; not compared, why
                let note: String
                /// compared with the ones before it (`PatchSession.isComparable`): the Usual column and the wear days;
                /// otherwise its own rows alone (`usual` empty, no `days`)
                var compares = true
            }

            /// nil: "No patch in use"
            let inUse: InUse?
        }

        /// the period shown
        let shown: StatsPeriod
        let naming: Naming
        /// the Today period's view (`shown` Today); nil for 7–90 d
        let today: Today?
        /// "1 Oct – 30 Oct"
        let dateRange: String
        /// "12"
        let count: String
        /// "patches"
        let countUnit: String
        /// "1 in use · 11 ended"
        let countDetail: String
        /// Wear time, Per patch, Insulin, In range
        let tiles: [Tile]
        /// "Each one overlapping the period counts whole: the oldest here began Mon 28 Sep."
        let periodNote: String?
        /// "12 patches"
        let wearDayDetail: String
        /// "Mean, mmol/L"
        let meanTitle: String
        let rangeRows: [RangeRow]
        let insulinRows: [InsulinRow]
        let wearDayNote: String
        let rows: [ListRow]
        let barNote: String
        /// newest first: the rows' (the detail's)
        let stats: [PatchStats]
        let settings: StatsSettings
        /// the wear bars' scale, h
        let scale: Double
        let asOf: Date
        /// sessions of more than one kind (or of another than the topic's): where the unit's name is shown, each says its
        /// kind ("Omnipod pod", "Dana site")
        let namesKinds: Bool

        @MainActor init(_ result: PatchesResult, settings: StatsSettings) {
            typealias Format = StatsFormatting
            let naming = Naming(result.topic)
            self.naming = naming
            self.settings = settings
            shown = result.period
            asOf = result.asOf
            stats = result.sessions
            let plugins = (result.sessions.map(\.session) + [result.inUse?.session].compactMap { $0 }).map(\.plugin)
            let scale = Self.barScale(longestWear: result.scaleWear, plugins: plugins)
            self.scale = scale
            let kinds = (result.sessions + result.previous + [result.inUse].compactMap { $0 }).map(\.session.kind)
            let namesKinds = Set(kinds + [result.topic?.kind].compactMap { $0 }).count > 1
            self.namesKinds = namesKinds
            today = result.period == .today
                ? Self.today(result, naming: naming, settings: settings, scale: scale, namesKinds: namesKinds)
                : nil
            dateRange = Format.dateRange(result.window, period: result.period, now: result.asOf)

            let sessions = result.sessions
            count = "\(sessions.count)"
            countUnit = sessions.count == 1 ? naming.one : naming.many
            let ended = sessions.filter { !$0.isInUse }
            countDetail = Self.countDetail(sessions, ended: ended)

            tiles = Self.tiles(sessions, ended: ended, naming: naming, settings: settings)

            // the notes
            // the recording's start: the oldest data of every session in the result; activated before it is that
            // session's own partial reason, the others (recorded late, a start not known) are said per session
            let recordingStart = result.recordingStart
            periodNote = Self.periodNote(sessions, recordingStart: recordingStart)

            // by wear day
            let wearDays = PatchStatsEngine.byWearDay(sessions)
            wearDayDetail = naming.count(sessions.filter(\.session.isWearCounted).count)
            meanTitle = String(
                format: NSLocalizedString("Mean, %@", comment: "Statistics Patches: the mean glucose's header, its unit"),
                Format.unit(settings.units)
            )
            rangeRows = Self.rangeRows(wearDays, naming: naming, settings: settings)
            insulinRows = Self.insulinRows(wearDays)
            wearDayNote = NSLocalizedString(
                "Day 1 is the first 24 hours from activation. Each row pools the time in that day; the one in use counts in the days it has reached.",
                comment: "Statistics Patches by wear day: what a row is"
            )

            // one by one
            rows = sessions.enumerated().map { index, stats in
                Self.listRow(stats, index: index, scale: scale)
            }
            barNote = Self.barNote(sessions, plugins: plugins, recordingStart: recordingStart)
        }

        // MARK: - The init's parts

        /// "1 in use · 11 ended", "12 ended"
        private static func countDetail(_ sessions: [PatchStats], ended: [PatchStats]) -> String {
            let endedText = String(
                format: NSLocalizedString("%d ended", comment: "Statistics Patches: the ones that ended"),
                ended.count
            )
            return sessions.contains(where: \.isInUse)
                ? String(
                    format: NSLocalizedString(
                        "1 in use · %@",
                        comment: "Statistics Patches: the one in use and the ones ended (\"11 ended\")"
                    ),
                    endedText
                )
                : endedText
        }

        /// Wear time, Per patch, Insulin, In range.
        @MainActor private static func tiles(
            _ sessions: [PatchStats],
            ended: [PatchStats],
            naming: Naming,
            settings: StatsSettings
        ) -> [Tile] {
            typealias Format = StatsFormatting
            // the tiles: the wear of those whose wear counts (a known activation; no site of months)
            let wears = ended.filter(\.session.isWearCounted).map(\.session.wear)
            let meanWear = wears.isEmpty ? nil : wears.reduce(0, +) / Double(wears.count)
            let wearUnit: String
            if let shortest = wears.min(), wears.count > 1 {
                wearUnit = String(
                    format: NSLocalizedString(
                        "mean · shortest %@",
                        comment: "Statistics Patches: the wear time's mean, the shortest (\"1 d 17 h\")"
                    ),
                    Self.hours(shortest)
                )
            } else {
                wearUnit = wears.isEmpty
                    ? NSLocalizedString("none ended yet", comment: "Statistics Patches: no wear time yet")
                    : NSLocalizedString("1 ended", comment: "Statistics Patches: the wear time of the only one ended")
            }
            // the insulin of each: the ended ones recorded whole (not partial)
            let totals = ended.filter { !$0.session.isPartial }.map(\.whole.total)
            let pooled = PatchNumbers.pooled(sessions.map(\.whole))
            return [
                Tile(
                    id: 0,
                    title: NSLocalizedString("Wear time", comment: "Statistics Patches: the time from activation to the end"),
                    value: meanWear.map { Self.hours($0) } ?? "–",
                    unit: wearUnit
                ),
                Tile(
                    id: 1,
                    title: naming.perOne,
                    value: totals.isEmpty ? "–" : StatsAmount.number(totals.reduce(0, +) / Double(totals.count), digits: 0),
                    unit: totals.max().map { most in
                        String(
                            format: NSLocalizedString(
                                "U · most %@ U",
                                comment: "Statistics Patches: the insulin of each, the most (\"184\")"
                            ),
                            StatsAmount.number(most, digits: 0)
                        )
                    } ?? NSLocalizedString(
                        "U · none recorded whole",
                        comment: "Statistics Patches: no ended one recorded from its activation"
                    )
                ),
                Tile(
                    id: 2,
                    title: NSLocalizedString("Insulin", comment: "Statistics topic"),
                    value: perDayText(pooled),
                    unit: NSLocalizedString("U per day", comment: "Statistics Insulin: the unit of a daily amount")
                ),
                Tile(
                    id: 3,
                    title: NSLocalizedString("In range", comment: "Statistics glucose band"),
                    value: inRangeText(pooled),
                    unit: pooled.mean.map { mean in
                        String(
                            format: NSLocalizedString(
                                "%1$@ %2$@ mean",
                                comment: "Statistics Patches: the mean glucose and its unit (\"6.3 mmol/L mean\")"
                            ),
                            Format.glucose(mean, units: settings.units),
                            Format.unit(settings.units)
                        )
                    }
                )
            ]
        }

        /// The sessions picked (the oldest one's activation), and why some are partial; nil without either.
        @MainActor private static func periodNote(_ sessions: [PatchStats], recordingStart: Date?) -> String? {
            let oldest = sessions.last.map { session in
                String(
                    format: NSLocalizedString(
                        "Each one overlapping the period counts whole: the oldest here began %@.",
                        comment: "Statistics Patches: the sessions picked, the oldest one's activation day (\"Mon 28 Sep\")"
                    ),
                    Trace.dayTitle(session.session.activation)
                )
            }
            let beforeRecording = sessions.first { stats in
                Self.partialReason(stats.session, recordingStart: recordingStart) == .beforeRecording
            }
            .map { stats in
                String(
                    format: NSLocalizedString(
                        "The pump data is recorded since %@; one activated before has its numbers from then on.",
                        comment: "Statistics Patches: the recording's start (\"Mon 26 Oct, 09:00\")"
                    ),
                    Self.dayAndTime(stats.session.dataStart)
                )
            }
            let laterPartial = sessions.contains { stats in
                let reason = Self.partialReason(stats.session, recordingStart: recordingStart)
                return reason == .recordedLate || reason == .startUnknown
            }
                ? NSLocalizedString(
                    "Other marked ones count from where their pump data starts: recorded late, or their activation isn't known.",
                    comment: "Statistics Patches: partial ones other than those activated before the recording"
                )
                : nil
            return [oldest, beforeRecording, laterPartial].compactMap { $0 }.joined(separator: " ").nonEmpty
        }

        /// By wear day: the bands and the mean of each.
        @MainActor private static func rangeRows(
            _ wearDays: [PatchWearDay],
            naming: Naming,
            settings: StatsSettings
        ) -> [RangeRow] {
            typealias Format = StatsFormatting
            return wearDays.map { day in
                let numbers = day.numbers
                let name = Self.dayName(day.index)
                let detail = naming.count(day.sessions)
                let inRange = inRangeText(numbers)
                let mean = numbers.mean.map { Format.glucose($0, units: settings.units) } ?? "–"
                return RangeRow(
                    id: day.index,
                    name: name,
                    detail: detail,
                    segments: numbers.bandShares.barSegments(GlucoseBand.allCases),
                    inRange: inRange,
                    mean: mean
                )
            }
        }

        /// By wear day: the insulin per 24 h of each, on the card's scale (whole 10s, at least 10).
        @MainActor private static func insulinRows(_ wearDays: [PatchWearDay]) -> [InsulinRow] {
            let perDays = wearDays.map(\.numbers.perDay)
            let insulinScale = Swift.max(10, ((perDays.compactMap { $0 }.max() ?? 0) / 10).rounded(.up) * 10)
            return wearDays.map { day in
                let parts = day.numbers.partsPerDay
                let name = Self.dayName(day.index)
                let value = perDayText(day.numbers)
                return InsulinRow(
                    id: day.index,
                    name: name,
                    segments: parts.map { StatsSplitBar.segments($0, styles: InsulinPart.allCases.map(\.style)) } ?? [],
                    width: (day.numbers.perDay ?? 0) / insulinScale,
                    value: value
                )
            }
        }

        /// What the wear bar shows: the tick (Medtrum, Omnipod), a notch, the dashed starts.
        private static func barNote(_ sessions: [PatchStats], plugins: [String?], recordingStart: Date?) -> String {
            let hasLimit = plugins.contains { PatchStatsEngine.wearLimit(plugin: $0) != nil }
            let bar = hasLimit
                ? NSLocalizedString(
                    "The bar: the wear from activation, the tick at 3 days; a notch is a gap in the pump data.",
                    comment: "Statistics Patches: what the wear bar shows (Medtrum, Omnipod)"
                )
                : NSLocalizedString(
                    "The bar: the wear from activation; a notch is a gap in the pump data.",
                    comment: "Statistics Patches: what the wear bar shows"
                )
            let reasons = Set(sessions.compactMap { Self.partialReason($0.session, recordingStart: recordingStart) })
            var dashed: [String] = []
            if reasons.contains(.beforeRecording), !reasons.contains(.recordedLate) {
                dashed.append(NSLocalizedString(
                    "Dashed: before the recording began.",
                    comment: "Statistics Patches: the dashed start of the wear bar"
                ))
            } else if reasons.contains(.recordedLate) {
                dashed.append(NSLocalizedString(
                    "Dashed: before its pump data begins.",
                    comment: "Statistics Patches: the dashed start of the wear bar, recorded late"
                ))
            }
            if reasons.contains(.startUnknown) {
                dashed.append(NSLocalizedString(
                    "A short dashed lead: its activation isn't known.",
                    comment: "Statistics Patches: the wear bar of one whose activation isn't known"
                ))
            }
            return ([bar] + dashed).joined(separator: " ")
        }

        // MARK: - The detail's session

        /// Where a pushed session is (`PatchDetailScreen`, by its id): at an index of the content shown (the previous
        /// one while it is read again), not there while a read without it is in flight (the last one shown stays), or
        /// gone (a refresh dropped it, or nothing is shown: the detail pops).
        enum DetailPlace: Equatable {
            case index(Int)
            case waiting
            case gone
        }

        static func detailPlace(of id: String, in content: Stat.ViewContent<Patches>) -> DetailPlace {
            switch content {
            case let .loaded(patches):
                return patches.stats.firstIndex { $0.id == id }.map { .index($0) } ?? .gone
            case let .loading(previous):
                return previous?.stats.firstIndex { $0.id == id }.map { .index($0) } ?? .waiting
            case .empty,
                 .failed:
                return .gone
            }
        }

        // MARK: - Rows

        @MainActor private static func listRow(
            _ stats: PatchStats,
            index: Int,
            scale: Double
        ) -> ListRow {
            let session = stats.session
            let wear = stats.isInUse
                ? String(
                    format: NSLocalizedString("%@ so far", comment: "Statistics Patches: the wear of the one in use"),
                    hours(session.wear)
                )
                : hours(session.wear)
            let second = session.isPartial
                ? String(
                    format: NSLocalizedString(
                        "recorded from %@",
                        comment: "Statistics Patches: a partial one's numbers start (\"Mon 26 Oct\")"
                    ),
                    Trace.dayTitle(session.dataStart)
                )
                : stats.whole.perDay.map { StatsAmount.perDayUnits(StatsAmount.number($0, digits: 1)) } ?? "–"
            let span = self.span(session, inUse: stats.isInUse)
            let inRange = inRangeText(stats.whole)
            let detail = wear + " · " + second
            return ListRow(
                id: session.id,
                index: index,
                span: span,
                isInUse: stats.isInUse,
                isPartial: session.isPartial,
                detail: detail,
                inRange: inRange,
                bar: bar(stats, scale: scale, big: false)
            )
        }

        // MARK: - Detail

        /// The session at `index` (of `stats`), formatted.
        @MainActor func detail(at index: Int) -> Detail {
            typealias Format = StatsFormatting
            let stats = self.stats[index]
            let session = stats.session
            let whole = stats.whole
            let units = settings.units
            let unitName = Self.unitName(session, namesKind: namesKinds)

            let facts = Self.facts(stats)

            let delivered = [whole.basal, whole.smb, whole.bolus]
            let percents = GlucoseStatsEngine.largestRemainder(delivered)
            let hasInsulin = whole.total > 0
            let visible = settings.bands.visibleBands
            let shares = whole.bandShares
            let days = Self.detailDays(stats, units: units)
            return Detail(
                title: stats.isInUse
                    ? String(
                        format: NSLocalizedString("Since %@", comment: "Statistics Patches: the one in use's activation"),
                        Trace.dayTitle(session.activation)
                    )
                    : Trace.dayTitle(session.activation) + " – " + Trace.dayTitle(session.end),
                subtitle: [
                    unitName,
                    stats.isInUse
                        ? NSLocalizedString("in use", comment: "Statistics Patches detail: the one in use")
                        : Self.duration(session.wear)
                ].compactMap { $0 }.joined(separator: " · "),
                navigationTitle: Self.span(session, inUse: stats.isInUse),
                bar: Self.bar(stats, scale: scale, big: true),
                facts: facts,
                total: hasInsulin ? StatsAmount.number(whole.total, digits: 1) : "–",
                soFar: stats.isInUse,
                perDay: whole.perDay.map { StatsAmount.perDayUnits(StatsAmount.number($0, digits: 1)) } ?? "–",
                external: whole.external > 0
                    ? String(
                        format: naming.externalFormat,
                        StatsAmount.units(whole.external, digits: 1)
                    )
                    : nil,
                split: StatsSplitBar.segments(delivered, styles: InsulinPart.allCases.map(\.style)),
                parts: InsulinPart.allCases.map { part in
                    PartRow(
                        part: part,
                        value: StatsAmount.units(delivered[part.rawValue], digits: 1),
                        percent: hasInsulin ? Format.percent(percents[part.rawValue]) : "–"
                    )
                },
                cgm: whole.cgmShare.map { share in
                    String(
                        format: NSLocalizedString(
                            "CGM data %@ of the time",
                            comment: "Statistics Patches detail: the CGM's share of the time (\"97%\")"
                        ),
                        Format.percent(fraction: share)
                    )
                } ?? "",
                inRange: Self.inRangeText(whole),
                rangeText: Format.inRangeLabel(bands: settings.bands, units: units),
                bands: shares.barSegments(visible),
                glucoseTiles: Self.glucoseTiles(whole, units: units),
                days: days,
                loopTiles: Self.loopTiles(whole)
            )
        }

        /// The detail's facts: activated, recorded from, the coverage's end, the wear, the grace used, the gaps.
        @MainActor private static func facts(_ stats: PatchStats) -> [Fact] {
            let session = stats.session
            var facts: [(String, String)] = [
                (
                    NSLocalizedString("Activated", comment: "Statistics Patches detail: the activation"),
                    session.isActivationKnown ? Self.dayAndTime(session.activation) : "–"
                )
            ]
            if session.isPartial {
                facts.append((
                    NSLocalizedString("Recorded from", comment: "Statistics Patches detail: the recording's start"),
                    Self.dayAndTime(session.dataStart)
                ))
            }
            facts.append((
                stats.isInUse
                    ? NSLocalizedString("Last pump data", comment: "Statistics Patches detail: the coverage's end, in use")
                    : NSLocalizedString("Last delivery", comment: "Statistics Patches detail: the coverage's end"),
                Self.dayAndTime(session.end)
            ))
            facts.append((
                NSLocalizedString("Wear time", comment: "Statistics Patches: the time from activation to the end"),
                Self.duration(session.wear)
            ))
            if session.isActivationKnown, let limit = PatchStatsEngine.wearLimit(plugin: session.plugin) {
                let grace: String
                if session.wear > limit {
                    grace = Self.duration(session.wear - limit)
                } else if stats.isInUse {
                    grace = "–"
                } else {
                    grace = String(
                        format: NSLocalizedString(
                            "none · ended at %@",
                            comment: "Statistics Patches detail: no grace used, the wear (\"2 d 17 h\")"
                        ),
                        Self.hours(session.wear)
                    )
                }
                facts.append((NSLocalizedString("Grace used", comment: "Statistics Patches detail: the time past 3 days"), grace))
            }
            facts.append((
                NSLocalizedString("Gaps in pump data", comment: "Statistics Patches detail: the gaps in the coverage"),
                session.gaps.isEmpty
                    ? NSLocalizedString("none", comment: "Statistics Patches detail: no gaps")
                    : String(
                        format: NSLocalizedString(
                            "%1$d · %2$@",
                            comment: "Statistics Patches detail: the gaps, their time (\"2 · 45 m\")"
                        ),
                        session.gaps.count,
                        Self.duration(session.gapSeconds)
                    )
            ))
            return facts.enumerated().map { Fact(id: $0.offset, name: $0.element.0, value: $0.element.1) }
        }

        /// The detail's wear days: those with time (an ended one's last day of under an hour left out).
        @MainActor private static func detailDays(_ stats: PatchStats, units: GlucoseUnits) -> [DayRow] {
            typealias Format = StatsFormatting
            return stats.wearDays.enumerated().compactMap { index, numbers -> DayRow? in
                // a day before the recording's start has no time, and an ended one's last day under an hour (72 h and a
                // second) adds nothing: left out; the one in use's current day shows from its start
                let isCurrent = stats.isInUse && index == stats.wearDays.count - 1
                guard numbers.seconds > 0, isCurrent || numbers.seconds >= PatchStatsEngine.minimumWearDayTime else {
                    return nil
                }
                return DayRow(
                    id: index,
                    name: Self.dayName(
                        index,
                        soFar: isCurrent && numbers.seconds < PatchStatsEngine.wearDay
                    ),
                    inRange: Self.inRangeText(numbers),
                    second: numbers.mean.map { Format.glucose($0, units: units) } ?? "–",
                    perDay: Self.perDayText(numbers)
                )
            }
        }

        /// Mean, CV.
        @MainActor private static func glucoseTiles(_ whole: PatchNumbers, units: GlucoseUnits) -> [Tile] {
            typealias Format = StatsFormatting
            return [
                Tile(
                    id: 0,
                    title: NSLocalizedString("Mean", comment: "Statistics Patches detail: the mean glucose"),
                    value: whole.mean.map { Format.glucose($0, units: units) } ?? "–",
                    unit: Format.unit(units)
                ),
                Tile(
                    id: 1,
                    title: NSLocalizedString("CV", comment: "Statistics Patches detail: the coefficient of variation"),
                    value: whole.cv.map { Format.percent(Int($0.rounded())) } ?? "–",
                    unit: NSLocalizedString("variation", comment: "Statistics Patches detail: the CV's unit")
                )
            ]
        }

        /// Loops, Negative IOB.
        @MainActor private static func loopTiles(_ whole: PatchNumbers) -> [Tile] {
            typealias Format = StatsFormatting
            return [
                Tile(
                    id: 0,
                    title: NSLocalizedString("Loops", comment: "Statistics Patches detail: the loops' success"),
                    value: whole.loopPercent.map { Format.percent(Int($0.rounded())) } ?? "–",
                    unit: NSLocalizedString("of expected", comment: "Statistics Patches detail: the loops per slot")
                ),
                Tile(
                    id: 1,
                    title: NSLocalizedString("Negative IOB", comment: "Statistics Insulin: the time with a negative IOB"),
                    value: whole.negativeIOBPerDay.map { Format.duration(seconds: $0) } ?? "–",
                    unit: NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count")
                )
            ]
        }

        // MARK: - Today

        @MainActor private static func today(
            _ result: PatchesResult,
            naming: Naming,
            settings: StatsSettings,
            scale: Double,
            namesKinds: Bool
        ) -> Today {
            guard let stats = result.inUse, let age = result.age else { return Today(inUse: nil) }
            // compared at its covered age: an hour out of the pump's range adds no hour to the usual only
            let comparisonAge = result.comparisonAge ?? age
            let session = stats.session
            let units = settings.units
            let me = stats.whole
            let previous = result.previous
            // each previous one up to the age (`PatchStats.numbers(from:to:)`)
            let atAge = previous.map { $0.numbers(to: comparisonAge) }
            let usual = PatchNumbers.pooled(atAge)

            let tiles = todayTiles(session, now: result.asOf)
            let rows = todayRows(me, units: units)
            let usualValues = todayUsual(atAge, previous: previous, usual: usual, units: units)
            let usualDays = PatchStatsEngine.byWearDay(previous, upTo: comparisonAge)
            let compares = session.isComparable
            let days = !compares ? [] : todayDays(stats, usualDays: usualDays)
            let ageHours = hours(comparisonAge)
            return Today(inUse: Today.InUse(
                plugin: unitName(session, namesKind: namesKinds) ?? "",
                dayName: session.isActivationKnown ? dayName(PatchStatsEngine.dayIndex(at: age)) : nil,
                age: session.isActivationKnown
                    ? String(format: NSLocalizedString("%@ old", comment: "Statistics Patches Today: the age"), duration(age))
                    : String(
                        format: NSLocalizedString(
                            "recorded for %@",
                            comment: "Statistics Patches Today: the time recorded of one whose activation isn't known (\"1 d 4 h\")"
                        ),
                        hours(age)
                    ),
                // its activation, or (unknown) its data's start
                since: String(
                    format: NSLocalizedString(
                        "since %@",
                        comment: "Statistics Patches Today: the activation (\"Tue 27 Oct, 19:40\")"
                    ),
                    dayAndTime(session.isActivationKnown ? session.activation : session.dataStart)
                ),
                bar: bar(stats, scale: scale, big: true, age: age),
                tiles: tiles,
                usualTitle: previous.isEmpty ? nil : String(
                    format: NSLocalizedString(
                        "by %1$@ · %2$d before",
                        comment: "Statistics Patches Today: the usual's age and how many it is over (\"2 d 19 h\", 10)"
                    ),
                    ageHours,
                    previous.count
                ),
                rows: rows,
                usual: compares ? usualValues : [],
                days: days,
                note: todayNote(
                    session,
                    compares: compares,
                    previous: previous,
                    hasEarlier: result.hasEarlier,
                    naming: naming,
                    ageHours: ageHours
                ),
                compares: compares
            ))
        }

        // MARK: Today's parts

        /// Expires, Grace ends (Medtrum, Omnipod); none without a known activation or a wear limit.
        @MainActor private static func todayTiles(_ session: PatchSession, now: Date) -> [Tile] {
            var tiles: [Tile] = []
            if session.isActivationKnown, let limit = PatchStatsEngine.wearLimit(plugin: session.plugin) {
                let expires = session.activation.addingTimeInterval(limit)
                let graceEnds = expires.addingTimeInterval(PatchStatsEngine.grace)
                tiles = [
                    Tile(
                        id: 0,
                        title: NSLocalizedString("Expires", comment: "Statistics Patches Today: the end of the 3 days"),
                        value: expires.formatted(date: .omitted, time: .shortened),
                        unit: relative(expires, now: now)
                    ),
                    Tile(
                        id: 1,
                        title: NSLocalizedString("Grace ends", comment: "Statistics Patches Today: the end of the grace"),
                        value: graceEnds.formatted(date: .omitted, time: .shortened),
                        unit: relative(graceEnds, now: now)
                    )
                ]
            }
            return tiles
        }

        /// Insulin, In range, Mean, Negative IOB per day: the one in use's.
        @MainActor private static func todayRows(_ me: PatchNumbers, units: GlucoseUnits) -> [Fact] {
            typealias Format = StatsFormatting
            return [
                Fact(
                    id: 0,
                    name: NSLocalizedString("Insulin", comment: "Statistics topic"),
                    value: StatsAmount.units(me.total, digits: 1)
                ),
                Fact(
                    id: 1,
                    name: NSLocalizedString("In range", comment: "Statistics glucose band"),
                    value: inRangeText(me)
                ),
                Fact(
                    id: 2,
                    name: String(
                        format: NSLocalizedString(
                            "Mean, %@",
                            comment: "Statistics Patches: the mean glucose's header, its unit"
                        ),
                        Format.unit(units)
                    ),
                    value: me.mean.map { Format.glucose($0, units: units) } ?? "–"
                ),
                Fact(
                    id: 3,
                    name: NSLocalizedString(
                        "Negative IOB per day",
                        comment: "Statistics Patches Today: the time with a negative IOB per day"
                    ),
                    value: me.negativeIOBPerDay.map { Format.duration(seconds: $0) } ?? "–"
                )
            ]
        }

        /// The usual of each row: the ones before it, each up to the age ("–" without any).
        @MainActor private static func todayUsual(
            _ atAge: [PatchNumbers],
            previous: [PatchStats],
            usual: PatchNumbers,
            units: GlucoseUnits
        ) -> [String] {
            typealias Format = StatsFormatting
            let totals = atAge.map(\.total)
            return [
                totals.isEmpty ? "–" : StatsAmount.units(totals.reduce(0, +) / Double(totals.count), digits: 1),
                previous.isEmpty ? "–" : inRangeText(usual),
                previous.isEmpty ? "–" : usual.mean.map { Format.glucose($0, units: units) } ?? "–",
                previous.isEmpty ? "–" : usual.negativeIOBPerDay.map { Format.duration(seconds: $0) } ?? "–"
            ]
        }

        /// The one in use's wear days, each against the usual of that day.
        @MainActor private static func todayDays(_ stats: PatchStats, usualDays: [PatchWearDay]) -> [DayRow] {
            let dayCount = stats.wearDays.count
            return stats.wearDays.enumerated().compactMap { index, numbers -> DayRow? in
                guard numbers.seconds > 0 else { return nil }
                let usualDay = usualDays.first { $0.index == index }?.numbers
                return DayRow(
                    id: index,
                    name: dayName(index, soFar: index == dayCount - 1 && numbers.seconds < PatchStatsEngine.wearDay),
                    inRange: inRangeText(numbers),
                    second: inRangeText(usualDay),
                    perDay: perDayText(numbers),
                    usualPerDay: perDayText(usualDay)
                )
            }
        }

        /// What the usual is; without any before it at its age, why; not compared, why.
        private static func todayNote(
            _ session: PatchSession,
            compares: Bool,
            previous: [PatchStats],
            hasEarlier: Bool,
            naming: Naming,
            ageHours: String
        ) -> String {
            !session.isActivationKnown
                ? NSLocalizedString(
                    "Its activation isn't known, so neither is its age: it isn't compared with earlier ones.",
                    comment: "Statistics Patches Today: the one in use, its activation unknown"
                )
                : !compares
                ? NSLocalizedString(
                    "No pump data for it yet: it is compared with the ones before it once there is.",
                    comment: "Statistics Patches Today: the one in use, nothing covered yet"
                )
                : previous.isEmpty ? (hasEarlier ? naming.noneReached : naming.noEarlier) : String(
                    format: NSLocalizedString(
                        "Usual: the %1$d before this one, each up to the same age (%2$@); one that ended sooner is left out.",
                        comment: "Statistics Patches Today: what the usual is (10, \"2 d 19 h\")"
                    ),
                    previous.count,
                    ageHours
                )
        }

        /// "74%", "–"
        @MainActor private static func inRangeText(_ numbers: PatchNumbers?) -> String {
            numbers?.inRangePercent.map { StatsFormatting.percent($0) } ?? "–"
        }

        /// "41.2", "–"
        @MainActor private static func perDayText(_ numbers: PatchNumbers?) -> String {
            numbers?.perDay.map { StatsAmount.number($0, digits: 1) } ?? "–"
        }

        // MARK: - The wear bar

        /// The bars' scale, h: the longest wear, at least the wear limit and its grace (3 d 8 h) of the plugins shown.
        static func barScale(longestWear: TimeInterval, plugins: [String?]) -> Double {
            let limit = plugins.compactMap { PatchStatsEngine.wearLimit(plugin: $0) }.max()
                .map { $0 + PatchStatsEngine.grace } ?? PatchStatsEngine.wearDay
            return Swift.max(longestWear, limit) / .hours(1)
        }

        /// A session's bar: its wear (in use: to its age, the rest to the grace's end outlined), the time before the
        /// recording's start, its gaps.
        @MainActor static func bar(_ stats: PatchStats, scale: Double, big: Bool, age: TimeInterval? = nil) -> PatchWearBar.Plot {
            let session = stats.session
            let hour = TimeInterval.hours(1)
            // no tick, no grace without a known activation
            let limit = session.isActivationKnown ? PatchStatsEngine.wearLimit(plugin: session.plugin) : nil
            let wear = Swift.max(session.wear, stats.isInUse ? age ?? 0 : 0) / hour
            let days = PatchStatsEngine.dayIndex(at: scale * hour) + 1
            return PatchWearBar.Plot(
                scale: scale,
                wear: wear,
                dataStart: session.dataStart.timeIntervalSince(session.activation) / hour,
                isStartUnknown: !session.isActivationKnown,
                gaps: session.gaps.map { gap in
                    PatchWearBar.Plot.Gap(
                        start: gap.start.timeIntervalSince(session.activation) / hour,
                        end: gap.end.timeIntervalSince(session.activation) / hour
                    )
                },
                isInUse: stats.isInUse,
                limit: limit.map { $0 / hour },
                restEnd: stats.isInUse ? limit.map { Swift.min(scale, ($0 + PatchStatsEngine.grace) / hour) } ?? scale : nil,
                // the days count from the activation: none named without one
                dayNames: big && session.isActivationKnown ? (0 ..< days).map { dayName($0) } : [],
                nowLabel: big && stats.isInUse
                    ? NSLocalizedString("now", comment: "Statistics Patches wear bar: the mark of the patch in use's age")
                    : nil,
                isBig: big
            )
        }

        // MARK: - Formatting

        /// "Day 1", "Day 3 so far"
        static func dayName(_ index: Int, soFar: Bool = false) -> String {
            soFar
                ? String(
                    format: NSLocalizedString("Day %d so far", comment: "Statistics Patches: the wear day the one in use is in"),
                    index + 1
                )
                : String(format: NSLocalizedString("Day %d", comment: "Statistics Patches: a wear day"), index + 1)
        }

        /// Why a session is partial (`PatchSession.isPartial`).
        enum PartialReason: Hashable {
            /// its activation is before the recording's start (the oldest data of the sessions shown)
            case beforeRecording
            /// its data starts more than the slack after its activation, later than the recording's start
            case recordedLate
            /// its activation isn't known
            case startUnknown
        }

        /// nil: not partial.
        static func partialReason(_ session: PatchSession, recordingStart: Date?) -> PartialReason? {
            guard session.isPartial else { return nil }
            guard session.isActivationKnown else { return .startUnknown }
            return recordingStart.map { session.dataStart <= $0 } == false ? .recordedLate : .beforeRecording
        }

        /// "Medtrum", "Omnipod"
        static func pluginName(_ plugin: String) -> String {
            plugin == PatchStatsEngine.omnipodPlugin ? "Omnipod" : plugin
        }

        /// The unit's name where it is shown (the detail's subtitle, Today's header): its pump ("Medtrum", "Omnipod"),
        /// with its kind in a mixed history ("Omnipod pod", "Dana site"); nil when neither is to say.
        static func unitName(_ session: PatchSession, namesKind: Bool) -> String? {
            let plugin = session.plugin.map { pluginName($0) }
            guard namesKind else { return plugin }
            let kind = kindName(session.kind)
            guard let plugin else { return kind.localizedCapitalized }
            return String(
                format: NSLocalizedString(
                    "%1$@ %2$@ (pump kind)",
                    value: "%1$@ %2$@",
                    comment: "Statistics Patches: a session's pump and its kind, in a mixed history (\"Omnipod pod\", \"Dana site\"); translate the value, the key's \"(pump kind)\" only keeps it apart"
                ),
                plugin,
                kind
            )
        }

        /// "patch", "pod", "site"
        static func kindName(_ kind: PatchKind) -> String {
            switch kind {
            case .patch: return NSLocalizedString("patch", comment: "Statistics Patches: the unit of a count of one patch")
            case .pod: return NSLocalizedString("pod", comment: "Statistics Patches: the unit of a count of one pod")
            case .site: return NSLocalizedString("site", comment: "Statistics Patches: the unit of a count of one site")
            }
        }

        /// "24 – 27 Oct", "29 Sep – 2 Oct"; in use "Since 27 Oct"
        static func span(_ session: PatchSession, inUse: Bool) -> String {
            guard !inUse else {
                return String(
                    format: NSLocalizedString("Since %@", comment: "Statistics Patches: the one in use's activation"),
                    session.activation.formatted(.dateTime.day().month(.abbreviated))
                )
            }
            return (session.activation ..< Swift.max(session.end, session.activation))
                .formatted(.interval.day().month(.abbreviated))
        }

        /// "Tue 27 Oct, 19:40"
        static func dayAndTime(_ date: Date) -> String {
            String(
                format: NSLocalizedString("%1$@, %2$@", comment: "Statistics Patches: a day and a time (\"Tue 27 Oct, 19:40\")"),
                Trace.dayTitle(date),
                date.formatted(date: .omitted, time: .shortened)
            )
        }

        /// "3 d 7 h 15 m", "7 h 05 m", "25 m"
        @MainActor static func duration(_ seconds: TimeInterval) -> String {
            let minutes = Int((Swift.max(seconds, 0) / 60).rounded())
            let days = minutes / (24 * 60)
            guard days > 0 else { return StatsFormatting.duration(minutes: Double(minutes)) }
            let rest = minutes - days * 24 * 60
            return String(
                format: NSLocalizedString(
                    "%1$d d %2$d h %3$02d m",
                    comment: "Statistics duration: days, hours and minutes"
                ),
                days,
                rest / 60,
                rest % 60
            )
        }

        /// "3 d 7 h", "7 h"
        static func hours(_ seconds: TimeInterval) -> String {
            let hours = Int((Swift.max(seconds, 0) / .hours(1)).rounded())
            guard hours >= 24 else {
                return String(format: NSLocalizedString("%d h", comment: "Statistics duration: hours"), hours)
            }
            return String(
                format: NSLocalizedString("%1$d d %2$d h", comment: "Statistics duration: days and hours"),
                hours / 24,
                hours % 24
            )
        }

        /// "today · in 5 h 05 m", "Sat · 2 h 10 m ago"
        @MainActor static func relative(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
            let day: String
            if calendar.isDate(date, inSameDayAs: now) {
                day = NSLocalizedString("today", comment: "Statistics Patches Today: the day of a time")
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                      calendar.isDate(date, inSameDayAs: tomorrow)
            {
                day = NSLocalizedString("tomorrow", comment: "Statistics Patches Today: the day of a time")
            } else {
                day = date.formatted(.dateTime.weekday(.abbreviated))
            }
            let distance = duration(abs(date.timeIntervalSince(now)))
            let when = date > now
                ? String(format: NSLocalizedString("in %@", comment: "Statistics Patches Today: a time to come"), distance)
                : String(format: NSLocalizedString("%@ ago", comment: "Statistics Patches Today: a time passed"), distance)
            return day + " · " + when
        }
    }
}
