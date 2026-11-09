import Observation
import SwiftUI

// MARK: - Formatting

/// The CGM topic's numbers in the user's unit: levels as the other topics show them, the small figures (noise, jitter,
/// errors) with one more decimal, the rate of change as the 5-minute change the loop works with.
@MainActor enum CGMFormat {
    /// mmol/L per mg/dL (`GlucoseUnits.exchangeRate`)
    static let mmolPerMgdl = NSDecimalNumber(decimal: GlucoseUnits.exchangeRate).doubleValue

    static func shown(_ mgdl: Double, units: GlucoseUnits) -> Double {
        units == .mmolL ? mgdl * mmolPerMgdl : mgdl
    }

    /// The decimals of a small figure: 2 in mmol/L, 1 in mg/dL.
    static func fineDigits(_ units: GlucoseUnits) -> Int {
        units == .mmolL ? 2 : 1
    }

    /// A small figure (noise, jitter, an error): "0.18", "3.4".
    static func fine(_ mgdl: Double, units: GlucoseUnits) -> String {
        number(shown(mgdl, units: units), digits: fineDigits(units))
    }

    /// A small figure's change: "+0.05", "−1.2", "±0.00".
    static func signedFine(_ mgdl: Double, units: GlucoseUnits) -> String {
        signed(shown(mgdl, units: units), digits: fineDigits(units))
    }

    /// A level's change: "+1.4", "−25".
    static func signedLevel(_ mgdl: Double, units: GlucoseUnits) -> String {
        signed(shown(mgdl, units: units), digits: units == .mmolL ? 1 : 0)
    }

    /// A rate (mg/dL a minute) as its 5-minute change: "+0.8", "−15".
    static func rate(_ perMinute: Double, units: GlucoseUnits) -> String {
        signedLevel(perMinute * 5, units: units)
    }

    /// A level as the notes say it, with its unit: "1.7 mmol/L", "30 mg/dL".
    static func amount(_ mgdl: Double, units: GlucoseUnits) -> String {
        StatsFormatting.glucose(mgdl, units: units) + " " + StatsFormatting.unit(units)
    }

    /// "97.3%"
    static func percent1(_ fraction: Double) -> String {
        number(fraction * 100, digits: 1) + "%"
    }

    /// "+12", "−3", "±0", the magnitude rounded first
    static func signed(_ value: Double, digits: Int) -> String {
        let scale = pow(10, Double(digits))
        let rounded = (value * scale).rounded() / scale
        let magnitude = number(abs(rounded), digits: digits)
        return (rounded > 0 ? "+" : rounded < 0 ? "−" : "±") + magnitude
    }

    static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// "26 Oct"
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "6 d 19 h", "7 h", "10 d" (`Stat.Patches.hours`, whole days without their 0 h)
    static func days(_ seconds: TimeInterval) -> String {
        let hours = Int((Swift.max(seconds, 0) / .hours(1)).rounded())
        guard hours >= 24, hours % 24 == 0 else { return Stat.Patches.hours(seconds) }
        return String(format: NSLocalizedString("%d d", comment: "Statistics duration: whole days"), hours / 24)
    }

    /// "a 5-min CGM": "5-min", "1-min"
    static func cadence(_ cadence: TimeInterval) -> String {
        String(
            format: NSLocalizedString("%d-min", comment: "Statistics CGM: a CGM's cadence (\"5-min\")"),
            Int((cadence / 60).rounded())
        )
    }

    /// A short name longer than this is cut at a word: a picker segment or a By CGM column holds about as much.
    static let shortNameLength = 12

    /// The picker's and the By CGM columns' name of a pick: "Unknown", a CGM's by its statistics id
    /// (`KnownPlugins.cgmIdForStatistics`, the source app for AppGroup: "G7", "Libre 3", "xDrip"); any other CGM its
    /// name, cut at a word to `shortNameLength` ("Dexcom ONE…").
    static func shortName(_ pick: Stat.CGMPick, name: String) -> String {
        switch pick {
        case .unknown: return name
        case let .cgm(id):
            switch id {
            case "dexcomG5": return NSLocalizedString("G5", comment: "Statistics CGM: the Dexcom G5, short")
            case "dexcomG6": return NSLocalizedString("G6", comment: "Statistics CGM: the Dexcom G6, short")
            case "dexcomG7": return NSLocalizedString("G7", comment: "Statistics CGM: the Dexcom G7, short")
            case "libre3": return NSLocalizedString("Libre 3", comment: "Statistics CGM: the FreeStyle Libre 3, short")
            case "libreTransmitter": return NSLocalizedString(
                    "Libre 2",
                    comment: "Statistics CGM: a FreeStyle Libre through LibreTransmitter, short"
                )
            case "eversense": return NSLocalizedString("Eversense", comment: "Statistics CGM: the Eversense, short")
            case "nightscout": return NSLocalizedString("Nightscout", comment: "Statistics CGM: Nightscout as the CGM, short")
            case "simulator": return NSLocalizedString("Simulator", comment: "Statistics CGM: the CGM simulator, short")
            case "enlite": return NSLocalizedString("Enlite", comment: "Statistics CGM: the Medtronic Enlite, short")
            case "xdrip": return NSLocalizedString("xDrip", comment: "Statistics CGM: xDrip4iOS as the CGM, short")
            case "glucoseDirect": return NSLocalizedString(
                    "Glucose Direct",
                    comment: "Statistics CGM: Glucose Direct as the CGM, short"
                )
            default: return cut(name)
            }
        }
    }

    /// A name cut at a word to `shortNameLength` with "…"; a first word longer than that cut inside it.
    static func cut(_ name: String) -> String {
        guard name.count > shortNameLength else { return name }
        var kept = ""
        for word in name.split(separator: " ") {
            let next = kept.isEmpty ? String(word) : kept + " " + word
            guard next.count < shortNameLength else { break }
            kept = next
        }
        return (kept.isEmpty ? String(name.prefix(shortNameLength - 1)) : kept) + "…"
    }
}

/// The CGM topic's colours: the Mean ramp's indigo (By weekday's), its four darker steps for the rate-of-change bands
/// (more ink, faster) and the third for the data.
enum CGMChartStyle {
    /// the rate-of-change bands, slow to very fast
    static let ramp: [Color] = [
        dynamic(light: 0xBEC6FF, dark: 0x484D91),
        dynamic(light: 0x9AA3F6, dark: 0x666CC8),
        dynamic(light: 0x7278E4, dark: 0x878FF6),
        dynamic(light: 0x4E4AC8, dark: 0xB2BBFF)
    ]
    /// the bars
    static let data = ramp[2]
    /// what stands out among them (sensor day 1)
    static let emphasis = ramp[3]

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        return Color(UIColor { traits in color(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}

// MARK: - The topic

extension Stat {
    /// The CGM topic, formatted for display from the provider's result (`CGMResult`) for the pick shown: every view's
    /// cards, the picker, the smoothing view's facts. Picking another CGM formats the result again; nothing is read.
    struct CGMReport: Equatable {
        /// A key and its value (and a note under it).
        struct Fact: Equatable, Identifiable {
            let id: Int
            let key: String
            let value: String
            var detail: String?
        }

        /// A callout: its title, the line in bold and the one under it.
        struct Callout: Equatable {
            let title: String
            let value: String
            let detail: String
        }

        struct PickerItem: Equatable, Identifiable {
            let pick: CGMPick
            /// the full name ("FreeStyle Libre 3 / 3+"), the menu's
            let title: String
            /// the segment's and the menu button's (`CGMFormat.shortName`: "Libre 3")
            let label: String

            var id: CGMPick { pick }
        }

        struct Readings: Equatable {
            let title: String
            let dateRange: String
            /// why the numbers are provisional: under `limitedSpan` of readings; nil when not
            let limitedNote: String?
            let coverage: String
            let coverageDetail: String
            let tiles: [StatsTileItem]
            let note: String
        }

        struct RateRow: Equatable, Identifiable {
            let id: Int
            let name: String
            let range: String
            let percent: String
            let perDay: String
        }

        struct Rate: Equatable {
            let unitTitle: String
            /// by band, the nonzero ones
            let segments: [StatsSplitBar.Segment]
            let rows: [RateRow]
            let fastest: Callout?
            let note: String
        }

        /// The By CGM table: a column per CGM.
        struct Comparison: Equatable {
            struct Row: Equatable, Identifiable {
                let id: Int
                let name: String
                let unit: String
                let values: [String]
            }

            let dateRange: String
            let columns: [String]
            let rows: [Row]
            let note: String
        }

        struct Overview: Equatable {
            let readings: Readings
            let rate: Rate?
            /// with two or more CGMs
            let comparison: Comparison?
        }

        struct SensorRow: Equatable, Identifiable {
            let id: UUID
            let title: String
            let isInUse: Bool
            /// "Ended early", "Ended at the CGM change"; nil when it didn't end early
            let earlyText: String?
            /// its dates and its length: "Sun 11 Oct, 23:06 – Mon 26 Oct, 10:37 · 14 d 13 h"
            let span: String
            /// its length of its expected life (its grace left out), 0...1; nil when the life isn't known
            let bar: Double?
            /// "noise 0.18 mmol/L"; nil without one
            let noise: String?
            /// its start entered by the user ("Entered by you")
            var isEntered = false
            /// named from Nightscout ("From Nightscout")
            var isBackfilled = false
        }

        struct NoiseDay: Equatable, Identifiable {
            let day: Int
            /// in the unit shown
            let value: Double
            let sensors: Int

            var id: Int { day }
        }

        struct Sensors: Equatable {
            let rows: [SensorRow]
            /// shown without rows
            let emptyText: String
            let note: String
            let noiseDays: [NoiseDay]
            /// the noise chart's gridlines, in the unit shown, and their labels
            let noiseLevels: [Double]
            let noiseLevelLabels: [String]
            let noiseCallout: Callout?
            let noiseNote: String
        }

        /// Unknown picked: what its readings are, and "Which CGM was this?" (with the editor).
        struct Unknown: Equatable {
            let detail: String
            let body: String
            let facts: [Fact]
            /// what the user entered, when they did
            var entered: Entered?
            /// the "Which CGM was this?" sheet's; nil: no button
            var editor: CGMUnknownEditor?
        }

        /// The sessions the user entered for Unknown readings: how many, Change (those in the sheet's 90 days) and Clear.
        struct Entered: Equatable {
            /// "3 periods entered by you"; "What you entered is older than 90 days."
            let text: String
            /// some are in the sheet's 90 days
            let canChange: Bool
            let editor: CGMUnknownEditor?
        }

        /// The smoothing view's facts (the analysis itself is `CGMSmoothingRuns`').
        struct Smoothing: Equatable {
            let key: CGMSmoothingRuns.Key
            /// the newest readings change when this content was read: a result that saw fewer is noted as such
            let readingsSeq: Int
            let facts: [Fact]
            /// the current setting (`settingsManager.settings.glucoseSmoothing`), marked in the tables
            let current: SmoothingCandidate
            /// the CGM shown and the days: the result cards' detail ("Libre 3 · 30 d")
            let detail: String
        }

        /// the period shown
        let period: StatsPeriod
        let pick: CGMPick
        let units: GlucoseUnits
        /// each CGM; empty with one CGM (hidden)
        let picker: [PickerItem]
        let unknown: Unknown?
        /// another pick than Unknown, with sessions the user entered: their card on the Overview
        let entered: Entered?
        let overview: Overview
        let sensors: Sensors
        let smoothing: Smoothing

        /// Fewer days of readings than this mark the numbers provisional: noise, reversals and jitter need several days to
        /// mean anything.
        static let limitedSpan: TimeInterval = .days(3)
        /// The noise by sensor day goes up to this day: later days have few sensors.
        static let lastSensorDay = 15

        /// - Parameters:
        ///   - pick: the CGM picked; nil, or one the period lacks: the default (`CGMResult.defaultPick`)
        ///   - readingsSeq: the newest readings change (`glucoseStatsChanged`) when the content was read
        ///   - editor: the "Which CGM was this?" sheet's (the state model's); nil: no button
        @MainActor init(
            _ result: CGMResult,
            pick: CGMPick?,
            units: GlucoseUnits,
            smoothing current: SmoothingCandidate,
            readingsSeq: Int = 0,
            editor: CGMUnknownEditor? = nil
        ) {
            let pick = result.shown(pick) ?? .unknown
            let shown = result.picks[pick]
            let names = Dictionary(uniqueKeysWithValues: result.cgms.map { ($0.pick, $0.name) })
            let multi = result.cgms.count > 1
            let who = names[pick] ?? ""
            let dateRange = StatsFormatting.dateRange(result.window, period: result.period, now: result.asOf)
            period = result.period
            self.pick = pick
            self.units = units
            picker = multi ? result.cgms.map {
                PickerItem(pick: $0.pick, title: $0.name, label: CGMFormat.shortName($0.pick, name: $0.name))
            } : []
            let stats = shown?.stats
            // the Unknown readings all from before the recording: "before …" is said of them
            let unknownEnd = result.picks[.unknown]?.stats.span?.end
            let allBefore = result.recordingStart.map { start in unknownEnd.map { $0 < start } ?? true } ?? false
            let unknownBefore = allBefore ? result.recordingStart : nil
            var enteredText: String?
            if result.enteredSessions == 1 {
                enteredText = NSLocalizedString(
                    "1 period entered by you",
                    comment: "Statistics CGM Unknown: the sessions the user entered, one"
                )
            } else if result.enteredSessions > 1 {
                enteredText = String(
                    format: NSLocalizedString(
                        "%d periods entered by you",
                        comment: "Statistics CGM Unknown: the sessions the user entered (3)"
                    ),
                    result.enteredSessions
                )
            } else if result.hasEnteredSessions {
                enteredText = NSLocalizedString(
                    "What you entered is older than 90 days.",
                    comment: "Statistics CGM Unknown: the sessions the user entered, none in the last 90 days"
                )
            }
            let entered = enteredText.map { text in
                Entered(text: text, canChange: result.enteredSessions > 0, editor: editor)
            }
            if pick == .unknown {
                var unknown = Self.makeUnknown(
                    stats,
                    recordingStart: result.recordingStart,
                    allBefore: allBefore,
                    backfilled: result.backfilledReadings,
                    canBackfill: result.backfillCanName
                )
                unknown.entered = entered
                unknown.editor = editor
                self.unknown = unknown
                self.entered = nil
            } else {
                unknown = nil
                self.entered = entered
            }

            let empty = Self.emptyStats
            let s = stats ?? empty
            let spanSeconds = s.span?.duration ?? 0
            let limitedNote = spanSeconds < Self.limitedSpan
                ? String(
                    format: NSLocalizedString(
                        "Under 3 days of readings: %@. Noise, reversals and jitter need more to settle.",
                        comment: "Statistics CGM limited data: the readings' span (\"1 d 20 h\")"
                    ),
                    CGMFormat.days(spanSeconds)
                )
                : nil
            overview = Overview(
                readings: Self.readings(s, title: who, dateRange: dateRange, limitedNote: limitedNote, units: units),
                rate: Self.rate(s, units: units),
                comparison: multi ? Self.comparison(result, dateRange: dateRange, units: units) : nil
            )
            sensors = Self.makeSensors(
                shown,
                pick: pick,
                recordingStart: unknownBefore,
                now: result.asOf,
                units: units
            )
            smoothing = Smoothing(
                key: CGMSmoothingRuns.Key(
                    period: result.period,
                    windowStart: result.window.start,
                    pick: pick
                ),
                readingsSeq: readingsSeq,
                facts: Self.smoothingFacts(
                    s,
                    who: who,
                    period: result.period,
                    dateRange: dateRange,
                    current: current
                ),
                current: current,
                detail: who + " · " + StatsFormatting.label(result.period)
            )
        }

        private static let emptyStats = CGMStatsEngine.stats(
            readings: [],
            sensorStarts: [],
            period: DateInterval(start: .distantPast, duration: 0),
            now: .distantPast
        )

        // MARK: Unknown

        /// - Parameters:
        ///   - recordingStart: the first session's start; nil without sessions
        ///   - allBefore: every Unknown reading is from before it (not from a time no session was open after it)
        /// - Parameters:
        ///   - backfilled: the period's readings Nightscout named (`CGMResult.backfilledReadings`)
        ///   - canBackfill: the backfill can still name some (`CGMResult.backfillCanName`)
        @MainActor private static func makeUnknown(
            _ stats: CGMStats?,
            recordingStart: Date?,
            allBefore: Bool,
            backfilled: Int,
            canBackfill: Bool
        ) -> Unknown {
            let count = (stats?.readings ?? 0).formatted(.number)
            var body: String
            if let recordingStart, allBefore {
                body = String(
                    format: NSLocalizedString(
                        "Readings from before iAPS recorded which CGM was in use. Recording started on %1$@; these %2$@ readings came earlier. They count in the Glucose statistics as always; here they are kept apart from the named CGMs.",
                        comment: "Statistics CGM Unknown: what its readings are (the recording's start, \"Mon 12 Oct, 10:20\"; the count)"
                    ),
                    Stat.Patches.dayAndTime(recordingStart),
                    count
                )
            } else if recordingStart == nil {
                body = NSLocalizedString(
                    "Readings from before iAPS recorded which CGM was in use. They count in the Glucose statistics as always; here they are kept apart from the named CGMs.",
                    comment: "Statistics CGM Unknown: what its readings are, no recording yet"
                )
            } else {
                body = String(
                    format: NSLocalizedString(
                        "Readings no recorded CGM session covers: from before iAPS recorded which CGM was in use, or from a time no CGM was recorded. These %@ readings count in the Glucose statistics as always; here they are kept apart from the named CGMs.",
                        comment: "Statistics CGM Unknown: what its readings are, some after the recording began (the count)"
                    ),
                    count
                )
            }
            // what the Nightscout backfill did, or can do
            if backfilled > 0 {
                body += " " + String(
                    format: NSLocalizedString(
                        "Nightscout named the CGM of %@ more readings of this period: they count with their CGMs.",
                        comment: "Statistics CGM Unknown: the readings the Nightscout backfill named (the count)"
                    ),
                    backfilled.formatted(.number)
                )
            } else if canBackfill {
                body += " " + NSLocalizedString(
                    "Backfilling glucose from Nightscout also names their CGM, where Nightscout’s entries say which it was.",
                    comment: "Statistics CGM Unknown: what the Nightscout glucose backfill can do for them"
                )
            }
            var facts: [Fact] = []
            if let span = stats?.span {
                facts.append(Fact(
                    id: 0,
                    key: NSLocalizedString("Readings", comment: "Statistics CGM Unknown: the readings' span"),
                    value: CGMFormat.day(span.start) + " – " + Stat.Patches.dayAndTime(span.end),
                    detail: String(
                        format: NSLocalizedString(
                            "%@ in this period",
                            comment: "Statistics CGM Unknown: the readings' span (\"3 d 4 h\")"
                        ),
                        CGMFormat.days(span.duration)
                    )
                ))
            }
            facts.append(Fact(
                id: 1,
                key: NSLocalizedString("Sensor starts", comment: "Statistics CGM Unknown: the sensor starts"),
                value: NSLocalizedString("Not known", comment: "Statistics CGM Unknown: no sensor starts"),
                detail: NSLocalizedString(
                    "so no sensors, no sensor days",
                    comment: "Statistics CGM Unknown: what no sensor starts leaves out"
                )
            ))
            var detail = ""
            if let recordingStart, allBefore {
                detail = String(
                    format: NSLocalizedString("before %@", comment: "Statistics CGM Unknown: the recording's start (\"12 Oct\")"),
                    CGMFormat.day(recordingStart)
                )
            }
            return Unknown(detail: detail, body: body, facts: facts)
        }

        // MARK: Overview

        @MainActor private static func readings(
            _ s: CGMStats,
            title: String,
            dateRange: String,
            limitedNote: String?,
            units: GlucoseUnits
        ) -> Readings {
            let unit = StatsFormatting.unit(units)
            let cadence = String(
                format: NSLocalizedString(
                    "every %@",
                    comment: "Statistics CGM: the readings' cadence (\"5 min\", \"1 and 5 min\")"
                ),
                String(
                    format: NSLocalizedString("%d min", comment: "Statistics CGM: one cadence"),
                    Int(((s.cadence ?? 300) / 60).rounded())
                )
            )
            let gapsUnit = s.gaps.isEmpty
                ? NSLocalizedString("none", comment: "Statistics Patches detail: no gaps")
                : String(
                    format: NSLocalizedString(
                        "longest %1$@ · %2$@ in all",
                        comment: "Statistics CGM: the longest gap and all of them (\"1 h 05 m\", \"4 h 20 m\")"
                    ),
                    StatsFormatting.duration(seconds: s.longestGap ?? 0),
                    StatsFormatting.duration(seconds: s.gapSeconds)
                )
            let tiles = [
                StatsTileItem(
                    id: 0,
                    title: NSLocalizedString("Gaps", comment: "Statistics CGM: the gaps tile"),
                    value: "\(s.gaps.count)",
                    unit: gapsUnit
                ),
                StatsTileItem(
                    id: 1,
                    title: NSLocalizedString("Noise", comment: "Statistics CGM: the noise tile"),
                    value: s.noise.map { CGMFormat.fine($0.mgdl, units: units) } ?? "–",
                    unit: s.noise.map { noise in
                        String(
                            format: NSLocalizedString(
                                "%1$@ · %2$@ of the level",
                                comment: "Statistics CGM: the noise's unit and its share of the level (\"mmol/L\", \"2.3%\")"
                            ),
                            unit,
                            CGMFormat.percent1(noise.fraction)
                        )
                    } ?? unit,
                    limitedNote: limitedNote
                ),
                StatsTileItem(
                    id: 2,
                    title: NSLocalizedString("Reversals", comment: "Statistics CGM: the reversals tile"),
                    value: s.reversals.rawPerDay.map {
                        String(
                            format: NSLocalizedString("%d a day", comment: "Statistics CGM: a count per day"),
                            Int($0.rounded())
                        )
                    } ?? "–",
                    unit: s.reversals.referencePerDay.map {
                        String(
                            format: NSLocalizedString(
                                "%d in the reference",
                                comment: "Statistics CGM: the reference's reversals per day (the body's turns)"
                            ),
                            Int($0.rounded())
                        )
                    },
                    limitedNote: limitedNote
                ),
                StatsTileItem(
                    id: 3,
                    title: NSLocalizedString("Delta jitter", comment: "Statistics CGM: the delta jitter tile"),
                    value: s.deltaJitter.map { CGMFormat.fine($0, units: units) } ?? "–",
                    unit: String(
                        format: NSLocalizedString(
                            "%@ · the 5-min delta",
                            comment: "Statistics CGM: the jitter's unit, of the 5-minute delta (\"mmol/L\")"
                        ),
                        unit
                    ),
                    limitedNote: limitedNote
                )
            ]
            var turn = CGMFormat.amount(CGMStatsEngine.turnThreshold, units: .mgdL)
            if units == .mmolL {
                turn = CGMFormat.amount(CGMStatsEngine.turnThreshold, units: .mmolL) + " (" + turn + ")"
            }
            let note = String(
                format: NSLocalizedString(
                    "Expected: one per cadence from the first reading to the last; a gap is over 5 min and over 1.5 cadences between two readings, a shorter one only lowers the coverage. Noise: the readings about their own local trend. Reversals: turns of the 5-minute series of at least %@; the reference is the after-the-fact centred fit, its turns the body’s.",
                    comment: "Statistics CGM Overview: what the first card's numbers are (the turns' threshold, \"0.2 mmol/L (3 mg/dL)\")"
                ),
                turn
            )
            return Readings(
                title: title,
                dateRange: dateRange,
                limitedNote: limitedNote,
                coverage: s.coverage.fraction.map { CGMFormat.percent1($0) } ?? "–",
                coverageDetail: String(
                    format: NSLocalizedString(
                        "%1$@ readings, %2$@",
                        comment: "Statistics CGM: the readings and their cadence (\"8,123\", \"every 5 min\")"
                    ),
                    s.readings.formatted(.number),
                    cadence
                ),
                tiles: tiles,
                note: limitedNote.map { note + " " + $0 } ?? note
            )
        }

        /// The rate-of-change bands' 5-minute edges in the unit shown: "0.3", "0.6", "0.8"; "5", "10", "15".
        @MainActor static func rateEdges(_ units: GlucoseUnits) -> [String] {
            CGMStatsEngine.rateBandEdges.map { StatsFormatting.glucose($0 * 5, units: units) }
        }

        @MainActor private static func rate(_ s: CGMStats, units: GlucoseUnits) -> Rate? {
            guard let rate = s.rateOfChange, rate.seconds > 0 else { return nil }
            let edges = rateEdges(units)
            let names = [
                NSLocalizedString("Slow", comment: "Statistics CGM rate of change: under 1 mg/dL a minute"),
                NSLocalizedString("Moderate", comment: "Statistics CGM rate of change: 1–2 mg/dL a minute"),
                NSLocalizedString("Fast", comment: "Statistics CGM rate of change: 2–3 mg/dL a minute"),
                NSLocalizedString("Very fast", comment: "Statistics CGM rate of change: 3 mg/dL a minute or more")
            ]
            let ranges = [
                String(
                    format: NSLocalizedString("under %@", comment: "Statistics CGM rate of change: a band's range (\"0.3\")"),
                    edges[0]
                ),
                edges[0] + "–" + edges[1],
                edges[1] + "–" + edges[2],
                String(
                    format: NSLocalizedString(
                        "%@ and over",
                        comment: "Statistics CGM rate of change: the last band's range (\"0.8\")"
                    ),
                    edges[2]
                )
            ]
            let shares = CGMRateBand.allCases.map { rate.share($0) }
            let percents = GlucoseStatsEngine.largestRemainder(shares)
            let spanDays = Swift.max(1, (s.span?.duration ?? 0) / .days(1))
            let rows = CGMRateBand.allCases.map { band -> RateRow in
                let index = band.rawValue
                return RateRow(
                    id: index,
                    name: names[index],
                    range: ranges[index],
                    percent: StatsFormatting.percent(percents[index], belowOne: percents[index] == 0 && shares[index] > 0),
                    perDay: String(
                        format: NSLocalizedString("%@ a day", comment: "Statistics CGM: a time per day (\"2 h 05 m\")"),
                        StatsFormatting.duration(seconds: rate.bandSeconds[index] / spanDays)
                    )
                )
            }
            let rise = rate.fastestRise.map {
                String(
                    format: NSLocalizedString("Rise %@", comment: "Statistics CGM: the fastest rise (\"+0.8\")"),
                    CGMFormat.rate($0.rate, units: units)
                )
            }
            let fall = rate.fastestFall.map {
                String(
                    format: NSLocalizedString("fall %@", comment: "Statistics CGM: the fastest fall (\"−0.9\")"),
                    CGMFormat.rate($0.rate, units: units)
                )
            }
            let times = [rate.fastestRise, rate.fastestFall].compactMap { $0.map { Stat.Patches.dayAndTime($0.time) } }
            let fastest = rise == nil && fall == nil ? nil : Callout(
                title: NSLocalizedString("Fastest", comment: "Statistics CGM: the fastest rise and fall"),
                value: [rise, fall].compactMap { $0 }.joined(separator: " · "),
                detail: times.joined(separator: " · ")
            )
            let unitTitle = String(
                format: NSLocalizedString("%@ per 5 min", comment: "Statistics CGM: the rate of change's unit (\"mmol/L\")"),
                StatsFormatting.unit(units)
            )
            let edgesNote = edges.joined(separator: ", ") + " " + StatsFormatting.unit(units)
            return Rate(
                unitTitle: unitTitle,
                segments: CGMRateBand.allCases.compactMap { band in
                    shares[band.rawValue] > 0.0005
                        ? StatsSplitBar.Segment(
                            id: band.rawValue,
                            style: StatsBarStyle(fill: CGMChartStyle.ramp[band.rawValue]),
                            fraction: shares[band.rawValue]
                        )
                        : nil
                },
                rows: rows,
                fastest: fastest,
                note: String(
                    format: NSLocalizedString(
                        "The 15-minute least-squares slope at each reading, as the 5-minute change the loop works with (1, 2, 3 mg/dL per minute are %@ per 5 min).",
                        comment: "Statistics CGM rate of change: what it is (the bands' edges, \"0.3, 0.6, 0.8 mmol/L\")"
                    ),
                    edgesNote
                )
            )
        }

        @MainActor private static func comparison(_ result: CGMResult, dateRange: String, units: GlucoseUnits) -> Comparison {
            // the short names: three columns on a 375 pt phone hold "Libre 3", not "FreeStyle Libre 3 / 3+"
            let columns = result.cgms.compactMap { source in
                result.picks[source.pick].map { (CGMFormat.shortName(source.pick, name: source.name), $0) }
            }
            func row(_ id: Int, _ name: String, _ unit: String = "", _ value: (CGMPickResult) -> String) -> Comparison.Row {
                Comparison.Row(id: id, name: name, unit: unit, values: columns.map { value($0.1) })
            }
            let unit = StatsFormatting.unit(units)
            return Comparison(
                dateRange: dateRange,
                columns: columns.map(\.0),
                rows: [
                    row(0, NSLocalizedString("Time", comment: "Statistics CGM By CGM: the readings' span")) {
                        CGMFormat.days($0.stats.span?.duration ?? 0)
                    },
                    row(1, NSLocalizedString("Cadence", comment: "Statistics CGM By CGM: the cadence")) {
                        $0.stats.cadence.map { cadence in
                            String(
                                format: NSLocalizedString("%@ min", comment: "Statistics CGM By CGM: the cadence (\"5\")"),
                                String(Int((cadence / 60).rounded()))
                            )
                        } ?? "–"
                    },
                    row(2, NSLocalizedString("Coverage", comment: "Statistics CGM By CGM: the coverage")) {
                        $0.stats.coverage.fraction.map { CGMFormat.percent1($0) } ?? "–"
                    },
                    row(3, NSLocalizedString("Noise", comment: "Statistics CGM: the noise tile"), unit) {
                        $0.stats.noise.map { CGMFormat.fine($0.mgdl, units: units) } ?? "–"
                    },
                    row(4, NSLocalizedString("Delta jitter", comment: "Statistics CGM: the delta jitter tile"), unit) {
                        $0.stats.deltaJitter.map { CGMFormat.fine($0, units: units) } ?? "–"
                    },
                    row(
                        5,
                        NSLocalizedString("Reversals", comment: "Statistics CGM: the reversals tile"),
                        NSLocalizedString("a day / reference", comment: "Statistics CGM By CGM: the reversals' unit")
                    ) { pick in
                        let raw = pick.stats.reversals.rawPerDay.map { String(Int($0.rounded())) } ?? "–"
                        let reference = pick.stats.reversals.referencePerDay.map { String(Int($0.rounded())) } ?? "–"
                        return raw + " / " + reference
                    }
                ],
                note: NSLocalizedString(
                    "Each column is that CGM’s own readings; Unknown is the readings no recorded CGM session covers.",
                    comment: "Statistics CGM By CGM: what a column is"
                )
            )
        }

        // MARK: Sensors

        @MainActor private static func makeSensors(
            _ shown: CGMPickResult?,
            pick: CGMPick,
            recordingStart: Date?,
            now: Date,
            units: GlucoseUnits
        ) -> Sensors {
            let unit = StatsFormatting.unit(units)
            let shownSensors: [CGMSensor] = pick == .unknown ? [] : shown?.sensors ?? []
            let rows = shownSensors.map { sensorRow($0, now: now, units: units) }
            let emptyText: String
            if pick != .unknown {
                emptyText = NSLocalizedString("No sensor in this period.", comment: "Statistics CGM Sensors: none in the period")
            } else if let recordingStart {
                emptyText = String(
                    format: NSLocalizedString(
                        "Sensors weren’t recorded before %@.",
                        comment: "Statistics CGM Unknown: the recording's start (\"Mon 12 Oct, 10:20\")"
                    ),
                    Stat.Patches.dayAndTime(recordingStart)
                )
            } else {
                emptyText = NSLocalizedString("Sensors weren’t recorded.", comment: "Statistics CGM Unknown: no sensors")
            }

            // the noise by sensor day
            let byDay: [Int: CGMNoise] = pick == .unknown ? [:] : shown?.stats.noiseBySensorDay ?? [:]
            let noiseDays = byDay.keys.filter { $0 <= lastSensorDay }.sorted().compactMap { day -> NoiseDay? in
                guard let noise = byDay[day] else { return nil }
                return NoiseDay(
                    day: day,
                    value: CGMFormat.shown(noise.mgdl, units: units),
                    sensors: shown?.sensorsBySensorDay[day] ?? 0
                )
            }
            let step = units == .mmolL ? 0.05 : 1.0
            let top = Swift.max(step, ((noiseDays.map(\.value).max() ?? 0) / step).rounded(.up) * step)
            let levels = [0, top / 2, top]
            let later = byDay.filter { $0.key >= 2 }.values
            let laterCount = later.reduce(0) { $0 + $1.count }
            // the later days pooled: their noises weighed by their readings
            let laterSum: Double = later.reduce(0) { $0 + $1.mgdl * Double($1.count) }
            let laterNoise: Double? = laterCount > 0 ? laterSum / Double(laterCount) : nil
            let noiseCallout = byDay[1].map { first in
                Callout(
                    title: NSLocalizedString("Day 1", comment: "Statistics CGM Sensors: the first sensor day"),
                    value: String(
                        format: NSLocalizedString(
                            "%1$@ %2$@ on the first day",
                            comment: "Statistics CGM Sensors: day 1's noise (\"0.24\", \"mmol/L\")"
                        ),
                        CGMFormat.fine(first.mgdl, units: units),
                        unit
                    ),
                    detail: [
                        laterNoise.map {
                            String(
                                format: NSLocalizedString(
                                    "against %@ from day 2 on",
                                    comment: "Statistics CGM Sensors: the later days' noise (\"0.17\")"
                                ),
                                CGMFormat.fine($0, units: units)
                            )
                        },
                        String(
                            format: NSLocalizedString("%d sensors", comment: "Statistics CGM Sensors: the sensors with a day 1"),
                            shown?.sensorsBySensorDay[1] ?? 0
                        )
                    ].compactMap { $0 }.joined(separator: " · ")
                )
            }
            let noiseNote = NSLocalizedString(
                "Day 1 is the first 24 hours after a sensor start; under each day, the sensors with readings on it. A noisier first day is what pre-soaking (inserting the new sensor hours early) avoids.",
                comment: "Statistics CGM Sensors: what the noise by sensor day is"
            )
            return Sensors(
                rows: rows,
                emptyText: emptyText,
                note: NSLocalizedString(
                    "The bar is the sensor’s time of its expected life, full at the end of its life. Ended early: it stopped more than 6 hours before. Why a sensor ended isn’t recorded.",
                    comment: "Statistics CGM Sensors: what a sensor's bar is"
                ),
                noiseDays: noiseDays,
                noiseLevels: levels,
                noiseLevelLabels: levels.map { CGMFormat.number($0, digits: CGMFormat.fineDigits(units)) },
                noiseCallout: noiseCallout,
                noiseNote: noiseNote
            )
        }

        /// A sensor's row: its dates and length, its length of its expected life, how it ended, its noise.
        ///
        /// "Ended early": a sensor no longer in use, shorter than its life (its grace left out) by more than
        /// `Provider.earlyEndMargin`, that something ended (`CGMSensor.hasEndCause`): its recorded session's end;
        /// else a gap of `CGMUnknownInference.splitGap` or more after its last reading (a warm-up, the readings
        /// stopped), no reading after it, or the next reading another CGM's (or Unknown), a recorded session's or a
        /// recorded sensor's. Never when an entered session of its CGM goes straight on from it with an inferred
        /// start. "Ended at the CGM change" instead when the next session, of another CGM, began where it ended.
        @MainActor static func sensorRow(_ sensor: CGMSensor, now: Date, units: GlucoseUnits) -> SensorRow {
            let end = sensor.end ?? now
            let length = Swift.max(end.timeIntervalSince(sensor.lifeStart), 0)
            let life = sensor.expectedLife.map { Swift.max($0 - sensor.grace, 0) }
            let early = !sensor.isInUse && sensor.hasEndCause &&
                life.map { length < $0 - Stat.Provider.earlyEndMargin } ?? false
            let endText = sensor.end.map { Stat.Patches.dayAndTime($0) }
                ?? NSLocalizedString("now", comment: "Statistics CGM Sensors: the end of the sensor in use")
            let span = Stat.Patches.dayAndTime(sensor.lifeStart) + " – " + endText + " · " + CGMFormat.days(length)
            let noise = sensor.noise.map { noise in
                String(
                    format: NSLocalizedString(
                        "noise %1$@ %2$@",
                        comment: "Statistics CGM Sensors: a sensor's noise (\"0.18\", \"mmol/L\")"
                    ),
                    CGMFormat.fine(noise.mgdl, units: units),
                    StatsFormatting.unit(units)
                )
            }
            var earlyText: String?
            if early {
                earlyText = sensor.endedAtCGMChange
                    ? NSLocalizedString(
                        "Ended at the CGM change",
                        comment: "Statistics CGM Sensors: a sensor ended early by a change of CGM"
                    )
                    : NSLocalizedString(
                        "Ended early",
                        comment: "Statistics CGM Sensors: a sensor stopped more than 6 hours early"
                    )
            }
            return SensorRow(
                id: sensor.id,
                title: sensor.name,
                isInUse: sensor.isInUse,
                earlyText: earlyText,
                span: span,
                bar: life.flatMap { $0 > 0 ? Swift.min(length / $0, 1) : nil },
                noise: noise,
                isEntered: sensor.isEntered,
                isBackfilled: sensor.isBackfilled
            )
        }

        // MARK: Smoothing

        @MainActor private static func smoothingFacts(
            _ s: CGMStats,
            who: String,
            period: StatsPeriod,
            dateRange: String,
            current: SmoothingCandidate
        ) -> [Fact] {
            [
                Fact(
                    id: 0,
                    key: NSLocalizedString("Period", comment: "Statistics CGM Smoothing: the period replayed"),
                    value: StatsFormatting.label(period) + " · " + dateRange
                ),
                Fact(
                    id: 1,
                    key: NSLocalizedString("CGM", comment: "Statistics CGM Smoothing: the CGM replayed"),
                    value: who,
                    detail: String(
                        format: NSLocalizedString(
                            "%1$@ of readings · %2$@",
                            comment: "Statistics CGM Smoothing: the readings' span and cadence (\"29 d 14 h\", \"1-min\")"
                        ),
                        CGMFormat.days(s.span?.duration ?? 0),
                        CGMFormat.cadence(s.cadence ?? 300)
                    )
                ),
                Fact(
                    id: 2,
                    key: NSLocalizedString("Options", comment: "Statistics CGM Smoothing: the settings compared"),
                    value: String(
                        format: NSLocalizedString("%d compared", comment: "Statistics CGM Smoothing: the settings compared (8)"),
                        SmoothingCandidate.all.count
                    ),
                    detail: NSLocalizedString(
                        "none, Savitzky-Golay 1–3 passes, Kalman Calm, Balanced, Responsive, Exponential",
                        comment: "Statistics CGM Smoothing: the settings compared"
                    )
                ),
                Fact(
                    id: 3,
                    key: NSLocalizedString("Your setting", comment: "Statistics CGM Smoothing: the current setting"),
                    value: CGMSmoothingTables.fullName(current),
                    detail: NSLocalizedString(
                        "Settings → CGM → Smoothing",
                        comment: "Statistics CGM Smoothing: where the setting is"
                    )
                )
            ]
        }
    }
}

// MARK: - The smoothing results

/// The smoothing analysis's results, formatted: no smoothing's own figures first, then each option's change from them,
/// the trend the loop saw (no reference needed) and against the after-the-fact reference; the current setting marked.
struct CGMSmoothingTables: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let name: String
        let detail: String?
        let isCurrent: Bool
        /// no smoothing's: the figures themselves, the others' are changes
        let isBaseline: Bool
        let cells: [String]
    }

    struct Column: Equatable, Identifiable {
        let id: Int
        let title: String
        let unit: String
    }

    let trendColumns: [Column]
    let trendRows: [Row]
    let trendNote: String
    let referenceColumns: [Column]
    let referenceRows: [Row]
    /// the ranking changes with the reference's width (`SmoothingRankingSensitivity`); nil when it doesn't
    let ranking: Stat.CGMReport.Callout?
    let referenceNote: String

    /// "Kalman filter", "Savitzky-Golay"
    @MainActor static func name(_ candidate: SmoothingCandidate) -> String {
        candidate.settings.algorithm.displayName
    }

    /// "2 passes", "Balanced"; nil for none and exponential
    @MainActor static func detail(_ candidate: SmoothingCandidate) -> String? {
        switch candidate {
        case .exponential,
             .none: return nil
        case let .savitzkyGolay(passes):
            return passes == .one
                ? NSLocalizedString("1 pass", comment: "Statistics CGM Smoothing: Savitzky-Golay's passes")
                : String(
                    format: NSLocalizedString("%d passes", comment: "Statistics CGM Smoothing: Savitzky-Golay's passes"),
                    passes.rawValue
                )
        case let .kalman(responsiveness):
            return responsiveness.displayName
        }
    }

    /// "Kalman filter · Balanced"
    @MainActor static func fullName(_ candidate: SmoothingCandidate) -> String {
        [name(candidate), detail(candidate)].compactMap { $0 }.joined(separator: " · ")
    }

    @MainActor init(_ result: SmoothingReplayResult, current: SmoothingCandidate, units: GlucoseUnits) {
        typealias Format = CGMFormat
        let unit = StatsFormatting.unit(units)
        let none = "–"
        func value(_ result: SmoothingCandidateResult, _ metric: SmoothingMetric) -> Double? {
            result.scores[metric].value
        }
        func change(_ result: SmoothingCandidateResult, _ metric: SmoothingMetric) -> SmoothingChange? {
            result.changes[metric]
        }
        func relative(_ result: SmoothingCandidateResult, _ metric: SmoothingMetric) -> String {
            change(result, metric)?.relative.map { Format.signed($0 * 100, digits: 0) + "%" } ?? none
        }
        func minutes(_ value: Double?) -> String {
            value.map {
                String(
                    format: NSLocalizedString("%@ m", comment: "Statistics CGM Smoothing: minutes (\"+3\")"),
                    Format.signed($0, digits: 0)
                )
            } ?? none
        }
        func row(_ result: SmoothingCandidateResult, cells: [String]) -> Row {
            Row(
                id: result.id,
                name: Self.name(result.candidate),
                detail: Self.detail(result.candidate),
                isCurrent: result.candidate == current,
                isBaseline: result.candidate == .none,
                cells: cells
            )
        }

        trendColumns = [
            Column(
                id: 0,
                title: NSLocalizedString("Reversals", comment: "Statistics CGM: the reversals tile"),
                unit: NSLocalizedString("a day", comment: "Statistics CGM Smoothing: the reversals' unit")
            ),
            Column(id: 1, title: NSLocalizedString("Jitter", comment: "Statistics CGM Smoothing: the delta jitter"), unit: unit),
            Column(
                id: 2,
                title: NSLocalizedString("Wrong way", comment: "Statistics CGM Smoothing: deltas against a clear move"),
                unit: NSLocalizedString("deltas", comment: "Statistics CGM Smoothing: the wrong-way deltas' unit")
            )
        ]
        trendRows = result.results.map { candidate in
            guard candidate.candidate != .none else {
                return row(candidate, cells: [
                    value(candidate, .reversals).map { String(Int($0.rounded())) } ?? none,
                    value(candidate, .deltaJitter).map { Format.fine($0, units: units) } ?? none,
                    value(candidate, .wrongWay).map { StatsFormatting.percent(fraction: $0) } ?? none
                ])
            }
            return row(candidate, cells: [
                relative(candidate, .reversals),
                relative(candidate, .deltaJitter),
                change(candidate, .wrongWay)?.difference.map {
                    String(
                        format: NSLocalizedString("%@ pt", comment: "Statistics CGM Smoothing: percentage points (\"+5\")"),
                        Format.signed($0 * 100, digits: 0)
                    )
                } ?? none
            ])
        }
        let moving = Format.amount(SmoothingReplay.movingRate, units: units)
        trendNote = result.referenceReversals.value.map { reference in
            String(
                format: NSLocalizedString(
                    "No smoothing: the figures for the readings as they came. Below it, each option’s change from them. Reversals: turns of the delta the loop saw (%1$d a day in the reference, the body’s own). Jitter: how much the 5-minute delta jumps from one loop to the next. Wrong way: deltas pointing against a clear move (%2$@ a minute or more).",
                    comment: "Statistics CGM Smoothing: the trend table (the reference's reversals, 42; the moving rate, \"0.06 mmol/L\")"
                ),
                Int(reference.rounded()),
                moving
            )
        } ?? String(
            format: NSLocalizedString(
                "No smoothing: the figures for the readings as they came. Below it, each option’s change from them. Reversals: turns of the delta the loop saw. Jitter: how much the 5-minute delta jumps from one loop to the next. Wrong way: deltas pointing against a clear move (%@ a minute or more).",
                comment: "Statistics CGM Smoothing: the trend table (the moving rate, \"0.06 mmol/L\")"
            ),
            moving
        )

        referenceColumns = [
            Column(
                id: 0,
                title: NSLocalizedString("Lag", comment: "Statistics CGM Smoothing: the lag"),
                unit: NSLocalizedString("min", comment: "Statistics CGM Smoothing: the lag's unit")
            ),
            Column(
                id: 1,
                title: NSLocalizedString("Low", comment: "Statistics glucose band"),
                unit: NSLocalizedString("cross", comment: "Statistics CGM Smoothing: the low crossing delay's unit")
            ),
            Column(
                id: 2,
                title: NSLocalizedString("Nadir", comment: "Statistics CGM Smoothing: the nadir miss"),
                unit: NSLocalizedString("miss", comment: "Statistics CGM Smoothing: the nadir miss's unit")
            ),
            Column(
                id: 3,
                title: NSLocalizedString("Level", comment: "Statistics CGM Smoothing: the level error"),
                unit: NSLocalizedString("error", comment: "Statistics CGM Smoothing: the errors' unit")
            ),
            Column(
                id: 4,
                title: NSLocalizedString("Delta", comment: "Statistics CGM Smoothing: the delta error"),
                unit: NSLocalizedString("error", comment: "Statistics CGM Smoothing: the errors' unit")
            )
        ]
        referenceRows = result.results.map { candidate in
            guard candidate.candidate != .none else {
                return row(candidate, cells: [
                    value(candidate, .lag).map { Format.number($0, digits: 0) } ?? none,
                    value(candidate, .lowCrossingDelay).map {
                        String(
                            format: NSLocalizedString("%@ m", comment: "Statistics CGM Smoothing: minutes (\"+3\")"),
                            Format.number($0, digits: 0)
                        )
                    } ?? none,
                    value(candidate, .nadirMiss).map { Format.fine($0, units: units) } ?? none,
                    value(candidate, .levelError).map { Format.fine($0, units: units) } ?? none,
                    value(candidate, .deltaError).map { Format.fine($0, units: units) } ?? none
                ])
            }
            // the difference-only scores (`SmoothingChange.relative` nil) as differences, never as percents
            return row(candidate, cells: [
                minutes(change(candidate, .lag)?.difference),
                minutes(change(candidate, .lowCrossingDelay)?.difference),
                change(candidate, .nadirMiss)?.difference.map { Format.signedFine($0, units: units) } ?? none,
                relative(candidate, .levelError),
                relative(candidate, .deltaError)
            ])
        }
        ranking = Self.ranking(result.sensitivity)
        referenceNote = String(
            format: NSLocalizedString(
                "The reference: a centred, robust local fit over ±20 minutes of the raw readings, known only afterwards. Lag: the shift that best lines the loop’s values up with it. Low cross: how much later than the reference the loop’s value went below %1$@. Nadir miss: how far it was from the bottom of a dip (%2$@). Level and delta error: the typical error of the newest value and of the 5-minute delta.",
                comment: "Statistics CGM Smoothing: the reference table (\"3.9 mmol/L\", \"mmol/L\")"
            ),
            Format.amount(SmoothingReplay.lowLimit, units: units),
            unit
        )
    }

    /// The first place the order at another reference width departs from the scored one's: the delta error's, else the
    /// lag's; nil when neither changes.
    @MainActor private static func ranking(_ sensitivity: SmoothingRankingSensitivity) -> Stat.CGMReport.Callout? {
        let scoring = sensitivity.halfWidths.firstIndex(of: SmoothingReplay.scoringHalfWidth) ?? 0
        func departure(_ orders: [[SmoothingCandidate]])
            -> (width: TimeInterval, above: SmoothingCandidate, below: SmoothingCandidate)?
        {
            guard orders.indices.contains(scoring) else { return nil }
            let scored = orders[scoring]
            for index in orders.indices where index != scoring {
                let order = orders[index]
                if let place = order.indices.first(where: { $0 < scored.count && order[$0] != scored[$0] }) {
                    return (sensitivity.halfWidths[index], order[place], scored[place])
                }
            }
            return nil
        }
        let text: String
        if sensitivity.deltaErrorRankingChanges, let found = departure(sensitivity.deltaErrorOrder) {
            text = String(
                format: NSLocalizedString(
                    "Against a ±%1$d min reference, %2$@ ranks above %3$@ on the delta error",
                    comment: "Statistics CGM Smoothing: the ranking at another reference width (15, \"Savitzky-Golay · 1 pass\", \"Exponential\")"
                ),
                Int((found.width / 60).rounded()),
                fullName(found.above),
                fullName(found.below)
            )
        } else if sensitivity.lagRankingChanges, let found = departure(sensitivity.lagOrder) {
            text = String(
                format: NSLocalizedString(
                    "Against a ±%1$d min reference, %2$@ ranks above %3$@ on the lag",
                    comment: "Statistics CGM Smoothing: the ranking at another reference width (15, \"Kalman filter · Calm\", \"Exponential\")"
                ),
                Int((found.width / 60).rounded()),
                fullName(found.above),
                fullName(found.below)
            )
        } else {
            return nil
        }
        return Stat.CGMReport.Callout(
            title: NSLocalizedString(
                "The ranking changes with the reference",
                comment: "Statistics CGM Smoothing: the reference width callout"
            ),
            value: text,
            detail: String(
                format: NSLocalizedString(
                    "The tables are against the ±%d min reference.",
                    comment: "Statistics CGM Smoothing: the reference scored against (20)"
                ),
                Int((SmoothingReplay.scoringHalfWidth / 60).rounded())
            )
        )
    }
}

// MARK: - The analysis

/// A cancel flag the replay polls from its threads.
final class CGMCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// The smoothing analyses of the CGM topic (`Stat.StateModel.cgmSmoothing`): one at a time, on Analyse, cancellable; their
/// results kept by key while Statistics is open. Observed only by the Smoothing view.
///
/// - **Key:** the period (its first day) and the pick. A result remembers the readings change it was analysed after
///   (`StatsChange.seq`): content read after newer ones shows it with a note and "Analyse again".
/// - **Runs:** a new one cancels the one in flight (its result dropped; a result it was replacing stays). Switching
///   views keeps it running; Statistics going down cancels it (`cancel`).
/// - **Progress:** the replay's, hopped to the main actor asynchronously; only the run's own and only forwards.
@MainActor @Observable final class CGMSmoothingRuns {
    struct Key: Hashable, Sendable {
        let period: StatsPeriod
        let windowStart: Date
        let pick: Stat.CGMPick
    }

    /// A result, when it was analysed and the newest readings change it saw.
    struct Entry: Equatable {
        let result: SmoothingReplayResult
        let analysedAt: Date
        let readingsSeq: Int
    }

    enum Status: Equatable {
        case idle
        /// 0...1
        case running(Double)
        /// `newerReadings`: the content shown was read after readings changes the analysis didn't see
        case done(SmoothingReplayResult, analysedAt: Date, newerReadings: Bool)
        /// the readings couldn't be read
        case failed
    }

    /// The analysis of a key: nil when cancelled (it polls `isCancelled`); `progress` from any thread.
    typealias Replay = @Sendable(
        _ key: Key,
        _ isCancelled: @escaping @Sendable() -> Bool,
        _ progress: @escaping @Sendable(Double) -> Void
    ) async throws -> SmoothingReplayResult?

    private(set) var results: [Key: Entry] = [:]
    private(set) var running: Key?
    private(set) var progress = 0.0
    private var failed: Set<Key> = []
    @ObservationIgnored private var flag: CGMCancelFlag?
    /// every run's task until it ends, a cancelled one's too (`finished`)
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    /// moved on by every run and cancel: a run's late progress and result are its own only
    @ObservationIgnored private var seq = 0

    /// nonisolated: a stored property's default value
    nonisolated init() {}

    /// - Parameter readingsSeq: the newest readings change the content shown was read after
    func status(_ key: Key, readingsSeq: Int) -> Status {
        if running == key {
            return .running(progress)
        }
        if let entry = results[key] {
            return .done(entry.result, analysedAt: entry.analysedAt, newerReadings: readingsSeq > entry.readingsSeq)
        }
        return failed.contains(key) ? .failed : .idle
    }

    /// Analyse: a result that saw `readingsSeq` stays, the run in flight for the key goes on; otherwise a new run (the
    /// one in flight for another key cancelled).
    /// - Parameter readingsSeq: the newest readings change now (`glucoseStatsChanged`)
    func analyse(_ key: Key, readingsSeq: Int, now: Date = Date(), replay: @escaping Replay) {
        guard running != key else { return }
        if let entry = results[key], entry.readingsSeq >= readingsSeq {
            return
        }
        cancel()
        failed.remove(key)
        let flag = CGMCancelFlag()
        self.flag = flag
        running = key
        progress = 0
        let seq = self.seq
        let progress: @Sendable(Double) -> Void = { [weak self] fraction in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.advance(fraction, seq: seq) }
            }
        }
        tasks[seq] = Task { [weak self] in
            defer { self?.tasks[seq] = nil }
            let result: SmoothingReplayResult?
            do {
                result = try await replay(key, { flag.isCancelled }, progress)
            } catch {
                warning(.service, "Statistics: the smoothing analysis couldn't read the readings", error: error)
                self?.finish(nil, key: key, seq: seq, failed: true, analysedAt: now, readingsSeq: readingsSeq)
                return
            }
            self?.finish(result, key: key, seq: seq, failed: false, analysedAt: now, readingsSeq: readingsSeq)
        }
    }

    /// Cancel: the run in flight stops (its result dropped); its key shows the result it was replacing, or idle.
    func cancel() {
        flag?.cancel()
        flag = nil
        running = nil
        progress = 0
        seq += 1
    }

    /// Every run started, cancelled ones too, ended (the tests').
    func finished() async {
        while let task = tasks.values.first {
            await task.value
            tasks = tasks.filter { $0.value != task }
        }
    }

    private func advance(_ fraction: Double, seq: Int) {
        guard seq == self.seq, fraction > progress else { return }
        progress = Swift.min(fraction, 1)
    }

    private func finish(
        _ result: SmoothingReplayResult?,
        key: Key,
        seq: Int,
        failed: Bool,
        analysedAt: Date,
        readingsSeq: Int
    ) {
        guard seq == self.seq else { return }
        running = nil
        flag = nil
        progress = 0
        if let result {
            results[key] = Entry(result: result, analysedAt: analysedAt, readingsSeq: readingsSeq)
        } else if failed {
            self.failed.insert(key)
        }
    }
}
